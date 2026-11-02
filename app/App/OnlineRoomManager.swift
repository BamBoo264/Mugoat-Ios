import Foundation
import Network
import UIKit

/// Represents a remote player connected to the current multiplayer room.
struct OnlinePeer: Identifiable {
    let id: String
    var name: String
    var position: [Float] = [0, 0, 0]
    var heading: Float = 0
    var vehicleModel: UInt32 = 0
    var weapon: UInt32 = 0
    var health: Int = 200
    var lastSeen: Date = Date()
}

/// Packet sent across the P2P room network.
struct RoomPacket: Codable {
    enum PacketType: String, Codable {
        case joinRequest = "JOIN_REQ"
        case joinAccept = "JOIN_ACC"
        case joinReject = "JOIN_REJ"
        case stateSync = "STATE"
        case ping = "PING"
        case leave = "LEAVE"
    }
    let type: PacketType
    let roomCode: String
    let senderId: String
    let senderName: String
    var position: [Float]?
    var heading: Float?
    var vehicleModel: UInt32?
    var weapon: UInt32?
    var health: Int?
}

/// Central manager for creating, joining, and synchronizing GTA V online multiplayer rooms.
final class OnlineRoomManager {
    static let shared = OnlineRoomManager()

    enum RoomState: Equatable {
        case idle
        case hosting(code: String)
        case connecting(code: String)
        case connected(code: String, isHost: Bool)
        case error(String)
    }

    private(set) var state: RoomState = .idle {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((RoomState) -> Void)?
    var onPeersUpdated: (([OnlinePeer]) -> Void)?

    private(set) var roomCode: String?
    private(set) var isHost = false
    private(set) var peers: [String: OnlinePeer] = [:]
    let localPlayerId = UUID().uuidString.prefix(8).uppercased()
    var localPlayerName: String {
        get { UserDefaults.standard.string(forKey: "onlinePlayerName") ?? "Player_\(localPlayerId)" }
        set { UserDefaults.standard.set(newValue, forKey: "onlinePlayerName") }
    }

    // Auto-spawn at host state
    private(set) var hasSpawnedAtHost = false
    private(set) var pendingSpawnCoords: [Float]?
    private var lastStatePushTime: TimeInterval = 0

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "vn.gta.online.room", qos: .userInitiated)
    private var syncTimer: Timer?

    var inRoom: Bool {
        if case .connected = state { return true }
        if case .hosting = state { return true }
        return false
    }

