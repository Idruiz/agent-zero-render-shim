FROM agent0ai/agent-zero:latest

COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
