#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
let dataDir = path.join(HERE, 'data');
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--data' && process.argv[i + 1]) dataDir = path.resolve(process.argv[++i]);
}

function readBridge() {
  const file = path.join(dataDir, 'bridge.json');
  if (!fs.existsSync(file)) throw Error(`找不到 ${file}，请先启动 universal-bridge.mjs`);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

async function callBridge(endpoint, body = null) {
  const { url, token } = readBridge();
  const res = await fetch(`${url}${endpoint}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await res.json();
  if (!res.ok || data.ok === false) throw Error(data.error || `HTTP ${res.status}`);
  return data;
}

const send = (obj) => process.stdout.write(JSON.stringify(obj) + '\n');
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', async (line) => {
  if (!line.trim()) return;
  let req;
  try { req = JSON.parse(line); } catch { return; }
  const { id, method, params } = req;
  if (id === undefined) return;
  try {
    if (method === 'initialize') {
      send({ jsonrpc: '2.0', id, result: { protocolVersion: '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'xiaoai-selena-cabin-universal', version: '1.0.0' } } });
    } else if (method === 'tools/list') {
      const { tools } = await callBridge('/v1/tools');
      send({ jsonrpc: '2.0', id, result: { tools: tools.map((t) => ({ name: t.function.name, description: t.function.description, inputSchema: t.function.parameters })) } });
    } else if (method === 'tools/call') {
      const out = await callBridge('/v1/tool', { name: params?.name, arguments: params?.arguments || {} });
      send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(out.result, null, 2) }] } });
    } else {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } });
    }
  } catch (err) {
    send({ jsonrpc: '2.0', id, error: { code: -32000, message: String(err.message || err) } });
  }
});