    /// Generates a clean 8-character formatted room code, e.g. K7Q2-M9XD
    static func generateRoomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        func chunk(_ length: Int) -> String {
            (0..<length).map { _ in String(chars[Int.random(in: 0..<chars.count)]) }.joined()
        }
        return "\(chunk(4))-\(chunk(4))"
    }

    /// Normalizes user-entered room code: uppercase, trim whitespace and hyphens
    static func normalizeCode(_ raw: String) -> String {
        let clean = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        if clean.count >= 8 {
            let p1 = clean.prefix(4)
            let p2 = clean.dropFirst(4).prefix(4)
            return "\(p1)-\(p2)"
        }
        return clean
    }

    // MARK: - Host Room

    /// Creates a new room as host, assigns a room code, and listens for connections.
    func createRoom() -> String {
        leaveRoom()
        let code = Self.generateRoomCode()
        roomCode = code
        isHost = true
        hasSpawnedAtHost = true // Host doesn't need to teleport to itself
        state = .hosting(code: code)
        startListener(code: code)
        startLocalBroadcast()
        return code
    }

    // MARK: - Join Room

    /// Joins an existing room with a room code.
    func joinRoom(code rawCode: String) {
        leaveRoom()
        let code = Self.normalizeCode(rawCode)
        guard code.count >= 8 else {
            state = .error("Mã phòng không hợp lệ (cần 8 ký tự, ví dụ: ABCD-1234)")
            return
        }
        roomCode = code
        isHost = false
        hasSpawnedAtHost = false
        state = .connecting(code: code)
        connectToHost(code: code)
    }

    // MARK: - Leave Room

    func leaveRoom() {
        if inRoom, let code = roomCode {
            broadcast(packet: RoomPacket(type: .leave, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName))
        }
        syncTimer?.invalidate()
        syncTimer = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        for conn in activeConnections { conn.cancel() }
        activeConnections.removeAll()
        for (_, peer) in peers {
            peer.id.withCString { PGRemoveRemotePeer($0) }
        }
        peers.removeAll()
        roomCode = nil
        isHost = false
        hasSpawnedAtHost = false
        pendingSpawnCoords = nil
        state = .idle
    }

    // MARK: - Network Engine (Network.framework)

    private func startListener(code: String) {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: 47520)
            listener.service = NWListener.Service(name: "GTAV-\(code)", type: "_gtavmp._udp")
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let err) = state {
                    self?.state = .error("Lỗi tạo phòng P2P: \(err.localizedDescription)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            state = .error("Không thể khởi động mạng: \(error.localizedDescription)")
        }
    }

    private func connectToHost(code: String) {
        // 1. Direct UDP broadcast fast-path on port 47520
        let hostEndpoint = NWEndpoint.hostPort(host: .ipv4(.broadcast), port: 47520)
        let connection = NWConnection(to: hostEndpoint, using: .udp)
        connection.stateUpdateHandler = { [weak self] connState in
            guard let self = self else { return }
            switch connState {
            case .ready:
                self.sendJoinRequest(connection: connection, code: code)
                self.receive(on: connection)
            case .failed(let err):
                self.state = .error("Không tìm thấy phòng \(code): \(err.localizedDescription)")
            default: break
            }
        }
        connection.start(queue: queue)
        activeConnections.append(connection)

        // 2. Bonjour discovery (_gtavmp._udp) for reliable local network discovery
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_gtavmp._udp", domain: nil)
        let browserParams = NWParameters.udp
        let browser = NWBrowser(for: descriptor, using: browserParams)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint, name.contains(code) {
                    let bonjourConn = NWConnection(to: result.endpoint, using: .udp)
                    bonjourConn.stateUpdateHandler = { [weak self] state in
                        if state == .ready {
                            self?.sendJoinRequest(connection: bonjourConn, code: code)
                            self?.receive(on: bonjourConn)
                        }
                    }
                    bonjourConn.start(queue: self.queue)
                    self.activeConnections.append(bonjourConn)
                }
            }
        }
        browser.start(queue: queue)
        self.browser = browser

        // Set a timeout for connection
        queue.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self else { return }
            if case .connecting = self.state {
                self.state = .connected(code: code, isHost: false)
                self.startLocalBroadcast()
            }
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func sendJoinRequest(connection: NWConnection, code: String) {
        let packet = RoomPacket(type: .joinRequest, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
        send(packet: packet, over: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self = self else { return }
            if let data = content, let packet = try? JSONDecoder().decode(RoomPacket.self, from: data) {
                self.handlePacket(packet, from: connection)
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    private func handlePacket(_ packet: RoomPacket, from connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard packet.roomCode == self.roomCode else { return }

            switch packet.type {
            case .joinRequest:
                if self.isHost {
                    self.peers[packet.senderId] = OnlinePeer(id: packet.senderId, name: packet.senderName)
                    self.state = .connected(code: self.roomCode ?? "", isHost: true)
                    self.onPeersUpdated?(Array(self.peers.values))

                    // Host includes current position so the joining guest can spawn directly at host!
                    var hostPos = [Float](repeating: 0, count: 3)
                    _ = PGGetPlayerPosition(&hostPos)
                    let hostHeading = PGGetPlayerHeading()

                    var reply = RoomPacket(type: .joinAccept, roomCode: packet.roomCode, senderId: String(self.localPlayerId), senderName: self.localPlayerName)
                    if hostPos[0] != 0 || hostPos[1] != 0 {
                        reply.position = hostPos
                        reply.heading = hostHeading
                    }
                    self.send(packet: reply, over: connection)
                }

            case .joinAccept:
                var peer = OnlinePeer(id: packet.senderId, name: packet.senderName)
                if let pos = packet.position { peer.position = pos }
                if let h = packet.heading { peer.heading = h }
                self.peers[packet.senderId] = peer
                self.state = .connected(code: packet.roomCode, isHost: false)
                self.startLocalBroadcast()
                self.onPeersUpdated?(Array(self.peers.values))

                // Auto-spawn guest at host's position
                if let pos = packet.position, pos[0] != 0 || pos[1] != 0 {
                    self.spawnAtHost(coords: pos)
                }

            case .stateSync:
                if var peer = self.peers[packet.senderId] {
                    if let pos = packet.position { peer.position = pos }
                    if let h = packet.heading { peer.heading = h }
                    if let v = packet.vehicleModel { peer.vehicleModel = v }
                    if let w = packet.weapon { peer.weapon = w }
                    if let hp = packet.health { peer.health = hp }
                    peer.lastSeen = Date()
                    self.peers[packet.senderId] = peer
                    self.onPeersUpdated?(Array(self.peers.values))

                    // If guest hasn't spawned at host yet, auto-teleport on receiving host's coordinates
                    if !self.isHost && !self.hasSpawnedAtHost, let pos = packet.position, pos[0] != 0 || pos[1] != 0 {
                        self.spawnAtHost(coords: pos)
                    }

                    // Feed into C engine
                    if let pos = packet.position {
                        peer.id.withCString { cId in
                            PGUpdateRemotePeer(cId, pos[0], pos[1], pos[2], packet.heading ?? 0, packet.vehicleModel ?? 0)
                        }
                    }
                } else {
                    var peer = OnlinePeer(id: packet.senderId, name: packet.senderName)
                    if let pos = packet.position { peer.position = pos }
                    self.peers[packet.senderId] = peer
                    self.onPeersUpdated?(Array(self.peers.values))
                }

            case .leave:
                packet.senderId.withCString { PGRemoveRemotePeer($0) }
                self.peers.removeValue(forKey: packet.senderId)
                self.onPeersUpdated?(Array(self.peers.values))

            default: break
            }
        }
    }

    private func send(packet: RoomPacket, over connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        connection.send(content: data, completion: .idempotent)
    }

    private func broadcast(packet: RoomPacket) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        for conn in activeConnections {
            conn.send(content: data, completion: .idempotent)
        }
    }

    private func startLocalBroadcast() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.heartbeatTick()
        }
    }

    private func heartbeatTick() {
        guard inRoom, let code = roomCode else { return }
        let packet = RoomPacket(type: .ping, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
        broadcast(packet: packet)
    }

    // MARK: - Game Sync & Spawn at Host

    /// Teleports the guest to the host's coordinates, offsetting slightly (+1.5m) to avoid collisions.
    func spawnAtHost(coords: [Float]) {
        guard coords.count >= 3, (coords[0] != 0 || coords[1] != 0) else { return }
        let gameStatus = PGGameStatus()
        if (gameStatus & 16) == 0 {
            // Player is alive and active in gameplay: teleport now!
            PGTeleportPlayer(coords[0] + 1.5, coords[1] + 1.5, coords[2])
            hasSpawnedAtHost = true
            pendingSpawnCoords = nil
        } else {
            // Still loading: hold pending coordinates until gameplay starts
            pendingSpawnCoords = coords
        }
    }

    /// Manually teleports the player to a peer (or host) in the room.
    func teleportToPartner() -> Bool {
        for (_, peer) in peers {
            if peer.position.count >= 3 && (peer.position[0] != 0 || peer.position[1] != 0) {
                PGTeleportPlayer(peer.position[0] + 1.5, peer.position[1] + 1.5, peer.position[2])
                return true
            }
        }
        return false
    }

    /// Called on every frame from NativePortViewController.pollController()
    func gameLoopTick() {
        guard inRoom else { return }
        let gameStatus = PGGameStatus()
        guard (gameStatus & 16) == 0 else { return }

        // Execute pending spawn at host if player was previously in a loading screen
        if !hasSpawnedAtHost, let target = pendingSpawnCoords {
            PGTeleportPlayer(target[0] + 1.5, target[1] + 1.5, target[2])
            hasSpawnedAtHost = true
            pendingSpawnCoords = nil
        }

        // Throttle network state broadcasting to 10 Hz (every 100ms)
        let now = CACurrentMediaTime()
        if now - lastStatePushTime >= 0.1 {
            lastStatePushTime = now
            var localPos = [Float](repeating: 0, count: 3)
            if PGGetPlayerPosition(&localPos) && (localPos[0] != 0 || localPos[1] != 0) {
                let heading = PGGetPlayerHeading()
                let hints = PGReadControlHints(PGCurrentTouchContext())
                pushLocalState(position: localPos, heading: heading, vehicleModel: hints.vehicleModel, weapon: 0, health: 200)
            }
        }

        // Continually feed active peers to C engine for smooth radar blips and avatar ped tracking
        for (_, peer) in peers {
            if peer.position.count >= 3 && (peer.position[0] != 0 || peer.position[1] != 0) {
                peer.id.withCString { cId in
                    PGUpdateRemotePeer(cId, peer.position[0], peer.position[1], peer.position[2], peer.heading, peer.vehicleModel)
                }
            }
        }
    }

    /// Pushes local player position, vehicle, weapon to all peers in the room.
    func pushLocalState(position: [Float], heading: Float, vehicleModel: UInt32, weapon: UInt32, health: Int) {
        guard inRoom, let code = roomCode else { return }
        var packet = RoomPacket(type: .stateSync, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
        packet.position = position
        packet.heading = heading
        packet.vehicleModel = vehicleModel
        packet.weapon = weapon
        packet.health = health
        broadcast(packet: packet)
    }
}
