import Foundation
/// Main-queue TLS transport, one in-flight send and one coalesced state packet.
final class NovaInternetTransport {
 var onPacket:((RoomPacket)->Void)?
 var onError:((String)->Void)?
 private var session:URLSession?,task:URLSessionWebSocketTask?
 private var generation=0,sending=false,joined=false
 private var pending:RoomPacket?
 private var pendingHit:RoomPacket?
 private var pingStartedAt: UInt64?
 private var nextPingAt: UInt64 = 0
 private(set) var relayPingMilliseconds: Int?
 func connect(base:URL,code:String,host:Bool,pvp:Bool,hello:RoomPacket){
  close();let g=generation
  var c=URLComponents(url:base.appendingPathComponent("room").appendingPathComponent(code),resolvingAgainstBaseURL:false)!
  c.queryItems=[URLQueryItem(name:"role",value:host ? "host":"guest"), URLQueryItem(name:"v",value:"3")]
  if host && pvp { c.queryItems?.append(URLQueryItem(name:"pvp",value:"1")) }
  guard let url=c.url,url.scheme=="wss" else{onError?("Relay URL invalid");return}
  let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=15;config.urlCache=nil
  let s=URLSession(configuration:config);session=s
  let t=s.webSocketTask(with:url);task=t;t.resume();receive(t,g);send(hello)
  DispatchQueue.main.asyncAfter(deadline:.now()+12){[weak self] in
   guard let self,self.generation==g,!self.joined else{return};self.fail("Relay chưa xác nhận phòng. Kiểm tra Internet hoặc thử lại.")
  }
 }
 func close(){
  generation &+= 1
  task?.cancel(with:.goingAway,reason:nil);task=nil
  session?.invalidateAndCancel();session=nil
  sending=false;pending=nil;pendingHit=nil;joined=false
  pingStartedAt = nil
  nextPingAt = 0
  relayPingMilliseconds = nil
 }

 func sampleRelayPing() {
  guard joined, let task else { return }
  let now = DispatchTime.now().uptimeNanoseconds
  if let started = pingStartedAt {
   if now - started >= 6_000_000_000 { relayPingMilliseconds = nil }
   return
  }
  guard now >= nextPingAt else { return }
  nextPingAt = now + 2_000_000_000
  pingStartedAt = now
  let currentGeneration = generation
  task.sendPing { [weak self] error in
   let elapsed = DispatchTime.now().uptimeNanoseconds - now
   DispatchQueue.main.async {
    guard let self, self.generation == currentGeneration else { return }
    self.pingStartedAt = nil
    self.relayPingMilliseconds = error == nil && elapsed < 6_000_000_000 ? Int(elapsed / 1_000_000) : nil
   }
  }
 }
 private func fail(_ message:String){let callback=onError;close();callback?(message)}
 func send(_ packet:RoomPacket){
  guard let t=task,NovaRoomProtocol.valid(packet) else{return}
  if sending {
   if packet.type == .stateSync { pending=packet }
   if packet.type == .hit, pendingHit == nil { pendingHit=packet }
   return
  }
  guard let data=try? JSONEncoder().encode(packet),data.count<=NovaRoomProtocol.maxPacketBytes,let text=String(data:data,encoding:.utf8) else{return}
  sending=true;let g=generation
  t.send(.string(text)){[weak self] error in DispatchQueue.main.async{
   guard let self,self.generation==g else{return};self.sending=false
   if error != nil{self.fail("Mất kết nối relay Internet.");return}
   if let hit=self.pendingHit { self.pendingHit=nil;self.send(hit) }
   else if let next=self.pending { self.pending=nil;self.send(next) }
  }}
 }
 private func receive(_ t:URLSessionWebSocketTask,_ g:Int){
  t.receive{[weak self] result in DispatchQueue.main.async{
   guard let self,self.generation==g else{return}
   switch result{
   case .failure:self.fail("Không kết nối được phòng. Host phải đang mở phòng và cả hai máy có Internet.")
   case .success(let message):
    let data:Data
    switch message{case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:self.fail("Gói relay không hỗ trợ.");return}
    guard data.count<=NovaRoomProtocol.maxPacketBytes,let p=try? JSONDecoder().decode(RoomPacket.self,from:data),NovaRoomProtocol.valid(p) else{self.fail("Relay gửi gói không hợp lệ.");return}
    if p.type == .joinAccept{self.joined=true};self.onPacket?(p)
    if self.generation==g{self.receive(t,g)}
   }
  }}
 }
}
