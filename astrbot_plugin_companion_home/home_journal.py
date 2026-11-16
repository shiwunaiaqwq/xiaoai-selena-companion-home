"""Daily household records and persona-written journals, independent of Qzone."""

import json
import uuid
from datetime import datetime, timedelta

from .engine import CN
from .layout import room_label


def daily_records(store, character, day):
    """Read actual committed facts and merge adjacent continuations of one action.

    Args:
        store: Original shared home store.
        character: Resident identifier.
        day: ISO Beijing date.

    Returns:
        Rows for the owner-only household timeline.
    """
    if datetime.fromisoformat(day).date().isoformat() != day:
        raise ValueError("日期不正确")
    with store.connect() as db:
        events = db.execute(
            "SELECT * FROM events WHERE character=? AND substr(time,1,10)=? ORDER BY time,id",
            (character, day),
        ).fetchall()
    rows = []
    for event in events:
        data = json.loads(event["payload"])
        title = data.get("activity") or data.get("summary") or "生活片段"
        detail = data.get("detail") or data.get("experience") or ""
        key = (data.get("interaction_id") or title, data.get("room"))
        row = {
            "id": event["id"],
            "time": event["time"],
            "last_time": event["time"],
            "activity": title,
            "detail": detail,
            "kind": event["kind"],
            "room": room_label(character, data["room"]) if data.get("room") else "",
            "gift_id": data.get("gift_id"),
            "owner_note": data.get("owner_note", ""),
            "_key": key,
        }
        if (
            rows
            and rows[-1]["_key"] == key
            and event["kind"] in ("activity", "progress")
            and rows[-1]["kind"] in ("activity", "progress")
        ):
            rows[-1].update(
                id=event["id"],
                last_time=event["time"],
                detail=detail or rows[-1]["detail"],
            )
        else:
            rows.append(row)
    for row in rows:
        row.pop("_key")
    return rows


