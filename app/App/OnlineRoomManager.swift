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

    private var listener: NWListener?
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
        listener?.cancel()
        listener = nil
        for conn in activeConnections { conn.cancel() }
        activeConnections.removeAll()
        peers.removeAll()
        roomCode = nil
        isHost = false
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
        // Connect via local broadcast / Bonjour or fallback port
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

        // Set a timeout for connection
        queue.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self else { return }
            if case .connecting = self.state {
                // Connected locally or proceed as peer room
                self.state = .connected(code: code, isHost: false)
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
                    let reply = RoomPacket(type: .joinAccept, roomCode: packet.roomCode, senderId: String(self.localPlayerId), senderName: self.localPlayerName)
                    self.send(packet: reply, over: connection)
                }

            case .joinAccept:
                self.peers[packet.senderId] = OnlinePeer(id: packet.senderId, name: packet.senderName)
                self.state = .connected(code: packet.roomCode, isHost: false)
                self.onPeersUpdated?(Array(self.peers.values))

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
                } else {
                    var peer = OnlinePeer(id: packet.senderId, name: packet.senderName)
                    if let pos = packet.position { peer.position = pos }
                    self.peers[packet.senderId] = peer
                    self.onPeersUpdated?(Array(self.peers.values))
                }

            case .leave:
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

    // MARK: - Game Sync

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
