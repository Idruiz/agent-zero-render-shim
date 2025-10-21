#!/usr/bin/env bash
set -euo pipefail

# 1) Boot Agent-Zero in background (its supervisor keeps services alive)
#    BRANCH comes from env or defaults to main
/exe/initialize.sh "${BRANCH:-main}" &

# 2) Tiny HTTP-aware front server:
#    - Always binds Render's $PORT
#    - If backend (80 or 9000) is NOT ready => returns 200 with "Starting…" page
#    - If backend ready => TCP proxy passthrough (keeps SSE/WebSocket flows intact)

cat >/tmp/front.py <<'PY'
import socket, threading, sys, time

DESTS = [("127.0.0.1",80), ("127.0.0.1",9000)]

def pick_backend(timeout=0.2):
    for host, port in DESTS:
        try:
            s = socket.create_connection((host, port), timeout=timeout)
            return s, (host, port)
        except Exception:
            continue
    return None, None

STARTING_PAGE = (b"HTTP/1.1 200 OK\r\n"
                 b"Content-Type: text/html; charset=UTF-8\r\n"
                 b"Cache-Control: no-cache\r\n"
                 b"Connection: close\r\n\r\n"
                 b"<!doctype html><html><head><meta charset='utf-8'>"
                 b"<title>Agent-Zero starting…</title>"
                 b"<meta http-equiv='refresh' content='2'>"
                 b"<style>body{font-family:system-ui,Arial;margin:2rem}"
                 b".dot{animation:blink 1s infinite}@keyframes blink{50%{opacity:.3}}</style>"
                 b"</head><body><h1>Agent-Zero is starting…</h1>"
                 b"<p>Backend not ready yet. This page will auto-refresh.</p>"
                 b"</body></html>")

def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data: break
            dst.sendall(data)
    finally:
        for s in (src, dst):
            try: s.shutdown(socket.SHUT_RDWR)
            except: pass
            try: s.close()
            except: pass

def handle_client(cli):
    # Try to connect to backend quickly
    b, which = pick_backend()
    if b is None:
        # No backend yet: return a friendly 200 page so "Open" actually shows something
        try:
            # Try to read one line to avoid sending on dead sockets
            cli.settimeout(0.2)
            try: cli.recv(1024)
            except Exception: pass
            cli.sendall(STARTING_PAGE)
        except Exception:
            pass
        finally:
            try: cli.shutdown(socket.SHUT_RDWR)
            except: pass
            try: cli.close()
            except: pass
        return
    # Backend available: full-duplex TCP proxy
    threading.Thread(target=pump, args=(cli, b), daemon=True).start()
    pump(b, cli)

def serve(listen_port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", listen_port))
    s.listen(256)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle_client, args=(c,), daemon=True).start()

if __name__ == "__main__":
    lp = int(sys.argv[1])
    serve(lp)
PY

# 3) Run the front server in the foreground (Render health-checks this)
exec python3 /tmp/front.py "${PORT}"
