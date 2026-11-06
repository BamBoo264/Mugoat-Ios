import Foundation
/// Nova LAN wire validation; not the native macport session protocol used by GTAV-v10.1.
enum NovaRoomProtocol {
 static let service="_novamp._udp",maxPacketBytes=8192,maxPeers=16
 static func valid(_ packet:RoomPacket)->Bool{
  let code=packet.roomCode.replacingOccurrences(of:"-",with:"")
  guard code.count==8,code.utf8.allSatisfy({($0>=65 && $0<=90)||($0>=48 && $0<=57)}),!packet.senderId.isEmpty,packet.senderId.utf8.count<=31,packet.senderName.utf8.count<=64 else{return false}
  guard packet.senderId.utf8.allSatisfy({($0>=65 && $0<=90)||($0>=97 && $0<=122)||($0>=48 && $0<=57)||$0==45||$0==95}),packet.senderName.unicodeScalars.allSatisfy({$0.value>=32}) else{return false}
  if packet.type == .stateSync && packet.position==nil{return false}
  if let p=packet.position{guard p.count==3,p.allSatisfy({$0.isFinite && abs($0)<=100000}) else{return false}}
  if let h=packet.heading,(!h.isFinite || abs(h)>100000){return false}
  if let owner = packet.rideOwner {
   guard packet.type == .stateSync, owner != packet.senderId, !owner.isEmpty, owner.utf8.count <= 31,
         owner.utf8.allSatisfy({($0>=65 && $0<=90)||($0>=97 && $0<=122)||($0>=48 && $0<=57)||$0==45||$0==95}),
         packet.vehicleModel == 0, let seat = packet.rideSeat, (0...7).contains(seat) else { return false }
  } else if packet.rideSeat != nil { return false }
  if let windows = packet.windows, windows > 15 { return false }
  if let reports = packet.glassReports {
   guard packet.type == .stateSync, reports.count <= 15,
         reports.allSatisfy({ $0.key != packet.senderId && $0.key.utf8.count <= 31 && !$0.key.isEmpty &&
                              $0.value.epoch != 0 && (1...15).contains($0.value.mask) }) else { return false }
  }
  if packet.type == .voice && packet.voiceFrame?.count != 1600 { return false }
  if packet.type == .hit {
   guard let target=packet.targetId, target != packet.senderId,
         !target.isEmpty, target.utf8.count<=31, let damage=packet.damage, (1...30).contains(damage) else {return false}
  }
  return true
 }
}
