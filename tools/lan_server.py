#!/usr/bin/env python3
"""Static web server + WebSocket tunnel for Caronado.

Godot web builds need a secure context (HTTPS, or localhost) to run, so on the LAN the page has
to be served over HTTPS. A page loaded from https:// may only open wss:// sockets, so this
server also accepts the game's WebSocket upgrade on the same port and tunnels it, byte for byte,
to the headless Godot referee on 127.0.0.1. One port, one certificate warning to accept.

usage: lan_server.py ROOT HTTP_PORT HTTPS_PORT CERT KEY [BACKEND_PORT]
"""
import asyncio
import os
import ssl
import sys
import urllib.parse

ROOT = os.path.realpath(sys.argv[1])
HTTP_PORT, HTTPS_PORT = int(sys.argv[2]), int(sys.argv[3])
CERT, KEY = sys.argv[4], sys.argv[5]
BACKEND = ("127.0.0.1", int(sys.argv[6]) if len(sys.argv) > 6 else 24571)
MIME = {
    ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
    ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json",
    ".css": "text/css",
}


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def reply(writer, code, text, body=b""):
    writer.write(f"HTTP/1.1 {code} {text}\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode() + body)
    await writer.drain()


async def handle(reader, writer):
    try:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 15)
        lines = head.decode("latin-1").split("\r\n")
        method, target, _ = lines[0].split(" ", 2)
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        if headers.get("upgrade", "").lower() == "websocket":
            try:
                back_r, back_w = await asyncio.open_connection(*BACKEND)
            except OSError:
                await reply(writer, 502, "Bad Gateway", b"game server is not running")
                return
            back_w.write(head)
            await back_w.drain()
            await asyncio.gather(pipe(reader, back_w), pipe(back_r, writer))
            return

        path = urllib.parse.unquote(target.split("?", 1)[0])
        if path.endswith("/"):
            path += "index.html"
        full = os.path.realpath(os.path.join(ROOT, path.lstrip("/")))
        if not full.startswith(ROOT + os.sep) or not os.path.isfile(full):
            await reply(writer, 404, "Not Found", b"not found")
            return
        ctype = MIME.get(os.path.splitext(full)[1].lower(), "application/octet-stream")
        writer.write((f"HTTP/1.1 200 OK\r\nContent-Type: {ctype}\r\nContent-Length: {os.path.getsize(full)}\r\n"
                      "Cache-Control: no-cache\r\nConnection: close\r\n\r\n").encode())
        if method != "HEAD":
            with open(full, "rb") as f:
                while chunk := f.read(262144):
                    writer.write(chunk)
                    await writer.drain()
        await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    http = await asyncio.start_server(handle, "0.0.0.0", HTTP_PORT)
    https = await asyncio.start_server(handle, "0.0.0.0", HTTPS_PORT, ssl=ctx)
    async with http, https:
        await asyncio.gather(http.serve_forever(), https.serve_forever())


asyncio.run(main())
