// Nova avatar relay. No game assets, saves, credentials or chat are stored.
import {DurableObject} from "cloudflare:workers";
export function valid(p) {
 if (!p || !/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(p.roomCode) || !/^[A-Za-z0-9_-]{1,31}$/.test(p.senderId) || typeof p.senderName!=="string" || new TextEncoder().encode(p.senderName).length>64 || /[\x00-\x1f]/.test(p.senderName)) return false;
 if (!["JOIN_REQ","STATE","PING","LEAVE","HIT","VOICE"].includes(p.type)) return false;
 if (p.type==="STATE" && !p.position) return false;
 if (p.type==="VOICE" && (typeof p.voiceFrame!=="string" || !/^[A-Za-z0-9+/]{2134}==$/.test(p.voiceFrame))) return false;
 if (p.rideOwner !== undefined) {
  if (p.type !== "STATE" || typeof p.rideOwner !== "string" || p.rideOwner === p.senderId ||
      !/^[A-Za-z0-9_-]{1,31}$/.test(p.rideOwner) || p.vehicleModel !== 0 ||
      !Number.isInteger(p.rideSeat) || p.rideSeat < 0 || p.rideSeat > 7) return false;
 } else if (p.rideSeat !== undefined) return false;
 if (p.type==="HIT" && (typeof p.targetId!=="string" || !/^[A-Za-z0-9_-]{1,31}$/.test(p.targetId) ||
     p.targetId===p.senderId || !Number.isInteger(p.damage) || p.damage<1 || p.damage>30)) return false;
 if(p.position && (!Array.isArray(p.position)||p.position.length!==3||!p.position.every(v=>Number.isFinite(v)&&Math.abs(v)<=100000))) return false;
 if(p.heading!==undefined && (!Number.isFinite(p.heading)||Math.abs(p.heading)>100000))return false;
 for(const k of ["vehicleModel","weapon","vehicleEpoch","shotSequence","impactSequence"])if(p[k]!==undefined && (!Number.isInteger(p[k])||p[k]<0||p[k]>4294967295))return false;
 if (p.windows!==undefined && (!Number.isInteger(p.windows) || p.windows<0 || p.windows>15)) return false;
 if (p.glassReports!==undefined) {
  if (p.type!=="STATE" || !p.glassReports || typeof p.glassReports!=="object" || Array.isArray(p.glassReports)) return false;
  const reports=Object.entries(p.glassReports);
  if (reports.length>15 || reports.some(([id,report])=>id===p.senderId || !/^[A-Za-z0-9_-]{1,31}$/.test(id) ||
      !report || !Number.isInteger(report.epoch) || report.epoch<1 || report.epoch>4294967295 ||
      !Number.isInteger(report.mask) || report.mask<1 || report.mask>15)) return false;
 }
 if(p.health!==undefined && (!Number.isInteger(p.health)||Math.abs(p.health)>100000))return false;
 return true;
}
export default {async fetch(req,env){
 const url=new URL(req.url);
 if(url.pathname==="/health")return Response.json({service:"nova-avatar-relay",version:1});
 const m=/^\/room\/([A-Z0-9]{4}-[A-Z0-9]{4})$/.exec(url.pathname);
 if(!m)return new Response("Not found",{status:404});
 if(req.headers.get("Upgrade")?.toLowerCase()!=="websocket")return new Response("WebSocket required",{status:426});
 return env.ROOMS.get(env.ROOMS.idFromName(m[1])).fetch(req);
}};
const PUBLIC_ROOM = "NOVA-CITY";
const PUBLIC_SERVER_ID = "NOVA_SERVER";

