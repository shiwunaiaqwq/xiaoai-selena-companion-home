"""Verified owner group chat and durable delivery of generated sister dialogue."""

import asyncio
import hashlib
import json
import time
from datetime import datetime, timedelta

from astrbot.api import logger
from astrbot.api.event import MessageChain

from .engine import CN, now_iso




class SisterGroup:
    """Keep the shared QQ discussion independent of private messages."""

    def __init__(self, home):
        self.home = home
        self.task = None
        with home.store.connect() as db:
            db.execute(
                "CREATE TABLE IF NOT EXISTS sister_group_context(id INTEGER PRIMARY KEY AUTOINCREMENT,event_key TEXT NOT NULL UNIQUE,time TEXT NOT NULL,actor TEXT NOT NULL,text TEXT NOT NULL)"
            )
            db.execute(
                "CREATE TABLE IF NOT EXISTS sister_group_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT,character TEXT NOT NULL,kind TEXT NOT NULL,exchange_id INTEGER NOT NULL,part TEXT NOT NULL,text TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'pending',created_at TEXT NOT NULL,sent_at TEXT,message_id TEXT,attempts INTEGER NOT NULL DEFAULT 0,retry_at REAL NOT NULL DEFAULT 0,error TEXT,UNIQUE(character,kind,exchange_id,part))"
            )

            db.execute(
                "UPDATE sister_group_outbox SET status='unknown',error='Previous delivery outcome is unknown' WHERE character=? AND status='sending'",
                (home.character,),
            )

    @property
    def bots(self):
        return {who: str(self.home.config.get(who + "_qq", "")).strip() for who in ("xiaoai", "selena")}

    @property
    def group_id(self):
        return str(self.home.config.get("sister_group_id", "")).strip()

    @property
    def enabled(self):
        return bool(
            self.home.config.get("sister_group_enabled", False)
            and self.group_id.isdigit()
            and all(v.isdigit() and int(v) > 0 for v in self.bots.values())
        )

    @property
    def umo(self):
        return self.home.owner_umo.partition(":")[0] + ":GroupMessage:" + self.group_id

    def record(self, key, actor, text):
        text = " ".join(str(text or "").split())[:1000]
        if not text:
            return
        with self.home.store.connect() as db:
            db.execute(
                "INSERT OR IGNORE INTO sister_group_context(event_key,time,actor,text) VALUES(?,?,?,?)",
                (str(key)[:180], now_iso(), actor, text),
            )

    def context(self):
        if not self.enabled:
            return []
        with self.home.store.connect() as db:
            rows = db.execute(
                "SELECT time,actor,text FROM sister_group_context WHERE time>=? ORDER BY id DESC LIMIT 10",
                ((datetime.now(CN) - timedelta(hours=6)).isoformat(),),
            ).fetchall()
        return [dict(row) for row in reversed(rows)]

    def location(self, pair, at):
        if not self.enabled:
            return self.home.housemates._location(pair, at)
        if len(pair) != 2 or not (
            7 <= at.hour < 23 or (at.hour == 23 and at.minute < 30)
        ):
            return ""
        from .meals import is_sleep_time

        if any(
            not row["fresh"] or row["state"].get("together") for row in pair.values()
        ) or any(is_sleep_time(who, at) for who in pair):
            return ""
        return "QQ家庭群"

    def on_message(self, event):
        if not self.enabled or str(event.get_group_id()) != self.group_id:
            return False
        sender = str(event.get_sender_id())
        if sender in self.bots.values():
            event.stop_event()
            return True
        if sender != str(self.home.config.get("owner_qq", "0")):
            return False
        mid = str(getattr(event.message_obj, "message_id", ""))
        text = str(event.get_message_str() or "")
        raw = getattr(event.message_obj, "raw_message", None)
        stamp = raw.get("time") if isinstance(raw, dict) else None
        if stamp:
            original = raw.get("message", raw.get("raw_message", text))
            canonical = json.dumps(original, ensure_ascii=False, sort_keys=True)
            mid = hashlib.sha256(
                f"{self.group_id}:{sender}:{stamp}:{canonical}".encode()
            ).hexdigest()
            # Each adapter omits its own first @ from message_str.
            # Use the original segments so both instances store one shared line.
            if isinstance(original, list):
                chunks = []
                for segment in original:
                    if not isinstance(segment, dict):
                        continue
                    data = segment.get("data") or {}
                    if segment.get("type") == "text":
                        chunks.append(str(data.get("text", "")))
                    elif segment.get("type") == "at":
                        chunks.append(" @" + str(data.get("qq", "")) + " ")
                text = "".join(chunks).strip() or text
        self.record("owner:" + mid, "主人", text)
        mentions = {
            str(getattr(part, "qq", ""))
            for part in event.get_messages()
            if part.__class__.__name__ == "At"
        }
        mentions.discard("")
        if (
            mentions
            and "all" not in mentions
            and self.bots[self.home.character] not in mentions
        ):
            event.stop_event()
            return True
        event.set_extra("sister_group_owner", True)
        event.is_at_or_wake_command = True
        # True suppresses AstrBot default replies; leave the normal agent enabled.
        event.should_call_llm(False)
        return True

    def enqueue(self, kind, exchange_id, part, text):
        if not self.enabled:
            return
        with self.home.store.connect() as db:
            db.execute(
                "INSERT OR IGNORE INTO sister_group_outbox(character,kind,exchange_id,part,text,created_at) VALUES(?,?,?,?,?,?)",
                (
                    self.home.character,
                    kind,
                    exchange_id,
                    part,
                    str(text)[:1000],
                    now_iso(),
                ),
            )
        self.kick()

    def ready(self, kind, exchange_id, at=None):
        if not self.enabled:
            return True
        at = at or datetime.now(CN)
        with self.home.store.connect() as db:
            row = db.execute(
                "SELECT sent_at FROM sister_group_outbox WHERE kind=? AND exchange_id=? AND part='opening' AND status='sent'",
                (kind, exchange_id),
            ).fetchone()
        return bool(
            row
            and row[0]
            and (at - datetime.fromisoformat(row[0])).total_seconds() >= 20
        )

    def kick(self):
        if self.enabled and (self.task is None or self.task.done()):
            self.task = asyncio.create_task(self.flush())

    async def flush(self):
        with self.home.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM sister_group_outbox WHERE character=? AND status='pending' AND retry_at<=? ORDER BY id LIMIT 1",
                (self.home.character, time.time()),
            ).fetchone()
            if row is None:
                return
            row = dict(row)
            db.execute(
                "UPDATE sister_group_outbox SET status='sending',attempts=attempts+1 WHERE id=?",
                (row["id"],),
            )
        try:
            sent = await self.home.context.send_message(
                self.umo, MessageChain().message(row["text"])
            )
            if not sent:
                raise RuntimeError("Group delivery returned no receipt")
            with self.home.store.connect() as db:
                db.execute(
                    "UPDATE sister_group_outbox SET status='sent',sent_at=?,error=NULL WHERE id=?",
                    (now_iso(), row["id"]),
                )
            self.record(
                f"auto:{row['id']}",
                "小爱" if self.home.character == "xiaoai" else "赛琳娜",
                row["text"],
            )
        except asyncio.CancelledError:
            with self.home.store.connect() as db:
                db.execute(
                    "UPDATE sister_group_outbox SET status='unknown',error='Delivery interrupted; do not retry blindly' WHERE id=?",
                    (row["id"],),
                )
            raise
        except Exception as exc:
            with self.home.store.connect() as db:
                db.execute(
                    "UPDATE sister_group_outbox SET status='pending',retry_at=?,error=? WHERE id=?",
                    (time.time() + 120, type(exc).__name__, row["id"]),
                )
            logger.warning(
                "[companion_home] Sister group delivery deferred: %s",
                type(exc).__name__,
            )

    async def status(self):
        result = {
            "enabled": self.enabled,
            "group_id": self.group_id,
            "connected": False,
        }
        if not self.enabled:
            return result
        try:
            platform = self.home.context.get_platform_inst(
                self.home.owner_umo.partition(":")[0]
            )
            client = platform.get_client()
            info = await client.call_action(
                "get_group_info", group_id=int(self.group_id), no_cache=True
            )
            members = await client.call_action(
                "get_group_member_list", group_id=int(self.group_id), no_cache=True
            )
            if isinstance(info, dict) and isinstance(info.get("data"), dict):
                info = info["data"]
            if isinstance(members, dict):
                members = members.get("data", [])
            ids = (
                {str(item.get("user_id")) for item in members}
                if isinstance(members, list)
                else set()
            )
            result.update(
                connected=True,
                group_name=info.get("group_name", ""),
                has_xiaoai=self.bots["xiaoai"] in ids,
                has_selena=self.bots["selena"] in ids,
                has_owner=str(self.home.config.get("owner_qq", "0")) in ids,
            )
        except Exception as exc:
            result["error"] = type(exc).__name__
        return result

    async def close(self):
        if self.task and not self.task.done():
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
