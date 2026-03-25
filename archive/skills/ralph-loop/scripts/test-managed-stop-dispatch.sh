#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_SCRIPT="$SCRIPT_DIR/managed-stop-dispatch.sh"

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

HOME_DIR="$TMP_DIR/home"
WORKSPACE="$TMP_DIR/workspace"
mkdir -p "$HOME_DIR/.codex/hooks" "$WORKSPACE/.codex/hooks"

cat >"$HOME_DIR/.codex/hooks/ralph-loop-stop.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -nc '{decision: "block", reason: "home ralph continuation"}'
EOF
chmod +x "$HOME_DIR/.codex/hooks/ralph-loop-stop.sh"

NO_STATE_OUTPUT="$(printf '%s' "$(make_stop_payload "$WORKSPACE" "")" | HOME="$HOME_DIR" bash "$DISPATCH_SCRIPT")"
assert_eq "$(jq -c . <<<"$NO_STATE_OUTPUT")" "{}" "dispatcher should allow when no Ralph state or repo dispatcher exists"

cat >"$WORKSPACE/.codex/ralph-loop-state.json" <<'EOF'
{
  "active": true,
  "prompt": "Keep working",
  "iteration": 0,
  "max_iterations": 2,
  "completion_promise": "DONE",
  "completion_signal": "<promise>DONE</promise>"
}
EOF

RALPH_OUTPUT="$(printf '%s' "$(make_stop_payload "$WORKSPACE" "")" | HOME="$HOME_DIR" bash "$DISPATCH_SCRIPT")"
assert_eq "$(jq -r '.decision' <<<"$RALPH_OUTPUT")" "block" "dispatcher should fall back to the home Ralph hook when repo-local Ralph hook is absent"
assert_eq "$(jq -r '.reason' <<<"$RALPH_OUTPUT")" "home ralph continuation" "dispatcher should preserve the home Ralph hook output"

rm -f "$WORKSPACE/.codex/ralph-loop-state.json"
cat >"$WORKSPACE/.codex/hooks/cmux-stop-dispatch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -nc '{decision: "block", reason: "cmux continuation"}'
EOF
chmod +x "$WORKSPACE/.codex/hooks/cmux-stop-dispatch.sh"

CMUX_OUTPUT="$(printf '%s' "$(make_stop_payload "$WORKSPACE" "")" | HOME="$HOME_DIR" CMUX_AUTOPILOT_ENABLED=1 bash "$DISPATCH_SCRIPT")"
assert_eq "$(jq -r '.decision' <<<"$CMUX_OUTPUT")" "block" "dispatcher should route repo-local cmux workspaces to their dispatcher"
assert_eq "$(jq -r '.reason' <<<"$CMUX_OUTPUT")" "cmux continuation" "dispatcher should preserve the repo-local cmux dispatcher output"

echo "All assertions passed ($TESTS_PASSED/$TESTS_TOTAL)."
