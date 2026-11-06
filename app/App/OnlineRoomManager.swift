import Foundation
import Network
import QuartzCore

/// Represents a remote player connected to the current multiplayer room.
struct OnlinePeer: Identifiable {
    let id: String
    var name: String
    var position: [Float] = [0, 0, 0]
    var heading: Float = 0
    var vehicleModel: UInt32 = 0
    var weapon: UInt32 = 0
    var health: Int = 200
    var impactSequence: UInt32?
    var impactEpoch: UInt32?
    var lastSeen: Date = Date()
}

struct OnlineGlassReport: Codable {
    let epoch: UInt32
    let mask: UInt32
}

/// Packet sent across the room network.
struct RoomPacket: Codable {
    enum PacketType: String, Codable {
        case joinRequest = "JOIN_REQ"
        case joinAccept = "JOIN_ACC"
        case joinReject = "JOIN_REJ"
        case stateSync = "STATE"
        case ping = "PING"
        case leave = "LEAVE"
        case hit = "HIT"
        case voice = "VOICE"
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
    var rideOwner: String?
    var rideSeat: Int32?
    var publicRoom: Bool?
    var pvp: Bool?
    var targetId: String?
    var damage: UInt32?
    var voiceFrame: Data?
    var impactSequence: UInt32?
    var shotSequence: UInt32?
    var vehicleEpoch: UInt32?
    var windows: UInt32?
    var glassReports: [String: OnlineGlassReport]?
}

/// Central manager for creating, joining, and synchronizing GTA V online multiplayer rooms.
final class OnlineRoomManager {
    static let shared = OnlineRoomManager()
    static let publicRoomCode = "NOVA-CITY"
    private static let publicServerID = "NOVA_SERVER"

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
    var onVehicleImpact: ((Float) -> Void)?
    var onVoiceFrame: ((String, Data) -> Void)?
    var onPeersUpdated: (([OnlinePeer]) -> Void)?

