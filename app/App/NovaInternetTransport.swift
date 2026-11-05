import Foundation
/// Main-queue TLS transport, one in-flight send and one coalesced state packet.
final class NovaInternetTransport {
 var onPacket:((RoomPacket)->Void)?
 var onError:((String)->Void)?
 private var session:URLSession?,task:URLSessionWebSocketTask?
 private var generation=0,sending=false,joined=false
 private var pending:RoomPacket?
 func connect(base:URL,code:String,host:Bool,hello:RoomPacket){
  close();let g=generation
  var c=URLComponents(url:base.appendingPathComponent("room").appendingPathComponent(code),resolvingAgainstBaseURL:false)!
  c.queryItems=[URLQueryItem(name:"role",value:host ? "host":"guest")]
  guard let url=c.url,url.scheme=="wss" else{onError?("Relay URL invalid");return}
  let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=15;config.urlCache=nil
  let s=URLSession(configuration:config);session=s
  let t=s.webSocketTask(with:url);task=t;t.resume();receive(t,g);send(hello)
  DispatchQueue.main.asyncAfter(deadline:.now()+12){[weak self] in
   guard let self,self.generation==g,!self.joined else{return};self.fail("Relay chưa xác nhận phòng. Kiểm tra Internet hoặc thử lại.")
  }
 }
 func close(){generation &+= 1;task?.cancel(with:.goingAway,reason:nil);task=nil;session?.invalidateAndCancel();session=nil;sending=false;pending=nil;joined=false}
 private func fail(_ message:String){let callback=onError;close();callback?(message)}
 func send(_ packet:RoomPacket){
  guard let t=task,NovaRoomProtocol.valid(packet) else{return}
  if sending{if packet.type == .stateSync{pending=packet};return}
  guard let data=try? JSONEncoder().encode(packet),data.count<=NovaRoomProtocol.maxPacketBytes,let text=String(data:data,encoding:.utf8) else{return}
  sending=true;let g=generation
  t.send(.string(text)){[weak self] error in DispatchQueue.main.async{
   guard let self,self.generation==g else{return};self.sending=false
   if error != nil{self.fail("Mất kết nối relay Internet.");return}
   if let next=self.pending{self.pending=nil;self.send(next)}
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
