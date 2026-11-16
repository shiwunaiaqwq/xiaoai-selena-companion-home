"""Persistent virtual-life state, isolated by character, with a local shared database."""

import json
import random
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .progress import unique_notes, similar_note
from .layout import (ROOMS, LAYOUT, adapt_plan, canonical_room, project_state, project_event)

CN = timezone(timedelta(hours=8))
CHARACTERS = {
    "xiaoai": {
        "name": "小爱",
        "title": "小爱的小窝",
        "subtitle": "把平常的日子，慢慢过成喜欢的样子",
        "theme": "rose",
        "symbol": "✧",
        "memory_persona": "爱弥斯",
    },
    "selena": {
        "name": "赛琳娜",
        "title": "赛琳娜的居所",
        "subtitle": "窗边的光，和还没有写完的那封信",
        "theme": "iris",
        "symbol": "♬",
        "memory_persona": "default",
    },
}
ROOM_NAMES = {**LAYOUT["legacy_names"], **{r["id"]: r["name"] for r in ROOMS}}


def now_iso():
    """Return a timezone-aware local timestamp."""
    return datetime.now(CN).isoformat(timespec="seconds")


def fallback_plan(character, at=None):
    """Use the same furniture cards if the model is unavailable."""
    from .activities import fallback_scene
    result = fallback_scene(character, at)
    result.update(quote="先在这里歇一会儿，等你忙完" if character=="xiaoai" else "这一页还没有写完，指挥官，不妨在这里坐一会儿", source="routine")
    return adapt_plan(character, result)


def normalize_plan(payload):
    """Accept only a bounded virtual scene, never arbitrary model fields.

    Args:
        payload: Model JSON or an explicit tool-submitted scene.

    Returns:
        A bounded plan dictionary.

    Raises:
        ValueError: The room or required content is invalid.
    """
    if not isinstance(payload, dict) or payload.get("room") not in ROOM_NAMES:
        raise ValueError("Invalid room")
    result = {"room": payload["room"]}
    identifier=payload.get("interaction_id", "")
    if not isinstance(identifier,str) or len(identifier)>64:
        raise ValueError("Invalid furniture action")
    result["interaction_id"]=identifier
    for key, limit in (("activity", 48), ("detail", 160), ("quote", 120)):
        value = payload.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError("Missing scene text")
        result[key] = value.strip()[:limit]
    plans = payload.get("plans", [])
    result["plans"] = (
        [str(x).strip()[:80] for x in plans[:4] if isinstance(x, str) and x.strip()]
        if isinstance(plans, list)
        else []
    )
    household = payload.get("household", {})
    if isinstance(household, dict):
        result["household"] = {
            k: {
                "title": str(v.get("title", ""))[:80],
                "detail": str(v.get("detail", ""))[:240],
            }
            for k, v in household.items()
            if k in ("project", "highlight", "draft")
            and isinstance(v, dict)
            and v.get("title")
        }
    return result


