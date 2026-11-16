"""Bounded public housemate exchanges; each instance writes only its own words."""

import json
from datetime import datetime, timedelta, timezone

from .layout import canonical_room, room_label
from .meals import is_sleep_time
from .dialogue_quota import shared_daily_count, shared_daily_limit

CN = timezone(timedelta(hours=8))
NAMES = {"xiaoai": "小爱", "selena": "赛琳娜"}
PUBLIC = {"living", "kitchen", "dining", "park", "store", "arcade", "restaurant"}


class Housemates:
    def __init__(self, store, character, config=None):
        self.store, self.character = store, character
        self.config = config if config is not None else {}
        with store.connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS housemate_exchanges(
                id INTEGER PRIMARY KEY AUTOINCREMENT,time TEXT NOT NULL,starter TEXT NOT NULL,
                recipient TEXT NOT NULL,location TEXT NOT NULL,opening TEXT NOT NULL,
                reply TEXT,reply_at TEXT,status TEXT NOT NULL DEFAULT 'pending')""")

    @property
    def daily_limit(self):
        return shared_daily_limit(self.config)

    def _pair(self, db, at):
        states = {}
        for row in db.execute(
            "SELECT character,state,heartbeat FROM residents WHERE character IN (?,?)",
            tuple(NAMES),
        ):
            state = json.loads(row["state"])
            who = row["character"]
            try:
                fresh = (
                    0
                    <= (at - datetime.fromisoformat(row["heartbeat"])).total_seconds()
                    < 180
                )
            except (ValueError, TypeError):
                fresh = False
            state["room"] = canonical_room(
                who, state.get("room"), state.get("activity", "")
            )
            h = db.execute(
                "SELECT data FROM household WHERE character=?", (who,)
            ).fetchone()
            household = json.loads(h[0]) if h else {}
            busy = (
                state.get("together")
                or at.timestamp() - household.get("owner_last", 0) < 600
            )
            busy = busy or household.get("companionship", {}).get("title") in (
                "安静陪伴",
                "各做各的",
                "认真听你说",
                "一起做事",
            )
            states[who] = {"state": state, "fresh": fresh, "busy": bool(busy)}
        return states

    @staticmethod
    def _location(pair, at):
        if (
            not (7 <= at.hour < 23 or (at.hour == 23 and at.minute < 30))
            or len(pair) != 2
        ):
            return ""
        if any(not x["fresh"] or x["busy"] for x in pair.values()):
            return ""
        if any(is_sleep_time(who, at) for who in NAMES):
            return ""
        rooms = [pair[k]["state"]["room"] for k in NAMES]
        if rooms[0] == rooms[1] and rooms[0] in PUBLIC:
            return rooms[0]
        if set(rooms) == {"music", "singing"}:
            return "adjacent_music_areas"
        return ""

    def _dialogue_location(self, pair, at):
        callback = getattr(self, "group_location", None)
        return callback(pair, at) if callback else self._location(pair, at)

    def view(self, character=None, at=None):
        who = character or self.character
        peer = "selena" if who == "xiaoai" else "xiaoai"
        at = at or datetime.now(CN)
        with self.store.connect() as db:
            pair = self._pair(db, at)
            other = pair.get(peer)
            messages = [
                dict(r)
                for r in db.execute(
                    "SELECT * FROM housemate_exchanges WHERE status IN ('pending','responding','replied','conversing','completed') ORDER BY id DESC LIMIT 4"
                )
            ]
            if db.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='bili_sister_exchanges'"
            ).fetchone():
                for row in db.execute(
                    "SELECT id,time,location,opening,reply,reply_at,status FROM bili_sister_exchanges WHERE status IN ('pending','responding','replied','conversing','completed') ORDER BY id DESC LIMIT 4"
                ):
                    item = dict(row)
                    item.update(
                        id=f"bili:{item['id']}",
                        starter="xiaoai",
                        recipient="selena",
                        kind="bilibili",
                    )
                    messages.append(item)
                messages.sort(key=lambda item: item["time"], reverse=True)
                messages = messages[:4]
            recent = db.execute(
                "SELECT time FROM housemate_exchanges ORDER BY id DESC LIMIT 1"
            ).fetchone()
            count = shared_daily_count(db, at)
            location = self._dialogue_location(pair, at)
            gap = (
                (at - datetime.fromisoformat(recent[0])).total_seconds()
                if recent
                else 999999
            )
            pending = db.execute(
                "SELECT 1 FROM housemate_exchanges WHERE status IN ('drafting','pending','responding') LIMIT 1"
            ).fetchone()
        private = other and other["state"]["room"] in ("bedroom", "bathroom", "balcony")
        public_activity = (
            (
                "正在自己的空间休息或忙碌"
                if private
                else other["state"].get("activity", "")
            )
            if other
            else "暂未开始日常"
        )
        return {
            "peer": {
                "id": peer,
                "name": NAMES[peer],
                "known": bool(other),
                "online": bool(other and other["fresh"]),
                "room": other["state"]["room"] if other else "",
                "room_name": room_label(peer, other["state"]["room"]) if other else "",
                "activity": public_activity,
                "busy_with_owner": bool(other and other["busy"]),
            },
            "can_start": bool(location and gap >= 5400 and count < self.daily_limit and not pending and not getattr(self, "conversation_busy", lambda: False)()),
            "location": location,
            "messages": messages,
            "relationship": "本小屋设定中赛琳娜是姐姐，小爱是妹妹；各自独立、自然相处，不改写原作亲属关系，不代替对方说话",
        }

    def start(self, line, at=None):
        if getattr(self, "conversation_busy", lambda: False)():
            return None
        drafting = line is None
        line = "" if drafting else " ".join(str(line).split())[:100].strip()
        at = at or datetime.now(CN)
        if not drafting and not line:
            return None
        who = self.character
        peer = "selena" if who == "xiaoai" else "xiaoai"
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            location = self._dialogue_location(self._pair(db, at), at)
            if not location:
                return None
            last = db.execute(
                "SELECT time FROM housemate_exchanges ORDER BY id DESC LIMIT 1"
            ).fetchone()
            if last and (at - datetime.fromisoformat(last[0])).total_seconds() < 5400:
                return None
            count = shared_daily_count(db, at)
            if (
                count >= self.daily_limit
                or db.execute(
                    "SELECT 1 FROM housemate_exchanges WHERE status IN ('drafting','pending','responding')"
                ).fetchone()
            ):
                return None
            row = db.execute(
                "INSERT INTO housemate_exchanges(time,starter,recipient,location,opening,status) VALUES(?,?,?,?,?,?)",
                (
                    at.isoformat(timespec="seconds"),
                    who,
                    peer,
                    location,
                    line,
                    "drafting" if drafting else "pending",
                ),
            )
            return row.lastrowid

    def finish_opening(self, id, line, at=None):
        at = at or datetime.now(CN)
        line = " ".join(str(line).split())[:100].strip()
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM housemate_exchanges WHERE id=? AND starter=? AND status='drafting'",
                (id, self.character),
            ).fetchone()
            if not row:
                return False
            if (
                not line
                or self._dialogue_location(self._pair(db, at), at) != row["location"]
                or (at - datetime.fromisoformat(row["time"])).total_seconds() > 600
            ):
                db.execute(
                    "UPDATE housemate_exchanges SET status='expired' WHERE id=?", (id,)
                )
                return False
            db.execute(
                "UPDATE housemate_exchanges SET opening=?,status='pending' WHERE id=?",
                (line, id),
            )
            return True

    def fail_opening(self, id):
        with self.store.connect() as db:
            db.execute(
                "UPDATE housemate_exchanges SET status='failed' WHERE id=? AND starter=? AND status='drafting'",
                (id, self.character),
            )

    def claim_reply(self, at=None):
        at = at or datetime.now(CN)
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            # A reload cannot leave an old generation permanently blocking the household.
            db.execute(
                "UPDATE housemate_exchanges SET status='expired' WHERE status IN ('drafting','pending','responding') AND time<?",
                ((at - timedelta(minutes=10)).isoformat(),),
            )
            row = db.execute(
                "SELECT * FROM housemate_exchanges WHERE recipient=? AND status='pending' ORDER BY id LIMIT 1",
                (self.character,),
            ).fetchone()
            if not row:
                return None
            row = dict(row)
            pair = self._pair(db, at)
            if self._dialogue_location(pair, at) != row["location"]:
                db.execute(
                    "UPDATE housemate_exchanges SET status='expired' WHERE id=?",
                    (row["id"],),
                )
                return None
            if not getattr(self, "group_ready", lambda *args: True)(
                "housemate", row["id"], at
            ):
                return None
            db.execute(
                "UPDATE housemate_exchanges SET status='responding' WHERE id=? AND status='pending'",
                (row["id"],),
            )
            return row

    def finish_reply(self, id, line, at=None):
        at = at or datetime.now(CN)
        line = " ".join(str(line).split())[:100].strip()
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM housemate_exchanges WHERE id=? AND recipient=? AND status='responding'",
                (id, self.character),
            ).fetchone()
            if not row:
                return False
            pair = self._pair(db, at)
            if (
                not line
                or self._dialogue_location(pair, at) != row["location"]
                or (at - datetime.fromisoformat(row["time"])).total_seconds() > 600
            ):
                db.execute(
                    "UPDATE housemate_exchanges SET status='expired' WHERE id=?", (id,)
                )
                return False
            stamp = at.isoformat(timespec="seconds")
            db.execute(
                "UPDATE housemate_exchanges SET reply=?,reply_at=?,status='replied' WHERE id=?",
                (line, stamp, id),
            )
            detail = f"{NAMES[row['starter']]}：{row['opening']}\n{NAMES[self.character]}：{line}"
            for who in NAMES:
                payload = {
                    "room": pair[who]["state"]["room"],
                    "activity": "和"
                    + NAMES["selena" if who == "xiaoai" else "xiaoai"]
                    + "聊了两句",
                    "detail": detail,
                    "housemate_exchange_id": id,
                }
                db.execute(
                    "INSERT INTO events(character,time,kind,payload) VALUES(?,?,?,?)",
                    (who, stamp, "housemate", json.dumps(payload, ensure_ascii=False)),
                )
            return True

    def fail_reply(self, id):
        with self.store.connect() as db:
            db.execute(
                "UPDATE housemate_exchanges SET status='failed' WHERE id=? AND recipient=? AND status='responding'",
                (id, self.character),
            )


def housemate_guidance():
    return (
        "\n[同住伙伴]\n本小屋共同生活设定中赛琳娜是姐姐，小爱是妹妹，两位各自独立、自然相处；这不是对原作亲属关系的断言。只依据housemate中的公开状态与小交谈了解对方，"
        "不能读取或猜测对方的私聊、便签、信件或私人记忆。可以关心对方的游戏、歌唱与音乐创作，保持自己的人设，"
        "不擅自发展恋爱、竞争或嫉妒关系，不安排对方的行动。"
        "只有can_start为真且确实想交流时，可选返回housemate_intent:true；实际发言将只依据公开动态单独生成。"
        "可以不说，不凑互动，不能写对方回答，不能把尚未收到的回复写成已经发生。"
        "对方的回应由她自己的实例与现用模型真实生成；完成的交流分别通过本人的原生记忆插件保存；启用家庭群时只向配置的家庭群发送，不向其他群或私聊转发。\n"
    )
