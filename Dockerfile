# Multi-UI-proof wrapper that forces binding to $PORT on Render.
FROM docker.io/agent0ai/agent-zero:latest

# Optional: default branch used by /exe/initialize.sh if not provided by env
ENV BRANCH=main

# Add our startup script and make it the entrypoint
COPY start.sh /start.sh
RUN chmod +x /start.sh

# IMPORTANT: replace the image's ENTRYPOINT so our script actually runs
ENTRYPOINT ["/bin/bash", "-lc", "/start.sh"]
