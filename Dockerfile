FROM agent0ai/agent-zero:latest

# Prevent any interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install nginx - force it to accept defaults and not prompt about config conflicts
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confdef" \
    nginx ca-certificates netcat-openbsd net-tools && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /etc/nginx/sites-enabled/default

# Copy the shim start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose port (Render will override with $PORT)
EXPOSE 10000

# Run the shim
CMD ["/start.sh"]
```

If it doesn't have `netcat-openbsd net-tools` on line 10, edit it and add those.

---

### Then redeploy on Render:

1. Go to Render dashboard
2. Click **"Manual Deploy"** → **"Clear build cache & deploy"** (important - use this option to force a fresh build)
3. Watch the logs

You should now see:
```
[shim] Waiting for Agent-Zero to start...
[shim] Still waiting... (attempt 1/30)
[shim] Still waiting... (attempt 2/30)
[shim] Found Agent-Zero running on port XXXX
