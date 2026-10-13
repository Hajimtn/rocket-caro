#!/usr/bin/env python3
"""Caronado accounts: sign up, log in, Elo ratings. Python standard library only.

Public API (proxied under /api/ by the web container):
  POST /api/register  {"name", "password"}  -> {"token", "user"}
  POST /api/login     {"name", "password"}  -> {"token", "user"}
  GET  /api/me        Authorization: Bearer <token> -> {"user"}
  GET  /api/top                              -> {"players": [user, ...]}  (best 20)
Internal API (only the game server, on the compose network, never proxied):
  GET  /internal/user/<id>                   -> {"user"}
  POST /internal/match {"x_uid", "o_uid", "winner": 1|2|0 (draw), "difficulty"}
                                             -> {"x": {"before", "after"}, "o": {...}}
  Both need the header X-Internal-Key: <RC_AUTH_SECRET>.

A token is  base64(json {uid, name, exp}) + "." + hex(HMAC-SHA256(secret, that base64)).
The Godot referee checks it with the same secret, so it never has to call us to know who is who.

Environment: RC_AUTH_SECRET (required, 32+ chars), RC_DB (default /data/accounts.db), PORT (8000).
"""
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SECRET = os.environ.get("RC_AUTH_SECRET", "").encode()
DB_PATH = os.environ.get("RC_DB", "/data/accounts.db")
PORT = int(os.environ.get("PORT", "8000"))

TOKEN_DAYS = 30
NAME_RE = re.compile(r"^[A-Za-z0-9_.]{3,16}$")
PASSWORD_MIN, PASSWORD_MAX = 6, 72
START_RATING = 1000
ELO_K = 32
MAX_BODY = 4096
# Abuse limits per client IP: (attempts, seconds)
LIMITS = {"login": (20, 600), "register": (5, 3600)}

_db_lock = threading.Lock()
_db = None
_hits = defaultdict(deque)
_hits_lock = threading.Lock()


# --- storage ------------------------------------------------------------------------------

def open_db(path):
    global _db
    if os.path.dirname(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    _db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
    _db.row_factory = sqlite3.Row
    _db.execute("PRAGMA journal_mode=WAL")
    _db.execute("""CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        pw TEXT NOT NULL,
        rating INTEGER NOT NULL DEFAULT %d,
        wins INTEGER NOT NULL DEFAULT 0,
        losses INTEGER NOT NULL DEFAULT 0,
        draws INTEGER NOT NULL DEFAULT 0,
        created INTEGER NOT NULL)""" % START_RATING)
    _db.execute("""CREATE TABLE IF NOT EXISTS matches (
        id INTEGER PRIMARY KEY,
        x_uid INTEGER NOT NULL, o_uid INTEGER NOT NULL,
        winner INTEGER NOT NULL, difficulty INTEGER NOT NULL,
        x_before INTEGER, x_after INTEGER, o_before INTEGER, o_after INTEGER,
        at INTEGER NOT NULL)""")


def public(row):
    return {"id": row["id"], "name": row["name"], "rating": row["rating"],
            "wins": row["wins"], "losses": row["losses"], "draws": row["draws"]}


def user_by_id(uid):
    with _db_lock:
        return _db.execute("SELECT * FROM users WHERE id = ?", (uid,)).fetchone()


# --- passwords and tokens -----------------------------------------------------------------

def hash_password(password):
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode(), salt=salt, n=2 ** 14, r=8, p=1, dklen=32)
    return "scrypt$16384$8$1$%s$%s" % (salt.hex(), dk.hex())


def check_password(password, stored):
    try:
        algo, n, r, p, salt, want = stored.split("$")
        dk = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p), dklen=32)
        return algo == "scrypt" and hmac.compare_digest(dk.hex(), want)
    except ValueError:
        return False


# Spent on unknown names too, so a failed login takes as long whether the name exists or not.
_DUMMY_HASH = None


def make_token(row):
    payload = base64.b64encode(json.dumps(
        {"uid": row["id"], "name": row["name"], "exp": int(time.time()) + TOKEN_DAYS * 86400},
        separators=(",", ":")).encode()).decode()
    sig = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()
    return payload + "." + sig


def read_token(token):
    try:
        payload, sig = token.split(".")
    except ValueError:
        return None
    want = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(want, sig):
        return None
    try:
        data = json.loads(base64.b64decode(payload))
    except ValueError:
        return None
    if not isinstance(data, dict) or data.get("exp", 0) < time.time():
        return None
    return data


# --- ratings ------------------------------------------------------------------------------

def elo(ra, rb, score_a):
    """New ratings after a game; score_a is 1 (a won), 0.5 (draw) or 0."""
    expect_a = 1.0 / (1.0 + 10 ** ((rb - ra) / 400.0))
    delta = round(ELO_K * (score_a - expect_a))
    return ra + delta, rb - delta


