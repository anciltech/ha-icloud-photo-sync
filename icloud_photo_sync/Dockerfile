FROM boredazfcuk/icloudpd:latest

COPY run.sh /run.sh

RUN if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache expect imagemagick; \
    elif command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      apt-get install -y --no-install-recommends expect imagemagick && \
      rm -rf /var/lib/apt/lists/*; \
    fi && \
    chmod 755 /run.sh

CMD ["/run.sh"]
