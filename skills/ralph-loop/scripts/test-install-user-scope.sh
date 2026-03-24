#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-user-scope.sh"

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

assert_file_exists() {
  local path="$1"
  local message="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ ! -f "$path" ]]; then
    echo "FAIL: $message" >&2
    echo "  missing file: $path" >&2
    exit 1
  fi
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FRESH_HOME="$TMP_DIR/fresh-home"
mkdir -p "$FRESH_HOME"

bash "$INSTALL_SCRIPT" --codex-home "$FRESH_HOME/.codex" >/dev/null

assert_file_exists "$FRESH_HOME/.codex/hooks/ralph-loop-stop.sh" "fresh install should write the home Ralph hook"
assert_file_exists "$FRESH_HOME/.codex/hooks/managed-stop-dispatch.sh" "fresh install should write the managed dispatcher"
assert_file_exists "$FRESH_HOME/.codex/skills/ralph-loop/SKILL.md" "fresh install should copy the skill bundle"
assert_eq "$(jq -r '.hooks.Stop[0].hooks[0].command' "$FRESH_HOME/.codex/hooks.json")" "sh -c 'exec \"\$HOME/.codex/hooks/managed-stop-dispatch.sh\"'" "fresh install should own hooks.json with the managed dispatcher"
assert_eq "$(grep -c '^codex_hooks = true$' "$FRESH_HOME/.codex/config.toml" || true)" "1" "fresh install should enable codex_hooks exactly once"

CMUX_HOME="$TMP_DIR/cmux-home"
mkdir -p "$CMUX_HOME/.codex"
cat >"$CMUX_HOME/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh -c 'exec \"$HOME/.codex/hooks/cmux-stop-dispatch.sh\"'",
            "timeout": 75
          }
        ]
      }
    ]
  }
}
EOF

bash "$INSTALL_SCRIPT" --codex-home "$CMUX_HOME/.codex" >/dev/null

assert_eq "$(jq -r '.hooks.Stop[0].hooks[0].command' "$CMUX_HOME/.codex/hooks.json")" "sh -c 'exec \"\$HOME/.codex/hooks/cmux-stop-dispatch.sh\"'" "install should preserve existing cmux dispatcher ownership"
assert_file_exists "$CMUX_HOME/.codex/hooks/ralph-loop-stop.sh" "cmux-owned install should still write the home Ralph hook"

UNKNOWN_HOME="$TMP_DIR/unknown-home"
mkdir -p "$UNKNOWN_HOME/.codex"
cat >"$UNKNOWN_HOME/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh -c 'echo custom-stop-hook'",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
EOF

set +e
bash "$INSTALL_SCRIPT" --codex-home "$UNKNOWN_HOME/.codex" >/dev/null 2>&1
UNKNOWN_EXIT=$?
set -e
assert_eq "$UNKNOWN_EXIT" "1" "install should refuse to replace an unknown Stop hook chain"

echo "All assertions passed ($TESTS_PASSED/$TESTS_TOTAL)."
