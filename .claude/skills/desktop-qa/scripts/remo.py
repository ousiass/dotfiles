#!/usr/bin/env python3
"""puppet-remo（Nefos Remote）の MCP を HTTP で直接呼ぶ小さなクライアント（desktop-qa 用・標準ライブラリだけ）。

  remo.py tools                                   道具の名前と説明の 1 行目を出す
  remo.py call <tool> ['<json 引数>'] [--save F]  結果の text（無ければ structuredContent）を出す。画像は F に保存
  remo.py shot <out.png> [--monitor N] [--window ID] [--zoom K]
                                                  スクショを保存。--window はそのウィンドウの矩形で切り抜く
                                                  （切り抜き・拡大は Pillow があるときだけ。無ければ元のまま保存して警告）
  remo.py close                                   操作権を返し、セッションを閉じる

セッション ID は REMO_STATE（0600）に残し、次の呼び出しでも同じセッションを使う。
操作権（lease）はセッションに付くので、呼び出しごとに新しいセッションを作ると
2 回目以降の入力が lease_held_by_other で落ちる。それを防ぐための保存。

環境変数:
  REMO_URL    既定 http://100.94.64.51:8765/mcp
  REMO_HOST   Host ヘッダー。既定は REMO_URL の host:port
  REMO_ENV    トークンを読むファイル。既定 ~/.env（PUPPET_REMO_TOKEN=...）
  REMO_STATE  セッション ID の保存先。既定 ${XDG_RUNTIME_DIR:-/tmp}/desktop-qa-remo-<uid>.json
  PUPPET_REMO_TOKEN  あれば REMO_ENV より優先

トークンの値は標準出力・標準エラー・保存ファイルのどこにも書かない（サーバーの返答に含まれても *** に置き換える）。
終了コード: 0 成功 / 1 道具のエラー（isError）/ 2 使い方・接続・認証の誤り
"""

import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_URL = "http://100.94.64.51:8765/mcp"
PROTOCOL = "2025-03-26"


class Fail(Exception):
    """接続・認証・使い方の誤り（終了コード 2）。"""


def load_token():
    tok = os.environ.get("PUPPET_REMO_TOKEN", "").strip()
    if tok:
        return tok
    path = os.path.expanduser(os.environ.get("REMO_ENV", "~/.env"))
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"\s*(?:export\s+)?PUPPET_REMO_TOKEN\s*=\s*(.*?)\s*$", line)
                if m:
                    tok = m.group(1).strip().strip("'\"")
    except OSError:
        pass
    if not tok:
        raise Fail("PUPPET_REMO_TOKEN が見つからない（環境変数か %s に置く）" % path)
    return tok


class Client:
    def __init__(self):
        self.url = os.environ.get("REMO_URL", DEFAULT_URL)
        self.host = os.environ.get("REMO_HOST") or urllib.parse.urlsplit(self.url).netloc
        self.token = load_token()
        self.state = os.environ.get("REMO_STATE") or os.path.join(
            os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "desktop-qa-remo-%d.json" % os.getuid()
        )
        self.sid = self._load_sid()
        self.next_id = 1

    def scrub(self, text):
        return text.replace(self.token, "***") if self.token else text

    # --- セッション ID の保存 ---
    def _load_sid(self):
        try:
            with open(self.state, encoding="utf-8") as f:
                data = json.load(f)
            return data.get("sid") if data.get("url") == self.url else None
        except (OSError, ValueError):
            return None

    def _save_sid(self):
        fd = os.open(self.state, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"url": self.url, "sid": self.sid}, f)
        os.chmod(self.state, 0o600)

    def _drop_sid(self):
        self.sid = None
        try:
            os.remove(self.state)
        except OSError:
            pass

    # --- HTTP ---
    def _post(self, body, method="POST"):
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Host": self.host,
            "Authorization": "Bearer " + self.token,
            "MCP-Protocol-Version": PROTOCOL,
        }
        if self.sid:
            headers["Mcp-Session-Id"] = self.sid
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=float(os.environ.get("REMO_TIMEOUT", "120"))) as r:
                sid = r.headers.get("Mcp-Session-Id")
                if sid:
                    self.sid = sid
                return r.headers.get("Content-Type", ""), r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise Fail("認証に失敗した（401）。PUPPET_REMO_TOKEN と接続の許可を確認する") from None
            if e.code == 404 and self.sid:
                raise StaleSession() from None
            detail = self.scrub(e.read().decode("utf-8", "replace"))[:300]
            raise Fail("HTTP %d: %s" % (e.code, detail)) from None
        except urllib.error.URLError as e:
            raise Fail("つながらない: %s（%s）" % (self.url, e.reason)) from None

    def _rpc(self, method, params=None, notify=False):
        body = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            body["params"] = params
        if not notify:
            body["id"] = self.next_id
            self.next_id += 1
        ctype, raw = self._post(body)
        if notify:
            return None
        if "event-stream" in ctype:
            msgs = [json.loads(l[5:]) for l in raw.splitlines() if l.startswith("data:") and l[5:].strip()]
            msgs = [m for m in msgs if m.get("id") == body["id"]] or msgs
            if not msgs:
                raise Fail("返答が空（%s）" % method)
            msg = msgs[-1]
        else:
            msg = json.loads(raw)
        if "error" in msg:
            raise Fail("%s: %s" % (method, self.scrub(json.dumps(msg["error"], ensure_ascii=False))))
        return msg.get("result", {})

    def _initialize(self):
        self.sid = None
        self._rpc(
            "initialize",
            {"protocolVersion": PROTOCOL, "capabilities": {}, "clientInfo": {"name": "desktop-qa", "version": "1"}},
        )
        self._rpc("notifications/initialized", notify=True)
        if self.sid:
            self._save_sid()

    def request(self, method, params=None):
        if not self.sid:
            self._initialize()
        try:
            return self._rpc(method, params)
        except StaleSession:
            print("remo: セッションが切れていたので作り直した（操作権は取り直しになる）", file=sys.stderr)
            self._drop_sid()
            self._initialize()
            return self._rpc(method, params)

    def call(self, name, args=None):
        return self.request("tools/call", {"name": name, "arguments": args or {}})

    def close(self):
        if not self.sid:
            return
        try:
            self._rpc("tools/call", {"name": "release_control", "arguments": {}})
            self._post(None, method="DELETE")
        except (Fail, StaleSession):
            pass
        self._drop_sid()


