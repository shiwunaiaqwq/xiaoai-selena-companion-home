# 🔌 通用 AI 接入适配指南（Universal AI Adapter）

本目录是专为**不使用 AstrBot**（或希望接入 **MCP / Claude Desktop / Cursor / DeepSeek Harness / OpenAI Function Calling / Python / NoneBot / Koishi** 等任意 AI 框架）的用户准备的**零依赖通用桥接适配器**。

> **致谢与来源声明**
> - 本项目基于 **VADS-Official** 开源的 [Cabin World](https://github.com/BabyBus2022/cabin-world) 改编，通用桥接架构完整遵循原项目的 **「游戏 ↔ 本地桥接 ↔ 任意外部 AI」** 双段分离协议；
> - 本改版仓库地址：[shiwunaiaqwq/xiaoai-selena-companion-home](https://github.com/shiwunaiaqwq/xiaoai-selena-companion-home)；
> - 牧场动物菲比创意与素材灵感来源：**CAICAI-AI**（B站 UID：`245034193`）。

---

## 一、 原仓库（Cabin World）是如何连接 AI 的？

原项目 `BabyBus2022/cabin-world` 严格坚持 **游戏本体不内置模型与 API Key** 的安全架构，采用两段本地通信：

1. **游戏端（Godot）↔ 桥接端（Node.js）**：
   - 本地 `127.0.0.1` 随机端口 **TCP + NDJSON（每行一条 JSON）**；
   - 桥接启动时在 `<dataDir>/world/game-link.json` 写入端口号与 32 字节随机 `token`，游戏读取后握手连接。
2. **桥接端（Node.js）↔ 外部 AI / 机器人**：
   - **本地 HTTP/1.1 JSON API**（默认 `http://127.0.0.1:18790`），凭证写入 `<dataDir>/bridge.json`（`Authorization: Bearer <token>`，且拒绝带浏览器 `Origin` 头的跨站请求）；
   - **标准 OpenAI Tools**（`GET /v1/tools` + `POST /v1/tool`）；
   - **MCP over stdio**（`mcp-server.mjs` 将 JSON-RPC 2.0 转为 HTTP 请求，支持 Claude / Cursor / DSH 等客户端即插即用）。

---

## 二、 3 分钟通用版快速启动（无需 AstrBot）

> 环境要求：**Node.js 22.13+**（零第三方依赖，直接复用内置 `node:sqlite`）

### 第 1 步：启动通用桥接服务
```bash
node universal-bridge.mjs --data ./data --port 18790
```
启动后会生成：
- `./data/world/game-link.json`（给 Godot 游戏客户端连接用）
- `./data/bridge.json`（给外部 AI / MCP / Python 脚本连接用）

### 第 2 步：启动小屋游戏并指向通用数据目录
```bash
CabinWorld-characters.exe -- --data "./data"
```

### 第 3 步：任选一种方式接入你的 AI

#### 方式 A：MCP 客户端接入（Claude Desktop / Cursor / Cherry Studio / DeepSeek Harness）
在你的 MCP 配置文件中加入：
```json
{
  "mcpServers": {
    "xiaoai-selena-cabin": {
      "command": "node",
      "args": ["/绝对路径/universal-ai-adapter/mcp-server.mjs", "--data", "/绝对路径/universal-ai-adapter/data"]
    }
  }
}
```
配置完成后，你的 AI 就会自动获得 `cabin_status`、`cabin_move`、`cabin_reply_note`、`cabin_write_visit_note`、`cabin_play_action` 五个工具！

#### 方式 B：Python / NoneBot / OpenAI API 接入
直接使用本目录下的零依赖客户端 `cabin_client.py`：
```python
from cabin_client import UniversalCabinClient

cabin = UniversalCabinClient("data/bridge.json")
summary = cabin.summary()
cabin.move("xiaoai", "balcony", "在三楼阳光花房照看雪绒豹多肉")
cabin.write_visit_note("selena", "ranch", "海狮菲比今天在池塘栈桥顶球顶得特别起劲。")
tools = cabin.tools()
```

#### 方式 C：HTTP API 直接调用（任意语言）
- `GET http://127.0.0.1:18790/v1/health` — 健康检查（无需鉴权）
- `GET http://127.0.0.1:18790/v1/tools` — 获取 OpenAI Tools Schema
- `GET http://127.0.0.1:18790/v1/summary` — 获取全屋状态摘要
- `POST http://127.0.0.1:18790/v1/tool` — 统一工具调用：`{"name": "cabin_move", "arguments": {...}}`
- `POST http://127.0.0.1:18790/v1/presence` — 快捷更新角色房间与活动

> 所有鉴权接口需携带 Header：`Authorization: Bearer <bridge.json 中的 token>`。