export class NovaRoom extends DurableObject {
 constructor(ctx,env){super(ctx,env);this.ctx=ctx;ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("keepalive","alive"));}
 sockets(){return this.ctx.getWebSockets().filter(s=>s.deserializeAttachment()?.id);}
 host(){return this.sockets().find(s=>s.deserializeAttachment().host);}
 send(s,p){try{s.send(JSON.stringify(p));}catch{try{s.close(1011,"Connection lost");}catch{}}}
 async fetch(req){
  if(this.ctx.getWebSockets().length>=16)return new Response("Room full",{status:429});
  const url=new URL(req.url),host=url.searchParams.get("role")==="host",code=url.pathname.split("/").pop();
  const publicRoom = code === PUBLIC_ROOM;
  const protocol = url.searchParams.get("v");
  if (publicRoom && host) return new Response("Public room is server-managed",{status:403});
  if (publicRoom && protocol !== "4" && protocol !== "5") return new Response("Update Nova to join the public room",{status:426});
  if(host && this.ctx.getWebSockets().some(s=>s.deserializeAttachment()?.host))return new Response("Room already exists",{status:409});
  if(!publicRoom && !host && !this.host())return new Response("Host not present",{status:404});
  const supportsPvP = protocol === "3" || protocol === "4" || protocol === "5";
  const pvp = publicRoom || (host && supportsPvP && url.searchParams.get("pvp")==="1");
  if (!host && this.host()?.deserializeAttachment().pvp && !supportsPvP) {
   return new Response("Nova update required for PvP rooms",{status:426});
  }
  const pair=new WebSocketPair(),[client,server]=Object.values(pair);
  this.ctx.acceptWebSocket(server);server.serializeAttachment({host,code,pvp,publicRoom,voice:protocol==="5",opened:Date.now(),bucket:Date.now(),count:0});
  await this.ctx.storage.setAlarm(Date.now()+30000);
  return new Response(null,{status:101,webSocket:client});
 }
 async webSocketMessage(ws,message){
  if(typeof message!=="string" || new TextEncoder().encode(message).length>8192){ws.close(1009,"Packet too large");return;}
  const a=ws.deserializeAttachment(),now=Date.now();if(!a)return;
  if(now-a.bucket>=1000){a.bucket=now;a.count=0;}
  if(++a.count>25){ws.close(1008,"Rate limit");return;}
  let p;try{p=JSON.parse(message);}catch{ws.close(1008,"Invalid JSON");return;}
  if(!valid(p)||p.roomCode!==a.code || (a.id && p.senderId!==a.id)){ws.close(1008,"Invalid packet");return;}
  if(!a.id){
   if(p.type!=="JOIN_REQ"||p.senderId===PUBLIC_SERVER_ID||this.sockets().some(s=>s.deserializeAttachment().id===p.senderId)){ws.close(1008,"Invalid join");return;}
   a.id=p.senderId;a.name=p.senderName;a.seen=now;ws.serializeAttachment(a);
   if (a.publicRoom) {
    this.send(ws,{type:"JOIN_ACC",roomCode:a.code,senderId:PUBLIC_SERVER_ID,senderName:"Nova City",publicRoom:true,pvp:true});
    for (const other of this.sockets()) {
     if (other === ws) continue;
     const peer = other.deserializeAttachment();
     this.send(ws,{type:"PING",roomCode:a.code,senderId:peer.id,senderName:peer.name});
     this.send(other,{type:"PING",roomCode:a.code,senderId:a.id,senderName:a.name});
    }
    return;
   }
   const host=this.host();if(!host){ws.close(1008,"Host not present");return;}
   const ha=host.deserializeAttachment();
   this.send(ws,{type:"JOIN_ACC",roomCode:a.code,senderId:ha.id,senderName:ha.name,pvp:ha.pvp===true,...(ha.state||{})});
   return;
  }
  a.seen=now;
  a.name=p.senderName;
  if (p.type === "STATE" && p.rideOwner) {
   const owner = this.sockets().find(socket=>socket.deserializeAttachment().id===p.rideOwner)?.deserializeAttachment();
   const ownerPosition = owner?.state?.position;
   if (!owner?.state?.vehicleModel || !ownerPosition ||
       Math.hypot(...p.position.map((value,index)=>value-ownerPosition[index])) > 35) {
    p = {...p};
    delete p.rideOwner;
    delete p.rideSeat;
   }
  }
  if (p.type==="STATE" && p.glassReports) {
   const accepted=Object.create(null);
   for (const socket of this.sockets()) {
    const peer=socket.deserializeAttachment();
    const report=Object.hasOwn(p.glassReports,peer.id) ? p.glassReports[peer.id] : null;
    if (!report || !peer.state?.vehicleModel || peer.state.vehicleEpoch!==report.epoch || !peer.state.position) continue;
    if (Math.hypot(...p.position.map((value,index)=>value-peer.state.position[index]))<=100) accepted[peer.id]=report;
   }
   p.glassReports=accepted;
  }
  if(p.type==="STATE")a.state={position:p.position,heading:p.heading,vehicleModel:p.vehicleModel,
                              weapon:p.weapon,health:p.health,vehicleEpoch:p.vehicleEpoch,windows:p.windows};
  ws.serializeAttachment(a);
  if(p.type==="LEAVE"){await this.remove(ws);ws.close(1000,"Left room");return;}
  if (p.type==="VOICE") {
   if (!a.voice || !a.state?.position || (a.lastVoice && now-a.lastVoice<65)) return;
   a.lastVoice=now;
   ws.serializeAttachment(a);
   for (const socket of this.sockets()) {
    if (socket===ws) continue;
    const peer=socket.deserializeAttachment();
    if (!peer.voice || !peer.state?.position) continue;
    if (Math.hypot(...a.state.position.map((value,index)=>value-peer.state.position[index]))>60) continue;
    this.send(socket,{type:"VOICE",roomCode:a.code,senderId:a.id,senderName:a.name,voiceFrame:p.voiceFrame});
   }
   return;
  }
  if (p.type==="HIT") {
   const host = this.host()?.deserializeAttachment();
   if (!(a.publicRoom || host?.pvp) || !a.state?.position || (a.lastHit && now-a.lastHit<200)) return;
   const victim = this.sockets().find(socket=>socket.deserializeAttachment().id===p.targetId);
   const victimPosition = victim?.deserializeAttachment()?.state?.position;
   if (!victimPosition) return;
   const distance = Math.hypot(...a.state.position.map((value,index)=>value-victimPosition[index]));
   if (distance>120) return;
   a.lastHit=now;
   ws.serializeAttachment(a);
   this.send(victim,{type:"HIT",roomCode:a.code,senderId:a.id,senderName:a.name,targetId:p.targetId,damage:p.damage});
   return;
  }
  if(p.type!=="STATE" && p.type!=="PING")return;
  for(const other of this.sockets())if(other!==ws)this.send(other,p);
 }
 async remove(ws){
  const a=ws.deserializeAttachment();if(!a?.id)return;
  ws.serializeAttachment({...a,id:null});
  for(const s of this.sockets()){
   this.send(s,{type:"LEAVE",roomCode:a.code,senderId:a.id,senderName:a.name});
   if(a.host){s.serializeAttachment({...s.deserializeAttachment(),id:null});try{s.close(1000,"Host left");}catch{}}
  }
 }
 async webSocketClose(ws){await this.remove(ws);try{ws.close(1000,"Closed");}catch{}}
 async webSocketError(ws){await this.remove(ws);try{ws.close(1011,"Network error");}catch{}}
 async alarm(){
  const now=Date.now();
  for(const s of this.ctx.getWebSockets()){
   const a=s.deserializeAttachment();if(now-(a?.seen||a?.opened||0)>45000){await this.remove(s);try{s.close(1000,"Idle timeout");}catch{}}
  }
  if(this.ctx.getWebSockets().length)await this.ctx.storage.setAlarm(now+30000);
 }
}
