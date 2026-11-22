#!/usr/bin/env node
/**
 * Universal AI Bridge for 《小爱与赛琳娜 · 她们的家（改编版）》 (v1.0)
 * Reference protocol compatible with Cabin World by VADS-Official (https://github.com/BabyBus2022/cabin-world).
 * Requires Node.js 22.13+ (zero external npm dependencies; uses built-in node:sqlite).
 */
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { StringDecoder } from 'node:string_decoder';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const TOOLS = JSON.parse(fs.readFileSync(path.join(HERE, 'openai-tools.json'), 'utf8'));

function parseArgs(argv) {
  const out = { dataDir: path.join(HERE, 'data'), port: 18790 };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--data' && argv[i + 1]) out.dataDir = path.resolve(argv[++i]);
    else if (argv[i] === '--port' && argv[i + 1]) out.port = Number(argv[++i]);
  }
  return out;
}

const cfg = parseArgs(process.argv);
fs.mkdirSync(path.join(cfg.dataDir, 'world'), { recursive: true });
const DB_PATH = path.join(cfg.dataDir, 'universal-home.sqlite3');
const GAME_LINK = path.join(cfg.dataDir, 'world', 'game-link.json');
const BRIDGE_JSON = path.join(cfg.dataDir, 'bridge.json');

const ROOM_MAP = {
  living: { sceneId: 'xiaojingyu-home', zone: 'sofa_left', label: '在客厅休息' },
  kitchen: { sceneId: 'xiaojingyu-home', zone: 'cook_stove', label: '在厨房忙活' },
  bedroom: { sceneId: 'shared-home-upstairs', zone: 'upstairs_center', label: '在二楼卧室' },
  music: { sceneId: 'shared-home-upstairs', zone: 'selena_studio', label: '在二楼琴房练琴' },
  singing: { sceneId: 'shared-home-upstairs', zone: 'xiaoai_sing', label: '在二楼练歌' },
  balcony: { sceneId: 'shared-home-upstairs', zone: 'xiaoai_balcony', label: '在阳台/三楼花房' },
  bathroom: { sceneId: 'shared-home-bathroom', zone: 'bath_soak', label: '在卫生间洗漱' },
  park: { sceneId: 'qianxia-park', zone: 'park_center', label: '在公园散步' },
  shop: { sceneId: 'qianxia-shop', zone: 'shop_center', label: '在逛小卖部' },
  arcade: { sceneId: 'world-arcade', zone: 'arcade_center', label: '在电玩城玩耍' },
  onsen: { sceneId: 'world-onsen', zone: 'onsen_center', label: '在汤屋泡温泉' },
  restaurant: { sceneId: 'world-restaurant', zone: 'restaurant_center', label: '在餐厅用餐' },
};

const NAMES = { xiaoai: '小爱', selena: '赛琳娜' };
const CRITTER_META = {
  smldino: { name: '小菲八', produce: '金黄菲鸟蛋', coins: 4, desc: '温顺的小腕龙菲比。' },
  bird: { name: '菲鸟', produce: '金黄菲鸟蛋', coins: 5, desc: '爱去草窝下蛋的鸵鸟菲比。' },
  horse: { name: '菲马', produce: '醇香菲马鲜奶', coins: 5, desc: '爱甩刘海的小马菲比。' },
  deer: { name: '鹿菲', produce: '晨露高枝花蜜', coins: 7, desc: '脖子超长的长颈鹿菲比。' },
  seal: { name: '海狮菲比', produce: '海狮幸运珍珠', coins: 8, desc: '最爱在池塘栈桥顶彩球。' },
  bigdino: { name: '大菲八', produce: '醇香菲马鲜奶', coins: 10, desc: '体型巨大的腕龙菲比。' },
  spider: { name: '大菲蛛', produce: '海狮幸运珍珠', coins: 12, desc: '八条腿魔性倒腾的牧场神兽。' },
};
const WORK_SPOTS = { sunroom: '三楼花房·捉虫护卫', onsen: '汤屋温泉·陪泡吉祥物', restaurant: '外出餐厅·招牌迎宾', park: '公园河畔·巡游团宠', shop: '小卖部·招财看板郎' };

const db = new DatabaseSync(DB_PATH);
db.exec(`
  CREATE TABLE IF NOT EXISTS residents(actor TEXT PRIMARY KEY, room TEXT NOT NULL, activity TEXT NOT NULL, sleeping INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT NOT NULL, target TEXT NOT NULL, content TEXT NOT NULL, reply TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending');
  CREATE TABLE IF NOT EXISTS ranch_animals(id INTEGER PRIMARY KEY AUTOINCREMENT, species TEXT NOT NULL, nickname TEXT NOT NULL, hat_type TEXT NOT NULL DEFAULT 'basic_hat', royal INTEGER NOT NULL DEFAULT 0, mood INTEGER NOT NULL DEFAULT 1, assigned_spot TEXT NOT NULL DEFAULT '');
`);

