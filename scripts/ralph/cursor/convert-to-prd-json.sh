#!/bin/bash
# Convert PRD markdown -> prd.json using Cursor CLI (multi-stage version).
#
# Usage:
#   ./scripts/ralph/cursor/convert-to-prd-json.sh <path-to-prd-markdown> [--cursor-model MODEL] [--out OUT_JSON]
#   (alias: --model MODEL)
#
# Defaults:
# - MODEL: $RALPH_CURSOR_MODEL, or "gpt-5.2"
# - OUT_JSON: <same directory as input>/<base>.prd.json
#
# Notes:
# - This is a convenience helper to streamline PRD->prd.json conversion.
# - It is intentionally separate from the Ralph iteration loop.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file if it exists (in workspace root)
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

PRD_MD_FILE=""
MODEL="${RALPH_CURSOR_MODEL:-gpt-5.2}"
OUT_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|--cursor-model)
      MODEL="${2:-}"
      shift 2
      ;;
    --out)
      OUT_JSON="${2:-}"
      shift 2
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$PRD_MD_FILE" ]]; then
        PRD_MD_FILE="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$PRD_MD_FILE" ]]; then
  echo "Usage: $0 <path-to-prd-markdown> [--cursor-model MODEL] [--out OUT_JSON]" >&2
  echo "Tip: these prompts are large; prefer a large model (default: $MODEL)." >&2
  exit 2
fi

if [[ -z "$MODEL" ]]; then
  echo "Error: --cursor-model/--model cannot be empty" >&2
  exit 2
fi

abs_path() {
  python3 - <<'PY' "$1"
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
}

PRD_MD_FILE="$(abs_path "$PRD_MD_FILE")"
if [[ ! -f "$PRD_MD_FILE" ]]; then
  echo "Error: PRD markdown file not found: $PRD_MD_FILE" >&2
  exit 1
fi

EXAMPLE_FILE="$SCRIPT_DIR/../prd.json.example"
if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo "Error: missing example file: $EXAMPLE_FILE" >&2
  exit 1
fi

CURSOR_BIN="${RALPH_CURSOR_BIN:-cursor}"

PRD_DIR="$(cd "$(dirname "$PRD_MD_FILE")" && pwd)"
PRD_FILENAME="$(basename "$PRD_MD_FILE")"

BASE_NAME="$PRD_FILENAME"
if [[ "$BASE_NAME" == *.prd.md ]]; then
  BASE_NAME="${BASE_NAME%.prd.md}"
elif [[ "$BASE_NAME" == *.md ]]; then
  BASE_NAME="${BASE_NAME%.md}"
fi

EXEC_ORDER_FILE="$PRD_DIR/$BASE_NAME.execution-order.md"
CONTEXT_FILE="$PRD_DIR/$BASE_NAME.context.md"
STEPS_FILE="$PRD_DIR/$BASE_NAME.steps.md"

if [[ -z "$OUT_JSON" ]]; then
  OUT_JSON="$PRD_DIR/$BASE_NAME.prd.json"
else
  OUT_JSON="$(abs_path "$OUT_JSON")"
fi

PROMPT_EXEC_ORDER_FILE="$SCRIPT_DIR/prompt.prd-to-execution-order.md"
PROMPT_CONTEXT_FILE="$SCRIPT_DIR/prompt.prd-to-context.md"
PROMPT_STEPS_FILE="$SCRIPT_DIR/prompt.execution-order-to-steps.md"
PROMPT_JSON_FILE="$SCRIPT_DIR/prompt.steps-to-prd-json.md"

for f in "$PROMPT_EXEC_ORDER_FILE" "$PROMPT_CONTEXT_FILE" "$PROMPT_STEPS_FILE" "$PROMPT_JSON_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: missing prompt template: $f" >&2
    exit 1
  fi
done