class HomeJournal:
    """Persist bounded journal requests and never use a QQ-space diary as input."""

    def __init__(self, store, character):
        self.store, self.character = store, character
        with store.connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS home_journals(
                character TEXT NOT NULL,day TEXT NOT NULL,status TEXT NOT NULL,content TEXT NOT NULL DEFAULT '',
                requested_at TEXT NOT NULL,updated_at TEXT,source_max INTEGER NOT NULL DEFAULT 0,
                attempts INTEGER NOT NULL DEFAULT 0,lease TEXT,token TEXT,error TEXT,
                PRIMARY KEY(character,day))""")

    def queue(self, day, at=None):
        """Queue a day with actual records; reading a page cannot request generation.

        Args:
            day: Requested completed day, or today's draft.
            at: Optional test clock.

        Returns:
            Whether a durable generation job is pending.
        """
        at = at or datetime.now(CN)
        date = datetime.fromisoformat(day).date()
        if date.isoformat() != day or date > at.date():
            raise ValueError("只能整理今天或过去的实际生活")
        rows = daily_records(self.store, self.character, day)
        if not rows:
            raise ValueError("这天还没有小屋生活记录，先留着空白")
        maximum = max(row["id"] for row in rows)
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            prior = db.execute(
                "SELECT * FROM home_journals WHERE character=? AND day=?",
                (self.character, day),
            ).fetchone()
            if prior and (
                prior["status"] in ("pending", "running")
                or prior["source_max"] >= maximum
                and prior["content"]
                and (prior["status"] == "written" or date == at.date())
            ):
                return {
                    "queued": prior["status"] in ("pending", "running"),
                    "message": "这一页已经在整理"
                    if prior["status"] in ("pending", "running")
                    else "这一天的新片段已经记下了",
                }
            if (
                prior
                and prior["updated_at"]
                and prior["day"] == at.date().isoformat()
                and (at - datetime.fromisoformat(prior["updated_at"])).total_seconds()
                < 600
            ):
                return {
                    "queued": False,
                    "message": "刚写下的这一页先留一会儿，晚些有新片段再续写",
                }
            stamp = at.isoformat(timespec="seconds")
            db.execute(
                """INSERT INTO home_journals(character,day,status,requested_at) VALUES(?,?,'pending',?)
                       ON CONFLICT(character,day) DO UPDATE SET status='pending',requested_at=excluded.requested_at,error=NULL,attempts=0,lease=NULL,token=NULL""",
                (self.character, day, stamp),
            )
        return {"queued": True, "message": "已交给她本人整理，这页只留在小屋里"}

    def claim(self, at=None):
        """Lease one queued journal so reloads and concurrent requests do not duplicate it."""
        at = at or datetime.now(CN)
        stamp = at.isoformat(timespec="seconds")
        with self.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute(
                "UPDATE home_journals SET status='pending' WHERE character=? AND status='running' AND lease<?",
                (self.character, stamp),
            )
            row = db.execute(
                "SELECT * FROM home_journals WHERE character=? AND status='pending' AND (lease IS NULL OR lease<=?) ORDER BY day LIMIT 1",
                (self.character, stamp),
            ).fetchone()
            if not row:
                return None
            token = uuid.uuid4().hex
            db.execute(
                "UPDATE home_journals SET status='running',token=?,attempts=attempts+1,lease=? WHERE character=? AND day=?",
                (
                    token,
                    (at + timedelta(minutes=3)).isoformat(),
                    self.character,
                    row["day"],
                ),
            )
        facts = daily_records(self.store, self.character, row["day"])
        return {
            "day": row["day"],
            "token": token,
            "facts": facts[-100:],
            "source_max": max((r["id"] for r in facts), default=0),
        }

    def finish(self, job, text, at=None):
        """Save only this resident's generated page for the leased source facts."""
        at = at or datetime.now(CN)
        text = str(text).strip().strip("`").strip()
        if not text or len(text) > 4000:
            raise ValueError("Journal response is empty or too long")
        with self.store.connect() as db:
            result = db.execute(
                """UPDATE home_journals SET content=?,status=?,updated_at=?,source_max=?,lease=NULL,error=NULL
                              WHERE character=? AND day=? AND token=? AND status='running'""",
                (
                    text,
                    "draft" if job["day"] == at.date().isoformat() else "written",
                    at.isoformat(timespec="seconds"),
                    job["source_max"],
                    self.character,
                    job["day"],
                    job["token"],
                ),
            )
            return result.rowcount == 1

    def failed(self, job, error, at=None):
        """Keep the old page and bound retries after a model failure."""
        at = at or datetime.now(CN)
        with self.store.connect() as db:
            if error == "reloaded":
                # A controlled plugin reload is not a failed model response.
                db.execute(
                    """UPDATE home_journals SET status='pending',attempts=max(0,attempts-1),
                       lease=NULL,token=NULL,error=NULL
                       WHERE character=? AND day=? AND token=? AND status='running'""",
                    (self.character, job["day"], job["token"]),
                )
                return
            db.execute(
                """UPDATE home_journals SET status=CASE WHEN attempts>=3 THEN 'failed' ELSE 'pending' END,
                       error=?,lease=? WHERE character=? AND day=? AND token=? AND status='running'""",
                (
                    str(error)[:80],
                    (at + timedelta(minutes=10)).isoformat(),
                    self.character,
                    job["day"],
                    job["token"],
                ),
            )

    def queue_yesterday(self, at=None):
        """Archive only a previous day that really has events, without offline stories."""
        at = at or datetime.now(CN)
        day = (at.date() - timedelta(days=1)).isoformat()
        with self.store.connect() as db:
            row = db.execute(
                "SELECT status FROM home_journals WHERE character=? AND day=?",
                (self.character, day),
            ).fetchone()
        if row and row[0] in ("written", "failed", "pending", "running"):
            return
        if daily_records(self.store, self.character, day):
            self.queue(day, at)

    def view(self, character=None):
        """Return stored pages; this never calls a model or starts a journal job."""
        with self.store.connect() as db:
            return [
                dict(row)
                for row in db.execute(
                    "SELECT day,status,content,updated_at,error FROM home_journals WHERE character=? ORDER BY day DESC LIMIT 30",
                    (character or self.character,),
                )
            ]
