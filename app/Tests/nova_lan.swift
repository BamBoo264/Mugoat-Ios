import Foundation
@main struct LANTests {
 static func wait(_ seconds:Double,_ condition:()->Bool){
  let end=Date().addingTimeInterval(seconds)
  while !condition() && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
  precondition(condition(),"Network condition timed out")
 }
 static func main(){
  let host=OnlineRoomManager(),one=OnlineRoomManager(),two=OnlineRoomManager(),wrong=OnlineRoomManager()
  let code=host.createRoom(advertise:false)
  one.joinRoom(code:code,hostAddress:"127.0.0.1");two.joinRoom(code:code,hostAddress:"127.0.0.1")
  wait(6){one.inRoom && two.inRoom && host.peers.count==2}
  one.pushLocalState(position:[10,20,30],heading:45,vehicleModel:0,weapon:0,health:200)
  wait(3){two.peers[String(one.localPlayerId)]?.position == [10,20,30]}
  wrong.joinRoom(code:code=="AAAA-BBBB" ? "AAAA-CCCC":"AAAA-BBBB",hostAddress:"127.0.0.1")
  wait(10){if case .error=wrong.state{return true};return false}
  precondition(!wrong.inRoom,"Missing ACK incorrectly reported connected")
  var bad=RoomPacket(type:.stateSync,roomCode:code,senderId:"peer",senderName:"test");bad.position=[1]
  precondition(!NovaRoomProtocol.valid(bad));bad.position=[1,2,.infinity];precondition(!NovaRoomProtocol.valid(bad));bad.position=[1,2,3];precondition(NovaRoomProtocol.valid(bad))
  one.leaveRoom();two.leaveRoom();host.leaveRoom();wrong.leaveRoom()
  precondition(host.peers.isEmpty && !one.inRoom && !two.inRoom)
  print("PASS: real Network.framework UDP loopback, two clients, host relay, wrong-code ACK timeout, malformed vectors, teardown; engine visuals stubbed, device test still required")
 }
}
