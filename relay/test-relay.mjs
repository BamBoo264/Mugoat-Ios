import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
const base=process.argv[2]||'ws://127.0.0.1:8787';
const code=randomBytes(4).toString('hex').toUpperCase().replace(/(.{4})/,'$1-');
const all=[];
function open(role,id,c=code){return new Promise((resolve,reject)=>{
 const ws=new WebSocket(`${base}/room/${c}?role=${role}`);all.push(ws);ws.packets=[];
 ws.addEventListener('message',e=>ws.packets.push(JSON.parse(e.data)));
 ws.addEventListener('error',()=>reject(new Error('Handshake rejected')),{once:true});
 ws.addEventListener('open',()=>{ws.send(JSON.stringify({type:'JOIN_REQ',roomCode:c,senderId:id,senderName:id}));resolve(ws)},{once:true});
 setTimeout(()=>reject(new Error('Open timeout')),6000).unref();
})}
async function wait(fn){for(let i=0;i<120;i++){if(fn())return;await new Promise(r=>setTimeout(r,25));}assert.fail('Packet timeout')}
const packet=(id,type='STATE',extra={})=>({type,roomCode:code,senderId:id,senderName:id,position:[10,20,30],heading:45,...extra});
try{
 await assert.rejects(open('guest','NOHOST'));
 const host=await open('host','HOST');await wait(()=>host.packets.some(p=>p.type==='JOIN_ACC'));
 await assert.rejects(open('host','TAKEOVER'));
 host.send(JSON.stringify(packet('HOST')));
 const one=await open('guest','ONE'),two=await open('guest','TWO');
 await wait(()=>one.packets.some(p=>p.type==='JOIN_ACC' && p.senderId==='HOST')&&two.packets.some(p=>p.type==='JOIN_ACC'));
 one.send(JSON.stringify(packet('ONE')));await wait(()=>two.packets.some(p=>p.type==='STATE'&&p.senderId==='ONE'));
 const bad=await open('guest','BAD');await wait(()=>bad.packets.length);
 let closed=false;bad.addEventListener('close',()=>closed=true);bad.send(JSON.stringify(packet('HOST')));
 await wait(()=>closed);assert(!two.packets.some(p=>p.type==='STATE'&&p.senderId==='HOST'&&p.senderName==='BAD'));
 const malformed=await open('guest','MALFORMED');await wait(()=>malformed.packets.length);let invalidClosed=false;malformed.addEventListener('close',()=>invalidClosed=true);
 malformed.send(JSON.stringify(packet('MALFORMED','STATE',{position:[1]})));await wait(()=>invalidClosed);
 one.close();await wait(()=>two.packets.some(p=>p.type==='LEAVE'&&p.senderId==='ONE'));
 const rejoin=await open('guest','ONE');await wait(()=>rejoin.packets.some(p=>p.type==='JOIN_ACC'));
 host.close();await wait(()=>two.packets.some(p=>p.type==='LEAVE'&&p.senderId==='HOST'));
 console.log('PASS: no-host rejection, host collision, 2 guests ACK, state relay, spoof/malformed rejection, leave, reconnect, host shutdown');
}finally{for(const ws of all)try{ws.close()}catch{}}
