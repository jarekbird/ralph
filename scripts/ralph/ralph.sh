#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [max_iterations] [--worker amp|cursor] [--model MODEL] [--prd PATH] [--workspace PATH] [--cursor-timeout SECONDS]
#        or set RALPH_WORKER environment variable (amp|cursor)
#        Default worker is 'amp' if not specified
#        Default PRD file is scripts/ralph/prd.json if not specified
#        Note: context/log files are read ONLY from the PRD (contextFile/logFile). Do not pass them as args.

set -e

# Helpers
usage() {
  cat <<'EOF'
Usage: ./ralph.sh [max_iterations] [--worker amp|cursor] [--model MODEL] [--prd PATH] [--workspace PATH] [--cursor-timeout SECONDS]

Notes:
- Ralph reads the context + log file paths ONLY from the PRD JSON fields: contextFile, logFile.
- Do not pass log/context/other parameter files as CLI args.
EOF
}

die() {
  echo "Error: $*" >&2
  echo "" >&2
  usage >&2
  exit 2
}

# Parse arguments
MAX_ITERATIONS=10
WORKER="${RALPH_WORKER:-amp}"
CURSOR_TIMEOUT="${RALPH_CURSOR_TIMEOUT:-1800}"  # Default: 30 minutes (in seconds)
CURSOR_BIN="${RALPH_CURSOR_BIN:-cursor}"
CURSOR_MODEL="${RALPH_CURSOR_MODEL:-auto}"
PRD_FILE_ARG=""
WORKSPACE_DIR_ARG=""
MAX_ITERATIONS_SET=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --worker)
      [[ -n "${2:-}" ]] || die "--worker requires a value (amp|cursor)"
      WORKER="$2"
      shift 2
      ;;
    --model|--cursor-model)
      [[ -n "${2:-}" ]] || die "--model/--cursor-model requires a value"
      CURSOR_MODEL="$2"
      shift 2
      ;;
    --prd)
      [[ -n "${2:-}" ]] || die "--prd requires a path to a PRD JSON file"
      PRD_FILE_ARG="$2"
      shift 2
      ;;
    --workspace)
      [[ -n "${2:-}" ]] || die "--workspace requires a directory path"
      WORKSPACE_DIR_ARG="$2"
      shift 2
      ;;
    --cursor-timeout)
      [[ -n "${2:-}" ]] || die "--cursor-timeout requires a number of seconds"
      CURSOR_TIMEOUT="$2"
      shift 2
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        [[ -z "$MAX_ITERATIONS_SET" ]] || die "max_iterations specified more than once (got: $1)"
        MAX_ITERATIONS="$1"
        MAX_ITERATIONS_SET="yes"
      elif [[ -z "$PRD_FILE_ARG" && ( "$1" == *.json || "$1" == *.JSON ) ]]; then
        # Convenience positional: treat a single .json arg as PRD path
        PRD_FILE_ARG="$1"
      else
        die "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

# Validate worker
if [[ "$WORKER" != "amp" && "$WORKER" != "cursor" ]]; then
  echo "Error: Worker must be 'amp' or 'cursor' (got: $WORKER)" >&2
  exit 1
fi

# Validate Cursor model selection (only when cursor worker is used)
if [[ "$WORKER" == "cursor" && -z "$CURSOR_MODEL" ]]; then
  echo "Error: --model/--cursor-model cannot be empty when using --worker cursor" >&2
  exit 1
fi

