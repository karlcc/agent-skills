#!/usr/bin/env bash
set -euo pipefail

emit_json() {
  local json="$1"
  printf '%s\n' "$json"
}

emit_system_message() {
  local message="$1"
  jq -nc --arg message "$message" '{systemMessage: $message}'
}

trimmed_non_empty() {
  local value="$1"
  [[ -n "${value//[[:space:]]/}" ]]
}

HOOK_INPUT="$(cat)"

STATE_ROOT="$PWD"
HOOK_CWD="$(jq -r '.cwd // empty' <<<"$HOOK_INPUT" 2>/dev/null || true)"
if trimmed_non_empty "$HOOK_CWD" && [[ -d "$HOOK_CWD" ]]; then
  STATE_ROOT="$HOOK_CWD"
fi
STATE_FILE="$STATE_ROOT/.codex/ralph-loop-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

if ! STATE_JSON="$(jq -e '.' "$STATE_FILE" 2>/dev/null)"; then
  rm -f "$STATE_FILE"
  emit_json "$(emit_system_message "Ralph Loop state was invalid JSON. Cancelling the loop.")"
  exit 0
fi

ACTIVE="$(jq -r '.active // false' <<<"$STATE_JSON")"
AUTO_CONTINUE="$(jq -r '.auto_continue // true' <<<"$STATE_JSON")"
PROMPT="$(jq -r '.prompt // empty' <<<"$STATE_JSON")"
ITERATION="$(jq -r '.iteration // 0' <<<"$STATE_JSON")"
MAX_ITERATIONS="$(jq -r '.max_iterations // 0' <<<"$STATE_JSON")"
COMPLETION_PROMISE="$(jq -r '.completion_promise // "DONE"' <<<"$STATE_JSON")"
COMPLETION_SIGNAL="$(jq -r '.completion_signal // empty' <<<"$STATE_JSON")"
CONTINUE_MAGIC_WORD="$(jq -r '.continue_magic_word // "RALPH_AUTO_CONTINUE"' <<<"$STATE_JSON")"
CONTINUE_SIGNAL="$(jq -r '.continue_signal // empty' <<<"$STATE_JSON")"

if [[ "$ACTIVE" != "true" ]] || ! trimmed_non_empty "$PROMPT"; then
  rm -f "$STATE_FILE"
  emit_json "$(emit_system_message "Ralph Loop state was incomplete. Cancelling the loop.")"
  exit 0
fi

if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  rm -f "$STATE_FILE"
  emit_json "$(emit_system_message "Ralph Loop state had invalid counters. Cancelling the loop.")"
  exit 0
fi

if [[ -z "$COMPLETION_SIGNAL" ]]; then
  COMPLETION_SIGNAL="$COMPLETION_PROMISE"
  if [[ "$COMPLETION_SIGNAL" != *"<"* ]]; then
    COMPLETION_SIGNAL="<promise>${COMPLETION_PROMISE}</promise>"
  fi
fi

if [[ "$AUTO_CONTINUE" != "true" && "$AUTO_CONTINUE" != "false" ]]; then
  rm -f "$STATE_FILE"
  emit_json "$(emit_system_message "Ralph Loop state had an invalid auto_continue flag. Cancelling the loop.")"
  exit 0
fi

if ! trimmed_non_empty "$CONTINUE_MAGIC_WORD"; then
  CONTINUE_MAGIC_WORD="RALPH_AUTO_CONTINUE"
fi

if [[ -z "$CONTINUE_SIGNAL" ]]; then
  CONTINUE_SIGNAL="<ralph-continue>${CONTINUE_MAGIC_WORD}</ralph-continue>"
fi

LAST_OUTPUT="$(jq -r '.last_assistant_message // ""' <<<"$HOOK_INPUT" 2>/dev/null || true)"

if trimmed_non_empty "$LAST_OUTPUT" && grep -Fq -- "$COMPLETION_SIGNAL" <<<"$LAST_OUTPUT"; then
  rm -f "$STATE_FILE"
  emit_json "$(emit_system_message "Ralph Loop completion signal detected. Allowing the turn to finish.")"
  exit 0
fi

if (( MAX_ITERATIONS > 0 && ITERATION >= MAX_ITERATIONS )); then
  rm -f "$STATE_FILE"
  emit_json "$(emit_system_message "Ralph Loop reached the max iteration limit (${MAX_ITERATIONS}). Allowing the turn to finish.")"
  exit 0
fi

NEW_ITERATION=$((ITERATION + 1))
UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMP_FILE="${STATE_FILE}.tmp"

jq \
  --argjson iteration "$NEW_ITERATION" \
  --arg updated_at "$UPDATED_AT" \
  '.iteration = $iteration | .updated_at = $updated_at' \
  "$STATE_FILE" >"$TMP_FILE"
mv "$TMP_FILE" "$STATE_FILE"

MAX_DISPLAY="$MAX_ITERATIONS"
if (( MAX_ITERATIONS == 0 )); then
  MAX_DISPLAY="inf"
fi

CONTINUE_SIGNAL_HINT=""
if trimmed_non_empty "$LAST_OUTPUT" && ! grep -Fq -- "$CONTINUE_SIGNAL" <<<"$LAST_OUTPUT"; then
  CONTINUE_SIGNAL_HINT="$(cat <<EOF

Continuation contract:
- Ralph Loop is in automatic continuation mode.
- Do not ask the user whether to continue.
- If you still need another turn after this one, include this exact continuation signal in your assistant message:
  $CONTINUE_SIGNAL
- Only omit the continuation signal when your final assistant message includes the completion signal:
  $COMPLETION_SIGNAL
EOF
)"
fi

CONTINUATION_PROMPT="$(cat <<EOF
Ralph Loop is still active for the current task.

Original task:
$PROMPT

Current loop state:
- Iteration: $NEW_ITERATION/$MAX_DISPLAY
- Auto continue: $AUTO_CONTINUE
- Completion promise: $COMPLETION_PROMISE
- Required completion signal: $COMPLETION_SIGNAL
- Continuation magic word: $CONTINUE_MAGIC_WORD
- Continuation signal for non-final turns: $CONTINUE_SIGNAL

Continue from the current workspace state. Do not restart the task from scratch.
Make concrete progress and verify the result where possible.
Do not ask whether you should keep going.$CONTINUE_SIGNAL_HINT

Only finish when your final assistant message contains the exact completion signal:
$COMPLETION_SIGNAL
EOF
)"

jq -nc \
  --arg reason "$CONTINUATION_PROMPT" \
  '{decision: "block", reason: $reason}'
