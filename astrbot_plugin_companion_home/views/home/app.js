/* Private native dashboard bridge; no provider keys or remote libraries. */
const $ = (id) => document.getElementById(id);
const paths = {
  sofa:'M4 11V7a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v4M3 10h2v5h14v-5h2v8H3v-8ZM5 18v2m14-2v2',
  bed:'M3 18V5m0 7h18v6M3 8h6v4H3m6-4h9a3 3 0 0 1 3 3v1M3 18v2m18-2v2',
  book:'M3 5c4-1 6-1 9 1 3-2 5-2 9-1v14c-4-1-6-1-9 1-3-2-5-2-9-1V5Zm9 1v14',
  shelf:'M4 3v18m16-18v18M4 19h16M4 12h16M7 4v6m4-6v6m4-6 2 6M8 14v3m4-3v3m4-3v3',
  sun:'M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
  cup:'M4 5h12v10a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4V5Zm12 1h3a3 3 0 0 1 0 6h-3M3 22h15',
  drop:'M12 3s7 8 7 12a7 7 0 0 1-14 0c0-4 7-12 7-12Zm-4 13a4 4 0 0 0 4 3',
  door:'M5 21V3h14v18M3 21h18M5 3l9 3v15m-3-8h1',
  leaf:'M20 3c-8 0-16 2-16 10a7 7 0 0 0 12 5c4-4 4-10 4-15ZM4 21l11-11',
  walk:'M12 5a2 2 0 1 1 0-4 2 2 0 0 1 0 4Zm-1 3 3 5 4 1M7 13l2-5h4l-1 8 4 6m-4-6-5 6',
  bag:'M5 7h14l1 14H4L5 7Zm3 0V5a4 4 0 0 1 8 0v2',
};
let activeCharacter = null;
let snapshot = null;
let sequence = 0;
let toastTimeout;
let serverOffset = 0;
let followingToday = true;
const watchedRequests = new Map();
function localDay() {
  return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(Date.now()+serverOffset));
}
try { activeCharacter = localStorage.getItem('companion-home-resident'); } catch { /* Storage can be disabled. */ }
if (!['xiaoai','selena'].includes(activeCharacter)) activeCharacter = null;
function toast(message) {
  clearTimeout(toastTimeout); $('toast').textContent = message; $('toast').style.display = 'block';
  toastTimeout = setTimeout(() => { $('toast').style.display = 'none'; }, 4500);
}
function timeLabel(iso, date=false) {
  if (!iso) return '—';
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.valueOf())) return '—';
  return new Intl.DateTimeFormat('zh-CN',{timeZone:'Asia/Shanghai', ...(date ? {month:'2-digit',day:'2-digit'} : {}),hour:'2-digit',minute:'2-digit',hour12:false}).format(parsed);
}
function online(data) {
  return Boolean(data?.heartbeat && (Date.now()+serverOffset-new Date(data.heartbeat).valueOf()) < 120000);
}
function updateClock() {
  const now = new Date(Date.now()+serverOffset);
  $('clock').textContent = timeLabel(now.toISOString());
  $('date').textContent = new Intl.DateTimeFormat('zh-CN',{timeZone:'Asia/Shanghai',month:'2-digit',day:'2-digit',weekday:'short'}).format(now);
  const hour = Number(new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Shanghai',hour:'2-digit',hourCycle:'h23'}).format(now));
  document.body.classList.toggle('daylight',hour>=6 && hour<18);
}
function node(tag, className, text) {
  const element=document.createElement(tag); if(className)element.className=className;
  if(text !== undefined)element.textContent=text; return element;
}
function render(data) {
  const profile=data.profile, state=data.state;
  document.documentElement.dataset.resident=data.character;
  document.title=profile.title;
  $('home-title').replaceChildren(document.createTextNode(profile.title),node('span','title-spark',profile.symbol));
  $('greeting').textContent=profile.subtitle;
  $('signature').textContent=data.character==='xiaoai' && state?.mode==='maru' ? '雷霆大雪绒' : profile.name;
  $('quote-symbol').textContent=profile.symbol;
  document.querySelectorAll('[data-character]').forEach(button=>{
    const selected=button.dataset.character===data.character;button.classList.toggle('selected',selected);button.setAttribute('aria-pressed',String(selected));
  });
  $('daily-meals').replaceChildren();
  for(const meal of data.daily_routine?.meals||[]){
    const box=node('article','house-item meal-row');box.append(node('b','',`${meal.eat_at} · ${meal.name}`),node('p','',`${meal.cook_at} ${meal.cook}做饭 · ${meal.wash_at} ${meal.wash_dishes}洗碗`));$('daily-meals').append(box);
  }
  for(const care of data.daily_routine?.care||[]){
    const box=node('article','house-item care-row');box.append(node('b','',care.time),node('p','',care.name));$('daily-meals').append(box);
  }
  const housemate=data.housemate||{},peer=housemate.peer;
  $('housemate-presence').textContent=peer ? `${peer.name} · ${peer.online ? peer.room_name+'，'+peer.activity : '保存着上次的日常'}` : '等同住伙伴开始今天的日常';
  $('housemate-exchanges').replaceChildren();
  for(const exchange of housemate.messages||[]){
    const box=node('article','housemate-exchange'),names={xiaoai:'小爱',selena:'赛琳娜'};
    box.append(node('small','',timeLabel(exchange.time,true)),node('p',`peer-line ${exchange.starter}`,`${names[exchange.starter]}：${exchange.opening}`));
    if(exchange.reply)box.append(node('p',`peer-line ${exchange.recipient}`,`${names[exchange.recipient]}：${exchange.reply}`));
    else box.append(node('span','quiet-reply','一句话留在这里，等她接着说'));
    $('housemate-exchanges').append(box);
  }
  if(!housemate.messages?.length)$('housemate-exchanges').append(node('p','empty-copy','偶尔碰面，聊两句眼前的小事'));
  const life=data.life || {};
  document.body.classList.toggle('sleeping',life.sleep==='睡着了');
  document.body.classList.toggle('waking',life.sleep==='被叫醒了');
  $('sleep-status').textContent=life.sleep || '';
  function items(id,values,empty){
    const target=$(id);target.replaceChildren();
    for(const item of values){const box=node('article','house-item');box.append(node('b','',item.title),node('p','',item.detail));if(item.experience){const fold=node('details','');fold.append(node('summary','','翻开这段回忆'),node('p','',item.experience));box.append(fold);}target.append(box);}
    if(!values.length)target.append(node('p','empty-copy',empty));
  }
  items('house-projects',life.projects || [],'暂时没有留下跨日的小计划');
  items('house-habits',(life.habits || []).filter(x=>x.confirmed),'相处久一点，习惯会慢慢留下');
  items('house-mementos',life.mementos || [],'等共同经历慢慢留下一件纪念');
  items('house-highlights',life.day_highlights || [],'今天值得记住的片刻，等它自然发生');
  items('house-draft',life.draft?[life.draft]:[],'今天的话，慢慢积累再写');
  $('house-companionship').textContent=life.companionship && life.companionship.title!=='结束陪伴'?life.companionship.title+' · '+life.companionship.detail:'';
  $('house-mail').replaceChildren();
  for(const mail of life.mail || []){const fold=node('details','mail-item');fold.append(node('summary','',mail.date+' · '+(data.character==='selena'?'午夜来信':'日记')),node('p','',mail.text));$('house-mail').append(fold);}
  if(!life.mail?.length)$('house-mail').append(node('p','empty-copy','成功发布后的日记和来信会留在这里'));
  const isOnline=online(data);
  document.querySelector('.live-status').classList.toggle('offline',!isOnline);
  $('backend-status').textContent=isOnline ? '她的日常正在继续' : state ? '保存着她上次的日常' : '等待她的实例启动';
  const working=data.pending>0 || data.planner?.running;
  $('refresh-plan').disabled=!isOnline || working;
  $('refresh-plan').textContent=working ? '她正在想接下来做什么…' : '✧  看看她接下来想做什么';
  const latest=data.latest_request;
  const feedback=$('plan-feedback');
  feedback.textContent=working ? '已收到，正在安排，完成后会在这里显示结果' : latest?.result?.message || '';
  if(latest && latest.id===watchedRequests.get(data.character) && latest.status==='done') {
    toast(latest.result?.message || '这次安排已经完成');watchedRequests.delete(data.character);
  }
  const plannerResult=data.planner?.result;
  if(!working && plannerResult?.status?.includes('模型暂不可用'))feedback.textContent=plannerResult.status+' · '+(latest?.result?.message || '下次会自动重试');
  const currentRoom=data.rooms.find(room=>room.id===state?.room);
  const roomName=currentRoom?.name || state?.room_name;
  $('current-room').textContent=roomName || '等她安顿下来';
  $('current-floor').textContent=currentRoom?.floor==='outside' ? '小屋外面' : currentRoom?.floor==='2F' ? '二楼 · 私人生活与音乐区' : currentRoom?.floor==='1F' ? '一楼 · 公共生活区' : '保存的位置';
  $('layout-description').textContent=data.character==='selena' ? '书房与卧室合为一间，书桌写信，床边休息，琴房仍在二楼另一侧' : '卧室与阳台在二楼，楼下打游戏喝茶，练歌时到二楼左侧';
  $('current-activity').textContent=state?.activity || '她的日常还没有开始';
  $('current-detail').textContent=state?.detail || '启动对应的AstrBot实例后，她会在这里留下今天的第一段日常';
  $('since').textContent=state ? `${timeLabel(state.since)} 开始` : '尚未安排';
  $('scene-source').textContent=state?.together ? '正与你一起' : state ? ({ai:'她自己的日常',chat:'随你们的聊天更新',routine:'日常安排'}[state.source] || '日常') : '日常';
  $('quote').textContent=state?.quote || '这一页，等她亲手写下';
  $('quote-time').textContent=state ? `${timeLabel(state.updated_at)} 留在这里` : '等待她写下这一刻';
  $('event-count').textContent=data.events.length;
  $('memory-count').textContent=data.memory.connected ? data.memory.count : '—';
  $('note-count').textContent=data.notes.length;
  $('home-presence').textContent=state ? ((data.rooms.find(r=>r.id===state.room)?.area==='outside') ? '她出门了' : '她在家') : '';
  function roomTile(room) {
      const current=state?.room===room.id;
      const tile=node('div',`room${current?' active':''}`);
      const icon=node('span','room-icon');
      icon.innerHTML=`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[room.icon] || paths.book}"/></svg>`;
      tile.append(icon,node('span','room-name',room.name),node('span','room-feature',(room.furniture||[]).join(' · ') || room.description || ''),node('span','room-state',current ? state.activity : ((life.traces || []).find(t=>t.title===room.id)?.detail || '静静等她来')));
      tile.title=room.description || room.name;
      if(current)tile.setAttribute('aria-label',`${room.name}，她正在${state.activity}`);
      return tile;
  }
  $('home-rooms').replaceChildren();
  for(const floor of data.layout?.floors || [{id:'1F',name:'家里'}]) {
    const block=node('section','floor-block');
    const heading=node('div','floor-heading');
    heading.append(node('span','floor-number',floor.id),node('h3','',floor.name));
    const grid=node('div','room-grid floor-grid');
    for(const room of data.rooms.filter(r=>r.area==='home' && (!r.floor || r.floor===floor.id)))grid.append(roomTile(room));
    if(grid.children.length){block.append(heading,grid);$('home-rooms').append(block);}
  }
  $('outside-rooms').replaceChildren();
  for(const room of data.rooms.filter(r=>r.area==='outside')) {
      $('outside-rooms').append(roomTile(room));
    }
  $('plans').replaceChildren();
  for(const plan of state?.plans || [])$('plans').append(node('li','',plan));
  if(!state?.plans?.length)$('plans').append(node('li','','暂时不赶路，把眼前这件小事做好'));
  const next=data.schedule?.next_at;
  $('next-update').textContent=state?.together ? '共同活动进行中 · 跟随你们的聊天，不自动跳走' : life.sleep==='睡着了' ? `正在休息 · ${life.wake_at||'07:00'}恢复日常，被叫醒时可回应` : isOnline && next ? `下次安排 ${timeLabel(next)} · 20～60分钟随机，饭点优先` : '每20～60分钟随机安排一次日常';
  $('memory-preview').textContent=data.memory.items?.[0]?.text || '等你们聊过更多日常，这里会慢慢留下值得记住的事';
  const waiting=data.experience_sync?.pending || 0;
  $('memory-status').textContent=waiting ? `${waiting}段经历正在同步记忆` : data.memory.connected ? `${timeLabel(data.memory.synced_at)} 已同步` : '记忆尚未连接';
  $('timeline').replaceChildren();
  for(const event of data.events) {
    const row=node('div','timeline-item');const detail=node('div','timeline-body');
    const heading=node('div','');heading.append(node('strong','',event.activity || ''),node('span','timeline-location',event.room_name || data.rooms.find(r=>r.id===event.room)?.name || ''));
    detail.append(heading,node('p','',(typeof event.experience==='string'?event.experience:event.experience?.summary) || event.detail || ''));
    row.append(node('span','timeline-time',timeLabel(event.time)),detail);$('timeline').append(row);
  }
  if(!data.events.length)$('timeline').append(node('p','empty-copy','这一天还没有记录的片段，不补写，只等下一次发生'));
  $('notes').replaceChildren();
  for(const note of data.notes) {
    const row=node('div',`note${note.author==='her'?' from-her':''}`), heading=node('div','note-head');
    heading.append(node('b','',note.author==='her'?profile.name:'你'),node('span','',timeLabel(note.time,true)));
    row.append(heading,node('p','',note.text));$('notes').append(row);
  }
  if(!data.notes.length)$('notes').append(node('p','empty-copy','第一张便签，等你来写'));
  $('memory-items').replaceChildren();
  for(const memory of data.memory.items || []) {
    const row=node('article','memory-entry');row.append(node('small','',(memory.topics || []).join(' · ') || `记忆 #${memory.id}`),node('p','',memory.text));$('memory-items').append(row);
  }
  if(!data.memory.items?.length)$('memory-items').append(node('p','empty-copy','暂时没有可展示的记忆，原记忆库不受影响'));
  if(data.preview)$('preview-banner').hidden=false;
}
async function load() {
  const token=++sequence;
  try {
    const params={};if(activeCharacter)params.character=activeCharacter;if(!followingToday && $('timeline-date').value)params.day=$('timeline-date').value;
    const data=await window.AstrBotPluginPage.apiGet('state',params);
    if(token!==sequence)return;
    snapshot=data;activeCharacter=data.character;serverOffset=new Date(data.server_time).valueOf()-Date.now();
    if(followingToday || !$('timeline-date').value)$('timeline-date').value=data.day;
    $('error-banner').hidden=true;render(data);updateClock();
  } catch(error) {
    if(token!==sequence)return;
    $('error-banner').textContent=error.message || '暂时无法读取日常，稍后会自动重试';$('error-banner').hidden=false;
  }
}
document.addEventListener('DOMContentLoaded',async()=>{
  updateClock();setInterval(updateClock,1000);
  document.querySelectorAll('[data-character]').forEach(button=>{button.onclick=()=>{
    activeCharacter=button.dataset.character;try{localStorage.setItem('companion-home-resident',activeCharacter);}catch{/* Optional preference. */}load();
  };});
  $('reload').onclick=load;$('timeline-date').onchange=()=>{followingToday=$('timeline-date').value===localDay();load();};
  $('open-memories').onclick=()=>{$('memory-dialog').showModal();};
  $('close-memories').onclick=()=>{$('memory-dialog').close();};
  $('note-form').onsubmit=async(event)=>{
    event.preventDefault();if(!snapshot)return;
    const text=$('note-text').value.trim();if(!text)return;
    $('save-note').disabled=true;
    try{await window.AstrBotPluginPage.apiPost('note',{character:activeCharacter,text});$('note-text').value='';toast('便签已留好，她安排日常和与你私聊时会看到');await load();}
    catch(error){toast(error.message || '便签没有保存成功');}finally{$('save-note').disabled=false;}
  };
  $('refresh-plan').onclick=async()=>{
    $('refresh-plan').disabled=true;
    const character=activeCharacter;
    try{const result=await window.AstrBotPluginPage.apiPost('refresh',{character});watchedRequests.set(character,result.id);toast('已收到，正在安排');await load();}
    catch(error){toast(error.message || '这次没有更新成功');$('refresh-plan').disabled=false;}
  };
  if(!window.AstrBotPluginPage){$('error-banner').textContent='请从AstrBot左侧“她们的家”打开此页面';$('error-banner').hidden=false;return;}
  await window.AstrBotPluginPage.ready();await load();setInterval(load,15000);
});