# Resolve workspace directory (used as the working directory for worker execution).
# Defaults to the current working directory if not provided.
WORKSPACE_DIR="${WORKSPACE_DIR_ARG:-${RALPH_WORKSPACE:-}}"
if [[ -n "$WORKSPACE_DIR" ]]; then
  if [[ "$WORKSPACE_DIR" = /* ]]; then
    # Absolute
    WORKSPACE_DIR="$WORKSPACE_DIR"
  else
    # Relative to invocation directory
    WORKSPACE_DIR="$(cd "$(dirname "$WORKSPACE_DIR")" && pwd)/$(basename "$WORKSPACE_DIR")"
  fi
  if [[ ! -d "$WORKSPACE_DIR" ]]; then
    echo "Error: workspace directory not found: $WORKSPACE_DIR" >&2
    exit 1
  fi
else
  WORKSPACE_DIR="$(pwd)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file if it exists (in repository root)
# Look for .env in common locations: repo root (parent of scripts/), or current directory
REPO_ROOT=""
if [ -f "$SCRIPT_DIR/../../.env" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
elif [ -f "$SCRIPT_DIR/../.env" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -f ".env" ]; then
  REPO_ROOT="$(pwd)"
fi

if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.env" ]; then
  # Temporarily disable exit on error to allow .env sourcing
  set +e
  # Use set -a to auto-export all variables, source .env, then restore
  set -a
  source "$REPO_ROOT/.env" 2>/dev/null
  set +a
  set -e
fi

# Determine PRD file path
if [[ -n "$PRD_FILE_ARG" ]]; then
  # If --prd is provided, resolve it (supports relative and absolute paths)
  if [[ "$PRD_FILE_ARG" = /* ]]; then
    # Absolute path
    PRD_FILE="$PRD_FILE_ARG"
  else
    # Relative path - resolve from current working directory
    PRD_FILE="$(cd "$(dirname "$PRD_FILE_ARG")" && pwd)/$(basename "$PRD_FILE_ARG")"
  fi
else
  # Default to prd.json in script directory
  PRD_FILE="$SCRIPT_DIR/prd.json"
fi

# Validate PRD file exists
if [[ ! -f "$PRD_FILE" ]]; then
  echo "Error: PRD file not found: $PRD_FILE" >&2
  exit 1
fi

# Require jq (used to read PRD fields)
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but was not found in PATH." >&2
  exit 1
fi

# Store progress/archive files in the PRD file's directory (allows multiple PRDs per repo)
PRD_DIR="$(cd "$(dirname "$PRD_FILE")" && pwd)"
# Force create PRD directory if it doesn't exist (shouldn't happen, but be safe)
mkdir -p "$PRD_DIR"
ARCHIVE_DIR="$PRD_DIR/archive"
LAST_BRANCH_FILE="$PRD_DIR/.last-branch"

# Resolve context + log files (relative to PRD directory by default)
CONTEXT_FILE_NAME="$(jq -er '.contextFile' "$PRD_FILE" 2>/dev/null)" || {
  echo "Error: PRD is missing required field: contextFile" >&2
  exit 1
}
LOG_FILE_NAME="$(jq -er '.logFile' "$PRD_FILE" 2>/dev/null)" || {
  echo "Error: PRD is missing required field: logFile" >&2
  exit 1
}

if [[ -z "$CONTEXT_FILE_NAME" || "$CONTEXT_FILE_NAME" == "null" ]]; then
  echo "Error: PRD field contextFile must be a non-empty string" >&2
  exit 1
fi
if [[ -z "$LOG_FILE_NAME" || "$LOG_FILE_NAME" == "null" ]]; then
  echo "Error: PRD field logFile must be a non-empty string" >&2
  exit 1
fi

if [[ "$CONTEXT_FILE_NAME" = /* ]]; then
  CONTEXT_FILE="$CONTEXT_FILE_NAME"
else
  CONTEXT_FILE="$PRD_DIR/$CONTEXT_FILE_NAME"
fi

if [[ "$LOG_FILE_NAME" = /* ]]; then
  LOG_FILE="$LOG_FILE_NAME"
else
  LOG_FILE="$PRD_DIR/$LOG_FILE_NAME"
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$CONTEXT_FILE" ] && cp "$CONTEXT_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$LOG_FILE" ] && cp "$LOG_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset context + log for new run
    cat > "$CONTEXT_FILE" << EOF
# Ralph Context

## Codebase Patterns

## Notes
- Started: $(date)
EOF

    echo "# Ralph Run Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Force create and initialize context + log files
# Always ensure they exist (the AI agent will append/update them)
if [ ! -f "$CONTEXT_FILE" ]; then
  cat > "$CONTEXT_FILE" << EOF
# Ralph Context

## Codebase Patterns

## Notes
- Started: $(date)
EOF
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "# Ralph Run Log" > "$LOG_FILE"
  echo "Started: $(date)" >> "$LOG_FILE"
  echo "---" >> "$LOG_FILE"
fi

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"
echo "Worker: $WORKER"
echo "PRD file: $PRD_FILE"
echo "Workspace: $WORKSPACE_DIR"
echo "Context file: $CONTEXT_FILE"
echo "Log file: $LOG_FILE"
if [[ "$WORKER" == "cursor" ]]; then
  echo "Cursor model: $CURSOR_MODEL"
  if [[ -z "${CURSOR_API_KEY:-}" ]]; then
    echo "Warning: CURSOR_API_KEY environment variable is not set."
    echo "  Some Cursor CLI tools require authentication. Set CURSOR_API_KEY if needed"
    echo "  Example: export CURSOR_API_KEY=your-api-key-here"
  else
    echo "Cursor API key: ${CURSOR_API_KEY:0:10}... (set)"
  fi
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS (Worker: $WORKER)"
  echo "═══════════════════════════════════════════════════════"
  
  # Select prompt and execute based on worker
  if [[ "$WORKER" == "amp" ]]; then
    # Amp worker: use prompt.md and execute amp
    # Inject PRD file path into prompt
    PROMPT_FILE="$SCRIPT_DIR/prompt.md"
    PROMPT_TEXT=$(cat "$PROMPT_FILE" | sed "s|Read the PRD at \`prd.json\` (in the same directory as this file)|Read the PRD at \`$PRD_FILE\`|g")
    OUTPUT=$( (cd "$WORKSPACE_DIR" && echo "$PROMPT_TEXT" | amp --dangerously-allow-all) 2>&1 | tee /dev/stderr ) || true
  elif [[ "$WORKER" == "cursor" ]]; then
    # Cursor worker: use cursor/prompt.cursor.md and execute cursor CLI
    # Uses non-interactive headless mode with file edits enabled
    # Always uses normal spawn (never PTY), stdin is closed (no interactive prompts)
    PROMPT_FILE="$SCRIPT_DIR/cursor/prompt.cursor.md"
    # Inject PRD file path into prompt
    PROMPT_TEXT=$(cat "$PROMPT_FILE" | sed "s|Read the PRD at \`prd.json\` (in the same directory as this file)|Read the PRD at \`$PRD_FILE\`|g")
    # Execute cursor with: --model "$CURSOR_MODEL" --print --force --approve-mcps
    # stdin is automatically closed when using command substitution in bash
    # Per-iteration hard timeout (wall-clock) - kills process if exceeded
    # Note: MCP cleanup is handled by Cursor CLI itself when processes exit normally
    # If MCP processes are orphaned, they may need manual cleanup (outside scope of this script)
    if command -v timeout >/dev/null 2>&1; then
      OUTPUT=$( (cd "$WORKSPACE_DIR" && timeout "$CURSOR_TIMEOUT" "$CURSOR_BIN" --model "$CURSOR_MODEL" --print --force --approve-mcps "$PROMPT_TEXT" </dev/null) 2>&1 | tee /dev/stderr ) || true
      TIMEOUT_EXIT=$?
      if [[ $TIMEOUT_EXIT -eq 124 ]]; then
        echo "Warning: Cursor iteration timed out after ${CURSOR_TIMEOUT} seconds" >&2
      fi
    else
      # Fallback if timeout command is not available
      OUTPUT=$( (cd "$WORKSPACE_DIR" && "$CURSOR_BIN" --model "$CURSOR_MODEL" --print --force --approve-mcps "$PROMPT_TEXT" </dev/null) 2>&1 | tee /dev/stderr ) || true
    fi
  fi
  
  # Always append raw worker output to the PRD-specified log file for auditability.
  {
    echo ""
    echo "=== Ralph iteration $i of $MAX_ITERATIONS (worker: $WORKER) @ $(date) ==="
    printf "%s\n" "$OUTPUT"
    echo "=== End Ralph iteration $i ==="
  } >> "$LOG_FILE"

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $LOG_FILE for status."
exit 1
