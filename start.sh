#!/usr/bin/env bash
set -euo pipefail
echo "[shim] Starting. BRANCH=${BRANCH:-main}  PORT=${PORT:-<unset>}  $(date -Is)" >&2

# 1) Boot Agent-Zero in the background
(/exe/initialize.sh "${BRANCH:-main}" 2>&1 | sed 's/^/[init] /' || echo "[init] Failed with exit code $?") &

# 2) Wait for Agent-Zero to start and detect its port
echo "[shim] Waiting for Agent-Zero to start..."
AGENT_PORT=""
for i in {1..30}; do
  sleep 2
  
  # Look for any listening port on 127.0.0.1 (excluding SSH on port 22)
  DETECTED=$(netstat -tlnp 2>/dev/null | grep '127.0.0.1:' | grep -v ':22 ' | awk '{print $4}' | cut -d: -f2 | head -n1)
  
  if [ -n "$DETECTED" ]; then
    AGENT_PORT=$DETECTED
    echo "[shim] Found Agent-Zero running on port $AGENT_PORT"
    break
  fi
  
  echo "[shim] Still waiting... (attempt $i/30)"
done

if [ -z "$AGENT_PORT" ]; then
  echo "[shim] ERROR: Could not find Agent-Zero!"
  echo "[shim] All listening ports:"
  netstat -tlnp || ss -tlnp || true
  exit 1
fi

# 3) Generate nginx config with the discovered port
if [ -z "${PORT:-}" ]; then export PORT=10000; fi

cat >/etc/nginx/nginx.conf <<NGX
worker_processes  1;
events { worker_connections 1024; }
http {
  include       mime.types;
  default_type  application/octet-stream;
  sendfile        on;
  keepalive_timeout  65;

  upstream a0_upstream {
    server 127.0.0.1:${AGENT_PORT};
  }

  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
  }

  server {
    listen       ${PORT} default_server;
    server_name  _;

    location = /healthz {
      return 200 'ok';
      add_header Content-Type text/plain;
    }

    location / {
      proxy_pass http://a0_upstream;
      proxy_http_version 1.1;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }
}
NGX

echo "[shim] Nginx configured: Agent-Zero on 127.0.0.1:$AGENT_PORT → nginx on 0.0.0.0:$PORT"
nginx -t
exec nginx -g 'daemon off;'