sanitize_and_validate() {
  # Args: <kind> <in_file> <out_file>
  # kind: execution_order | context | steps
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys

kind, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(src, "r", encoding="utf-8", errors="replace").read()

# Remove fenced code blocks entirely (agent sometimes wraps the whole answer).
raw = re.sub(r"(?ms)^```.*?^```\s*", "", raw)

bad_line_prefixes = (
  "Created ",
  "I've created ",
  "I have created ",
  "Wrote ",
  "Saved ",
  "Here is ",
  "Here's ",
  "Output saved",
  "Return ONLY",
  "Do not include",
  "Git commands",
  "Per the workspace rules",
  "You should commit",
  "You should push",
  "/workspace/",
)

lines = raw.splitlines()
clean = []
for line in lines:
  stripped = line.strip()
  if not stripped:
    clean.append(line)
    continue
  if any(stripped.startswith(p) for p in bad_line_prefixes):
    continue
  clean.append(line)

# Trim leading/trailing blank lines.
while clean and not clean[0].strip():
  clean.pop(0)
while clean and not clean[-1].strip():
  clean.pop()

def first_index_where(pred):
  for i, line in enumerate(clean):
    if pred(line):
      return i
  return None

if kind == "context":
  idx = first_index_where(lambda l: l.strip() == "# Ralph Context")
  if idx is not None:
    clean = clean[idx:]
elif kind in ("execution_order", "steps"):
  idx = first_index_where(lambda l: re.match(r"^\s*1\.\s+\S", l))
  if idx is not None:
    clean = clean[idx:]

out = "\n".join(clean).rstrip() + "\n"
open(dst, "w", encoding="utf-8").write(out)

# Validate expected shape to catch bad outputs early.
def fail(msg):
  raise SystemExit(msg)

if kind == "context":
  if not out.lstrip().startswith("# Ralph Context"):
    fail("must start with '# Ralph Context'")
  required = ["## Codebase Patterns", "## Domain / Product Context", "## Technical Constraints", "## Notes"]
  missing = [h for h in required if h not in out]
  if missing:
    fail(f"missing required headings: {missing}")
elif kind in ("execution_order", "steps"):
  if not re.search(r"(?m)^\s*1\.\s+\S", out):
    fail("must contain an ordered list starting with '1.'")
else:
  fail(f"unknown kind: {kind}")
PY
}

run_cursor() {
  # Support multiple Cursor CLI variants:
  # - "agent" binary (Cursor Agent CLI)
  # - "cursor agent" subcommand (some installs)
  # - "cursor" with flags (legacy/newer interface)
  local prompt="$1"
  local out_file="$2"

  if [[ "$CURSOR_BIN" == "agent" ]] || [[ "$(basename "$CURSOR_BIN")" == "agent" ]]; then
    "$CURSOR_BIN" --print --force --approve-mcps --model "$MODEL" "$prompt" </dev/null > "$out_file"
  elif "$CURSOR_BIN" --help 2>&1 | grep -q "agent"; then
    "$CURSOR_BIN" agent --print --force --approve-mcps --model "$MODEL" "$prompt" </dev/null > "$out_file"
  else
    "$CURSOR_BIN" --model "$MODEL" --print --force --approve-mcps "$prompt" </dev/null > "$out_file"
  fi
}

run_stage() {
  local prompt_file="$1"
  local stage_name="$2"
  local out_file="$3"
  local out_kind="$4" # execution_order | context | steps
  shift 4

  local prompt_text
  prompt_text="$(
    cat "$prompt_file"
    printf "\n\n---\n\n"
    printf "## Inputs (file paths)\n"
    for input in "$@"; do
      printf -- "- %s\n" "$input"
    done
    printf "\n"
    printf "## Output\n"
    printf "Return ONLY the full file contents (no preambles, no explanations).\n"
    printf "Do NOT mention file paths (especially not /workspace/...).\n"
    printf "Do NOT say you created/wrote/saved a file.\n"
    printf "Do NOT include git instructions.\n"
    printf "Do not include code fences. Do not include commentary.\n"
  )"

  echo ""
  echo "==> Stage: $stage_name"
  echo "    Output: $out_file"

  mkdir -p "$(dirname "$out_file")"
  # Remove any prior output so we can tell if the agent wrote to disk this run.
  rm -f "$out_file"

  local tmp_file
  tmp_file="$(mktemp)"
  set +e
  run_cursor "$prompt_text" "$tmp_file" 2>/dev/stderr
  local exit_code=$?
  set -e
  if [[ $exit_code -ne 0 ]]; then
    echo "Error: Cursor CLI failed during stage: $stage_name (exit $exit_code)" >&2
    rm -f "$tmp_file"
    exit $exit_code
  fi

  # Candidate selection:
  # - stdout candidate: what the agent printed (captured in tmp_file)
  # - on-disk candidate: what the agent may have written directly to out_file
  local stdout_clean disk_clean
  stdout_clean="$(mktemp)"
  disk_clean="$(mktemp)"

  local stdout_ok="no"
  local disk_ok="no"

  if sanitize_and_validate "$out_kind" "$tmp_file" "$stdout_clean" >/dev/null 2>&1; then
    stdout_ok="yes"
  fi

  if [[ -f "$out_file" ]]; then
    if sanitize_and_validate "$out_kind" "$out_file" "$disk_clean" >/dev/null 2>&1; then
      disk_ok="yes"
    fi
  fi

  if [[ "$disk_ok" == "yes" ]]; then
    mv "$disk_clean" "$out_file"
  elif [[ "$stdout_ok" == "yes" ]]; then
    mv "$stdout_clean" "$out_file"
  else
    echo "Error: invalid output from Cursor Agent for stage '$stage_name' (kind: $out_kind)" >&2
    echo "  Neither stdout nor on-disk output matched the required shape." >&2
    rm -f "$stdout_clean" "$disk_clean" "$tmp_file"
    exit 1
  fi

  rm -f "$stdout_clean" "$disk_clean" "$tmp_file"
}

