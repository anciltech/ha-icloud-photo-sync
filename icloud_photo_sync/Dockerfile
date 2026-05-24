FROM boredazfcuk/icloudpd:latest

COPY run.sh /run.sh

RUN if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache expect imagemagick python3 py3-pip py3-pillow && \
      (apk add --no-cache libheif-tools || true) && \
      (python3 -m pip install --no-cache-dir --break-system-packages pillow-heif || true); \
    elif command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      (apt-get install -y --no-install-recommends expect imagemagick python3 python3-pip python3-pil libheif-examples || \
        apt-get install -y --no-install-recommends expect imagemagick python3 python3-pip python3-pil) && \
      (python3 -m pip install --no-cache-dir --break-system-packages pillow-heif || \
        python3 -m pip install --no-cache-dir pillow-heif || true) && \
      rm -rf /var/lib/apt/lists/*; \
    fi && \
    chmod 755 /run.sh

CMD ["/run.sh"]
