import Foundation
@main struct InternetTests {
 static func wait(_ seconds:Double,_ condition:()->Bool){let end=Date().addingTimeInterval(seconds);while !condition() && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.02))};precondition(condition(),"Internet condition timed out")}
 static func main(){
  let url=URL(string:"wss://mugoat-nova-relay.hutaolee264.workers.dev")!
  let host=OnlineRoomManager(relayBase:url),one=OnlineRoomManager(relayBase:url),two=OnlineRoomManager(relayBase:url)
  let code=host.createRoom(internet:true);wait(15){host.inRoom}
  one.joinRoom(code:code,internet:true);two.joinRoom(code:code,internet:true)
  wait(15){one.inRoom && two.inRoom}
  wait(8){host.relayPingMilliseconds != nil && one.relayPingMilliseconds != nil}
  host.pushLocalState(position:[100,200,30],heading:1,vehicleModel:0,weapon:0,health:200)
  one.pushLocalState(position:[101,200,30],heading:2,vehicleModel:0,weapon:0,health:200)
  wait(8){two.peers[String(one.localPlayerId)]?.position == [101,200,30] && one.peers[String(host.localPlayerId)]?.position == [100,200,30]}
  one.leaveRoom();wait(8){two.peers[String(one.localPlayerId)]==nil}
  one.joinRoom(code:code,internet:true);wait(15){one.inRoom}
  host.leaveRoom();wait(8){!one.inRoom && !two.inRoom}
  one.leaveRoom();two.leaveRoom()
  print("PASS: production Swift URLSession TLS relay, real host ACK, 2 guests, positions, leave/rejoin, host close. Engine calls stubbed; not iPhone gameplay test.")
 }
}