class StaleSession(Exception):
    pass


def text_of(result):
    parts = [c["text"] for c in result.get("content", []) if c.get("type") == "text"]
    if parts:
        return "\n".join(parts)
    if result.get("structuredContent") is not None:
        return json.dumps(result["structuredContent"], ensure_ascii=False)
    return ""


def image_of(result):
    for c in result.get("content", []):
        if c.get("type") == "image" and c.get("data"):
            return base64.b64decode(c["data"])
    return None


def take_shot(cl, out, monitor=None, window=None, zoom=1.0):
    box = None
    if window:
        wins = json.loads(text_of(cl.call("list_windows"))).get("windows", [])
        hit = [w for w in wins if str(w.get("id")) == str(window)]
        if not hit:
            raise Fail("window %s が list_windows に無い" % window)
        r = hit[0]["rect"]
        monitor = hit[0].get("monitor", monitor)
        box = (r["x"], r["y"], r["x"] + r["width"], r["y"] + r["height"])
    args = {} if monitor is None else {"monitor": int(monitor)}
    res = cl.call("screenshot", args)
    if res.get("isError"):
        return res
    img = image_of(res)
    if img is None:
        raise Fail("screenshot に画像が無い")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    if box or zoom != 1.0:
        try:
            import io

            from PIL import Image

            im = Image.open(io.BytesIO(img))
            if box:
                im = im.crop(box)
            if zoom != 1.0:
                im = im.resize((int(im.width * zoom), int(im.height * zoom)), Image.LANCZOS)
            im.save(out)
            return {"saved": out, "size": [im.width, im.height], "monitor": monitor}
        except ImportError:
            print("remo: Pillow が無いので切り抜き・拡大せずに保存した（他のウィンドウが写っていないか確かめる）", file=sys.stderr)
    with open(out, "wb") as f:
        f.write(img)
    return {"saved": out, "monitor": monitor}


def parse_opts(argv, names):
    opts, rest, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in names:
            if i + 1 >= len(argv):
                raise Fail("%s に値が要る" % a)
            opts[a[2:]] = argv[i + 1]
            i += 2
        else:
            rest.append(a)
            i += 1
    return opts, rest


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    cmd, argv = argv[0], argv[1:]
    cl = Client()
    try:
        if cmd == "tools":
            for t in cl.request("tools/list", {}).get("tools", []):
                print("%s\t%s" % (t["name"], (t.get("description") or "").split(". ")[0]))
            return 0
        if cmd == "call":
            opts, rest = parse_opts(argv, {"save"})
            if not rest:
                raise Fail("call <tool> ['<json 引数>']")
            args = json.loads(rest[1]) if len(rest) > 1 else {}
            res = cl.call(rest[0], args)
            if opts.get("save"):
                img = image_of(res)
                if img is not None:
                    with open(opts["save"], "wb") as f:
                        f.write(img)
            out = cl.scrub(text_of(res))
            if res.get("isError"):
                print(out, file=sys.stderr)
                return 1
            print(out)
            return 0
        if cmd == "shot":
            opts, rest = parse_opts(argv, {"monitor", "window", "zoom"})
            if not rest:
                raise Fail("shot <out.png> [--monitor N] [--window ID] [--zoom K]")
            res = take_shot(cl, rest[0], opts.get("monitor"), opts.get("window"), float(opts.get("zoom", "1")))
            if res.get("isError"):
                print(cl.scrub(text_of(res)), file=sys.stderr)
                return 1
            print(json.dumps(res, ensure_ascii=False))
            return 0
        if cmd == "close":
            cl.close()
            return 0
        raise Fail("知らないコマンド: %s" % cmd)
    except Fail as e:
        print("remo: " + cl.scrub(str(e)), file=sys.stderr)
        return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Fail as e:  # Client() の生成（トークン読み込み）で落ちたとき
        print("remo: " + str(e), file=sys.stderr)
        sys.exit(2)
