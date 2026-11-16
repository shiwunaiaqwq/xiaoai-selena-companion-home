# 安装与配置

## AstrBot 两实例

参考版本 AstrBot 4.29.4；本包没有修改你的框架。将同一个 `astrbot_plugin_companion_home` 文件夹分别放入两实例的 `data/plugins` 中，再从管理页加载。模型由当前实例的有效提供商决定，不绑定任何中转站或模型密钥。

在配置页选择 `xiaoai` / `selena`。两实例的 `shared_directory` 必须指向同一**绝对目录**，但每实例自己的 `character` 必须不同。请使用一个新目录开始，避免误连接备份数据库。`owner_qq` 默认 0，必须自行填写；`owner_umo` 使用适配器实际会话来源，例如 `平台ID:FriendMessage:主人QQ`。不要把示例文字原样填入。

复制 `cards/xiaoai.txt` 与 `cards/selena.txt` 到对应主聊天人格。`xiaoai-maru.txt` 是可选的雷霆大雪绒口吻附加说明，本包没有把个人环境的双人格切换插件一起分发，因此不会凭这个文件自动进行 15% 抽签。小屋内部使用插件下 `personas/` 的副本；修改人物卡时同步修改对应副本。

姐妹群默认为关闭。要启用，设置 `sister_group_enabled`、`sister_group_id`、`xiaoai_qq`、`selena_qq`，并让两个机器人都加入该群。两者共用 `sister_dialogue_daily_limit=5` 的额度。先确认适配器支持发送消息，再开启自动群对话。

局域网访问默认关闭。需要时设置 `lan_enabled`，自行配置强密码和适当防火墙规则。不附带原用户的 LAN 密码。

可选截图功能：在插件目录运行 `npm install` 安装 playwright-core，并安装 Microsoft Edge。若不使用 QQ 房间截图，可以不装截图依赖。

## 游戏和桥接

安装 Node.js 22.13 或更新版本（桥接使用内置 `node:sqlite`）。安装与 `project.godot` 中版本特性兼容的 Godot 4.7，在编辑器中导入 `character-edition/game/project.godot`，首次导入会重建 `.godot` 缓存。包内没有预编译引擎。

先运行两个 AstrBot 实例，使共享目录内出现 `home.sqlite3` 且有两位角色数据。然后在 PowerShell 中：

```powershell
$env:COMPANION_HOME_DB = 'D:\YourHomeData\home.sqlite3'
node .\astrbot-link\bridge.mjs
```

保持桥接运行，另一个终端从仓库根目录运行（替换 Godot 路径）：

```powershell
& 'D:\Tools\Godot.exe' --path .\character-edition\game -- --data "$PWD\character-edition\data-astrbot-live" --save "$PWD\character-edition\data-astrbot-live\saves"
```

桥接读取小屋数据库并展示，不能把旧状态文件当成数据源。`COMPANION_GAME_DIR` 可选，用于自定义包含 `game/` 的目录。不要把运行后产生的 `data-astrbot-live/`、控制令牌或数据库上传到公开仓库。

## 可选依赖与边界

外部记忆、QQ空间日记、B站浏览并不是本包的完整独立功能。请自行按各依赖插件文档配置；未安装时不要开启需要它们的任务。本包没有携带你的记忆向量库、QQ会话、视频观看记录或模型密钥。

检查桥接映射：`node .\astrbot-link\test-mapping.mjs`。第一次使用建议禁用群发送，在独立数据目录验证配置后再启用。
