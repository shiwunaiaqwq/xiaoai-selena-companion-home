"""One shared daily quota for ordinary and video-sharing conversations."""
from datetime import timedelta

def shared_daily_count(db, at):
    start = at.date().isoformat()
    end = (at.date() + timedelta(days=1)).isoformat()
    total = 0
    for table in ('housemate_exchanges', 'bili_sister_exchanges'):
        if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone():
            total += db.execute('SELECT COUNT(*) FROM '+table+' WHERE time>=? AND time<?',(start,end)).fetchone()[0]
    return total

def shared_daily_limit(config):
    try:
        return max(1,min(20,int(config.get('sister_dialogue_daily_limit',5))))
    except (TypeError,ValueError):
        return 5