run_stage "$PROMPT_EXEC_ORDER_FILE" "PRD -> execution order" "$EXEC_ORDER_FILE" "execution_order" "$PRD_MD_FILE"
run_stage "$PROMPT_CONTEXT_FILE" "PRD + execution order -> context" "$CONTEXT_FILE" "context" "$PRD_MD_FILE" "$EXEC_ORDER_FILE"
run_stage "$PROMPT_STEPS_FILE" "execution order -> steps" "$STEPS_FILE" "steps" "$PRD_MD_FILE" "$EXEC_ORDER_FILE" "$CONTEXT_FILE"

echo ""
echo "==> Stage: steps -> prd.json"
echo "    Output: $OUT_JSON"

PROMPT_TEXT_JSON="$(
  cat "$PROMPT_JSON_FILE"
  printf "\n\n---\n\n"
  printf "## Inputs (file paths)\n"
  printf -- "- Steps file: %s\n" "$STEPS_FILE"
  printf -- "- PRD markdown (for titles/description): %s\n" "$PRD_MD_FILE"
  printf -- "- Format reference: %s\n" "$EXAMPLE_FILE"
  printf "\n"
  printf "## Output\n"
  printf "Return ONLY valid JSON (no preambles, no explanations).\n"
  printf "Do NOT mention file paths (especially not /workspace/...).\n"
  printf "Do NOT say you created/wrote/saved a file.\n"
  printf "Do NOT include git instructions.\n"
  printf "Do not include code fences. Do not include commentary.\n"
)"

TMP_JSON="$(mktemp)"
set +e
rm -f "$OUT_JSON"
run_cursor "$PROMPT_TEXT_JSON" "$TMP_JSON" 2>/dev/stderr
JSON_EXIT=$?
set -e
if [[ $JSON_EXIT -ne 0 ]]; then
  echo "Error: Cursor CLI failed during stage: steps -> prd.json (exit $JSON_EXIT)" >&2
  rm -f "$TMP_JSON"
  exit $JSON_EXIT
fi

python3 - <<'PY' "$TMP_JSON" "$OUT_JSON"
import json, os, sys

stdout_src, dst = sys.argv[1], sys.argv[2]

def read(path):
  return open(path, "r", encoding="utf-8", errors="replace").read().strip()

# Choose candidate: prefer on-disk output if the agent wrote it this run.
raw = ""
if dst and os.path.exists(dst):
  raw = read(dst)
else:
  raw = read(stdout_src)

if not raw:
  raise SystemExit("Error: empty output from Cursor Agent for prd.json")

# Best-effort: extract first {...} blob if the model added stray text.
start = raw.find("{")
end = raw.rfind("}")
if start == -1 or end == -1 or end <= start:
  raise SystemExit("Error: output does not appear to contain a JSON object")

candidate = raw[start:end+1]
obj = json.loads(candidate)

# Small sanity checks so Ralph won't break later.
required_keys = ["project", "branchName", "contextFile", "logFile", "description", "userStories"]
missing = [k for k in required_keys if k not in obj]
if missing:
  raise SystemExit(f"Error: prd.json missing required keys: {missing}")

open(dst, "w", encoding="utf-8").write(json.dumps(obj, indent=2) + "\n")
PY

rm -f "$TMP_JSON"

echo ""
echo "Done."
echo "Generated:"
echo "- $EXEC_ORDER_FILE"
echo "- $CONTEXT_FILE"
echo "- $STEPS_FILE"
echo "- $OUT_JSON"

