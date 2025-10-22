# Render-proof Agent-Zero wrapper with a hard, always-on HTTP listener.
FROM docker.io/agent0ai/agent-zero:latest

# 1) Install a tiny web server to bind $PORT reliably.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx-light ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 2) Default branch for Agent-Zero bootstrap (safe if env BRANCH is unset)
ENV BRANCH=main

# 3) Add our startup script and make it the entrypoint
COPY start.sh /start.sh
RUN chmod +x /start.sh

# 4) Force OUR entrypoint (no guessing about the base image's entrypoint)
ENTRYPOINT ["/bin/bash", "-lc", "/start.sh"]
