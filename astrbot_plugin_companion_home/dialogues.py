"""Persisted alternating group conversations; only confirmed sends become memories."""
import asyncio
import json
import random
import time
from datetime import datetime, timedelta

from astrbot.api import logger
from .engine import CN, now_iso
from .dialogue_quota import shared_daily_count, shared_daily_limit

NAMES = {"xiaoai": "小爱", "selena": "赛琳娜"}
TABLES = {"housemate": "housemate_exchanges", "bilibili": "bili_sister_exchanges"}


class Dialogues:
    def __init__(self, home):
        self.home = home
        self.task = None
        with home.store.connect() as db:
            db.execute("CREATE TABLE IF NOT EXISTS sister_dialogues(id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,exchange_id INTEGER NOT NULL,starter TEXT NOT NULL,location TEXT NOT NULL,topic TEXT NOT NULL,target INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'active',started_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_at REAL NOT NULL DEFAULT 0,lease_until REAL NOT NULL DEFAULT 0,failures INTEGER NOT NULL DEFAULT 0,reason TEXT,UNIQUE(kind,exchange_id))")
            db.execute("CREATE TABLE IF NOT EXISTS sister_dialogue_turns(session_id INTEGER NOT NULL,seq INTEGER NOT NULL,actor TEXT NOT NULL,text TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'queued',sent_at TEXT,PRIMARY KEY(session_id,seq))")

    def busy(self):
        with self.home.store.connect() as db:
            return bool(db.execute("SELECT 1 FROM sister_dialogues WHERE status IN ('active','generating') LIMIT 1").fetchone())

    def adopt(self, kind, exchange):
        if not self.home.group.enabled or kind not in TABLES:
            return False
        table = TABLES[kind]
        with self.home.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM sister_dialogues WHERE kind=? AND exchange_id=?", (kind, exchange["id"])).fetchone():
                return True
            if db.execute("SELECT 1 FROM sister_dialogues WHERE status IN ('active','generating') LIMIT 1").fetchone():
                return False
            row = db.execute("SELECT * FROM " + table + " WHERE id=?", (exchange["id"],)).fetchone()
            if not row or row["status"] not in ('drafting','pending','responding'):
                return False
            starter = row["starter"] if kind == "housemate" else "xiaoai"
            topic = row["topic"] if kind == "bilibili" else "{}"
            if shared_daily_count(db, datetime.now(CN)) > shared_daily_limit(self.home.config):
                return False
            target = 10
            stamp = now_iso()
            result = db.execute("INSERT INTO sister_dialogues(kind,exchange_id,starter,location,topic,target,started_at,updated_at) VALUES(?,?,?,?,?,?,?,?)", (kind, row["id"], starter, row["location"], topic, target, stamp, stamp))
            db.execute("UPDATE " + table + " SET status='conversing' WHERE id=?", (row["id"],))
            if row["opening"]:
                delivered = db.execute("SELECT status,sent_at FROM sister_group_outbox WHERE kind=? AND exchange_id=? AND part='opening'", (kind,row["id"])).fetchone()
                if delivered and delivered["status"] == "sent":
                    db.execute("INSERT INTO sister_dialogue_turns(session_id,seq,actor,text,status,sent_at) VALUES(?,?,?,?,?,?)", (result.lastrowid,1,starter,row["opening"],"sent",delivered["sent_at"]))
            return True

    def kick(self):
        if self.home.group.enabled and (self.task is None or self.task.done()):
            self.task = asyncio.create_task(self.tick())

    def _close(self, db, session, reason):
        stamp = now_iso()
        db.execute("UPDATE sister_dialogues SET status='completed',updated_at=?,reason=?,lease_until=0 WHERE id=?", (stamp,reason,session["id"]))
        db.execute("UPDATE " + TABLES[session["kind"]] + " SET status='completed',reply_at=? WHERE id=?", (stamp,session["exchange_id"]))

    def _sync_memories(self):
        home = self.home
        with home.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            for session in db.execute("SELECT * FROM sister_dialogues WHERE status='completed'").fetchall():
                key = "sister_dialogue:" + str(session["id"]) + ":" + home.character
                if db.execute("SELECT 1 FROM experience_outbox WHERE event_key=?", (key,)).fetchone():
                    continue
                turns = db.execute("SELECT actor,text,sent_at FROM sister_dialogue_turns WHERE session_id=? AND status='sent' ORDER BY seq", (session["id"],)).fetchall()
                if not turns:
                    continue
                lines = [(r["sent_at"], NAMES[r["actor"]] + "：" + r["text"]) for r in turns]
                for owner in db.execute("SELECT time,text FROM sister_group_context WHERE actor='主人' AND time>=? AND time<=? ORDER BY id", (session["started_at"],session["updated_at"])).fetchall():
                    lines.append((owner["time"], "主人：" + owner["text"]))
                lines.sort(key=lambda item:item[0])
                detail = "家庭群实际交流（" + ("视频分享" if session["kind"] == "bilibili" else "日常") + "）：\n" + "\n".join(line for _,line in lines)
                payload = home.experience_payload(detail,"sister_group_dialogue",source_session=home.group.umo)
                payload["summary"] = detail[:12000]
                db.execute("INSERT OR IGNORE INTO experience_outbox(character,event_key,event_id,time,payload) VALUES(?,?,?,?,?)", (home.character,key,None,session["updated_at"],json.dumps(payload,ensure_ascii=False)))
                state = home.store.snapshot(home.character)["state"]
                db.execute("INSERT INTO events(character,time,kind,payload) VALUES(?,?,?,?)", (home.character,session["updated_at"],"housemate",json.dumps({"room":state["room"],"activity":"和同住伙伴聊了一会儿","detail":detail,"dialogue_id":session["id"]},ensure_ascii=False)))

    async def tick(self):
        home = self.home
        session = None
        claim = None
        try:
            self._sync_memories()
            now = time.time()
            with home.store.connect() as db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute("SELECT * FROM sister_dialogues WHERE status IN ('active','generating') ORDER BY id LIMIT 1").fetchone()
                if not row:
                    return
                session = dict(row)
                if session["status"] == "generating":
                    if session["lease_until"] > now:
                        return
                    db.execute("UPDATE sister_dialogues SET status='active',lease_until=0 WHERE id=?",(session["id"],))
                turns = [dict(r) for r in db.execute("SELECT * FROM sister_dialogue_turns WHERE session_id=? ORDER BY seq", (session["id"],)).fetchall()]
                for turn in turns:
                    if turn["status"] == "sent":
                        continue
                    delivery = db.execute("SELECT status,sent_at FROM sister_group_outbox WHERE kind=? AND exchange_id=? AND part=?", (session["kind"],session["exchange_id"],"turn_"+str(turn["seq"]))).fetchone()
                    if delivery and delivery["status"] == "sent":
                        turn.update(status="sent",sent_at=delivery["sent_at"])
                        db.execute("UPDATE sister_dialogue_turns SET status='sent',sent_at=? WHERE session_id=? AND seq=?", (delivery["sent_at"],session["id"],turn["seq"]))
                        next_at = datetime.fromisoformat(delivery["sent_at"]).timestamp() + random.uniform(20,40)
                        db.execute("UPDATE sister_dialogues SET next_at=?,updated_at=? WHERE id=?",(next_at,now_iso(),session["id"]))
                        session["next_at"] = next_at
                    elif not delivery:
                        if turn["actor"] == home.character:
                            claim = ("repair",turn)
                        break
                    elif delivery["status"] == "unknown":
                        self._close(db,session,"delivery_unknown")
                        return
                    else:
                        return
                if claim:
                    pass
                elif len(turns) >= session["target"] and all(t["status"] == "sent" for t in turns):
                    self._close(db,session,"finished")
                    return
                elif any(t["status"] != "sent" for t in turns):
                    return
                else:
                    at = datetime.now(CN)
                    if (at-datetime.fromisoformat(session["started_at"])).total_seconds()>1200 or not home.group.location(home.housemates._pair(db,at),at):
                        self._close(db,session,"household_unavailable_or_timeout")
                        return
                    owner = db.execute("SELECT time FROM sister_group_context WHERE actor='主人' ORDER BY id DESC LIMIT 1").fetchone()
                    owner_stamp = owner[0] if owner else ""
                    if now < session["next_at"] or (owner_stamp and now-datetime.fromisoformat(owner_stamp).timestamp()<25):
                        return
                    seq = len(turns)+1
                    actor = session["starter"] if seq%2 else ("selena" if session["starter"]=="xiaoai" else "xiaoai")
                    if actor != home.character or (home.peer_task and not home.peer_task.done()):
                        return
                    db.execute("UPDATE sister_dialogues SET status='generating',lease_until=?,updated_at=? WHERE id=?",(now+90,now_iso(),session["id"]))
                    claim = ("generate",{"seq":seq,"turns":turns,"owner_stamp":owner_stamp})
            if claim[0] == "repair":
                turn = claim[1]
                home.group.enqueue(session["kind"],session["exchange_id"],"turn_"+str(turn["seq"]),turn["text"])
                return
            seq = claim[1]["seq"]
            history = [{"角色":NAMES[t["actor"]],"发言":t["text"]} for t in claim[1]["turns"]]
            line = await home.public_housemate_line(history[-1]["发言"] if history else None,video=json.loads(session["topic"]) if session["kind"]=="bilibili" else None,conversation={"已实际发送的本段对话":history,"当前是第几条发言":seq,"最多发言数":session["target"],"这一条自然收尾":seq==session["target"]})
            line = str(line or "").strip()
            end_requested = line.endswith("[[结束对话]]")
            line = line.replace("[[结束对话]]", "").strip()
            with home.store.connect() as db:
                db.execute("BEGIN IMMEDIATE")
                current = db.execute("SELECT status FROM sister_dialogues WHERE id=?",(session["id"],)).fetchone()
                owner = db.execute("SELECT time FROM sister_group_context WHERE actor='主人' ORDER BY id DESC LIMIT 1").fetchone()
                if not current or current[0] != "generating":
                    return
                at = datetime.now(CN)
                if not home.group.location(home.housemates._pair(db,at),at):
                    self._close(db,session,"household_unavailable")
                    return
                if (owner[0] if owner else "") != claim[1]["owner_stamp"]:
                    db.execute("UPDATE sister_dialogues SET status='active',lease_until=0,next_at=? WHERE id=?",(time.time()+25,session["id"]))
                    return
                if end_requested and (not line or any(line==t["text"] for t in claim[1]["turns"])):
                    self._close(db,session,"natural_finish")
                    return
                if not line or len(line)>350 or any(line==t["text"] for t in claim[1]["turns"]):
                    raise ValueError("Empty, repeated, or overlong dialogue turn")
                db.execute("INSERT INTO sister_dialogue_turns(session_id,seq,actor,text) VALUES(?,?,?,?)",(session["id"],seq,home.character,line))
                db.execute("UPDATE sister_dialogues SET status='active',lease_until=0,updated_at=? WHERE id=?",(now_iso(),session["id"]))
                if end_requested:
                    db.execute("UPDATE sister_dialogues SET target=? WHERE id=?",(seq,session["id"]))
                table=TABLES[session["kind"]]
                if seq<=2:
                    db.execute("UPDATE "+table+" SET "+("opening" if seq==1 else "reply")+"=? WHERE id=?",(line,session["exchange_id"]))
            home.group.enqueue(session["kind"],session["exchange_id"],"turn_"+str(seq),line)
        except asyncio.CancelledError:
            self._release(session,"cancelled",False)
            raise
        except Exception as exc:
            self._release(session,type(exc).__name__,True)
            logger.warning("[companion_home] Dialogue turn deferred: %s",type(exc).__name__)

    def _release(self, session, reason, failed):
        if not session:
            return
        with self.home.store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row=db.execute("SELECT * FROM sister_dialogues WHERE id=? AND status='generating'",(session["id"],)).fetchone()
            if not row:
                return
            failures=row["failures"]+int(failed)
            if failures>=3:
                self._close(db,dict(row),reason)
            else:
                db.execute("UPDATE sister_dialogues SET status='active',lease_until=0,failures=?,next_at=? WHERE id=?",(failures,time.time()+60,session["id"]))

    async def close(self):
        if self.task and not self.task.done():
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
