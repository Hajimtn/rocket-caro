#!/usr/bin/env python3
"""Checks for backend/accounts.py against a real server on a scratch database:
    python3 tools/test_accounts.py
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = 18765
SECRET = "test-secret-" + "x" * 40
BASE = "http://127.0.0.1:%d" % PORT
fails = 0


def call(method, path, body=None, headers=None):
    req = urllib.request.Request(BASE + path, method=method, headers=headers or {},
                                 data=json.dumps(body).encode() if body is not None else None)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def check(ok, what):
    global fails
    if not ok:
        fails += 1
        print("FAIL:", what)


def main():
    tmp = tempfile.mkdtemp()
    env = dict(os.environ, RC_AUTH_SECRET=SECRET, RC_DB=os.path.join(tmp, "a.db"), PORT=str(PORT))
    proc = subprocess.Popen([sys.executable, "-I", os.path.join(ROOT, "backend", "accounts.py")], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                if call("GET", "/health")[0] == 200:
                    break
            except OSError:
                time.sleep(0.1)
        code, res = call("POST", "/api/register", {"name": "Minh_1", "password": "secret1"})
        check(code == 200 and res["user"]["rating"] == 1000 and "." in res["token"], "register")
        tok_a = res.get("token", "")
        check(call("POST", "/api/register", {"name": "minh_1", "password": "secret1"})[0] == 409, "names are unique, any case")
        check(call("POST", "/api/register", {"name": "a b", "password": "secret1"})[1].get("error") == "bad_name", "name rules")
        check(call("POST", "/api/register", {"name": "lan", "password": "123"})[1].get("error") == "bad_password", "password length")
        code, res = call("POST", "/api/register", {"name": "lan", "password": "matkhau"})
        check(code == 200, "second user")
        uid_b = res["user"]["id"]

        check(call("POST", "/api/login", {"name": "MINH_1", "password": "secret1"})[0] == 200, "login (any case)")
        check(call("POST", "/api/login", {"name": "Minh_1", "password": "wrong!"})[1].get("error") == "bad_login", "wrong password")
        check(call("POST", "/api/login", {"name": "nobody", "password": "secret1"})[1].get("error") == "bad_login", "unknown name")

        code, res = call("GET", "/api/me", headers={"Authorization": "Bearer " + tok_a})
        check(code == 200 and res["user"]["name"] == "Minh_1", "me")
        forged = tok_a[:-1] + ("0" if tok_a[-1] != "0" else "1")
        check(call("GET", "/api/me", headers={"Authorization": "Bearer " + forged})[0] == 401, "forged token")

        key = {"X-Internal-Key": SECRET}
        check(call("POST", "/internal/match", {"x_uid": 1, "o_uid": uid_b, "winner": 1})[0] == 403, "internal API needs the key")
        code, res = call("POST", "/internal/match", {"x_uid": 1, "o_uid": uid_b, "winner": 1, "difficulty": 2}, key)
        check(code == 200 and res["x"]["after"] == 1016 and res["o"]["after"] == 984, "elo after a win: %s" % res)
        code, res = call("POST", "/internal/match", {"x_uid": 1, "o_uid": uid_b, "winner": 0}, key)
        check(code == 200 and res["x"]["after"] < 1016 and res["o"]["after"] > 984, "a draw pulls ratings together")
        check(call("POST", "/internal/match", {"x_uid": 1, "o_uid": 1, "winner": 1}, key)[0] == 404, "no match against yourself")
        code, res = call("GET", "/internal/user/1", headers=key)
        check(code == 200 and res["user"]["wins"] == 1 and res["user"]["draws"] == 1, "stats recorded")
        code, res = call("GET", "/api/top")
        check(code == 200 and [p["name"] for p in res["players"]] == ["Minh_1", "lan"], "leaderboard")

        codes = [call("POST", "/api/login", {"name": "x", "password": "y"})[0] for _ in range(25)]
        check(429 in codes, "login attempts are rate limited")
    finally:
        proc.terminate()
        proc.wait()
    print("RESULT:", "FAIL" if fails else "OK")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