const nowIso = () => new Date().toISOString();
db.prepare('INSERT OR IGNORE INTO residents VALUES(?,?,?,?,?)').run('xiaoai', 'singing', '在二楼练歌', 0, nowIso());
db.prepare('INSERT OR IGNORE INTO residents VALUES(?,?,?,?,?)').run('selena', 'music', '在二楼琴房练琴', 0, nowIso());
db.prepare("INSERT OR IGNORE INTO kv VALUES('coins','120')").run();
db.prepare("INSERT OR IGNORE INTO kv VALUES('ai_notes','[]')").run();
db.prepare("INSERT OR IGNORE INTO kv VALUES('ranch_hats','{\"basic_hat\":2,\"flower_hat\":0,\"royal_hat\":0}')").run();
db.prepare("INSERT OR IGNORE INTO kv VALUES('ranch_feathers','0')").run();
db.prepare("INSERT OR IGNORE INTO kv VALUES('ranch_max_slots','6')").run();
db.prepare("INSERT OR IGNORE INTO kv VALUES('helper_owned','0')").run();
if (db.prepare('SELECT COUNT(*) AS c FROM ranch_animals').get().c === 0) {
  db.prepare('INSERT INTO ranch_animals(species,nickname,hat_type,royal,mood) VALUES(?,?,?,?,?)').run('smldino', '小菲八', 'basic_hat', 0, 1);
  db.prepare('INSERT INTO ranch_animals(species,nickname,hat_type,royal,mood) VALUES(?,?,?,?,?)').run('seal', '海狮菲比', 'basic_hat', 0, 1);
}

const getKV = (k, fallback) => { const row = db.prepare('SELECT value FROM kv WHERE key=?').get(k); return row ? JSON.parse(row.value) : fallback; };
const setKV = (k, v) => db.prepare('INSERT OR REPLACE INTO kv VALUES(?,?)').run(k, JSON.stringify(v));

function buildPresence() {
  const out = {};
  for (const r of db.prepare('SELECT * FROM residents').all()) {
    const m = ROOM_MAP[r.room] || ROOM_MAP.living;
    out[r.actor] = { sceneId: m.sceneId, zone: m.zone, label: r.activity || m.label, sleeping: Boolean(r.sleeping), action: '' };
  }
  return out;
}

function buildPlaySnapshot() {
  const animals = db.prepare('SELECT * FROM ranch_animals ORDER BY id').all().map((a) => ({ ...a, ...(CRITTER_META[a.species] || CRITTER_META.smldino) }));
  return {
    notes: db.prepare('SELECT * FROM notes ORDER BY id DESC LIMIT 12').all(),
    meals: [], meal_menu: [], duets: [],
    garden: { pots: [], max_slots: 15, helper_owned: Boolean(getKV('helper_owned', 0)), shiny_charm: 0, care_coins_today: 0, care_coins_cap: 30, pantry: {}, dex: [], shiny_dex: [], total_species: 8 },
    arcade: { daily_earned: 0, daily_cap: 20, recent: [] },
    ranch: {
      animals, feathers: Number(getKV('ranch_feathers', 0)), work_spots: WORK_SPOTS, max_slots: Number(getKV('ranch_max_slots', 6)),
      hats: getKV('ranch_hats', { basic_hat: 2, flower_hat: 0, royal_hat: 0 }),
      forest: [{ slot: 1, species: 'bird', name: '菲鸟', rarity: 'common', x: 0.30, y: 0.56 }, { slot: 2, species: 'horse', name: '菲马', rarity: 'common', x: 0.58, y: 0.38 }, { slot: 3, species: 'spider', name: '大菲蛛', rarity: 'rare', x: 0.68, y: 0.62 }],
      dex: [...new Set(animals.map((a) => a.species))], total_species: 7, coins_today: 0, coins_cap: 55,
    },
    ai_notes: getKV('ai_notes', []),
  };
}

function buildSummary() {
  const play = buildPlaySnapshot();
  return {
    residents: Object.fromEntries(db.prepare('SELECT * FROM residents').all().map((r) => [r.actor, { name: NAMES[r.actor], room: r.room, activity: r.activity, sleeping: Boolean(r.sleeping) }])),
    coins: Number(getKV('coins', 120)),
    garden_admin: play.garden.helper_owned ? '闪光·雪绒豹（巡逻中）' : '未任命',
    ranch_animals: play.ranch.animals.map((a) => `${a.nickname}${a.assigned_spot ? `（打工：${WORK_SPOTS[a.assigned_spot]}）` : ''}`),
    pending_notes: play.notes.filter((n) => n.status === 'pending'),
    recent_ai_notes: play.ai_notes.slice(0, 5),
  };
}

