// Nova avatar relay. No game assets, saves, credentials or chat are stored.
import {DurableObject} from "cloudflare:workers";
export function valid(p) {
 if (!p || !/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(p.roomCode) || !/^[A-Za-z0-9_-]{1,31}$/.test(p.senderId) || typeof p.senderName!=="string" || new TextEncoder().encode(p.senderName).length>64 || /[\x00-\x1f]/.test(p.senderName)) return false;
 if (!["JOIN_REQ","STATE","PING","LEAVE"].includes(p.type)) return false;
 if (p.type==="STATE" && !p.position) return false;
 if(p.position && (!Array.isArray(p.position)||p.position.length!==3||!p.position.every(v=>Number.isFinite(v)&&Math.abs(v)<=100000))) return false;
 if(p.heading!==undefined && (!Number.isFinite(p.heading)||Math.abs(p.heading)>100000))return false;
 for(const k of ["vehicleModel","weapon"])if(p[k]!==undefined && (!Number.isInteger(p[k])||p[k]<0||p[k]>4294967295))return false;
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
export class NovaRoom extends DurableObject {
 constructor(ctx,env){super(ctx,env);this.ctx=ctx;ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("keepalive","alive"));}
 sockets(){return this.ctx.getWebSockets().filter(s=>s.deserializeAttachment()?.id);}
 host(){return this.sockets().find(s=>s.deserializeAttachment().host);}
 send(s,p){try{s.send(JSON.stringify(p));}catch{try{s.close(1011,"Connection lost");}catch{}}}
 async fetch(req){
  if(this.ctx.getWebSockets().length>=16)return new Response("Room full",{status:429});
  const url=new URL(req.url),host=url.searchParams.get("role")==="host",code=url.pathname.split("/").pop();
  if(host && this.ctx.getWebSockets().some(s=>s.deserializeAttachment()?.host))return new Response("Room already exists",{status:409});
  if(!host && !this.host())return new Response("Host not present",{status:404});
  const pair=new WebSocketPair(),[client,server]=Object.values(pair);
  this.ctx.acceptWebSocket(server);server.serializeAttachment({host,code,opened:Date.now(),bucket:Date.now(),count:0});
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
   if(p.type!=="JOIN_REQ"||this.sockets().some(s=>s.deserializeAttachment().id===p.senderId)){ws.close(1008,"Invalid join");return;}
   a.id=p.senderId;a.name=p.senderName;a.seen=now;ws.serializeAttachment(a);
   const host=this.host();if(!host){ws.close(1008,"Host not present");return;}
   const ha=host.deserializeAttachment();
   this.send(ws,{type:"JOIN_ACC",roomCode:a.code,senderId:ha.id,senderName:ha.name,...(ha.state||{})});
   return;
  }
  a.seen=now;
  if(p.type==="STATE")a.state={position:p.position,heading:p.heading,vehicleModel:p.vehicleModel,weapon:p.weapon,health:p.health};
  ws.serializeAttachment(a);
  if(p.type==="LEAVE"){await this.remove(ws);ws.close(1000,"Left room");return;}
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
