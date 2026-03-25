#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-user-scope.sh [--codex-home DIR] [--mode copy|symlink]

Notes:
  - Installs the skill bundle into CODEX_HOME/skills/ralph-loop.
  - Installs shared home Stop-hook helpers into CODEX_HOME/hooks/.
  - Preserves an existing cmux-managed Stop hook when hooks.json already points
    at cmux-stop-dispatch.sh.
EOF
}

codex_home_default() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s/.codex\n' "$HOME"
  fi
}

remove_path() {
  local path="$1"
  if [[ -L "$path" || -e "$path" ]]; then
    rm -rf "$path"
  fi
}

ensure_codex_hooks_enabled() {
  local config_file="$1"
  local tmp_config

  tmp_config="$(mktemp)"
  if [[ -f "$config_file" ]]; then
    cp "$config_file" "$tmp_config"
  else
    : >"$tmp_config"
  fi

  awk '
    BEGIN {
      in_features = 0
      saw_features = 0
      wrote_codex_hooks = 0
      total_lines = 0
    }
    {
      total_lines += 1
    }
    /^\[features\][[:space:]]*$/ {
      if (in_features && !wrote_codex_hooks) {
        print "codex_hooks = true"
        wrote_codex_hooks = 1
      }
      saw_features = 1
      in_features = 1
      print
      next
    }
    in_features && /^\[/ {
      if (!wrote_codex_hooks) {
        print "codex_hooks = true"
        wrote_codex_hooks = 1
      }
      in_features = 0
    }
    in_features && /^[[:space:]]*codex_hooks[[:space:]]*=/ {
      if (!wrote_codex_hooks) {
        print "codex_hooks = true"
        wrote_codex_hooks = 1
      }
      next
    }
    {
      print
    }
    END {
      if (in_features && !wrote_codex_hooks) {
        print "codex_hooks = true"
        wrote_codex_hooks = 1
      }
      if (!saw_features) {
        if (total_lines > 0) {
          print ""
        }
        print "[features]"
        print "codex_hooks = true"
      }
    }
  ' "$tmp_config" >"$config_file"
  rm -f "$tmp_config"
}

MODE="copy"
CODEX_HOME_DIR="$(codex_home_default)"

while (($# > 0)); do
  case "$1" in
    --codex-home)
      CODEX_HOME_DIR="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  copy|symlink) ;;
  *)
    echo "Unsupported install mode: $MODE" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="${CODEX_HOME_DIR}/hooks"
SKILLS_DIR="${CODEX_HOME_DIR}/skills"
TARGET_SKILL_DIR="${SKILLS_DIR}/ralph-loop"
HOOKS_FILE="${CODEX_HOME_DIR}/hooks.json"
CONFIG_FILE="${CODEX_HOME_DIR}/config.toml"
RALPH_HOOK_TARGET="${HOOKS_DIR}/ralph-loop-stop.sh"
DISPATCH_TARGET="${HOOKS_DIR}/managed-stop-dispatch.sh"
MANAGED_COMMAND="sh -c 'exec \"\$HOME/.codex/hooks/managed-stop-dispatch.sh\"'"

mkdir -p "$HOOKS_DIR" "$SKILLS_DIR"

if [[ -f "$HOOKS_FILE" ]]; then
  if ! jq -e '.' "$HOOKS_FILE" >/dev/null 2>&1; then
    echo "Existing hooks.json is not valid JSON: $HOOKS_FILE" >&2
    exit 1
  fi
fi

EXISTING_STOP_COMMANDS="$(
  if [[ -f "$HOOKS_FILE" ]]; then
    jq -r '.hooks.Stop[]?.hooks[]? | select(.type == "command") | .command' "$HOOKS_FILE"
  fi
)"

HOOKS_MODE="managed"
if [[ -n "$EXISTING_STOP_COMMANDS" ]]; then
  if grep -Fq 'cmux-stop-dispatch.sh' <<<"$EXISTING_STOP_COMMANDS"; then
    if printf '%s\n' "$EXISTING_STOP_COMMANDS" | grep -Fv 'cmux-stop-dispatch.sh' | grep -q .; then
      echo "Existing hooks.json mixes cmux and unknown Stop hooks. Refusing to replace it." >&2
      printf '%s\n' "$EXISTING_STOP_COMMANDS" >&2
      exit 1
    fi
    HOOKS_MODE="cmux"
  elif printf '%s\n' "$EXISTING_STOP_COMMANDS" | grep -Fv 'managed-stop-dispatch.sh' | grep -q .; then
    echo "Existing hooks.json already has an unknown Stop hook chain. Refusing to replace it." >&2
    echo "Current Stop commands:" >&2
    printf '%s\n' "$EXISTING_STOP_COMMANDS" >&2
    exit 1
  fi
fi

if [[ "$HOOKS_MODE" != "cmux" ]] && [[ -n "$EXISTING_STOP_COMMANDS" ]] && ! grep -Fq 'managed-stop-dispatch.sh' <<<"$EXISTING_STOP_COMMANDS"; then
  echo "Existing hooks.json already has an unknown Stop hook chain. Refusing to replace it." >&2
  echo "Current Stop commands:" >&2
  printf '%s\n' "$EXISTING_STOP_COMMANDS" >&2
  exit 1
fi

remove_path "$TARGET_SKILL_DIR"
if [[ "$MODE" == "copy" ]]; then
  cp -R "$SKILL_ROOT" "$TARGET_SKILL_DIR"
else
  ln -s "$SKILL_ROOT" "$TARGET_SKILL_DIR"
fi

cp "$SCRIPT_DIR/stop-hook.sh" "$RALPH_HOOK_TARGET"
cp "$SCRIPT_DIR/managed-stop-dispatch.sh" "$DISPATCH_TARGET"
chmod 755 "$RALPH_HOOK_TARGET" "$DISPATCH_TARGET"

ensure_codex_hooks_enabled "$CONFIG_FILE"

if [[ "$HOOKS_MODE" == "managed" ]]; then
  tmp_hooks="$(mktemp)"
  if [[ -f "$HOOKS_FILE" ]]; then
    jq \
      --arg command "$MANAGED_COMMAND" \
      '
        .hooks = (.hooks // {}) |
        .hooks.Stop = [
          {
            hooks: [
              {
                type: "command",
                command: $command,
                timeout: 75
              }
            ]
          }
        ]
      ' \
      "$HOOKS_FILE" >"$tmp_hooks"
  else
    jq -n \
      --arg command "$MANAGED_COMMAND" \
      '{
        hooks: {
          Stop: [
            {
              hooks: [
                {
                  type: "command",
                  command: $command,
                  timeout: 75
                }
              ]
            }
          ]
        }
      }' >"$tmp_hooks"
  fi
  mv "$tmp_hooks" "$HOOKS_FILE"
fi

echo "Installed Ralph Loop into $TARGET_SKILL_DIR"
echo "Home stop hook: $RALPH_HOOK_TARGET"
echo "Home dispatcher: $DISPATCH_TARGET"
if [[ "$HOOKS_MODE" == "cmux" ]]; then
  echo "hooks.json: preserved existing cmux dispatcher ownership"
else
  echo "hooks.json: managed-stop-dispatch.sh"
fi
