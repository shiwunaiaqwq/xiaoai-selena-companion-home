"""Bound scene repetition and compare notes without another model request."""

import re
from datetime import datetime
from difflib import SequenceMatcher


def note_key(text):
    return re.sub(r"[\W_]+", "", str(text)).lower()


def similar_note(left, right):
    left, right = note_key(left), note_key(right)
    if not left or not right:
        return False
    if left == right:
        return True
    if min(len(left), len(right)) < 12:
        return False
    return (
        left in right or right in left
        or SequenceMatcher(None, left, right, autojunk=False).ratio() >= 0.59
    )


def unique_notes(notes, limit=12):
    result = []
    for item in notes:
        if item["author"] != "her" or not any(
            old["author"] == "her" and similar_note(item["text"], old["text"])
            for old in result
        ):
            result.append(item)
        if len(result) >= limit:
            break
    return result


def elapsed_minutes(state, at):
    try:
        return max(0, (at - datetime.fromisoformat(state["since"])).total_seconds() / 60)
    except (KeyError, TypeError, ValueError):
        return 0


def progress_plan(character, old, proposed, baseline, at):
    """At an autonomous 20–60 minute turn, move to the next task, never an owner outing."""
    from .activities import BY_ID
    threshold=min(20,BY_ID.get(old.get("interaction_id"),{}).get("max_minutes",20))
    if old.get("together") or elapsed_minutes(old, at) < threshold:
        return proposed, False
    old_key=old.get("interaction_id") or old.get("activity")
    new_key=proposed.get("interaction_id") or proposed.get("activity")
    if (old.get("room"),old_key)!=(proposed["room"],new_key):
        return proposed, False
    result = dict(baseline)
    baseline_key=result.get("interaction_id") or result.get("activity")
    if (old.get("room"),old_key)==(result["room"],baseline_key):
        room, activity, detail = (
            ("window", "歇一会儿", "收好手里的东西，端着水在窗边坐一会儿")
            if character == "xiaoai" else
            ("balcony", "在阳台歇一会儿", "合上手边的书，去阳台看看天色，让思绪歇一歇")
        )
        result.update(room="balcony",interaction_id="balcony_view",activity=activity,detail=detail)
    # Do not turn a routine fallback into an invented first-person letter or memory.
    result["quote"] = old.get("quote") or baseline["quote"]
    result["household"] = {}
    return result, True
