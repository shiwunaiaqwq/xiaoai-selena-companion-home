"""Real Bilibili watch poses and a separately budgeted sister conversation queue."""

import asyncio
import json
from datetime import datetime, timedelta

from astrbot.api import logger

from .engine import CN, now_iso
from .dialogue_quota import shared_daily_count, shared_daily_limit


class BiliLife:
    """Keep video sharing independent of ordinary housemate conversation limits."""

    def __init__(self, home):
        self.home = home
        self.task = None
        with home.store.connect() as db:
            db.execute(
                "CREATE TABLE IF NOT EXISTS bili_topics(bvid TEXT PRIMARY KEY,created_at TEXT NOT NULL,topic TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'pending')"
            )
            db.execute(
                "CREATE TABLE IF NOT EXISTS bili_sister_exchanges(id INTEGER PRIMARY KEY AUTOINCREMENT,time TEXT NOT NULL,bvid TEXT NOT NULL UNIQUE,location TEXT NOT NULL,topic TEXT NOT NULL,opening TEXT NOT NULL DEFAULT '',reply TEXT,reply_at TEXT,status TEXT NOT NULL)"
            )

    def begin_watch(self):
        home = self.home
        if home.character != "xiaoai" or not home.config.get("enabled", True):
            return None
        at = datetime.now(CN)
        before = home.store.snapshot("xiaoai")["state"]
        life = home.life.view(at)
        if (
            life.get("night")
            or before.get("together")
            or life.get("companionship", {}).get("title")
            in ("安静陪伴", "各做各的", "认真听你说", "一起做事")
        ):
            return None
        meal = before.get("interaction_id") in {"breakfast", "lunch", "dinner"}
        room = "dining" if meal else "bedroom" if at.hour >= 22 else "living"
        interaction = (
            "eat_phone" if meal else "bed_phone" if room == "bedroom" else "sofa_phone"
        )
        description = (
            "吃饭时顺手刷一条视频"
            if meal
            else "躺在床上用手机刷视频"
            if room == "bedroom"
            else "坐在沙发上用手机刷视频"
        )
        plan = {
            **before,
            "room": room,
            "interaction_id": interaction,
            "activity": description,
            "detail": "正在读取B站视频的采样画面和字幕，看看有没有新鲜的内容。",
            "bili_pose": "eat_phone"
            if meal
            else "bed_phone"
            if room == "bedroom"
            else "sofa_phone",
            "bili_until": (at + timedelta(minutes=10)).isoformat(),
        }
        revision = before.get("revision", 0)
        if home.store.commit_plan(
            "xiaoai", plan, "bilibili", "正在看视频", expected_revision=revision
        ):
            return {"before": before, "revision": revision + 1}
        return None

    def end_watch(self, token):
        home = self.home
        current = home.store.snapshot("xiaoai")["state"]
        if (
            current.get("source") != "bilibili"
            or current.get("revision") != token["revision"]
        ):
            return
        before = dict(token["before"])
        before.update(bili_pose="", bili_until="")
        home.store.commit_plan(
            "xiaoai",
            before,
            before.get("source", "ai"),
            "视频看完，继续之前的日常",
            expected_revision=token["revision"],
        )

    def offer(self, topic):
        if (
            self.home.character != "xiaoai"
            or not topic.get("bvid")
            or topic.get("score", 0) < 7
        ):
            return
        with self.home.store.connect() as db:
            db.execute(
                "INSERT OR IGNORE INTO bili_topics(bvid,created_at,topic) VALUES(?,?,?)",
                (topic["bvid"], now_iso(), json.dumps(topic, ensure_ascii=False)),
            )

    def kick(self):
        if not self.home.config.get("enabled", True):
            return
        if self.task is None or self.task.done():
            self.task = asyncio.create_task(self.tick())

    async def close(self):
        if self.task and not self.task.done():
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass

    def _location(self, db, at):
        pair = self.home.housemates._pair(db, at)
        return self.home.housemates._dialogue_location(pair, at)

    async def tick(self):
        home = self.home
        at = datetime.now(CN)
        exchange = None
        try:
            with home.store.connect() as db:
                db.execute("BEGIN IMMEDIATE")
                for row in db.execute(
                    "SELECT * FROM bili_sister_exchanges WHERE status='replied'"
                ).fetchall():
                    event_key = f"bili_sister:{row['id']}:{home.character}"
                    summary = f"小爱看了B站视频《{json.loads(row['topic']).get('title', '')}》后与赛琳娜分享。小爱：{row['opening']}；赛琳娜：{row['reply']}"
                    payload = home.experience_payload(
                        summary, "bilibili_sister_exchange"
                    )
                    db.execute(
                        "INSERT OR IGNORE INTO experience_outbox(character,event_key,event_id,time,payload) VALUES(?,?,?,?,?)",
                        (
                            home.character,
                            event_key,
                            None,
                            row["reply_at"],
                            json.dumps(payload, ensure_ascii=False),
                        ),
                    )
                db.execute(
                    "UPDATE bili_sister_exchanges SET status='expired' WHERE status IN ('drafting','pending','responding') AND time<?",
                    ((at - timedelta(minutes=10)).isoformat(),),
                )
                if home.dialogues.busy():
                    return
                if home.peer_task and not home.peer_task.done():
                    return
                location = self._location(db, at)
                if not location:
                    return
                if home.character == "selena":
                    row = db.execute(
                        "SELECT * FROM bili_sister_exchanges WHERE status='pending' ORDER BY id LIMIT 1"
                    ).fetchone()
                    if (
                        row
                        and row["location"] == location
                        and (
                            not getattr(home, "group", None)
                            or home.group.ready("bilibili", row["id"], at)
                        )
                    ):
                        exchange = dict(row)
                        db.execute(
                            "UPDATE bili_sister_exchanges SET status='responding' WHERE id=? AND status='pending'",
                            (row["id"],),
                        )
                else:
                    count = shared_daily_count(db, at)
                    recent = db.execute(
                        "SELECT time FROM bili_sister_exchanges ORDER BY id DESC LIMIT 1"
                    ).fetchone()
                    busy = db.execute(
                        "SELECT 1 FROM bili_sister_exchanges WHERE status IN ('drafting','pending','responding')"
                    ).fetchone()
                    if (
                        count >= shared_daily_limit(home.config)
                        or busy
                        or (
                            recent
                            and (at - datetime.fromisoformat(recent[0])).total_seconds()
                            < 1800
                        )
                    ):
                        return
                    row = db.execute(
                        "SELECT * FROM bili_topics WHERE status='pending' AND created_at>=? ORDER BY json_extract(topic,'$.score') DESC,created_at LIMIT 1",
                        ((at - timedelta(days=2)).isoformat(),),
                    ).fetchone()
                    if row:
                        cursor = db.execute(
                            "INSERT INTO bili_sister_exchanges(time,bvid,location,topic,status) VALUES(?,?,?,?,?)",
                            (
                                now_iso(),
                                row["bvid"],
                                location,
                                row["topic"],
                                "drafting",
                            ),
                        )
                        db.execute(
                            "UPDATE bili_topics SET status='used' WHERE bvid=?",
                            (row["bvid"],),
                        )
                        exchange = {
                            "id": cursor.lastrowid,
                            "location": location,
                            "topic": row["topic"],
                            "opening": "",
                        }
            if not exchange:
                return
            if home.group.enabled:
                if not home.dialogues.adopt("bilibili", exchange):
                    with home.store.connect() as db:
                        db.execute("UPDATE bili_sister_exchanges SET status='failed' WHERE id=? AND status IN ('drafting','responding')", (exchange["id"],))
                return
            line = await home.public_housemate_line(
                exchange["opening"] if home.character == "selena" else None,
                video=json.loads(exchange["topic"]),
            )
            line = " ".join(str(line or "").split())[:160].strip()
            with home.store.connect() as db:
                db.execute("BEGIN IMMEDIATE")
                if (
                    not line
                    or self._location(db, datetime.now(CN)) != exchange["location"]
                ):
                    db.execute(
                        "UPDATE bili_sister_exchanges SET status='expired' WHERE id=?",
                        (exchange["id"],),
                    )
                elif home.character == "xiaoai":
                    db.execute(
                        "UPDATE bili_sister_exchanges SET opening=?,status='pending' WHERE id=? AND status='drafting'",
                        (line, exchange["id"]),
                    )
                else:
                    stamp = now_iso()
                    db.execute(
                        "UPDATE bili_sister_exchanges SET reply=?,reply_at=?,status='replied' WHERE id=? AND status='responding'",
                        (line, stamp, exchange["id"]),
                    )
                    for who in ("xiaoai", "selena"):
                        payload = {
                            "room": exchange["location"],
                            "activity": "分享刚看见的趣事",
                            "detail": f"小爱：{exchange['opening']}\n赛琳娜：{line}",
                            "bili_exchange_id": exchange["id"],
                        }
                        db.execute(
                            "INSERT INTO events(character,time,kind,payload) VALUES(?,?,?,?)",
                            (
                                who,
                                stamp,
                                "housemate",
                                json.dumps(payload, ensure_ascii=False),
                            ),
                        )
            if getattr(home, "group", None):
                with home.store.connect() as db:
                    delivered = db.execute(
                        "SELECT status FROM bili_sister_exchanges WHERE id=?",
                        (exchange["id"],),
                    ).fetchone()
                if delivered and delivered[0] == (
                    "pending" if home.character == "xiaoai" else "replied"
                ):
                    home.group.enqueue(
                        "bilibili",
                        exchange["id"],
                        "opening" if home.character == "xiaoai" else "reply",
                        line,
                    )
        except asyncio.CancelledError:
            if exchange:
                with home.store.connect() as db:
                    db.execute(
                        "UPDATE bili_sister_exchanges SET status='failed' WHERE id=? AND status IN ('drafting','responding')",
                        (exchange["id"],),
                    )
            raise
        except Exception as exc:
            if exchange:
                with home.store.connect() as db:
                    db.execute(
                        "UPDATE bili_sister_exchanges SET status='failed' WHERE id=? AND status IN ('drafting','responding')",
                        (exchange["id"],),
                    )
            logger.warning(
                "[companion_home] Bilibili sister exchange failed: %s",
                type(exc).__name__,
            )