let gameSocket = null;
const gameToken = randomBytes(32).toString('hex');
const sendToGame = (frame) => { if (gameSocket && !gameSocket.destroyed) gameSocket.write(JSON.stringify(frame) + '\n'); };
const pushWorld = () => { sendToGame({ type: 'clock', now: Date.now() }); sendToGame({ type: 'world', presence: buildPresence() }); };

function handlePanelAction(action, body = {}) {
  if (action === 'note.add') {
    const target = NAMES[body.target] ? body.target : 'xiaoai';
    const content = String(body.content || '').trim().slice(0, 160);
    if (!content) throw Error('便签内容不能为空');
    const info = db.prepare('INSERT INTO notes(time,target,content,status) VALUES(?,?,?,?)').run(nowIso(), target, content, 'pending');
    return { ok: true, data: { id: Number(info.lastInsertRowid), message: `便签已贴好，等待外部 AI（${NAMES[target]}）回复` } };
  }
  if (action === 'ranch.assign') {
    const aid = Number(body.animal_id || 0), spot = String(body.spot_id || '');
    if (spot && !WORK_SPOTS[spot]) throw Error('未知打工岗位');
    if (spot) db.prepare("UPDATE ranch_animals SET assigned_spot='' WHERE assigned_spot=?").run(spot);
    db.prepare('UPDATE ranch_animals SET assigned_spot=? WHERE id=?').run(spot, aid);
    return { ok: true, data: { message: spot ? `已外派至 ${WORK_SPOTS[spot]}` : '已召回牧场草坪' } };
  }
  if (action === 'ranch.visit_worker') {
    const coins = Number(getKV('coins', 120)) + 2;
    setKV('coins', coins);
    return { ok: true, data: { gain: 2, coins, message: '去探班了打工中的菲比（+2 小屋零钱）！' } };
  }
  if (action === 'garden.buy_helper' || action === 'garden.promote_helper') {
    setKV('helper_owned', 1);
    return { ok: true, data: { message: '「闪光·雪绒豹」已正式上任三楼花园管理员！' } };
  }
  return { ok: true, data: { message: `通用桥接已受理指令：${action}` } };
}

const tcpServer = net.createServer((peer) => {
  let buffer = '', authed = false;
  const decoder = new StringDecoder('utf8');
  const deadline = setTimeout(() => peer.destroy(), 4000);
  peer.on('error', () => {});
  peer.on('close', () => { clearTimeout(deadline); if (gameSocket === peer) gameSocket = null; });
  peer.on('data', (chunk) => {
    buffer += decoder.write(chunk);
    for (;;) {
      const idx = buffer.indexOf('\n'); if (idx < 0) break;
      const line = buffer.slice(0, idx); buffer = buffer.slice(idx + 1);
      let f; try { f = JSON.parse(line); } catch { peer.destroy(); return; }
      if (!authed) {
        const a = Buffer.from(String(f.token || '')), b = Buffer.from(gameToken);
        if (f.type !== 'hello' || a.length !== b.length || !timingSafeEqual(a, b) || gameSocket) { peer.destroy(); return; }
        authed = true; clearTimeout(deadline); gameSocket = peer;
        sendToGame({ type: 'welcome', residents: false, social: 0, bodySave: 0, host: { name: 'Universal AI Bridge', audioSettings: false } });
        pushWorld(); continue;
      }
      if (f.type === 'ping') sendToGame({ type: 'pong' });
      else if (f.type === 'panel.get') {
        const play = buildPlaySnapshot(), coins = Number(getKV('coins', 120)), residents = {};
        for (const actor of ['xiaoai', 'selena']) residents[actor] = { features: { character: actor, source: 'universal-ai', records: [], journals: [], backpack: { total: 0, items: [], catalog: [], wallet: { coins }, affection: { connected: false, value: 0 } }, play } };
        sendToGame({ type: 'panel.data', id: f.id, panel: f.panel, day: f.day, ok: true, data: { residents, products: [], source: 'universal-ai' } });
      } else if (f.type === 'panel.do') {
        try { const res = handlePanelAction(f.action, f); sendToGame({ type: 'panel.did', id: f.id, action: f.action, who: f.who, ok: true, data: res.data }); }
        catch (err) { sendToGame({ type: 'panel.did', id: f.id, action: f.action, who: f.who, ok: false, error: err.message }); }
      }
    }
  });
});

await new Promise((resolve, reject) => tcpServer.once('error', reject).listen(0, '127.0.0.1', resolve));
fs.writeFileSync(GAME_LINK, JSON.stringify({ port: tcpServer.address().port, token: gameToken, at: Date.now() }) + '\n', { mode: 0o600 });

