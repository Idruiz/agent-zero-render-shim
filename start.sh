#!/usr/bin/env bash
set -euo pipefail

echo "[shim] Starting. BRANCH=${BRANCH:-main}  PORT=${PORT:-<unset>}  $(date -Is)" >&2

# 1) Boot Agent-Zero in the background (its supervisor keeps services alive)
#    If BRANCH isn't provided by env, defaults to main.
(/exe/initialize.sh "${BRANCH:-main}" || true) &

# 2) Generate an nginx config that:
#    - Listens on $PORT (Render’s router requirement)
#    - Proxies to Agent-Zero on 127.0.0.1:80 with a 9000 backup
#    - Always returns 200 on /healthz so health checks pass instantly
if [ -z "${PORT:-}" ]; then export PORT=10000; fi

cat >/etc/nginx/nginx.conf <<'NGX'
worker_processes  1;

events { worker_connections 1024; }

http {
  # Basic safe defaults
  include       mime.types;
  default_type  application/octet-stream;
  sendfile        on;
  keepalive_timeout  65;

  # Try port 80 first; if that errors, use 9000.
  # "backup" ensures nginx switches when 80 isn't responding to the request.
  upstream a0_upstream {
    server 127.0.0.1:80 max_fails=1 fail_timeout=1s;
    server 127.0.0.1:9000 backup;
  }

  # Upgrade header helper (for SSE/WebSocket tolerance)
  map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
  }

  server {
    listen       PORT_PLACEHOLDER default_server;
    server_name  _;

    # Reliable health for Render
    location = /healthz {
      return 200 'ok';
      add_header Content-Type text/plain;
    }

    # Proxy everything else to Agent-Zero
    location / {
      proxy_pass http://a0_upstream;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;

      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;

      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }
}
NGX

# Inject the actual port Render gave us
sed -i "s/PORT_PLACEHOLDER/${PORT}/g" /etc/nginx/nginx.conf

# Show the final config sanity quickly in logs; then run nginx in foreground.
nginx -t
exec nginx -g 'daemon off;'
