#!/bin/bash
# Ralph Loop Stop Hook for Codex CLI
# Returns StopOutcome JSON to control agent looping behavior.

set -euo pipefail

STATE_FILE=".codex/ralph-loop-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"should_block": false, "should_stop": false}'
  exit 0
fi

ITERATION=$(jq -r '.iteration' "$STATE_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations' "$STATE_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise' "$STATE_FILE")
ORIGINAL_PROMPT=$(jq -r '.prompt' "$STATE_FILE")

if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "🛑 Ralph loop: max iterations ($MAX_ITERATIONS) reached." >&2
  rm -f "$STATE_FILE"
  echo '{"should_block": false, "should_stop": false}'
  exit 0
fi

HOOK_INPUT=$(cat -)
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)

if [[ -n "$COMPLETION_PROMISE" ]] && echo "$LAST_OUTPUT" | grep -qF "$COMPLETION_PROMISE"; then
  echo "✅ Ralph loop: completion promise detected." >&2
  rm -f "$STATE_FILE"
  echo '{"should_block": false, "should_stop": false}'
  exit 0
fi

NEW_ITERATION=$((ITERATION + 1))
jq --arg iter "$NEW_ITERATION" '.iteration = ($iter | tonumber)' "$STATE_FILE" > "${STATE_FILE}.tmp"
mv "${STATE_FILE}.tmp" "$STATE_FILE"

cat <<EOF
{
  "should_block": true,
  "block_message_for_model": "Continue working on the task. Iteration ${NEW_ITERATION}/${MAX_ITERATIONS}. Original task: ${ORIGINAL_PROMPT}\n\nWhen complete, output <promise>${COMPLETION_PROMISE}</promise>",
  "should_stop": false
}
EOF
