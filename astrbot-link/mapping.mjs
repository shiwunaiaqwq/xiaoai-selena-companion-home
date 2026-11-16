import fs from 'node:fs';
import {fileURLToPath} from 'node:url';

export const layout=JSON.parse(fs.readFileSync(fileURLToPath(new URL('./cabin_layout.json',import.meta.url)),'utf8'));
export const layoutVersion=layout.version;
const catalogue=JSON.parse(fs.readFileSync(fileURLToPath(new URL('./activity_catalog.json',import.meta.url)),'utf8'));
export const activityVersion=catalogue.version;
export const ROOMS=Object.fromEntries([...Object.entries(layout.legacy_names),...layout.rooms.map(r=>[r.id,r.name])]);
const U='shared-home-upstairs';
export function roomsFor(actor){return layout.rooms.filter(r=>(r.characters||layout.characters).includes(actor));}
export function canonicalRoom(actor,room,activity=''){
 const aliases={...layout.aliases.common,...layout.aliases[actor]};room=aliases[room]||room;
 if(room==='kitchen'&&/吃|用餐|早餐|午餐|晚餐|早饭|午饭|晚饭/.test(activity)&&!/准备|做饭|做菜|烹|煮|泡|冲|洗菜|备餐|备菜|烘|收拾|清洗/.test(activity))return 'dining';
 return room;
}
function sleepInfo(actor,state,house,now){
 const local=new Date(now+8*3600000),minute=local.getUTCHours()*60+local.getUTCMinutes();
 const night=minute<(layout.daily_rhythm?.wake_minutes?.[actor]??420);
 const ownerActive=now/1000-Number(house.owner_last||0)<600;
 const awake=Object.values(house.wakes||{}).some(expiry=>Number(expiry)>now/1000);
 return {night,ownerActive,awake,sleep:night&&!ownerActive&&!state.together&&!awake};
}
export function sleeping(state,house={},now=Date.now(),actor='selena'){return sleepInfo(actor,state,house,now).sleep;}
function valueFor(value,actor){return typeof value==='string'?value:value[actor];}
export function mapState(actor,state,house={},now=Date.now()){
 if(!layout.characters.includes(actor))throw Error('Unknown resident');
 const activity=String(state.activity||'').slice(0,160),detail=String(state.detail||'').slice(0,250);
 const sleep=sleepInfo(actor,state,house,now);
 const room=sleep.sleep?'bedroom':canonicalRoom(actor,String(state.room||''),activity);
 const row=roomsFor(actor).find(r=>r.id===room);
 const base={name:actor==='xiaoai'?'小爱':'赛琳娜',label:activity,action:'',sleeping:sleep.sleep,outfit:'',travel:null,at:now,sourceRoom:state.room,sourceRevision:state.revision??null,canonicalRoom:room,layoutVersion,supported:!!row};
 if(!row)return {...base,sceneId:null,zone:null,place:(ROOMS[room]||room||'待同步')+'（地图暂无此处，保留上次画面）'};
 const card=catalogue.activities.find(a=>a.id===state.interaction_id&&a.room===room&&a.characters.includes(actor));
 if(card&&!sleep.sleep&&card.id!=='sleep')return {...base,sceneId:row.scene,zone:valueFor(card.zone,actor),action:valueFor(card.action,actor),sleeping:false,interactionId:card.id,place:(row.names?.[actor]||row.name)+(row.floor==='outside'?'':' · '+(row.floor==='1F'?'一楼':'二楼'))};
 let scene=row.scene,zone=valueFor(row.zone,actor),action='';
 if(sleep.sleep)zone=actor+'_bed';
 else switch(room){
 case 'singing':if(/回放|录音|试听/.test(activity)){action='life_listen';zone='xiaoai_lyrics';}else if(/整理|标记|修改|歌词|曲谱/.test(activity)){action='life_write';zone='xiaoai_lyrics';}else if(/唱|练歌|歌唱|试唱/.test(activity)){zone='xiaoai_sing';action='music_sing';}break;
 case 'music':if(/回放|录音|试听/.test(activity)){action='life_listen';zone='selena_score_work';}else if(/整理.*小提琴|摆放.*小提琴|器乐|展柜/.test(activity)){action='life_select';zone='selena_violin';}else if(/整理|修改|标记|乐谱/.test(activity)){action='life_write';zone='selena_score_work';}else if(/弹琴|练琴|弹奏|演奏钢琴|钢琴/.test(activity)){zone='selena_studio';action='music_piano';}else if(/小提琴/.test(activity))zone='selena_violin';break;
 case 'bedroom':
  if(/穿衣镜|照镜|梳妆|整理仪容/.test(activity)){zone=actor+'_mirror';action='home_mirror';}
  else if(/衣柜|换衣|挑衣|选衣|收衣/.test(activity)){zone=actor+'_wardrobe';action='home_wardrobe';}
  else if(/睡|躺|手机|醒|回消息|聊/.test(activity)){
   zone=actor+'_bed';
   if(/手机|醒|回消息|聊/.test(activity)||(sleep.night&&sleep.awake))action='bed_phone';
  }else if(actor==='selena'&&/写日记|记录日记|写手记|日记/.test(activity)){zone='selena_diary';action='home_diary';}
  else if(/收拾|打扫|清扫|整理房间/.test(activity)){zone=actor+'_room_tidy';action='life_tidy';}
  else if(actor==='selena'&&/写|创作/.test(activity)){zone='selena_diary';action='home_diary';}
  else if(actor==='selena'&&/读|阅读|书|手记|笔记|信/.test(activity)){zone='selena_diary';action=/旧信|旧.*手记/.test(activity)?'home_old_letters':'home_desk_read';}
  else if(/读|阅读|书|手记|笔记|信/.test(activity)){zone='xiaoai_lyrics';action='life_read';}
  if(sleep.night&&sleep.awake&&activity==='睡觉'){action='bed_phone';base.label='醒来聊一会儿';}
  break;
 case 'balcony':action=/盆栽|浇水|照料|照看植物/.test(activity)?'life_water':'home_view';break;
 case 'living':
  if(/收拾|打扫|清扫|整理客厅/.test(activity)){zone='living_center';action='life_tidy';break;}
  if(/选书|挑书|书柜/.test(activity)){zone='living_reading';action='life_select';break;}
  if(/手机|刷视频|回消息/.test(activity)){zone='sofa_'+actor;action='sofa_phone';}
  else if(actor==='xiaoai'&&/相册|照片/.test(activity)){zone='sofa_xiaoai';action='sofa_album';}
  else if(/听音乐|听歌|戴.*耳机/.test(activity)){zone='sofa_'+actor;action='sofa_music';}
  else if(/看书|读书|阅读/.test(activity)){zone='sofa_'+actor;action='sofa_read';}
  else if(/休息|发呆|靠在沙发/.test(activity)){zone='sofa_'+actor;action='sofa_rest';}
  else if(actor==='xiaoai'&&/游戏|手柄/.test(activity)){zone='sofa_xiaoai';action='sofa_game';}
  else if(actor==='selena'&&/喝茶|品茶/.test(activity)){zone='sofa_selena';action='sofa_tea';}
  else if(/沙发|看电视|看电影/.test(activity))zone=actor==='xiaoai'?'sofa_xiaoai':'sofa_selena';
  break;
 case 'kitchen':if(/泡茶|冲茶|沏茶/.test(activity)){zone='cook_tea';action='life_tea';}else if(/准备食材|备菜|切菜|备餐|准备.*饭|准备.*餐/.test(activity)){zone='cook_prep';action='life_prep';}else if(/洗碗|洗盘|清洗餐具|刷碗/.test(activity)){zone='kitchen_wash';action='home_wash_dishes';}else if(/洗菜|择菜|清洗食材|冲洗蔬菜/.test(activity)){zone='kitchen_wash';action='home_wash_food';}else if(/烹|做饭|做菜|煮|炒|煎|烘/.test(activity)){zone='cook_stove';action='home_cook';}else if(/冰箱|食材/.test(activity))zone='kitchen_fridge';break;
 case 'dining':if(/吃|用餐|早餐|午餐|晚餐|早饭|午饭|晚饭|进餐/.test(activity)&&!/准备|收拾|清洗/.test(activity))action=/手机|刷视频|回消息/.test(activity)?'home_eat_phone':'home_eat';break;
 case 'bathroom':zone=/泡澡|泡浴|浴缸/.test(activity)?'bath_soak':/洗澡|淋浴|冲澡/.test(activity)?'bath_shower':'bath_sink';action=zone==='bath_sink'?'life_washface':zone==='bath_soak'?'home_soak':'home_shower';break;
 case 'onsen':if(/休息|放松|歇|坐/.test(activity)){zone=actor==='xiaoai'?'onsen_rest_a':'onsen_rest_b';action='life_onsen_rest';}else if(/洗澡|淋浴|冲澡/.test(activity))zone=actor==='xiaoai'?'onsen_shower_a':'onsen_shower_b';else if(/泡汤|泡澡|温泉/.test(activity))zone=actor==='xiaoai'?'onsen_soak_a':'onsen_soak_b';break;
 case 'park':if(/长椅|歇脚|坐|休息/.test(activity)){zone='bench';action='life_bench';}break;
 case 'store':zone='magazines';action=/翻|读|杂志|看书/.test(activity)?'life_read':'life_select';break;
 case 'arcade':if(/棋/.test(activity)){zone=actor==='xiaoai'?'arcade_xiangqi_far':'arcade_xiangqi_near';action='life_chess';}else{zone='arcade_mines';action='life_arcade';}break;
 case 'restaurant':if(/吃|用餐|早餐|午餐|晚餐|早饭|午饭|晚饭/.test(activity)){zone=actor==='xiaoai'?'seat-c3_use':'seat-c4_use';action='life_outside_eat';}break;
 }
 return {...base,sceneId:scene,zone,action,place:(row.names?.[actor]||row.name)+(row.floor==='outside'?'':' · '+(row.floor==='1F'?'一楼':'二楼'))};
}
export function validateLayout(world){
 let checked=0;
 for(const actor of layout.characters){
  for(const row of roomsFor(actor)){
   const zone=valueFor(row.zone,actor);
   if(!world.scenes[row.scene]?.zones[zone])throw Error(`Invalid CabinWorld zone: ${row.scene}/${zone}`);
   const extra=layout.interaction_zones[row.id];
   const zones=Array.isArray(extra)?extra:extra?.[actor]||[];
   for(const id of zones)if(!world.scenes[row.scene]?.zones[id])throw Error(`Invalid interaction zone: ${row.scene}/${id}`);
   checked+=1+zones.length;
  }
 }
 for(const card of catalogue.activities)for(const actor of card.characters){
  const row=roomsFor(actor).find(r=>r.id===card.room),zone=valueFor(card.zone,actor);
  if(!row||!world.scenes[row.scene]?.zones[zone])throw Error('Invalid furniture action: '+card.id+'/'+actor);
  checked++;
 }
 return {version:layoutVersion,activityVersion,checked};
}
