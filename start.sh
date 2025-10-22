#!/usr/bin/env bash
set -euo pipefail
echo "[shim] Starting. BRANCH=${BRANCH:-main}  PORT=${PORT:-<unset>}  $(date -Is)" >&2

# 1) Boot Agent-Zero in the background
(/exe/initialize.sh "${BRANCH:-main}" || true) &

# 2) Wait for Agent-Zero to be ready (check common ports)
echo "[shim] Waiting for Agent-Zero to start..."
AGENT_PORT=""
for i in {1..30}; do
  sleep 2
  # Check common ports Agent-Zero might use
  for port in 80 8080 7860 5000 3000 8000 9000; do
    if nc -z 127.0.0.1 $port 2>/dev/null; then
      AGENT_PORT=$port
      echo "[shim] Found Agent-Zero running on port $port"
      break 2
    fi
  done
  echo "[shim] Still waiting... (attempt $i/30)"
done

if [ -z "$AGENT_PORT" ]; then
  echo "[shim] ERROR: Could not find Agent-Zero on any expected port!"
  echo "[shim] Checking what's actually listening:"
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

    # Health check
    location = /healthz {
      return 200 'ok';
      add_header Content-Type text/plain;
    }

    # Proxy to Agent-Zero
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

echo "[shim] Nginx config generated for Agent-Zero on port $AGENT_PORT, nginx listening on port $PORT"
nginx -t
exec nginx -g 'daemon off;'
