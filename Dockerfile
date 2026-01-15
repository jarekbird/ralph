FROM debian:bookworm-slim

# Ralph runner container.
# - Expects a project workspace mounted at /workspace
# - Installs Cursor Agent CLI directly in the image
# - Reads CURSOR_API_KEY from workspace .env file

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    coreutils \
    python3 \
    nodejs \
    npm \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf /usr/bin/nodejs /usr/local/bin/node || true

# Install Cursor Agent CLI
RUN curl -fsSL https://cursor.com/install | bash || true \
  && if [ -f /usr/local/lib/cursor/cursor-agent ]; then \
      mkdir -p /usr/local/bin && \
      ln -sf /usr/local/lib/cursor/cursor-agent /usr/local/bin/cursor-agent && \
      ln -sf /usr/local/lib/cursor/cursor-agent /usr/local/bin/agent && \
      echo "cursor-agent installed in /usr/local/bin"; \
    elif [ -f /root/.local/bin/cursor-agent ]; then \
      mkdir -p /usr/local/bin && \
      ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor-agent && \
      ln -sf /root/.local/bin/cursor-agent /usr/local/bin/agent && \
      echo "cursor-agent installed from /root/.local/bin"; \
    elif command -v cursor-agent >/dev/null 2>&1; then \
      CURSOR_PATH=$(command -v cursor-agent) && \
      mkdir -p /usr/local/bin && \
      ln -sf "$CURSOR_PATH" /usr/local/bin/cursor-agent && \
      ln -sf "$CURSOR_PATH" /usr/local/bin/agent && \
      echo "cursor-agent symlinked from found location: $CURSOR_PATH"; \
    else \
      echo "Warning: cursor-agent not found after installation"; \
    fi

# Ensure /usr/local/bin is in PATH
ENV PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

# Copy ralph scripts/prompts into the image (kept separate from the mounted /workspace)
WORKDIR /opt/ralph
COPY ./scripts ./scripts
COPY ./tests ./tests

# Default workspace mount point
WORKDIR /workspace

COPY ./docker/entrypoint.sh /usr/local/bin/ralph-entrypoint
RUN chmod +x /usr/local/bin/ralph-entrypoint

ENTRYPOINT ["/usr/local/bin/ralph-entrypoint"]