def record_match(x_uid, o_uid, winner, difficulty):
    with _db_lock:
        _db.execute("BEGIN IMMEDIATE")
        try:
            x = _db.execute("SELECT * FROM users WHERE id = ?", (x_uid,)).fetchone()
            o = _db.execute("SELECT * FROM users WHERE id = ?", (o_uid,)).fetchone()
            if x is None or o is None or x_uid == o_uid:
                _db.execute("ROLLBACK")
                return None
            score = {1: 1.0, 2: 0.0}.get(winner, 0.5)
            x_after, o_after = elo(x["rating"], o["rating"], score)
            col = {1: ("wins", "losses"), 2: ("losses", "wins")}.get(winner, ("draws", "draws"))
            _db.execute("UPDATE users SET rating = ?, %s = %s + 1 WHERE id = ?" % (col[0], col[0]), (x_after, x_uid))
            _db.execute("UPDATE users SET rating = ?, %s = %s + 1 WHERE id = ?" % (col[1], col[1]), (o_after, o_uid))
            _db.execute("INSERT INTO matches (x_uid, o_uid, winner, difficulty, x_before, x_after, o_before, o_after, at) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (x_uid, o_uid, winner, difficulty, x["rating"], x_after, o["rating"], o_after, int(time.time())))
            _db.execute("COMMIT")
        except Exception:
            _db.execute("ROLLBACK")
            raise
    return {"x": {"before": x["rating"], "after": x_after}, "o": {"before": o["rating"], "after": o_after}}


# --- HTTP ---------------------------------------------------------------------------------

def limited(kind, ip):
    count, window = LIMITS[kind]
    now = time.time()
    with _hits_lock:
        q = _hits[(kind, ip)]
        while q and q[0] < now - window:
            q.popleft()
        if len(q) >= count:
            return True
        q.append(now)
        return False


class Handler(BaseHTTPRequestHandler):
    server_version = "RocketCaroAccounts/1"

    def log_message(self, fmt, *args):   # one line per request, without the client's IP
        print("[accounts] %s" % (fmt % args), flush=True)

    def client_ip(self):
        # Set by the host nginx from the real TCP peer, and passed through by the web container.
        return self.headers.get("X-Real-IP") or self.client_address[0]

    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if self.path.startswith("/api/"):
            # The itch.io build calls us from another origin. Tokens travel in a header, not a
            # cookie, so allowing any origin does not let other sites act as a logged-in player.
            self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def error(self, code, what):
        self.send_json(code, {"error": what})

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            return None
        try:
            data = json.loads(self.rfile.read(n))
        except ValueError:
            return None
        return data if isinstance(data, dict) else None

    def internal_ok(self):
        return hmac.compare_digest(self.headers.get("X-Internal-Key", "").encode(), SECRET)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/me":
            auth = self.headers.get("Authorization", "")
            data = read_token(auth[7:]) if auth.startswith("Bearer ") else None
            row = user_by_id(data["uid"]) if data else None
            return self.send_json(200, {"user": public(row)}) if row else self.error(401, "unauthorized")
        if self.path == "/api/top":
            with _db_lock:
                rows = _db.execute("SELECT * FROM users WHERE wins + losses + draws > 0 "
                                   "ORDER BY rating DESC, wins DESC LIMIT 20").fetchall()
            return self.send_json(200, {"players": [public(r) for r in rows]})
        if self.path == "/health":
            return self.send_json(200, {"ok": True})
        m = re.fullmatch(r"/internal/user/(\d+)", self.path)
        if m:
            if not self.internal_ok():
                return self.error(403, "forbidden")
            row = user_by_id(int(m.group(1)))
            return self.send_json(200, {"user": public(row)}) if row else self.error(404, "not_found")
        self.error(404, "not_found")

    def do_POST(self):
        if self.path == "/internal/match":
            if not self.internal_ok():
                return self.error(403, "forbidden")
            data = self.body()
            try:
                res = record_match(int(data["x_uid"]), int(data["o_uid"]), int(data["winner"]), int(data.get("difficulty", 0)))
            except (TypeError, KeyError, ValueError):
                return self.error(400, "bad_request")
            return self.send_json(200, res) if res else self.error(404, "not_found")
        if self.path not in ("/api/register", "/api/login"):
            return self.error(404, "not_found")
        kind = self.path[5:]
        if limited(kind, self.client_ip()):
            return self.error(429, "too_many")
        data = self.body()
        if data is None:
            return self.error(400, "bad_request")
        name = str(data.get("name", "")).strip()
        password = str(data.get("password", ""))
        if kind == "register":
            if not NAME_RE.match(name):
                return self.error(400, "bad_name")
            if not PASSWORD_MIN <= len(password) <= PASSWORD_MAX:
                return self.error(400, "bad_password")
            pw = hash_password(password)
            try:
                with _db_lock:
                    cur = _db.execute("INSERT INTO users (name, pw, created) VALUES (?, ?, ?)", (name, pw, int(time.time())))
                    row = _db.execute("SELECT * FROM users WHERE id = ?", (cur.lastrowid,)).fetchone()
            except sqlite3.IntegrityError:
                return self.error(409, "taken")
            return self.send_json(200, {"token": make_token(row), "user": public(row)})
        with _db_lock:
            row = _db.execute("SELECT * FROM users WHERE name = ?", (name,)).fetchone()
        if not check_password(password, row["pw"] if row else _DUMMY_HASH) or row is None:
            return self.error(401, "bad_login")
        return self.send_json(200, {"token": make_token(row), "user": public(row)})


def main():
    global _DUMMY_HASH
    if len(SECRET) < 32:
        raise SystemExit("RC_AUTH_SECRET must be set (32+ characters)")
    open_db(DB_PATH)
    _DUMMY_HASH = hash_password(secrets.token_hex(8))
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print("[accounts] listening on :%d, db %s" % (PORT, DB_PATH), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
