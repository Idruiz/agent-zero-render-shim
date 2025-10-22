FROM agent0ai/agent-zero:latest

# Prevent any interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install nginx - force it to accept defaults and not prompt about config conflicts
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confdef" \
    nginx ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /etc/nginx/sites-enabled/default

# Copy the shim start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose port (Render will override with $PORT)
EXPOSE 10000

# Run the shim
CMD ["/start.sh"]
