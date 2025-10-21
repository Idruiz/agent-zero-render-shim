#!/usr/bin/env bash
set -euo pipefail

# 1) Boot Agent-Zero (it runs its own supervisor and keeps services alive)
#    BRANCH comes from env; defaults to main
/exe/initialize.sh "${BRANCH:-main}" &

# 2) Create a tiny TCP proxy that binds Render's $PORT and forwards
#    to whichever internal port Agent-Zero is actually using (80 or 9000).
cat >/tmp/tcp_proxy.py <<'PY'
import socket, threading, sys

DSTS = [("127.0.0.1", 80), ("127.0.0.1", 9000)]

def dial():
    # Try 80 first, then 9000 for every incoming connection
    for host,port in DSTS:
        try:
            s = socket.create_connection((host,port), timeout=1.0)
            return s
        except Exception:
            continue
    return None

def pump(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    finally:
        for s in (a, b):
            try: s.shutdown(socket.SHUT_RDWR)
            except: pass
            try: s.close()
            except: pass

def serve(listen_port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", listen_port))
    s.listen(128)
    while True:
        c, _ = s.accept()
        d = dial()
        if not d:
            try: c.close()
            except: pass
            continue
        threading.Thread(target=pump, args=(c, d), daemon=True).start()
        pump(d, c)

if __name__ == "__main__":
    lp = int(sys.argv[1])
    serve(lp)
PY

# 3) Run the proxy in the foreground; this is what Render will health-check.
exec python3 /tmp/tcp_proxy.py "${PORT}"
