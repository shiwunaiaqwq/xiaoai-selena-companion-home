import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {mapState,sleeping,canonicalRoom,roomsFor,validateLayout} from './mapping.mjs';

const worldSource=fs.readFileSync(new URL('../character-edition/game/assets/world.json', import.meta.url));
const world=JSON.parse(worldSource.toString('utf8'));
const day=Date.parse('2026-11-13T17:00:00+08:00'),night=Date.parse('2026-11-14T02:00:00+08:00');
let checks=0;
const eq=(a,b)=>{assert.equal(a,b);checks++;};
const good=(x)=>{assert.ok(x);checks++;};
const validation=validateLayout(world);
good(validation.checked>60);
for(const actor of ['xiaoai','selena'])for(const room of roomsFor(actor)){
 const mapped=mapState(actor,{room:room.id,activity:'日常整理'},{},day);
 good(mapped.supported);good(world.scenes[mapped.sceneId].zones[mapped.zone]);
}
eq(canonicalRoom('selena','study'),'bedroom');
eq(mapState('selena',{room:'study',activity:'给指挥官写一封信'},{},day).zone,'selena_diary');
eq(mapState('selena',{room:'bedroom',activity:'阅读剧本'},{},day).sceneId,'shared-home-upstairs');
eq(mapState('selena',{room:'bedroom',activity:'阅读剧本'},{},day).zone,'selena_diary');
eq(mapState('selena',{room:'bedroom',activity:'睡觉'},{},night).zone,'selena_bed');
eq(mapState('selena',{room:'music',activity:'整理乐谱'},{},day).zone,'selena_score_work');
eq(mapState('selena',{room:'music',activity:'弹琴'},{},day).action,'music_piano');
eq(mapState('xiaoai',{room:'singing',activity:'练歌'},{},day).action,'music_sing');
eq(mapState('xiaoai',{room:'gaming',activity:'打游戏'},{},day).zone,'sofa_xiaoai');
eq(mapState('xiaoai',{room:'gaming',activity:'打游戏'},{},day).canonicalRoom,'living');
eq(mapState('selena',{room:'living',activity:'坐在沙发喝茶'},{},day).action,'sofa_tea');
eq(mapState('xiaoai',{room:'kitchen',activity:'准备午餐'},{},day).zone,'cook_prep');
eq(mapState('xiaoai',{room:'kitchen',activity:'吃午餐'},{},day).zone,'dining_xiaoai');
eq(mapState('selena',{room:'restaurant',activity:'吃午餐'},{},day).sceneId,'world-restaurant');
eq(mapState('xiaoai',{room:'bathroom',activity:'洗澡'},{},day).zone,'bath_shower');
eq(mapState('xiaoai',{room:'bedroom',activity:'穿衣镜前整理衣领'},{},day).zone,'xiaoai_mirror');
eq(mapState('xiaoai',{room:'bedroom',activity:'整理衣柜'},{},day).zone,'xiaoai_wardrobe');
eq(sleeping({},{},night),true);
eq(sleeping({together:true},{},night),false);
eq(sleeping({},{owner_last:night/1000-3},night),false);
eq(sleeping({},{wakes:{owner:night/1000+20}},night),false);
eq(sleeping({},{},Date.parse('2026-11-14T06:59:59+08:00')),true);
eq(sleeping({},{},Date.parse('2026-11-14T07:00:00+08:00')),false);
const awake=mapState('selena',{room:'bedroom',activity:'睡觉'},{wakes:{group:night/1000+30}},night);
eq(awake.action,'bed_phone');eq(awake.sleeping,false);eq(awake.zone,'selena_bed');
const unsupported=mapState('xiaoai',{room:'bookstore',activity:'看书'},{},day);
eq(unsupported.supported,false);eq(unsupported.sceneId,null);good(unsupported.place.includes('保留上次画面'));
eq(mapState('selena',{room:'singing',activity:'练歌'},{},day).supported,false);
eq(mapState('selena',{room:'bedroom',activity:'写日记'},{},day).action,'home_diary');
eq(mapState('xiaoai',{room:'kitchen',activity:'做饭'},{},day).action,'home_cook');
eq(mapState('selena',{room:'dining',activity:'吃晚饭'},{},day).action,'home_eat');
eq(mapState('selena',{room:'bathroom',activity:'泡澡'},{},day).action,'home_soak');
for(const [actor,room,activity,action] of [['xiaoai','living','翻看相册','sofa_album'],['selena','living','坐沙发休息','sofa_rest'],['selena','living','坐在沙发看书','sofa_read'],['selena','living','坐沙发听音乐','sofa_music'],['xiaoai','balcony','看风景','home_view'],['selena','bedroom','整理衣柜','home_wardrobe'],['xiaoai','bedroom','照镜子','home_mirror'],['xiaoai','kitchen','洗菜','home_wash_food'],['selena','kitchen','洗碗','home_wash_dishes']])eq(mapState(actor,{room,activity},{},day).action,action);
for(const actor of ['xiaoai','selena'])for(const [room,activity,action] of [['living','坐沙发看书','sofa_read'],['living','坐沙发听音乐','sofa_music'],['living','坐沙发休息','sofa_rest'],['kitchen','切菜准备食材','life_prep'],['kitchen','泡茶','life_tea'],['bathroom','洗漱','life_washface'],['balcony','照料盆栽浇水','life_water'],['bedroom','收拾房间','life_tidy'],['park','长椅歇脚','life_bench'],['store','挑选杂志','life_read'],['arcade','玩机台','life_arcade'],['arcade','棋桌游戏','life_chess'],['onsen','休息区放松','life_onsen_rest'],['restaurant','外面吃晚饭','life_outside_eat']]){
 const pose=mapState(actor,{room,activity},{},day);eq(pose.action,action);good(world.scenes[pose.sceneId].zones[pose.zone]);
}
eq(mapState('selena',{room:'bedroom',activity:'翻看旧信与手记'},{},day).action,'home_old_letters');
eq(mapState('selena',{room:'bedroom',activity:'阅读'},{},day).action,'home_desk_read');
eq(mapState('selena',{room:'music',activity:'听演奏回放'},{},day).action,'life_listen');
eq(mapState('xiaoai',{room:'singing',activity:'整理歌词换气标记'},{},day).action,'life_write');
const report={ok:true,checks,layout:validation,world_sha256:createHash('sha256').update(worldSource).digest('hex'),synthetic_only:true};
// Standalone installed checks print their report without assuming the staging tree exists.
if(import.meta.url.includes('/work/cabin_bridge_20261113/'))fs.writeFileSync(new URL('../../outputs/小屋世界适配-2026-11-13/mapping-tests.json',import.meta.url),JSON.stringify(report,null,2));
console.log(JSON.stringify(report));
