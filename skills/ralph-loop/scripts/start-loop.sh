#!/usr/bin/env bash
set -euo pipefail

DEFAULT_MAX_ITERATIONS=50
DEFAULT_COMPLETION_PROMISE="DONE"

usage() {
  cat <<'EOF'
Usage:
  start-loop.sh --workspace DIR --prompt "task" [--max-iterations N] [--completion-promise TEXT] [--force]
  start-loop.sh --workspace DIR [--max-iterations N] [--completion-promise TEXT] -- task words here
  start-loop.sh --workspace DIR --show
  start-loop.sh --workspace DIR --cancel

Notes:
  - The state file is written to WORKSPACE/.codex/ralph-loop-state.json.
  - --max-iterations 0 means no hard cap.
  - The completion signal defaults to <promise>DONE</promise>.
EOF
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Missing value for $flag" >&2
    exit 1
  fi
}

assert_integer() {
  local value="$1"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "Expected a non-negative integer, got: $value" >&2
    exit 1
  fi
}

MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"
COMPLETION_PROMISE="$DEFAULT_COMPLETION_PROMISE"
PROMPT=""
WORKSPACE=""
FORCE=false
SHOW=false
CANCEL=false

while (($# > 0)); do
  case "$1" in
    --workspace)
      shift
      require_value "--workspace" "${1:-}"
      WORKSPACE="$1"
      ;;
    --prompt)
      shift
      require_value "--prompt" "${1:-}"
      PROMPT="$1"
      ;;
    --max-iterations)
      shift
      require_value "--max-iterations" "${1:-}"
      MAX_ITERATIONS="$1"
      ;;
    --completion-promise)
      shift
      require_value "--completion-promise" "${1:-}"
      COMPLETION_PROMISE="$1"
      ;;
    --force)
      FORCE=true
      ;;
    --show)
      SHOW=true
      ;;
    --cancel)
      CANCEL=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      PROMPT="$*"
      break
      ;;
    *)
      if [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      else
        PROMPT="$PROMPT $1"
      fi
      ;;
  esac
  shift || true
done

if [[ -z "$WORKSPACE" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$WORKSPACE" ]]; then
  echo "Workspace directory does not exist: $WORKSPACE" >&2
  exit 1
fi

WORKSPACE="$(cd "$WORKSPACE" && pwd)"
STATE_FILE="$WORKSPACE/.codex/ralph-loop-state.json"
STATE_DIR="$(dirname "$STATE_FILE")"

if $SHOW; then
  if [[ -f "$STATE_FILE" ]]; then
    jq '.' "$STATE_FILE"
  else
    echo "No active Ralph Loop state at $STATE_FILE" >&2
    exit 1
  fi
  exit 0
fi

if $CANCEL; then
  rm -f "$STATE_FILE"
  echo "Removed $STATE_FILE"
  exit 0
fi

assert_integer "$MAX_ITERATIONS"

if [[ -z "$PROMPT" ]]; then
  usage >&2
  exit 1
fi

if [[ -f "$STATE_FILE" ]] && ! $FORCE; then
  echo "State file already exists at $STATE_FILE. Re-run with --force to replace it." >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

COMPLETION_SIGNAL="$COMPLETION_PROMISE"
if [[ "$COMPLETION_SIGNAL" != *"<"* ]]; then
  COMPLETION_SIGNAL="<promise>${COMPLETION_PROMISE}</promise>"
fi

TMP_FILE="${STATE_FILE}.tmp"
CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg prompt "$PROMPT" \
  --arg completion_promise "$COMPLETION_PROMISE" \
  --arg completion_signal "$COMPLETION_SIGNAL" \
  --arg created_at "$CREATED_AT" \
  --argjson max_iterations "$MAX_ITERATIONS" \
  '{
    active: true,
    prompt: $prompt,
    iteration: 0,
    max_iterations: $max_iterations,
    completion_promise: $completion_promise,
    completion_signal: $completion_signal,
    created_at: $created_at,
    updated_at: $created_at,
    state_version: 1
  }' >"$TMP_FILE"

mv "$TMP_FILE" "$STATE_FILE"

echo "Initialized Ralph Loop state at $STATE_FILE"
echo "Completion signal: $COMPLETION_SIGNAL"
if [[ "$MAX_ITERATIONS" == "0" ]]; then
  echo "Max iterations: unlimited"
else
  echo "Max iterations: $MAX_ITERATIONS"
fi
