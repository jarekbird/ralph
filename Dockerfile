FROM debian:bookworm-slim

# Ralph runner container.
# - Expects a project workspace mounted at /workspace
# - Expects Cursor Agent CLI available as /usr/local/bin/agent (mount from host or bake in yourself)

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    coreutils \
  && rm -rf /var/lib/apt/lists/*

# Copy ralph scripts/prompts into the image (kept separate from the mounted /workspace)
WORKDIR /opt/ralph
COPY ./scripts ./scripts
COPY ./tests ./tests

# Default workspace mount point
WORKDIR /workspace

COPY ./docker/entrypoint.sh /usr/local/bin/ralph-entrypoint
RUN chmod +x /usr/local/bin/ralph-entrypoint

ENTRYPOINT ["/usr/local/bin/ralph-entrypoint"]
