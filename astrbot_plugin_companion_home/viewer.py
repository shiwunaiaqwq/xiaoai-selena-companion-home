"""Password-protected LAN read-only viewer using the same bundled home page."""

import asyncio
import hashlib
import hmac
import ipaddress
import json
import secrets
import time
from pathlib import Path

from aiohttp import web

BRIDGE = """window.AstrBotPluginPage={ready:async()=>{},apiGet:async(e,p={})=>{const r=await fetch('/api/'+e+'?'+new URLSearchParams(p));if(r.status===401){location.reload();throw Error('请重新登录')}if(!r.ok)throw Error('读取失败');return r.json()},apiPost:async()=>{throw Error('手机页面仅供查看，请在QQ私聊中操作')}};document.addEventListener('DOMContentLoaded',()=>{document.querySelector('#note-form').hidden=true;document.querySelector('#refresh-plan').hidden=true});"""
LOGIN = """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>她们的家</title><style>body{background:#201b32;color:#fff;font:18px sans-serif;max-width:380px;margin:15vh auto;padding:24px}input,button{box-sizing:border-box;width:100%;padding:14px;margin-top:18px;border-radius:12px;border:0}button{background:#e7c8ed}</style><h1>她们的家</h1><p>输入主人访问密码</p><form method="post" action="/login"><input type="password" name="password" autocomplete="current-password" required maxlength="100"><button>进屋看看</button></form></html>"""


class LanViewer:
    """Expose only read-only home data after authentication, never AstrBot admin APIs."""

    def __init__(self, plugin):
        self.plugin = plugin
        self.runner = None
        self.attempts = {}
        path = plugin.root / "lan_access.json"
        if not path.exists():
            path.write_text(
                json.dumps(
                    {
                        "password": secrets.token_urlsafe(15),
                        "secret": secrets.token_hex(32),
                    }
                ),
                encoding="utf-8",
            )
        self.access = json.loads(path.read_text(encoding="utf-8"))

    async def start(self, host, port=18782):
        """Bind to the configured private interface with a bounded login body."""
        if host == "auto":
            process = await asyncio.create_subprocess_exec(
                "powershell.exe",
                "-NoProfile",
                "-Command",
                "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'WLAN|Wi-Fi|无线' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -ExpandProperty IPAddress",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                output, _ = await asyncio.wait_for(process.communicate(), timeout=12)
            except (TimeoutError, asyncio.CancelledError):
                process.kill()
                await process.wait()
                raise
            candidates = output.decode("ascii", errors="ignore").split()
            host = next(
                (
                    value
                    for value in candidates
                    if any(
                        ipaddress.ip_address(value) in net
                        for net in (
                            ipaddress.ip_network("192.168.0.0/16"),
                            ipaddress.ip_network("10.0.0.0/8"),
                            ipaddress.ip_network("172.16.0.0/12"),
                        )
                    )
                ),
                "",
            )
            if not host:
                raise ValueError("No private Wi-Fi address available")
        address = ipaddress.ip_address(host)
        if not address.is_private or address.is_loopback:
            raise ValueError("LAN viewer requires a private network address")
        app = web.Application(client_max_size=2048)
        app.router.add_route("*", "/{path:.*}", self.handle)
        self.runner = web.AppRunner(app, access_log=None)
        await self.runner.setup()
        await web.TCPSite(self.runner, host, int(port)).start()
        self.host = host

    async def close(self):
        """Release the listener during plugin reload."""
        if self.runner:
            await self.runner.cleanup()

    async def handle(self, request):
        """Authenticate LAN requests and serve a strict asset/data allowlist."""
        peer = request.remote or ""
        try:
            if not ipaddress.ip_address(peer).is_private:
                raise web.HTTPForbidden()
        except ValueError:
            raise web.HTTPForbidden() from None
        now = int(time.time())
        token = request.cookies.get("home_session", "")
        expiry, _, signature = token.partition(".")
        signed = hmac.new(
            self.access["secret"].encode(), expiry.encode(), hashlib.sha256
        ).hexdigest()
        authenticated = (
            expiry.isdigit()
            and now < int(expiry) <= now + 28800
            and hmac.compare_digest(signature, signed)
        )
        if request.path == "/login" and request.method == "POST":
            count, since = self.attempts.get(peer, (0, now))
            if now - since > 600:
                count, since = 0, now
            if count >= 5:
                raise web.HTTPTooManyRequests(text="稍后再试")
            form = await request.post()
            if not hmac.compare_digest(
                str(form.get("password", "")).encode("utf-8"),
                self.access["password"].encode("utf-8"),
            ):
                self.attempts[peer] = (count + 1, since)
                return web.Response(
                    text=LOGIN.replace("输入主人访问密码", "密码不正确，请重试"),
                    content_type="text/html",
                    status=401,
                )
            self.attempts.pop(peer, None)
            expiry = str(now + 28800)
            signature = hmac.new(
                self.access["secret"].encode(), expiry.encode(), hashlib.sha256
            ).hexdigest()
            response = web.HTTPFound("/")
            response.set_cookie(
                "home_session",
                expiry + "." + signature,
                httponly=True,
                samesite="Strict",
                max_age=28800,
            )
            raise response
        if not authenticated:
            return web.Response(
                text=LOGIN,
                content_type="text/html",
                status=200 if request.path == "/" else 401,
                headers={"Cache-Control": "no-store"},
            )
        if request.method != "GET":
            raise web.HTTPMethodNotAllowed(request.method, ["GET"])
        headers = {
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer",
            "X-Frame-Options": "DENY",
        }
        if request.path == "/api/state":
            character = request.query.get("character", self.plugin.character)
            if character not in ("xiaoai", "selena"):
                raise web.HTTPBadRequest()
            day = request.query.get("day")
            if day and (len(day) != 10 or not all(x.isdigit() for x in day.split("-"))):
                raise web.HTTPBadRequest()
            return web.json_response(
                self.plugin.home_snapshot(character, day), headers=headers
            )
        if request.path == "/api/plugin/page/bridge-sdk.js":
            return web.Response(
                text=BRIDGE, content_type="text/javascript", headers=headers
            )
        name = {
            "/": "index.html",
            "/index.html": "index.html",
            "/style.css": "style.css",
            "/theme.css": "theme.css",
            "/app.js": "app.js",
        }.get(request.path)
        if not name:
            raise web.HTTPNotFound()
        path = Path(__file__).parent / "views/home" / name
        mime = {".html": "text/html", ".css": "text/css", ".js": "text/javascript"}[
            path.suffix
        ]
        return web.Response(body=path.read_bytes(), content_type=mime, headers=headers)
