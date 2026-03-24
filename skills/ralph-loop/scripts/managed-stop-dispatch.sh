#!/usr/bin/env bash
set -euo pipefail

emit_allow() {
  jq -nc '{}'
}

trimmed_non_empty() {
  local value="$1"
  [[ -n "${value//[[:space:]]/}" ]]
}

codex_home_dir() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s/.codex\n' "$HOME"
  fi
}

resolve_workspace_root() {
  local candidate="$1"

  if ! trimmed_non_empty "$candidate" || [[ ! -d "$candidate" ]]; then
    candidate="$(pwd)"
  fi

  git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$candidate"
}

route_to_hook() {
  local hook_path="$1"

  if [[ ! -f "$hook_path" ]]; then
    return 1
  fi

  printf '%s' "$HOOK_INPUT" | bash "$hook_path"
}

HOOK_INPUT="$(cat)"
HOOK_CWD="$(jq -r '.cwd // empty' <<<"$HOOK_INPUT" 2>/dev/null || true)"
WORKSPACE_ROOT="$(resolve_workspace_root "$HOOK_CWD")"
WORKSPACE_STATE_FILE="${WORKSPACE_ROOT}/.codex/ralph-loop-state.json"
WORKSPACE_RALPH_HOOK="${WORKSPACE_ROOT}/.codex/hooks/ralph-loop-stop.sh"
WORKSPACE_CMUX_DISPATCH="${WORKSPACE_ROOT}/.codex/hooks/cmux-stop-dispatch.sh"
HOME_RALPH_HOOK="$(codex_home_dir)/hooks/ralph-loop-stop.sh"

if [[ -f "$WORKSPACE_STATE_FILE" ]]; then
  if route_to_hook "$WORKSPACE_RALPH_HOOK"; then
    exit 0
  fi

  if route_to_hook "$HOME_RALPH_HOOK"; then
    exit 0
  fi

  emit_allow
  exit 0
fi

if route_to_hook "$WORKSPACE_CMUX_DISPATCH"; then
  exit 0
fi

emit_allow
