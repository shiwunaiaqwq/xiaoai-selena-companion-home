"""Stdlib-only Python Client for the Universal AI Bridge (NoneBot / Koishi / OpenAI / Custom Bots)."""
from __future__ import annotations
import json
import urllib.request
from pathlib import Path


class UniversalCabinClient:
    def __init__(self, bridge_json: str | Path = "data/bridge.json"):
        self.bridge_json = Path(bridge_json)

    def _cfg(self) -> tuple[str, str]:
        data = json.loads(self.bridge_json.read_text(encoding="utf-8"))
        return str(data["url"]).rstrip("/"), str(data["token"])

    def _request(self, endpoint: str, payload: dict | None = None) -> dict:
        url, token = self._cfg()
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
        headers = {"Authorization": f"Bearer {token}"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(f"{url}{endpoint}", data=body, headers=headers, method="POST" if body else "GET")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def tools(self) -> list[dict]:
        return self._request("/v1/tools")["tools"]

    def summary(self) -> dict:
        return self._request("/v1/summary")["data"]

    def call_tool(self, name: str, arguments: dict | None = None) -> dict:
        return self._request("/v1/tool", {"name": name, "arguments": arguments or {}})["result"]

    def move(self, actor: str, room: str, activity: str, sleeping: bool = False) -> dict:
        return self.call_tool("cabin_move", {"actor": actor, "room": room, "activity": activity, "sleeping": sleeping})

    def reply_note(self, actor: str, reply: str, note_id: int | None = None) -> dict:
        args = {"actor": actor, "reply": reply}
        if note_id is not None:
            args["note_id"] = note_id
        return self.call_tool("cabin_reply_note", args)

    def write_visit_note(self, actor: str, place: str, text: str) -> dict:
        return self.call_tool("cabin_write_visit_note", {"actor": actor, "place": place, "text": text})


if __name__ == "__main__":
    print(json.dumps(UniversalCabinClient().summary(), ensure_ascii=False, indent=2))
