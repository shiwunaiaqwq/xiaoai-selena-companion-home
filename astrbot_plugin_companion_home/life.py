"""Persistent household details and event-driven sleep, without extra model calls."""

import json
from datetime import datetime, timedelta, timezone
from .meals import is_sleep_time,wake_at

CN = timezone(timedelta(hours=8))
SPACES = {
    "xiaoai": [
        ("singing", "练歌角", "cup"),
        ("gaming", "游戏角", "sofa"),
        ("memories", "相册与回忆墙", "book"),
        ("window", "窗边小窝", "sun"),
    ],
    "selena": [("music", "音乐工作室", "book")],
}
GUIDANCE = {
    "xiaoai": "唱歌、游戏、相册和窗边是她的生活兴趣。可以卡关、试唱不满意、临时改变主意，避免永远顺利或永远闯祸。",
    "selena": "卧室兼书房，卧室书桌负责阅读、手记与书信，不再有独立书房；二楼音乐工作室负责试奏、修改乐谱和与雪歌听录音回放。保留探索欲、幽默和自己的判断，不只写情书或忧伤。",
}


class Life:
    """Keep all household additions separate from existing scene and memory data."""

    def __init__(self, store, character):
        self.store, self.character = store, character
        with store.connect() as db:
            db.execute(
                "CREATE TABLE IF NOT EXISTS household(character TEXT PRIMARY KEY, data TEXT NOT NULL)"
            )
            db.execute("INSERT OR IGNORE INTO household VALUES(?,?)", (character, "{}"))

    def view(self, at=None):
        """Read saved details and derive sleep at the requested Shanghai time."""
        at = at or datetime.now(CN)
        with self.store.connect() as db:
            data = json.loads(
                db.execute(
                    "SELECT data FROM household WHERE character=?", (self.character,)
                ).fetchone()[0]
            )
        scene = self.store.snapshot(self.character)["state"]
        night = is_sleep_time(self.character,at)
        owner_active = at.timestamp() - data.get("owner_last", 0) < 600
        awake = any(
            expiry > at.timestamp() for expiry in data.get("wakes", {}).values()
        )
        data["sleep"] = (
            "清醒陪伴中"
            if night and (owner_active or scene.get("together"))
            else (
                "被叫醒了"
                if night and awake
                else (
                    "睡着了"
                    if night
                    else ("准备休息" if at.hour == 23 and at.minute >= 50 else "清醒")
                )
            )
        )
        data["night"] = night
        data["wake_at"] = wake_at(self.character)
        data["day_highlights"] = [
            x
            for x in data.get("highlights", [])
            if x["time"][:10] == at.date().isoformat()
        ][-3:]
        return data

    def contact(self, session, owner, direct, text, message_id="", at=None):
        """Record real contact once; a wake only admits the originating conversation."""
        at = at or datetime.now(CN)
        stamp = at.timestamp()
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            data = json.loads(
                db.execute(
                    "SELECT data FROM household WHERE character=?", (self.character,)
                ).fetchone()[0]
            )
            wakes = {k: v for k, v in data.get("wakes", {}).items() if v > stamp}
            first_wake = is_sleep_time(self.character,at) and session not in wakes
            accepted = direct or session in wakes
            if accepted:
                wakes[session] = stamp + (600 if owner else 300)
            data["wakes"] = wakes
            if owner and accepted:
                data["owner_last"] = stamp
                arrival = (
                    "回家"
                    if text.strip() in ("我回来了", "回来了", "我到家了")
                    else (
                        "出门"
                        if text.strip() in ("我出门了", "我走了", "我先出门了")
                        else ""
                    )
                )
                if arrival and data.get("last_arrival_id") != (
                    message_id or f"{session}:{text}:{int(stamp // 60)}"
                ):
                    data["arrival"] = {
                        "kind": arrival,
                        "time": at.isoformat(),
                        "text": text[:120],
                    }
                    data["last_arrival_id"] = (
                        message_id or f"{session}:{text}:{int(stamp // 60)}"
                    )
                    db.execute(
                        "INSERT INTO events(character,time,kind,payload) VALUES(?,?,?,?)",
                        (
                            self.character,
                            at.isoformat(),
                            "arrival",
                            json.dumps(
                                {
                                    "activity": "你" + arrival + "了",
                                    "detail": text[:120],
                                },
                                ensure_ascii=False,
                            ),
                        ),
                    )
            db.execute(
                "UPDATE household SET data=? WHERE character=?",
                (json.dumps(data, ensure_ascii=False), self.character),
            )
        return accepted, first_wake

    def update(self, kind, title, detail, evidence, reference="", at=None):
        """Persist sourced projects, repeated habits, memorabilia and quiet companionship."""
        at = at or datetime.now(CN)
        if (
            kind
            not in (
                "project",
                "habit",
                "memento",
                "companionship",
                "highlight",
                "trace",
                "draft",
            )
            or not title.strip()
            or not evidence
        ):
            raise ValueError("Invalid household update")
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            data = json.loads(
                db.execute(
                    "SELECT data FROM household WHERE character=?", (self.character,)
                ).fetchone()[0]
            )
            key = {
                "project": "projects",
                "habit": "habits",
                "memento": "mementos",
                "highlight": "highlights",
                "trace": "traces",
            }.get(kind)
            item = {
                "title": title.strip()[:80],
                "detail": detail.strip()[:240],
                "time": at.isoformat(),
                "reference": str(reference)[:80],
                "evidence": [evidence],
            }
            if key:
                items = data.setdefault(key, [])
                old = next((x for x in items if x["title"] == item["title"]), None)
                if old:
                    item["evidence"] = list(
                        dict.fromkeys(old.get("evidence", []) + [evidence])
                    )[-10:]
                    items.remove(old)
                if kind == "habit":
                    item["confirmed"] = len(item["evidence"]) >= 3
                items.append(item)
                data[key] = items[-24:]
            else:
                if kind == "companionship":
                    scene = self.store.snapshot(self.character)["state"]
                    if title in (
                        "安静陪伴",
                        "认真听你说",
                        "一起做事",
                        "各做各的",
                    ) and not data.get("paused_scene"):
                        data["paused_scene"] = scene
                    if title == "结束陪伴":
                        item["resume"] = data.pop("paused_scene", None)
                data[kind] = item
            db.execute(
                "UPDATE household SET data=? WHERE character=?",
                (json.dumps(data, ensure_ascii=False), self.character),
            )
        return item

    def trace_scene(self, old, plan):
        """Retain the last actual activity in each room when the resident moves."""
        if old.get("room") != plan["room"]:
            self.update(
                "trace",
                old.get("room", "living"),
                old.get("detail", ""),
                old.get("updated_at", "scene"),
            )


def rooms_for(character, base):
    """Return a character-specific room catalogue without affecting legacy rooms."""
    result = [dict(r) for r in base]
    result.extend(
        {"id": i, "name": n, "icon": icon, "area": "home"}
        for i, n, icon in SPACES[character]
    )
    return result