    private(set) var roomCode: String?
    private(set) var isHost = false
    private(set) var pvpEnabled = false
    private(set) var isPublicRoom = false
    private var nextHitSend: TimeInterval = 0
    private(set) var peers: [String: OnlinePeer] = [:]
    let localPlayerId = UUID().uuidString.prefix(8).uppercased()
    var localPlayerName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "onlinePlayerName") ?? ""
            let name = Self.normalizedPlayerName(saved)
            return name.isEmpty ? "Player_\(localPlayerId)" : name
        }
        set {
            UserDefaults.standard.set(Self.normalizedPlayerName(newValue), forKey: "onlinePlayerName")
        }
    }

    static func normalizedPlayerName(_ raw: String) -> String {
        let clean = raw.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result = ""
        var bytes = 0
        for character in clean.prefix(24) {
            let size = String(character).utf8.count
            guard bytes + size <= 64 else { break }
            result.append(character)
            bytes += size
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // Auto-spawn at host state
    private(set) var hasSpawnedAtHost = false
    private(set) var pendingSpawnCoords: [Float]?
    private var lastStatePushTime: TimeInterval = 0

    private var internet:NovaInternetTransport?
    private let relayBase:URL?
    init(relayBase:URL?=OnlineRoomManager.relayURL){self.relayBase=relayBase}
    static var relayURL:URL? {
        guard let text=Bundle.main.object(forInfoDictionaryKey:"NovaRelayURL") as? String,let url=URL(string:text),url.scheme=="wss" else{return nil}
        return url
    }
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    private let queue=DispatchQueue.main // NW callbacks, UI and peer state have one owner.
    private var sessionGeneration=0
    private var connectionPeers:[ObjectIdentifier:String]=[:]
    private var endpoints=Set<NWEndpoint>()
    private var hostPeerId:String?
    private var syncTimer: Timer?

    var inInternetRoom: Bool { inRoom && internet != nil }
    var relayPingMilliseconds: Int? { internet?.relayPingMilliseconds }

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
    func createRoom(advertise:Bool=true, internet useInternet:Bool=false, pvp:Bool=false) -> String {
        leaveRoom()
        var code = Self.generateRoomCode()
        while code == Self.publicRoomCode { code = Self.generateRoomCode() }
        roomCode = code
        isHost = true
        hasSpawnedAtHost = true // Host doesn't need to teleport to itself
        if useInternet {state = .connecting(code:code);startInternet(code:code,host:true,pvp:pvp);return code}
        state = .hosting(code: code)
        startListener(code:code,advertise:advertise)
        startLocalBroadcast()
        return code
    }

    // MARK: - Join Room

    /// Joins an existing room with a room code.
    func joinRoom(code rawCode:String, hostAddress:String?=nil, internet useInternet:Bool=false) {
        leaveRoom()
        let code = Self.normalizeCode(rawCode)
        guard code.count==9,code.replacingOccurrences(of:"-",with:"").utf8.allSatisfy({($0>=65 && $0<=90)||($0>=48 && $0<=57)}) else {
            state = .error("Mã phòng không hợp lệ (cần 8 ký tự, ví dụ: ABCD-1234)")
            return
        }
        roomCode = code
        isHost = false
        isPublicRoom = useInternet && code == Self.publicRoomCode
        hasSpawnedAtHost = isPublicRoom
        state = .connecting(code: code)
        if useInternet{startInternet(code:code,host:false);return}
        connectToHost(code:code,address:hostAddress)
        let generation=sessionGeneration
        queue.asyncAfter(deadline:.now()+8){[weak self] in
         guard let self,self.sessionGeneration==generation else{return}
         if case .connecting=self.state{self.leaveRoom();self.state = .error("Chưa nhận xác nhận từ máy chủ. Kiểm tra cùng Wi-Fi/IP, mã phòng và quyền Mạng cục bộ.")}
        }
    }

    // MARK: - Leave Room

    func leaveRoom() {
        sessionGeneration &+= 1
        internet?.close();internet=nil
        pvpEnabled = false
        isPublicRoom = false
        nextHitSend = 0
        PGSetOnlinePvP(false)
        PGSetOnlineSession(false)
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
        activeConnections.removeAll();connectionPeers.removeAll();endpoints.removeAll();hostPeerId=nil
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

    private func startInternet(code:String,host:Bool,pvp:Bool=false){
        guard let url=relayBase else{state = .error("Bản này chưa cấu hình relay Internet.");return}
        let transport=NovaInternetTransport();internet=transport
        let generation=sessionGeneration
        transport.onError={[weak self] message in guard let self,self.sessionGeneration==generation else{return};self.leaveRoom();self.state = .error(message)}
        transport.onPacket={[weak self] packet in guard let self,self.sessionGeneration==generation else{return};self.handleInternet(packet)}
        transport.connect(base:url,code:code,host:host,pvp:pvp,hello:RoomPacket(type:.joinRequest,roomCode:code,senderId:String(localPlayerId),senderName:localPlayerName))
    }
    private func handleInternet(_ p:RoomPacket){
        guard p.roomCode==roomCode else{return}
        if p.type == .joinAccept{
            guard case .connecting=state else{return}
            if isPublicRoom {
                guard p.publicRoom == true, p.senderId == Self.publicServerID else {
                    leaveRoom()
                    state = .error("Máy chủ chung chưa xác nhận phòng.")
                    return
                }
                state = .connected(code:p.roomCode,isHost:false)
            } else if isHost {
                guard p.senderId == String(localPlayerId) else { return }
                state = .hosting(code:p.roomCode)
            } else {
                hostPeerId = p.senderId
                var peer = OnlinePeer(id:p.senderId,name:p.senderName)
                if let position = p.position {
                    peer.position = position
                    pendingSpawnCoords = position
                }
                peers[p.senderId] = peer
                state = .connected(code:p.roomCode,isHost:false)
            }
            pvpEnabled = p.pvp == true
            PGSetOnlinePvP(pvpEnabled)
            startLocalBroadcast();onPeersUpdated?(Array(peers.values));return
        }
        guard inRoom,p.senderId != String(localPlayerId),p.senderId != Self.publicServerID else{return}
        if p.type == .voice {
            if let frame = p.voiceFrame { onVoiceFrame?(p.senderId, frame) }
            return
        }
        if p.type == .hit {
            if pvpEnabled, p.targetId == String(localPlayerId), let damage = p.damage {
                PGQueueOnlineHit(damage)
            }
            return
        }
        if p.type == .leave{
            if !isHost,p.senderId==hostPeerId{leaveRoom();state = .error("Máy chủ đã rời phòng.");return}
            peers.removeValue(forKey:p.senderId);p.senderId.withCString{PGRemoveRemotePeer($0)}
        }else if p.type == .stateSync || p.type == .ping{
            guard peers[p.senderId] != nil || peers.count<NovaRoomProtocol.maxPeers else{return}
            var peer=peers[p.senderId] ?? OnlinePeer(id:p.senderId,name:p.senderName)
            peer.name = p.senderName
            if let pos=p.position{peer.position=pos};if let h=p.heading{peer.heading=h};if let v=p.vehicleModel{peer.vehicleModel=v}
            if let w=p.weapon{peer.weapon=w};if let hp=p.health{peer.health=hp};peer.lastSeen=Date();peers[p.senderId]=peer
            if p.type == .stateSync {
                if let epoch = p.vehicleEpoch, epoch != 0, let impact = p.impactSequence {
                    if impact != 0, peer.impactEpoch == epoch, let previous = peer.impactSequence,
                       previous != impact, let position = p.position {
                        var local = [Float](repeating: 0, count: 3)
                        if PGGetPlayerPosition(&local) {
                            let dx = position[0] - local[0], dy = position[1] - local[1], dz = position[2] - local[2]
                            let distance = sqrt(dx*dx + dy*dy + dz*dz)
                            if distance < 35 { onVehicleImpact?(distance) }
                        }
                    }
                    peer.impactEpoch = epoch
                    peer.impactSequence = impact
                    peers[p.senderId] = peer
                }
                feedRemoteState(p)
                if let report = p.glassReports?[String(localPlayerId)] {
                    PGQueueOnlineGlass(report.epoch, report.mask)
                }
            }
            if !isHost,!hasSpawnedAtHost,p.senderId==hostPeerId,let pos=p.position{pendingSpawnCoords=pos}
        }
        onPeersUpdated?(Array(peers.values))
    }

    private func feedRemoteState(_ packet: RoomPacket) {
        guard let position = packet.position, position.count == 3 else { return }
        let rideOwner = packet.rideOwner.map { $0 == String(localPlayerId) ? "@local" : $0 } ?? ""
        packet.senderId.withCString { peerID in
            rideOwner.withCString { ownerID in
                PGUpdateRemotePeerState(peerID, position[0], position[1], position[2],
                                        packet.heading ?? 0, packet.vehicleModel ?? 0,
                                        packet.weapon ?? 0, ownerID, packet.rideSeat ?? -1,
                                        packet.shotSequence ?? 0, packet.vehicleEpoch ?? 0, packet.windows ?? 0)
            }
        }
    }

    // MARK: - Network Engine (Network.framework)

    private func startListener(code:String,advertise:Bool) {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true
            let listener = try NWListener(using: params, on: 47520)
            if advertise{listener.service=NWListener.Service(name:"GTAV-\(code)",type:NovaRoomProtocol.service)}
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

    private func connectToHost(code:String,address:String?){
        let generation=sessionGeneration
        if let address=address?.trimmingCharacters(in:.whitespacesAndNewlines),!address.isEmpty{
            connect(endpoint:.hostPort(host:NWEndpoint.Host(address),port:47520),code:code,generation:generation);return
        }
        let params=NWParameters.udp;params.includePeerToPeer=true
        let browser=NWBrowser(for:.bonjour(type:NovaRoomProtocol.service,domain:nil),using:params)
        browser.browseResultsChangedHandler={[weak self] results,_ in
            guard let self,self.sessionGeneration==generation else{return}
            guard case .connecting=self.state else{return}
            for result in results{
                if case .service(let name,_,_,_)=result.endpoint,name=="GTAV-"+code,!self.endpoints.contains(result.endpoint){
                    self.endpoints.insert(result.endpoint);self.connect(endpoint:result.endpoint,code:code,generation:generation)
                }
            }
        }
        browser.start(queue:queue);self.browser=browser
    }
    private func connect(endpoint:NWEndpoint,code:String,generation:Int){
        let params=NWParameters.udp;params.includePeerToPeer=true
        let connection=NWConnection(to:endpoint,using:params)
        connection.stateUpdateHandler={[weak self,weak connection] status in
            guard let self,let connection,self.sessionGeneration==generation else{return}
            if case .ready=status{self.sendJoinRequest(connection:connection,code:code);self.receive(on:connection);self.retryJoin(connection,code:code,generation:generation)}
            if case .failed=status{self.drop(connection)}
        }
        activeConnections.append(connection);connection.start(queue:queue)
    }
    private func retryJoin(_ connection:NWConnection,code:String,generation:Int){
        queue.asyncAfter(deadline:.now()+1){[weak self,weak connection] in
            guard let self,let connection,self.sessionGeneration==generation,self.activeConnections.contains(where:{$0===connection}) else{return}
            if case .connecting=self.state{self.sendJoinRequest(connection:connection,code:code);self.retryJoin(connection,code:code,generation:generation)}
        }
    }
    private func drop(_ connection:NWConnection){
        activeConnections.removeAll{$0===connection}
        if let id=connectionPeers.removeValue(forKey:ObjectIdentifier(connection)){
            peers.removeValue(forKey:id);id.withCString{PGRemoveRemotePeer($0)};onPeersUpdated?(Array(peers.values))
            if !isHost,id==hostPeerId{leaveRoom();state = .error("Đã mất kết nối máy chủ.")}
        }
        connection.cancel()
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        guard activeConnections.count<NovaRoomProtocol.maxPeers else{connection.cancel();return}
        let generation=sessionGeneration
        activeConnections.append(connection)
        connection.stateUpdateHandler={[weak self,weak connection] state in
            guard let self,let connection,self.sessionGeneration==generation else{return}
            if case .failed=state{self.drop(connection)}
        }
        connection.start(queue:queue);receive(on:connection)
        queue.asyncAfter(deadline:.now()+10){[weak self,weak connection] in
            guard let self,let connection,self.sessionGeneration==generation,self.connectionPeers[ObjectIdentifier(connection)]==nil else{return};self.drop(connection)
        }
    }

    private func sendJoinRequest(connection: NWConnection, code: String) {
        let packet = RoomPacket(type: .joinRequest, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
        send(packet: packet, over: connection)
    }

    private func receive(on connection: NWConnection) {
        let generation=sessionGeneration
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self,self.sessionGeneration==generation else{return}
            if let data=content,data.count<=NovaRoomProtocol.maxPacketBytes,let packet=try? JSONDecoder().decode(RoomPacket.self,from:data),NovaRoomProtocol.valid(packet){
                self.handlePacket(packet, from: connection)
            }
            if error==nil{self.receive(on:connection)}else{self.drop(connection)}
        }
    }

    private func handlePacket(_ packet: RoomPacket, from connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard packet.roomCode==self.roomCode,packet.senderId != String(self.localPlayerId),NovaRoomProtocol.valid(packet) else{return}
            let bound=self.connectionPeers[ObjectIdentifier(connection)]
            if packet.type == .stateSync || packet.type == .ping || packet.type == .leave{
                guard self.isHost ? bound==packet.senderId : bound==self.hostPeerId && self.hostPeerId != nil else{return}
            }

            switch packet.type {
            case .joinRequest:
                if self.isHost {
                    guard self.peers[packet.senderId] != nil || self.peers.count<NovaRoomProtocol.maxPeers else{return}
                    self.connectionPeers[ObjectIdentifier(connection)]=packet.senderId
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
                guard !self.isHost else{return}
                guard case .connecting=self.state else{return}
                self.connectionPeers[ObjectIdentifier(connection)]=packet.senderId;self.hostPeerId=packet.senderId;self.browser?.cancel();self.browser=nil
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
                if self.isHost{self.relay(packet,excluding:connection)}
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

                    self.feedRemoteState(packet)
                } else {
                    var peer = OnlinePeer(id: packet.senderId, name: packet.senderName)
                    if let pos = packet.position { peer.position = pos }
                    self.peers[packet.senderId] = peer
                    self.feedRemoteState(packet)
                    self.onPeersUpdated?(Array(self.peers.values))
                }

            case .ping:
                if var peer=self.peers[packet.senderId]{peer.lastSeen=Date();self.peers[packet.senderId]=peer}
                if self.isHost{self.relay(packet,excluding:connection)}
            case .leave:
                if self.isHost{self.relay(packet,excluding:connection)}
                if !self.isHost,packet.senderId==self.hostPeerId{self.leaveRoom();self.state = .error("Máy chủ đã rời phòng.");return}
                packet.senderId.withCString { PGRemoveRemotePeer($0) }
                self.peers.removeValue(forKey: packet.senderId)
                self.onPeersUpdated?(Array(self.peers.values))

            default: break
            }
        }
    }

    private func relay(_ packet:RoomPacket,excluding origin:NWConnection){
        for c in activeConnections where c !== origin && connectionPeers[ObjectIdentifier(c)] != nil{send(packet:packet,over:c)}
    }
    private func send(packet: RoomPacket, over connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        connection.send(content: data, completion: .idempotent)
    }

    private func broadcast(packet: RoomPacket) {
        if let internet{internet.send(packet);return}
        guard let data = try? JSONEncoder().encode(packet) else { return }
        for conn in activeConnections {
            conn.send(content: data, completion: .idempotent)
        }
    }

    private func startLocalBroadcast() {
        PGSetOnlineSession(true)
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.heartbeatTick()
        }
    }

    private func heartbeatTick() {
        guard inRoom, let code = roomCode else { return }
        internet?.sampleRelayPing()
        let expired=peers.values.filter{Date().timeIntervalSince($0.lastSeen)>15}.map{$0.id}
        for id in expired{
            peers.removeValue(forKey:id);id.withCString{PGRemoveRemotePeer($0)}
            if isHost{for c in activeConnections.filter({connectionPeers[ObjectIdentifier($0)]==id}){drop(c)}}
        }
        if !expired.isEmpty{onPeersUpdated?(Array(peers.values))}
        if !isHost,let hostPeerId,expired.contains(hostPeerId){leaveRoom();state = .error("Máy chủ không phản hồi.");return}
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
                var owner = [CChar](repeating: 0, count: 32)
                var seat: Int32 = -1
                var shot: UInt32 = 0
                var vehicle: UInt32 = 0
                var windows: UInt32 = 0
                var impact: UInt32 = 0
                let weapon = PGReadOnlineLoadout(&owner, &seat, &shot, &vehicle, &windows, &impact)
                var glassReports: [String: OnlineGlassReport] = [:]
                if inInternetRoom {
                    for peer in peers.values where peer.vehicleModel != 0 {
                        var epoch: UInt32 = 0
                        let mask = peer.id.withCString { PGReadOnlinePeerGlass($0, &epoch) }
                        if mask != 0 && epoch != 0 { glassReports[peer.id] = OnlineGlassReport(epoch: epoch, mask: mask) }
                    }
                }
                let rideOwner = owner.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                pushLocalState(position: localPos, heading: heading, vehicleModel: rideOwner.isEmpty ? hints.vehicleModel : 0,
                               weapon: weapon, health: 200, rideOwner: rideOwner.isEmpty ? nil : rideOwner,
                               rideSeat: rideOwner.isEmpty ? nil : seat,
                               shotSequence: shot, vehicleEpoch: rideOwner.isEmpty && hints.vehicleModel != 0 ? vehicle : 0,
                               windows: windows, impactSequence: impact, glassReports: glassReports)
            }
        }

        if pvpEnabled, let code = roomCode, now >= nextHitSend {
            nextHitSend = now + 0.1
            for peer in peers.values {
                let damage = peer.id.withCString { PGTakeOnlineHit($0) }
                guard damage > 0 else { continue }
                var hit = RoomPacket(type: .hit, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
                hit.targetId = peer.id
                hit.damage = damage
                broadcast(packet: hit)
                nextHitSend = now + 0.26
                break
            }
        }
    }

    func sendVoiceFrame(_ data: Data) {
        guard inInternetRoom, let code = roomCode, data.count == 1600 else { return }
        var packet = RoomPacket(type: .voice, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
        packet.voiceFrame = data
        broadcast(packet: packet)
    }

    /// Pushes local player position, vehicle, weapon to all peers in the room.
    func pushLocalState(position: [Float], heading: Float, vehicleModel: UInt32, weapon: UInt32, health: Int, rideOwner: String? = nil, rideSeat: Int32? = nil,
                        shotSequence: UInt32 = 0, vehicleEpoch: UInt32 = 0, windows: UInt32 = 0, impactSequence: UInt32 = 0,
                        glassReports: [String: OnlineGlassReport] = [:]) {
        guard inRoom, let code = roomCode else { return }
        var packet = RoomPacket(type: .stateSync, roomCode: code, senderId: String(localPlayerId), senderName: localPlayerName)
        packet.position = position
        packet.heading = heading
        packet.vehicleModel = vehicleModel
        packet.weapon = weapon
        packet.rideOwner = rideOwner
        packet.rideSeat = rideSeat
        packet.impactSequence = vehicleEpoch != 0 ? impactSequence : 0
        packet.shotSequence = shotSequence
        packet.vehicleEpoch = vehicleEpoch
        packet.windows = vehicleEpoch != 0 ? windows : 0
        if !glassReports.isEmpty { packet.glassReports = glassReports }
        packet.health = health
        broadcast(packet: packet)
    }
}