class HomeStore:
    """Use short transactions so both AstrBot instances can share one local home."""

    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS residents(character TEXT PRIMARY KEY, state TEXT NOT NULL, heartbeat TEXT, memory TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT, character TEXT NOT NULL, time TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS events_resident_time ON events(character,time);
                CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, character TEXT NOT NULL, time TEXT NOT NULL, author TEXT NOT NULL, text TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS requests(id INTEGER PRIMARY KEY AUTOINCREMENT, character TEXT NOT NULL, time TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending');
                CREATE TABLE IF NOT EXISTS experience_outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, character TEXT NOT NULL, event_key TEXT NOT NULL UNIQUE, event_id INTEGER, time TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, memory_id TEXT, retry_at TEXT, error TEXT);
                CREATE TABLE IF NOT EXISTS activity_schedule(character TEXT PRIMARY KEY, next_at TEXT NOT NULL, interval_seconds INTEGER NOT NULL, arranged_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS planner_status(character TEXT PRIMARY KEY, data TEXT NOT NULL);
            """)
            columns = {r[1] for r in db.execute("PRAGMA table_info(requests)")}
            for name in ("finished_at", "result"):
                if name not in columns:
                    db.execute(f"ALTER TABLE requests ADD COLUMN {name} TEXT")

    @contextmanager
    def connect(self):
        """Return a short-lived connection with a bounded writer wait."""
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def ensure(self, character):
        """Seed a character once; never manufacture elapsed offline history."""
        initial = {
            **fallback_plan(character),
            "since": now_iso(),
            "updated_at": now_iso(),
            "planned_hour": "",
            "status": "等待首次安排",
            "mode": "normal",
        }
        with self.connect() as db:
            db.execute(
                "INSERT OR IGNORE INTO residents(character,state) VALUES (?,?)",
                (character, json.dumps(initial, ensure_ascii=False)),
            )
        self.ensure_schedule(character)

    def _set_next_schedule(self, db, character, at):
        """Draw once per arrangement and persist the deadline in the same transaction."""
        seconds = random.randint(20 * 60, 60 * 60)
        next_at = (at + timedelta(seconds=seconds)).isoformat(timespec="seconds")
        db.execute(
            "INSERT INTO activity_schedule VALUES(?,?,?,?) "
            "ON CONFLICT(character) DO UPDATE SET next_at=excluded.next_at, "
            "interval_seconds=excluded.interval_seconds, arranged_at=excluded.arranged_at",
            (character, next_at, seconds, at.isoformat(timespec="seconds")),
        )
        return next_at

    def ensure_schedule(self, character, at=None):
        """Keep a saved deadline through page refreshes and process restarts."""
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT next_at,interval_seconds FROM activity_schedule WHERE character=?", (character,)
            ).fetchone()
            return row[0] if row and 1200<=row[1]<=3600 else self._set_next_schedule(
                db, character, at or datetime.now(CN)
            )

    def reschedule(self, character, at=None):
        """Postpone a due check without altering the current activity or memories."""
        with self.connect() as db:
            return self._set_next_schedule(db, character, at or datetime.now(CN))

    def schedule_info(self, character):
        """Read the actual deadline; a web view never starts or redraws a timer."""
        with self.connect() as db:
            row = db.execute(
                "SELECT next_at,interval_seconds,arranged_at FROM activity_schedule WHERE character=?",
                (character,),
            ).fetchone()
        return dict(row) if row else {}

    def snapshot(self, character, day=None):
        """Read one character's state, timeline, and notes without mixing residents.

        Args:
            character: One of the configured resident identifiers.
            day: ISO date for the timeline, defaulting to today in Shanghai.

        Returns:
            A private dashboard snapshot or an unloaded placeholder.
        """
        day = day or datetime.now(CN).date().isoformat()
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM residents WHERE character=?", (character,)
            ).fetchone()
            events = db.execute(
                "SELECT id,time,kind,payload FROM events WHERE character=? AND substr(time,1,10)=? ORDER BY id DESC LIMIT 100",
                (character, day),
            ).fetchall()
            notes = db.execute(
                "SELECT id,time,author,text FROM notes WHERE character=? ORDER BY id DESC LIMIT 60",
                (character,),
            ).fetchall()
            pending = db.execute(
                "SELECT COUNT(*) FROM requests WHERE character=? AND status IN ('pending','running')",
                (character,),
            ).fetchone()[0]
            latest_request = db.execute(
                "SELECT id,time,status,finished_at,result FROM requests WHERE character=? ORDER BY id DESC LIMIT 1",
                (character,),
            ).fetchone()
            planner = db.execute("SELECT data FROM planner_status WHERE character=?", (character,)).fetchone()
            experiences = db.execute(
                "SELECT time,payload,status,memory_id FROM experience_outbox WHERE character=? ORDER BY id DESC LIMIT 12",
                (character,),
            ).fetchall()
            sync = dict(
                db.execute(
                    "SELECT status,COUNT(*) FROM experience_outbox WHERE character=? GROUP BY status",
                    (character,),
                ).fetchall()
            )
        return {
            "character": character,
            "profile": CHARACTERS[character],
            "state": project_state(character, json.loads(row["state"])) if row else None,
            "heartbeat": row["heartbeat"] if row else None,
            "memory": json.loads(row["memory"]) if row else {},
            "events": [
                {
                    "id": e["id"],
                    "time": e["time"],
                    "kind": e["kind"],
                    **project_event(character, json.loads(e["payload"])),
                }
                for e in events
            ],
            "notes": unique_notes([dict(n) for n in notes]),
            "pending": pending,
            "latest_request": {**dict(latest_request), "result": json.loads(latest_request["result"] or "{}")} if latest_request else None,
            "planner": json.loads(planner[0]) if planner else {},
            "day": day,
            "experiences": [
                {
                    "time": row["time"],
                    **json.loads(row["payload"]),
                    "memory_status": row["status"],
                    "memory_id": row["memory_id"],
                }
                for row in experiences
            ],
            "experience_sync": sync,
            "schedule": self.schedule_info(character),
        }

    def commit_plan(
        self,
        character,
        payload,
        source,
        status,
        hour=None,
        *,
        together=None,
        experience=None,
        event_key=None,
        expected_revision=None,
    ):
        """Save one scene; keep its original start time when the activity continues.

        Args:
            character: Resident identifier.
            payload: Validated virtual scene.
            source: ai, routine, or chat.
            status: Human-readable generation status.
            hour: Optional completed hourly slot; chat changes preserve this cursor.
        """
        payload = adapt_plan(character, payload)
        payload.setdefault("routine_key", "")
        payload.setdefault("routine_until", "")
        self.ensure(character)
        timestamp = now_iso()
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            old = json.loads(
                db.execute(
                    "SELECT state FROM residents WHERE character=?", (character,)
                ).fetchone()[0]
            )
            if (
                expected_revision is not None
                and old.get("revision", 0) != expected_revision
            ):
                return False
            if (
                event_key
                and db.execute(
                    "SELECT 1 FROM experience_outbox WHERE event_key=?", (event_key,)
                ).fetchone()
            ):
                return True
            same_room=canonical_room(character,old.get("room"),old.get("activity",""))==payload["room"]
            same_action=(old.get("interaction_id")==payload.get("interaction_id")) if old.get("interaction_id") and payload.get("interaction_id") else old.get("activity")==payload["activity"]
            changed=not (same_room and same_action)
            detail_changed = payload["detail"] != old.get("detail")
            state = {
                **old,
                **payload,
                "source": source,
                "status": status,
                "updated_at": timestamp,
                "since": timestamp if changed else old.get("since", timestamp),
                "revision": old.get("revision", 0) + 1,
            }
            if together is not None:
                state["together"] = together
            if hour is not None:
                state["planned_hour"] = hour
            db.execute(
                "UPDATE residents SET state=? WHERE character=?",
                (json.dumps(state, ensure_ascii=False), character),
            )
            if hour is not None or changed:
                self._set_next_schedule(db, character, datetime.now(CN))
            if (
                changed
                or detail_changed
                or experience
                or not db.execute(
                    "SELECT 1 FROM events WHERE character=? LIMIT 1", (character,)
                ).fetchone()
            ):
                cursor = db.execute(
                    "INSERT INTO events(character,time,kind,payload) VALUES (?,?,?,?)",
                    (
                        character,
                        timestamp,
                        "experience" if experience else "activity" if changed else "progress",
                        json.dumps(
                            {
                                "room": payload["room"],
                                "interaction_id":payload.get("interaction_id", ""),
                                "activity": payload["activity"],
                                "detail": payload["detail"],
                                "source": source,
                                "experience": experience.get("summary", "")
                                if experience
                                else "",
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
                if experience:
                    db.execute(
                        "INSERT INTO experience_outbox(character,event_key,event_id,time,payload) VALUES (?,?,?,?,?)",
                        (
                            character,
                            event_key,
                            cursor.lastrowid,
                            timestamp,
                            json.dumps(experience, ensure_ascii=False),
                        ),
                    )
            return True

    def pulse(self, character, mode):
        """Record the actual backend heartbeat and external persona mode."""
        with self.connect() as db:
            row = db.execute(
                "SELECT state FROM residents WHERE character=?", (character,)
            ).fetchone()
            if row:
                state = json.loads(row[0])
                state["mode"] = mode
                db.execute(
                    "UPDATE residents SET heartbeat=?,state=? WHERE character=?",
                    (now_iso(), json.dumps(state, ensure_ascii=False), character),
                )

    def save_memory(self, character, memory):
        """Store a read-only memory snapshot; never modify LivingMemory databases."""
        with self.connect() as db:
            db.execute(
                "UPDATE residents SET memory=? WHERE character=?",
                (json.dumps(memory, ensure_ascii=False), character),
            )

    def add_note(self, character, text, author="you"):
        """Persist an owner note or an actually generated character message."""
        with self.connect() as db:
            if author == "her":
                recent = db.execute(
                    "SELECT id,text FROM notes WHERE character=? AND author='her' ORDER BY id DESC LIMIT 24",
                    (character,),
                ).fetchall()
                for old in recent:
                    if similar_note(text, old["text"]):
                        return old["id"]
            cursor = db.execute(
                "INSERT INTO notes(character,time,author,text) VALUES (?,?,?,?)",
                (character, now_iso(), author, text[:1000]),
            )
            return cursor.lastrowid

    def enqueue(self, character):
        """Deduplicate pending manual updates across both dashboards."""
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT id FROM requests WHERE character=? AND status IN ('pending','running') LIMIT 1",
                (character,),
            ).fetchone()
            if row:
                return row[0]
            return db.execute(
                "INSERT INTO requests(character,time,kind) VALUES (?,?,?)",
                (character, now_iso(), "refresh"),
            ).lastrowid

    def claim(self, character):
        """Claim an update in one transaction, preventing duplicate model requests."""
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT id FROM requests WHERE character=? AND status='pending' ORDER BY id LIMIT 1",
                (character,),
            ).fetchone()
            if row:
                db.execute("UPDATE requests SET status='running' WHERE id=?", (row[0],))
                return row[0]
        return None

    def finish(self, request_id, result=None):
        """Mark one completed manual request without affecting another resident."""
        with self.connect() as db:
            db.execute(
                "UPDATE requests SET status='done',finished_at=?,result=? WHERE id=?",
                (now_iso(), json.dumps(result or {}, ensure_ascii=False), request_id),
            )

    def planner_update(self, character, **values):
        with self.connect() as db:
            row = db.execute("SELECT data FROM planner_status WHERE character=?", (character,)).fetchone()
            data = json.loads(row[0]) if row else {}
            data.update(values)
            db.execute(
                "INSERT INTO planner_status VALUES(?,?) ON CONFLICT(character) DO UPDATE SET data=excluded.data",
                (character, json.dumps(data, ensure_ascii=False)),
            )