const httpToken = randomBytes(24).toString('hex');
const readBody = (req) => new Promise((resolve, reject) => {
  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 2 * 1024 * 1024) reject(Error('Payload too large')); });
  req.on('end', () => { try { resolve(raw ? JSON.parse(raw) : {}); } catch { reject(Error('Invalid JSON')); } });
  req.on('error', reject);
});

function dispatchTool(name, args = {}) {
  if (name === 'cabin_status') return buildSummary();
  if (name === 'cabin_move') {
    const actor = NAMES[args.actor] ? args.actor : 'xiaoai', room = ROOM_MAP[args.room] ? args.room : 'living';
    const activity = String(args.activity || ROOM_MAP[room].label).slice(0, 60), sleeping = args.sleeping ? 1 : 0;
    db.prepare('INSERT OR REPLACE INTO residents VALUES(?,?,?,?,?)').run(actor, room, activity, sleeping, nowIso());
    pushWorld();
    return { ok: true, actor, room, activity, sleeping: Boolean(sleeping) };
  }
  if (name === 'cabin_reply_note') {
    const actor = NAMES[args.actor] ? args.actor : 'xiaoai', reply = String(args.reply || '').trim().slice(0, 200);
    if (!reply) throw Error('reply 不能为空');
    const row = args.note_id ? db.prepare('SELECT id FROM notes WHERE id=?').get(Number(args.note_id)) : db.prepare("SELECT id FROM notes WHERE target=? AND status='pending' ORDER BY id DESC LIMIT 1").get(actor);
    if (!row) throw Error('没有找到待回复的便签');
    db.prepare("UPDATE notes SET reply=?, status='replied' WHERE id=?").run(reply, row.id);
    return { ok: true, note_id: row.id, actor, reply };
  }
  if (name === 'cabin_write_visit_note') {
    const actor = NAMES[args.actor] ? args.actor : 'xiaoai', place = args.place === 'garden' ? 'garden' : 'ranch', text = String(args.text || '').trim().slice(0, 120);
    if (!text) throw Error('text 不能为空');
    const list = getKV('ai_notes', []);
    list.unshift({ character: actor, name: NAMES[actor], place, text, time: nowIso() });
    setKV('ai_notes', list.slice(0, 10));
    return { ok: true, actor, place, text };
  }
  if (name === 'cabin_play_action') return handlePanelAction(String(args.action || ''), args.fields || {});
  throw Error(`Unknown tool: ${name}`);
}

const httpServer = http.createServer(async (req, res) => {
  if (req.headers.origin) { res.writeHead(403); res.end('Forbidden'); return; }
  const url = new URL(req.url, 'http://127.0.0.1');
  const reply = (code, data) => { res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data)); };
  if (req.method === 'GET' && url.pathname === '/v1/health') return reply(200, { ok: true, gameConnected: Boolean(gameSocket), protocol: 'cabin-universal/1' });
  const auth = req.headers.authorization === `Bearer ${httpToken}` || req.headers['x-cabin-token'] === httpToken;
  if (!auth) return reply(401, { ok: false, error: 'Unauthorized' });
  try {
    if (req.method === 'GET' && url.pathname === '/v1/tools') return reply(200, { ok: true, tools: TOOLS });
    if (req.method === 'GET' && url.pathname === '/v1/summary') return reply(200, { ok: true, data: buildSummary() });
    if (req.method === 'POST' && url.pathname === '/v1/tool') { const body = await readBody(req); return reply(200, { ok: true, result: dispatchTool(body.name, body.arguments || {}) }); }
    if (req.method === 'POST' && url.pathname === '/v1/presence') { const body = await readBody(req); return reply(200, { ok: true, result: dispatchTool('cabin_move', body) }); }
    reply(404, { ok: false, error: 'Not Found' });
  } catch (err) { reply(400, { ok: false, error: err.message }); }
});

await new Promise((resolve, reject) => httpServer.once('error', reject).listen(cfg.port, '127.0.0.1', resolve));
const actualPort = httpServer.address().port;
fs.writeFileSync(BRIDGE_JSON, JSON.stringify({ url: `http://127.0.0.1:${actualPort}`, token: httpToken, pid: process.pid, at: Date.now() }, null, 2) + '\n', { mode: 0o600 });
const timer = setInterval(pushWorld, 3000);
process.on('SIGINT', () => { clearInterval(timer); tcpServer.close(); httpServer.close(); db.close(); process.exit(0); });
console.log(`[Universal AI Bridge] Ready on http://127.0.0.1:${actualPort} (TCP ${tcpServer.address().port})`);
