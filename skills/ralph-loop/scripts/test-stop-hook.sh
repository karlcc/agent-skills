#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start-loop.sh"
HOOK_SCRIPT="$SCRIPT_DIR/stop-hook.sh"

TESTS_PASSED=0
TESTS_TOTAL=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

make_stop_payload() {
  jq -nc \
    --arg cwd "$1" \
    --arg last_assistant_message "$2" \
    '{
      session_id: "session-test",
      turn_id: "turn-test",
      transcript_path: null,
      cwd: $cwd,
      hook_event_name: "Stop",
      model: "gpt-5.4",
      permission_mode: "default",
      stop_hook_active: false,
      last_assistant_message: $last_assistant_message
    }'
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WORKSPACE="$TMP_DIR/workspace"
mkdir -p "$WORKSPACE"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
NO_STATE_OUTPUT="$(cd "$WORKSPACE" && printf '%s' "$(make_stop_payload "$WORKSPACE" "")" | bash "$HOOK_SCRIPT")"
if [[ -n "$NO_STATE_OUTPUT" ]]; then
  echo "FAIL: hook should emit nothing when no state exists" >&2
  echo "$NO_STATE_OUTPUT" >&2
  exit 1
fi
TESTS_PASSED=$((TESTS_PASSED + 1))

cd "$WORKSPACE"
bash "$START_SCRIPT" --workspace "$WORKSPACE" --max-iterations 2 --completion-promise DONE --prompt "Create smoke.txt with smoke"
assert_eq "$(jq -r '.auto_continue' .codex/ralph-loop-state.json)" "true" "state should enable auto continue"
assert_eq "$(jq -r '.continue_magic_word' .codex/ralph-loop-state.json)" "RALPH_AUTO_CONTINUE" "state should store the default continuation magic word"
assert_eq "$(jq -r '.continue_signal' .codex/ralph-loop-state.json)" "<ralph-continue>RALPH_AUTO_CONTINUE</ralph-continue>" "state should store the default continuation signal"

FIRST_OUTPUT="$(cd "$TMP_DIR" && printf '%s' "$(make_stop_payload "$WORKSPACE" "draft one")" | bash "$HOOK_SCRIPT")"
assert_eq "$(jq -r '.decision' <<<"$FIRST_OUTPUT")" "block" "first stop should block even outside the workspace cwd"
assert_eq "$(jq -r '.reason | contains("Do not ask whether")' <<<"$FIRST_OUTPUT")" "true" "block reason should force automatic continuation"
assert_eq "$(jq -r '.reason | contains("<ralph-continue>RALPH_AUTO_CONTINUE</ralph-continue>")' <<<"$FIRST_OUTPUT")" "true" "block reason should include the default continuation signal"
assert_eq "$(jq -r '.iteration' .codex/ralph-loop-state.json)" "1" "iteration should increment after first block"

SECOND_OUTPUT="$(printf '%s' "$(make_stop_payload "$WORKSPACE" "<promise>DONE</promise>")" | bash "$HOOK_SCRIPT")"
assert_eq "$(jq -r '.systemMessage | contains("completion signal detected")' <<<"$SECOND_OUTPUT")" "true" "completion should allow the turn to finish"
assert_eq "$([[ -f .codex/ralph-loop-state.json ]] && echo yes || echo no)" "no" "state file should be removed after completion"

bash "$START_SCRIPT" --workspace "$WORKSPACE" --max-iterations 1 --completion-promise DONE --magic-word TURBO_KEEP_GOING --prompt "Reach max iterations"
assert_eq "$(jq -r '.continue_magic_word' .codex/ralph-loop-state.json)" "TURBO_KEEP_GOING" "state should store the custom continuation magic word"
assert_eq "$(jq -r '.continue_signal' .codex/ralph-loop-state.json)" "<ralph-continue>TURBO_KEEP_GOING</ralph-continue>" "state should store the custom continuation signal"

MAX_FIRST_OUTPUT="$(printf '%s' "$(make_stop_payload "$WORKSPACE" "draft")" | bash "$HOOK_SCRIPT")"
assert_eq "$(jq -r '.decision' <<<"$MAX_FIRST_OUTPUT")" "block" "first pass of max-iteration test should block"
assert_eq "$(jq -r '.reason | contains("<ralph-continue>TURBO_KEEP_GOING</ralph-continue>")' <<<"$MAX_FIRST_OUTPUT")" "true" "custom continuation signal should appear in the block reason"
MAX_SECOND_OUTPUT="$(printf '%s' "$(make_stop_payload "$WORKSPACE" "still working")" | bash "$HOOK_SCRIPT")"
assert_eq "$(jq -r '.systemMessage | contains("max iteration limit")' <<<"$MAX_SECOND_OUTPUT")" "true" "max iterations should allow the turn to finish"
assert_eq "$([[ -f .codex/ralph-loop-state.json ]] && echo yes || echo no)" "no" "state file should be removed after max iteration exit"

echo "All assertions passed ($TESTS_PASSED/$TESTS_TOTAL)."
