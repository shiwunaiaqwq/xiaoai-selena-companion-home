import fs from 'node:fs';import path from 'node:path';import net from 'node:net';import {randomBytes,timingSafeEqual} from 'node:crypto';import {DatabaseSync} from 'node:sqlite';import {fileURLToPath} from 'node:url';
import {validateLayout,layoutVersion} from './mapping.mjs';
import {displayState,presentationMode,validatePresentation} from './presentation.mjs';
import {StringDecoder} from 'node:string_decoder';
import {HomePanels} from './panels.mjs';
const HERE=path.dirname(fileURLToPath(import.meta.url));
const ED=path.resolve(process.env.COMPANION_GAME_DIR || path.join(HERE,'../character-edition'));
const DATA=path.join(ED,'data-astrbot-live');
const DB=path.resolve(process.env.COMPANION_HOME_DB || path.join(HERE,'../runtime/home/home.sqlite3'));
const statusFile=path.join(DATA,'connection-status.json'),discovery=path.join(DATA,'world/game-link.json');
const panels=new HomePanels(path.dirname(DB));
fs.mkdirSync(path.dirname(discovery),{recursive:true});
const alive=port=>new Promise(resolve=>{const s=net.connect({host:'127.0.0.1',port});s.setTimeout(700);s.once('connect',()=>{s.destroy();resolve(true)});s.once('error',()=>resolve(false));s.once('timeout',()=>{s.destroy();resolve(false)});});
if(fs.existsSync(discovery)){let old;try{old=JSON.parse(fs.readFileSync(discovery,'utf8'));}catch{}if(old?.port&&await alive(old.port)){console.log('AstrBot display bridge is already running.');process.exit(0);}fs.unlinkSync(discovery);}
const db=new DatabaseSync(DB,{readOnly:true});db.exec('PRAGMA query_only=ON');
const residents=db.prepare('SELECT character,state,heartbeat FROM residents WHERE character IN (?,?)');
const homes=db.prepare('SELECT character,data FROM household WHERE character IN (?,?)');
const world=JSON.parse(fs.readFileSync(path.join(ED,'game/assets/world.json'),'utf8').replace(/^\uFEFF/,''));
const layoutValidation=validateLayout(world);
const presentationValidation=validatePresentation(world);
let socket=null,cycles=0,lastSync=0,lastError='',presence={},source=[],positions={},gameHello=null,lastHeard=0;
const token=randomBytes(32).toString('hex');
const send=frame=>{if(socket&&!socket.destroyed)socket.write(JSON.stringify(frame)+'\n');};
function saveStatus(){const safe={service:'astrbot-existing-home-display',pid:process.pid,database:DB,readOnly:true,gameConnected:!!socket,gameOwnsLife:false,homePanels:'home-features/1',panelStatus:panels.status,layoutVersion,layoutValidation,presentationMode,presentationValidation,lastSync,cycles,lastError,source,positions,gameCapabilities:gameHello?{game:gameHello.game,residents:gameHello.residents}:null};try{fs.writeFileSync(statusFile+'.tmp',JSON.stringify(safe,null,2));fs.renameSync(statusFile+'.tmp',statusFile);}catch(error){if(!['EBUSY','EPERM','EACCES'].includes(error.code))throw error;/* A Windows reader may briefly block replacement; the next refresh retries. */}}
function refresh(){
 try{
  const now=Date.now(),homeBy={};db.exec('BEGIN');let rows;
  try{rows=residents.all('xiaoai','selena');for(const h of homes.all('xiaoai','selena'))homeBy[h.character]=JSON.parse(h.data);}finally{db.exec('ROLLBACK');}
  if(rows.length!==2)throw Error('Both original resident rows are required');
  const next={};source=[];
  for(const r of rows){const state=JSON.parse(r.state),fresh=now-Date.parse(r.heartbeat)<180000;
   const mapped=displayState(r.character,state,homeBy[r.character]||{},now);
   if(mapped.supported&&!world.scenes[mapped.sceneId]?.zones[mapped.zone])throw Error('Invalid display mapping');
   source.push({actor:r.character,heartbeat:r.heartbeat,fresh,revision:state.revision,room:state.room,canonicalRoom:mapped.canonicalRoom,mappedScene:mapped.sceneId,mappedZone:mapped.zone,supported:mapped.supported,displayAction:mapped.action,displaySleeping:mapped.sleeping,presentationMode:mapped.presentationMode});
   if(!mapped.supported){if(presence[r.character])next[r.character]={...presence[r.character],label:mapped.place};continue;}
   next[r.character]=!fresh&&presence[r.character]?{...presence[r.character],label:'AstrBot 心跳过期，保留上次状态'}:mapped;
  }
  presence=next;lastSync=now;cycles++;lastError='';
  send({type:'clock',now});send({type:'world',presence});
 }catch(error){lastError=error.message;}
 saveStatus();
}
refresh();
const saveDir=path.join(DATA,'saves');fs.mkdirSync(saveDir,{recursive:true});
const residentsSave=path.join(saveDir,'residents.json');
if(!fs.existsSync(residentsSave)&&Object.keys(presence).length===2){const people={};for(const [actor,p]of Object.entries(presence)){const scene=world.scenes[p.sceneId],point=scene.zones[p.zone];people[actor]={scene:p.sceneId,want_scene:p.sceneId,want_zone:p.zone,x:point.x,y:point.y,next:'',layout_revision:scene.layoutRevision||''};}fs.writeFileSync(residentsSave,JSON.stringify({version:1,people,seats:{}}));}
const server=net.createServer(peer=>{
 let buffer='',authed=false;const decoder=new StringDecoder('utf8');const deadline=setTimeout(()=>peer.destroy(),4000);
 peer.on('error',()=>{});
 peer.on('close',()=>{clearTimeout(deadline);if(socket===peer){socket=null;saveStatus();}});
 peer.on('data',chunk=>{
  buffer+=decoder.write(chunk);if(Buffer.byteLength(buffer)>1048576){peer.destroy();return;}
  for(;;){const e=buffer.indexOf('\n');if(e<0)break;const line=buffer.slice(0,e);buffer=buffer.slice(e+1);let f;try{f=JSON.parse(line);}catch{peer.destroy();return;}
   if(!authed){const a=Buffer.from(String(f.token||'')),b=Buffer.from(token);if(f.type!=='hello'||a.length!==b.length||!timingSafeEqual(a,b)||socket){peer.destroy();return;}
    authed=true;clearTimeout(deadline);socket=peer;lastHeard=Date.now();gameHello={game:f.game,residents:f.residents};
    send({type:'welcome',residents:false,social:0,bodySave:0,host:{name:'AstrBot · 原小屋',audioSettings:false}});refresh();console.log('Game connected; both original AstrBot residents synchronized.');continue;
   }
   lastHeard=Date.now();
   if(f.type==='ping')send({type:'pong'});
   else if(f.type==='walk.position')positions[f.actor]={scene:f.scene,zone:f.zone,walking:f.walking,targetScene:f.targetScene,targetZone:f.targetZone,at:Date.now()};
   else if(f.type==='panel.get'||f.type==='panel.do'){
    const reading=f.type==='panel.get';
    Promise.resolve().then(()=>reading?panels.get(f):panels.do(f)).then(result=>{
     if(socket===peer&&!peer.destroyed)peer.write(JSON.stringify({...result,type:reading?'panel.data':'panel.did',id:f.id,panel:f.panel,action:f.action,who:f.who,day:f.day})+'\n');
    }).catch(error=>{
     const message=/[\u4e00-\u9fff]/.test(String(error.message||''))?String(error.message).slice(0,120):'小屋连接或操作暂未完成，请稍后刷新';
     if(socket===peer&&!peer.destroyed)peer.write(JSON.stringify({type:reading?'panel.data':'panel.did',id:f.id,panel:f.panel,action:f.action,who:f.who,day:f.day,ok:false,error:message})+'\n');
    });
   }
  }
 });
});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
fs.writeFileSync(discovery,JSON.stringify({port:server.address().port,token,at:Date.now()})+'\n',{flag:'wx',mode:0o600});
const showRequest=path.join(DATA,'show-window.request');
const restartRequest=path.join(DATA,'restart-game.request');
const timer=setInterval(()=>{if(socket&&Date.now()-lastHeard>15000)socket.destroy();if(socket&&fs.existsSync(restartRequest)){fs.unlinkSync(restartRequest);send({type:'quit'});}if(socket&&fs.existsSync(showRequest)){fs.unlinkSync(showRequest);send({type:'window.show'});}refresh();},2000);
function shutdown(){clearInterval(timer);socket?.destroy();server.close();try{if(JSON.parse(fs.readFileSync(discovery,'utf8')).token===token)fs.unlinkSync(discovery);}catch{}db.close();process.exit(0);}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
console.log('Read-only AstrBot display bridge ready; original planners remain authoritative.');saveStatus();
