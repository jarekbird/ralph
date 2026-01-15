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
  shift 3

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
    printf "Return ONLY the full contents for: %s\n" "$out_file"
    printf "Do not include code fences. Do not include commentary.\n"
  )"

  echo ""
  echo "==> Stage: $stage_name"
  echo "    Output: $out_file"

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

  mkdir -p "$(dirname "$out_file")"
  mv "$tmp_file" "$out_file"
}

run_stage "$PROMPT_EXEC_ORDER_FILE" "PRD -> execution order" "$EXEC_ORDER_FILE" "$PRD_MD_FILE"
run_stage "$PROMPT_CONTEXT_FILE" "PRD + execution order -> context" "$CONTEXT_FILE" "$PRD_MD_FILE" "$EXEC_ORDER_FILE"
run_stage "$PROMPT_STEPS_FILE" "execution order -> steps" "$STEPS_FILE" "$PRD_MD_FILE" "$EXEC_ORDER_FILE" "$CONTEXT_FILE"

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
  printf "Return ONLY valid JSON for: %s\n" "$OUT_JSON"
  printf "Do not include code fences. Do not include commentary.\n"
)"

TMP_JSON="$(mktemp)"
set +e
run_cursor "$PROMPT_TEXT_JSON" "$TMP_JSON" 2>/dev/stderr
JSON_EXIT=$?
set -e
if [[ $JSON_EXIT -ne 0 ]]; then
  echo "Error: Cursor CLI failed during stage: steps -> prd.json (exit $JSON_EXIT)" >&2
  rm -f "$TMP_JSON"
  exit $JSON_EXIT
fi

python3 - <<'PY' "$TMP_JSON" "$OUT_JSON" "$BASE_NAME"
import json, sys
src, dst, base_name = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(src, "r", encoding="utf-8").read().strip()
if not raw:
  raise SystemExit("Error: empty output from Cursor CLI for prd.json")

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

