"""Owner gifts, a shared shop purse and durable household facts."""

import hashlib
import json
import re
from datetime import datetime, timedelta
from pathlib import Path

from .engine import CHARACTERS, CN

CATALOG = json.loads(Path(__file__).with_name("gift_catalog.json").read_text("utf-8"))
ITEMS = {item["id"]: item for item in CATALOG["items"]}


class Belongings:
    """Keep shop orders and gift ownership in the existing authoritative home DB."""

    def __init__(self, store, owner):
        self.store, self.owner = store, str(owner)
        with store.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS home_wallet(owner TEXT PRIMARY KEY,coins INTEGER NOT NULL,day TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS home_gifts(
                    id TEXT PRIMARY KEY,owner TEXT NOT NULL,character TEXT NOT NULL,item TEXT NOT NULL,
                    time TEXT NOT NULL,note TEXT NOT NULL DEFAULT '',price INTEGER NOT NULL,delta INTEGER NOT NULL,
                    location TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'stored',remaining INTEGER NOT NULL DEFAULT 0,
                    use_count INTEGER NOT NULL DEFAULT 0,last_use TEXT,reaction TEXT NOT NULL DEFAULT '',
                    reaction_status TEXT NOT NULL DEFAULT 'pending',reaction_retry TEXT,
                    affection_status TEXT NOT NULL DEFAULT 'pending',affection_result TEXT NOT NULL DEFAULT '{}');
                CREATE INDEX IF NOT EXISTS home_gifts_character_time ON home_gifts(character,time);
                CREATE TABLE IF NOT EXISTS home_gift_actions(
                    id TEXT PRIMARY KEY,gift_id TEXT NOT NULL,character TEXT NOT NULL,action TEXT NOT NULL,
                    time TEXT NOT NULL,result TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS home_affection(character TEXT PRIMARY KEY,data TEXT NOT NULL);
            """)
            db.execute(
                "INSERT OR IGNORE INTO home_wallet VALUES(?,?,?)",
                (
                    self.owner,
                    CATALOG["wallet"]["start"],
                    datetime.now(CN).date().isoformat(),
                ),
            )

    def grant_daily(self, at=None):
        """Apply the existing shop's allowance rule once per Beijing day.

        Args:
            at: Optional timezone-aware test clock.

        Returns:
            The committed balance; missed offline days are not minted retroactively.
        """
        at = at or datetime.now(CN)
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT coins,day FROM home_wallet WHERE owner=?", (self.owner,)
            ).fetchone()
            coins = row["coins"]
            if row["day"] < at.date().isoformat():
                coins = max(
                    coins,
                    min(CATALOG["wallet"]["cap"], coins + CATALOG["wallet"]["daily"]),
                )
                db.execute(
                    "UPDATE home_wallet SET coins=?,day=? WHERE owner=?",
                    (coins, at.date().isoformat(), self.owner),
                )
            return coins

    @staticmethod
    def _request_id(value):
        if not isinstance(value, str) or not re.fullmatch(
            r"[A-Za-z0-9_-]{8,96}", value
        ):
            raise ValueError("操作编号不正确，请刷新后重试")
        return value

    def purchase(self, character, item, note, request_id, at=None):
        """Atomically charge one purchase, record its owner and queue its real receipt.

        Args:
            character: The gift recipient.
            item: A catalogue identifier.
            note: The owner's short attached message, treated only as data.
            request_id: Stable client idempotency identifier.
            at: Optional test clock.

        Returns:
            A committed order summary, including whether this was a replay.

        Raises:
            ValueError: The item, recipient, balance or request is invalid.
        """
        if (
            character not in CHARACTERS
            or item not in ITEMS
            or not isinstance(note, str)
            or len(note) > 200
        ):
            raise ValueError("礼物、收件人或附言不正确")
        request_id = self._request_id(request_id)
        at = at or datetime.now(CN)
        stamp = at.isoformat(timespec="seconds")
        product = ITEMS[item]
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            prior = db.execute(
                "SELECT * FROM home_gifts WHERE id=?", (request_id,)
            ).fetchone()
            if prior:
                if (
                    prior["owner"],
                    prior["character"],
                    prior["item"],
                    prior["note"],
                ) != (self.owner, character, item, note):
                    raise ValueError("这个操作编号已用于另一份礼物")
                return self.receipt(prior, True)
            row = db.execute(
                "SELECT coins,day FROM home_wallet WHERE owner=?", (self.owner,)
            ).fetchone()
            coins = row["coins"]
            if row["day"] < at.date().isoformat():
                coins = max(
                    coins,
                    min(CATALOG["wallet"]["cap"], coins + CATALOG["wallet"]["daily"]),
                )
            if coins < product["price"]:
                raise ValueError("小屋零钱不足，先挑一件轻巧的小礼物吧")
            today = at.date().isoformat()
            count, awarded = db.execute(
                "SELECT COUNT(*),COALESCE(SUM(delta),0) FROM home_gifts WHERE character=? AND time>=?",
                (character, today),
            ).fetchone()
            repeats = db.execute(
                "SELECT COUNT(*) FROM home_gifts WHERE character=? AND item=? AND time>=?",
                (character, item, (at - timedelta(hours=24)).isoformat()),
            ).fetchone()[0]
            delta = max(0, min(3 - count, 6 - awarded))
            if repeats:
                delta = min(delta, 1 if repeats == 1 else 0)
            db.execute(
                "UPDATE home_wallet SET coins=?,day=? WHERE owner=?",
                (coins - product["price"], today, self.owner),
            )
            db.execute(
                """INSERT INTO home_gifts(id,owner,character,item,time,note,price,delta,location,remaining)
                          VALUES(?,?,?,?,?,?,?,?,?,?)""",
                (
                    request_id,
                    self.owner,
                    character,
                    item,
                    stamp,
                    note,
                    product["price"],
                    delta,
                    product["location"],
                    product["charges"],
                ),
            )
            payload = {
                "activity": "收到礼物",
                "detail": f"主人送来{product['name']}，已收进自己的背包",
                "item": item,
                "gift_id": request_id,
                "owner_note": note,
                "source": "home_owner_gift",
            }
            db.execute(
                "INSERT INTO events(character,time,kind,payload) VALUES(?,?,?,?)",
                (character, stamp, "gift", json.dumps(payload, ensure_ascii=False)),
            )
            row = db.execute(
                "SELECT * FROM home_gifts WHERE id=?", (request_id,)
            ).fetchone()
            return self.receipt(row, False)

    @staticmethod
    def receipt(row, replayed=False):
        return {
            "id": row["id"],
            "character": row["character"],
            "item": row["item"],
            "name": ITEMS[row["item"]]["name"],
            "price": row["price"],
            "replayed": replayed,
            "message": "礼物已送到她的背包，心意正在由她本人回应",
        }

    def act(self, character, gift_id, action, request_id, at=None):
        """Save a real owner inventory action without moving the resident.

        Args:
            character: Gift owner.
            gift_id: Existing owned gift identifier.
            action: use, carry, store or treasure.
            request_id: Stable idempotency key.
            at: Optional test clock.

        Returns:
            The committed change or an identical earlier result.
        """
        request_id = self._request_id(request_id)
        if action not in ("use", "carry", "store", "treasure"):
            raise ValueError("不支持这项背包操作")
        at = at or datetime.now(CN)
        stamp = at.isoformat(timespec="seconds")
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            previous = db.execute(
                "SELECT * FROM home_gift_actions WHERE id=?", (request_id,)
            ).fetchone()
            if previous:
                if (previous["gift_id"], previous["character"], previous["action"]) != (
                    gift_id,
                    character,
                    action,
                ):
                    raise ValueError("操作编号已用于别的动作")
                return json.loads(previous["result"])
            row = db.execute(
                "SELECT * FROM home_gifts WHERE id=? AND character=? AND owner=?",
                (gift_id, character, self.owner),
            ).fetchone()
            if not row:
                raise ValueError("这份礼物不在她的背包里")
            product = ITEMS[row["item"]]
            if row["status"] == "used" and action != "treasure":
                raise ValueError("这份已经用完，纪念记录仍然保留着")
            status, location, remaining = (
                row["status"],
                row["location"],
                row["remaining"],
            )
            if action == "use":
                if (
                    row["last_use"]
                    and (at - datetime.fromisoformat(row["last_use"])).total_seconds()
                    < 60
                ):
                    return {
                        "ok": True,
                        "message": "刚刚已经用过，先留住这会儿的小片段",
                        "id": gift_id,
                    }
                remaining = max(0, remaining - 1)
                if product["charges"] and remaining == 0:
                    status, location = "used", "已经用完，心意留下了"
                db.execute(
                    "UPDATE home_gifts SET use_count=use_count+1,last_use=? WHERE id=?",
                    (stamp, gift_id),
                )
            elif action == "carry":
                status, location = "stored", "随身带着"
            elif action == "store":
                status, location = "stored", product["location"]
            else:
                location = "纪念物收纳处"
                if status != "used":
                    status = "treasured"
            db.execute(
                "UPDATE home_gifts SET status=?,location=?,remaining=? WHERE id=?",
                (status, location, remaining, gift_id),
            )
            detail = (
                f"使用了主人送的{product['name']}"
                if action == "use"
                else f"把主人送的{product['name']}带在身边"
                if action == "carry"
                else f"把主人送的{product['name']}收在{location}"
            )
            result = {
                "ok": True,
                "id": gift_id,
                "message": detail,
                "location": location,
            }
            db.execute(
                "INSERT INTO home_gift_actions VALUES(?,?,?,?,?,?)",
                (
                    request_id,
                    gift_id,
                    character,
                    action,
                    stamp,
                    json.dumps(result, ensure_ascii=False),
                ),
            )
            db.execute(
                "INSERT INTO events(character,time,kind,payload) VALUES(?,?,?,?)",
                (
                    character,
                    stamp,
                    "gift_use" if action == "use" else "gift_store",
                    json.dumps(
                        {
                            "activity": "使用礼物" if action == "use" else "收好心意",
                            "detail": detail,
                            "gift_id": gift_id,
                            "item": row["item"],
                            "action_id": request_id,
                        },
                        ensure_ascii=False,
                    ),
                ),
            )
            return result

    def observe(self, character, state, at=None):
        """Let suitable owned gifts accompany actual existing furniture activities.

        Args:
            character: Current resident.
            state: The committed original home state.
            at: Optional test clock.
        """
        at = at or datetime.now(CN)
        action = state.get("interaction_id")
        if not action or state.get("activity") == "睡觉":
            return
        with self.store.connect() as db:
            rows = db.execute(
                "SELECT * FROM home_gifts WHERE character=? AND status='stored' ORDER BY time LIMIT 80",
                (character,),
            ).fetchall()
        for row in rows:
            product = ITEMS.get(row["item"])
            if not product or action not in product["actions"]:
                continue
            if row["last_use"] and row["last_use"][:10] == at.date().isoformat():
                continue
            key = (
                "auto-"
                + hashlib.sha256(
                    (
                        character
                        + ":"
                        + str(state.get("revision", 0))
                        + ":"
                        + row["id"]
                    ).encode()
                ).hexdigest()[:48]
            )
            self.act(character, row["id"], "use", key, at)
            break

    def view(self, character):
        """Project the actual bag and shared purse without granting money on reads."""
        with self.store.connect() as db:
            wallet = dict(
                db.execute(
                    "SELECT coins,day FROM home_wallet WHERE owner=?", (self.owner,)
                ).fetchone()
            )
            rows = db.execute(
                "SELECT * FROM home_gifts WHERE character=? AND owner=? ORDER BY time DESC,id DESC LIMIT 200",
                (character, self.owner),
            ).fetchall()
            total = db.execute(
                "SELECT COUNT(*) FROM home_gifts WHERE character=? AND owner=?",
                (character, self.owner),
            ).fetchone()[0]
            affection = db.execute(
                "SELECT data FROM home_affection WHERE character=?", (character,)
            ).fetchone()
        gifts = []
        for row in rows:
            if row["item"] not in ITEMS:
                continue
            gifts.append(
                {
                    **ITEMS[row["item"]],
                    "gift_id": row["id"],
                    "received_at": row["time"],
                    "note": row["note"],
                    "location": row["location"],
                    "status": row["status"],
                    "remaining": row["remaining"],
                    "use_count": row["use_count"],
                    "reaction": row["reaction"],
                    "affection_status": row["affection_status"],
                    "affection": json.loads(row["affection_result"]),
                }
            )
        return {
            "items": gifts,
            "total": total,
            "wallet": wallet,
            "catalog": CATALOG["items"],
            "affection": json.loads(affection[0])
            if affection
            else {"connected": False},
            "currency": "小屋零钱",
        }

    def facts(self, character, private=False):
        """Return a short factual context for this resident's own gifts."""
        result = []
        for row in self.view(character)["items"][:6]:
            fact = {
                "id": row["gift_id"],
                "礼物": row["name"],
                "收到": row["received_at"],
                "放在": row["location"],
                "使用过": row["use_count"],
            }
            if private and row["note"]:
                fact["主人附言"] = row["note"]
            result.append(fact)
        return result
