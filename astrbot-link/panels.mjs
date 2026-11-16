// Owner-only household panels. Commands are delegated to the original AstrBot instances.
import fs from 'node:fs';
import path from 'node:path';

export class HomePanels {
  constructor(root, now = Date.now) {
    this.root = root;
    this.now = now;
    this.cache = new Map();
    this.revision = 0;
    this.status = {};
  }

  async backend(actor, endpoint, body, day) {
    if (!['xiaoai', 'selena'].includes(actor)) throw Error('没有这位小屋住户');
    const local = JSON.parse(fs.readFileSync(path.join(this.root, `${actor}_control.json`), 'utf8'));
    if (local.character !== actor || !Number.isInteger(local.port) || local.port < 1 || local.port > 65535 || typeof local.token !== 'string') throw Error('小屋控制接口尚未就绪');
    const url = new URL(`http://127.0.0.1:${local.port}/${endpoint}`);
    if (day) url.searchParams.set('day', day);
    const response = await fetch(url, {
      method: body ? 'POST' : 'GET',
      headers: { 'X-Home-Control': local.token, ...(body ? { 'Content-Type': 'application/json' } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(9000),
    });
    const data = await response.json();
    if (!response.ok || data.ok === false) throw Error(data.error || '原小屋暂时没有回应');
    return data;
  }

  async snapshot(actor, day) {
    const key = actor + ':' + (day || 'today');
    const old = this.cache.get(key);
    if (old && this.now() - old.at < 2500) return old.data;
    const revision = this.revision;
    const data = await this.backend(actor, 'snapshot', null, day);
    if (data.character !== actor || data.source !== 'original-home') throw Error('小屋数据来源不匹配');
    if (revision === this.revision) this.cache.set(key, { at: this.now(), data });
    this.status[actor] = { connected: true, at: this.now(), records: data.records.length, gifts: data.backpack.total, journals: data.journals.length };
    return data;
  }

  async get(frame) {
    if (!['usage', 'activity', 'world'].includes(frame.panel)) throw Error('这个入口已收进每日记录、背包和小屋日记');
    const day = frame.day || undefined;
    if (day && !/^\d{4}-\d{2}-\d{2}$/.test(day)) throw Error('日期不正确');
    const all = await Promise.allSettled(['xiaoai', 'selena'].map(async actor => [actor, await this.snapshot(actor, day)]));
    const residents = {}, records = {};
    let products = [];
    for (let index = 0; index < all.length; index++) {
      const result = all[index];
      const actor = ['xiaoai', 'selena'][index];
      if (result.status === 'fulfilled') {
        const [who, data] = result.value;
        products = data.backpack.catalog;
        residents[who] = { features: data, today: { count: data.records.length, props: 0 }, life: { diary: data.journals.map(row => ({ day: row.day, text: row.content, status: row.status })) } };
        records[who] = data.records.map(row => ({ id: 'home-' + row.id, at: Date.parse(row.time), name: row.activity, detail: row.detail, category: row.kind, action: row.room, status: '小屋记录' }));
      } else {
        this.status[actor] = { connected: false, error: '原小屋实例暂未连上' };
        residents[actor] = { features: { character: actor, error: '原小屋实例暂未连上，请保持机器人实例运行' } };
        records[actor] = [];
      }
    }
    return { ok: true, data: frame.panel === 'activity' ? { residents: records, day } : { residents, products, day, features_version: 'home-features/1', source: 'original-home' } };
  }

  async do(frame) {
    if (!['gift.buy', 'gift.act', 'journal.request'].includes(frame.action)) throw Error('这项操作不属于小屋送礼或生活日记');
    if (!['xiaoai', 'selena'].includes(frame.who)) throw Error('请先选择小爱或赛琳娜');
    const body = { action: frame.action };
    for (const key of ['item', 'note', 'request_id', 'gift_id', 'operation', 'day']) if (frame[key] !== undefined) body[key] = frame[key];
    const result = await this.backend(frame.who, 'do', body);
    this.revision++;
    this.cache.clear();
    return result;
  }
}
