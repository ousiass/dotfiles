#!/usr/bin/env python3
"""desktop_qa_skill_test.sh 用の偽 puppet-remo MCP サーバー（標準ライブラリだけ）。

  fake_remo.py <port_file> <token> <host>

- 127.0.0.1 の空きポートで待ち受け、ポート番号を <port_file> に書く（準備完了の合図）。
- Authorization が Bearer <token> でなければ 401、Host が <host> でなければ 403。
- 本物と同じく、操作権（lease）はセッションに付く。入力の道具は最初の呼び出しで操作権を取り、
  ほかのセッションが持っていれば lease_held_by_other を返す。
- tools/call は SSE（text/event-stream）で、ほかは JSON で返す（両方の読み取りを試すため）。
- 試験用の道具: echo_auth（受け取った Authorization をそのまま返す。伏せ字の確認用）、
  _forget_sessions（全セッションと操作権を忘れる。サーバー再起動の代わり）、_state（lease の持ち主を返す）。
"""

import base64
import json
import os
import struct
import sys
import uuid
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, TOKEN, HOST = sys.argv[1], sys.argv[2], sys.argv[3]


def make_png(pixels):
    """1 行の RGB 画素列から PNG を作る（Pillow なしで試せるように）。"""

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    row = b"\x00" + b"".join(bytes(p) for p in pixels)
    ihdr = struct.pack(">IIBBBBB", len(pixels), 1, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(row)) + chunk(b"IEND", b"")


# 2x1 の PNG（左が赤、右が青）。list_windows の窓 42 は右の 1 画素
PNG = make_png([(255, 0, 0), (0, 0, 255)])

sessions = set()
lease = {"holder": None}
INPUT_TOOLS = {"left_click", "type", "key", "clipboard_read", "clipboard_write", "get_ui_tree", "launch_app"}


def ok(payload):
    return {"content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}], "structuredContent": payload}


def err(code, message):
    return {"isError": True, "content": [{"type": "text", "text": message}], "structuredContent": {"code": code, "message": message}}


def call_tool(sid, name, args, auth):
    if name in INPUT_TOOLS or name == "acquire_control":
        if lease["holder"] not in (None, sid):
            return err("lease_held_by_other", "another session holds the control lease")
        lease["holder"] = sid
        if name == "acquire_control":
            return ok({"state": "held", "mine": True})
        return ok({"ok": True, "tool": name, "args": args})
    if name == "release_control":
        if lease["holder"] == sid:
            lease["holder"] = None
        return ok({"ok": True})
    if name == "get_control_status":
        return ok({"state": "held" if lease["holder"] else "idle", "mine": lease["holder"] == sid})
    if name == "list_windows":
        return ok({"windows": [{"id": "42", "title": "App", "monitor": 1, "rect": {"x": 1, "y": 0, "width": 1, "height": 1}}]})
    if name == "screenshot":
        return {"content": [{"type": "image", "mimeType": "image/png", "data": base64.b64encode(PNG).decode()}]}
    if name == "echo_auth":
        return ok({"you_sent": auth})
    if name == "_forget_sessions":
        sessions.clear()
        lease["holder"] = None
        return ok({"ok": True})
    if name == "_state":
        return ok({"holder": lease["holder"], "sessions": len(sessions)})
    return err("invalid_argument", "unknown tool " + name)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body=None, sid=None, sse=False):
        data = b""
        if body is not None:
            text = json.dumps(body, ensure_ascii=False)
            data = ("event: message\ndata: %s\n\n" % text if sse else text).encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/event-stream" if sse else "application/json")
        if sid:
            self.send_header("Mcp-Session-Id", sid)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def check(self):
        auth = self.headers.get("Authorization", "")
        if auth != "Bearer " + TOKEN:
            self.reply(401, {"error": "unauthorized", "echo": auth})
            return None
        if self.headers.get("Host") != HOST:
            self.reply(403, {"error": "bad host"})
            return None
        return auth

    def do_DELETE(self):
        if self.check() is None:
            return
        sessions.discard(self.headers.get("Mcp-Session-Id"))
        self.reply(200)

    def do_POST(self):
        auth = self.check()
        if auth is None:
            return
        msg = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        method = msg.get("method")
        if method == "initialize":
            sid = uuid.uuid4().hex
            sessions.add(sid)
            self.reply(200, {"jsonrpc": "2.0", "id": msg["id"], "result": {"serverInfo": {"name": "fake"}}}, sid=sid)
            return
        sid = self.headers.get("Mcp-Session-Id")
        if sid not in sessions:
            self.reply(404, {"error": "session not found"})
            return
        if "id" not in msg:  # notification
            self.reply(202)
            return
        if method == "tools/list":
            tools = [{"name": n, "description": "fake %s. more" % n} for n in sorted(INPUT_TOOLS)]
            self.reply(200, {"jsonrpc": "2.0", "id": msg["id"], "result": {"tools": tools}})
            return
        if method == "tools/call":
            p = msg.get("params", {})
            res = call_tool(sid, p.get("name"), p.get("arguments", {}), auth)
            self.reply(200, {"jsonrpc": "2.0", "id": msg["id"], "result": res}, sse=True)
            return
        self.reply(200, {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "no method"}})


srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
os.replace(PORT_FILE + ".tmp", PORT_FILE)
srv.serve_forever()
