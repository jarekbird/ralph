#!/usr/bin/env bash
set -euo pipefail

RALPH_SCRIPT="/opt/ralph/scripts/ralph/ralph.sh"

if [[ ! -f "$RALPH_SCRIPT" ]]; then
  echo "Error: Ralph script not found at $RALPH_SCRIPT" >&2
  exit 1
fi

# Load environment variables from workspace .env file if it exists
if [[ -f /workspace/.env ]]; then
  set -a
  source /workspace/.env 2>/dev/null || true
  set +a
fi

# If caller didn't provide a cursor binary override, and `agent` exists, prefer it.
# This avoids the Cursor IDE dependency that `cursor` sometimes requires.
if [[ -z "${RALPH_CURSOR_BIN:-}" ]] && command -v agent >/dev/null 2>&1; then
  export RALPH_CURSOR_BIN="agent"
fi

exec bash "$RALPH_SCRIPT" "$@"

