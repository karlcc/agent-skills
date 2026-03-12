---
name: autopilot
description: Install or refresh a repo-local Claude autopilot bundle into the current repository or an explicitly provided target repository. Use when asked to set up repo-local autopilot hooks, install autopilot into `.claude/`, refresh a repo-local autopilot bundle to the latest design, or reset a repo's local autopilot workflow.
---

# Repo-local Autopilot

Install the bundled Claude autopilot files into a target repository's local `.claude/` directory.

## Bundle rules

- Keep the skill self-contained so it can install and initialize from a fresh workspace clone of this repo.
- Do not depend on `~/.claude/`, a sibling `cmux` checkout, or any external template path at install time.
- When syncing from another repository, copy the behavior into this skill's bundled `templates/` and `scripts/` files before shipping.

## What this installs

Running the installer writes these repo-local files into the target repository:

- `.claude/hooks/autopilot-keep-running.sh`
- `.claude/hooks/session-start.sh`
- `.claude/commands/autopilot_reset.md`
- `.claude/settings.json` patched to wire the repo-local hooks

The install is repo-local by design. It does not depend on `~/.claude/` and should not install or update global Claude settings.

## Default target

If you do not pass a target path, the installer uses the current working directory.

## Explicit target repo

Use `--target-repo /absolute/or/relative/path` to install into another repository.

## Installer entrypoint

Run the installer from the copy of this skill bundle you actually have available.

Examples:

```bash
python3 skills/autopilot/scripts/install_repo_local_autopilot.py
```

If you copied the skill bundle somewhere else first, run that copied installer path instead:

```bash
python3 /path/to/autopilot/scripts/install_repo_local_autopilot.py --target-repo /path/to/repo
```

## Runtime dependencies

The installed hooks require:

- `jq`
- `shasum` or `sha256sum` for idle-state hashing

The installer performs this preflight and should fail clearly when a required command is missing.

## Installed runtime behavior

After install, the bundle behaves like this:

- `session-start.sh` persists Claude's `session_id` to `/tmp/claude-current-session-id` and exposes `CLAUDE_SESSION_ID`.
- `autopilot-keep-running.sh` must run first in the `Stop` hook chain and manages session-scoped files under `/tmp/claude-autopilot-*`.
- Idle detection fingerprints git state and releases autopilot after `CLAUDE_AUTOPILOT_IDLE_THRESHOLD` unchanged turns. The default is `3`.
- Late-session monitoring uses `CLAUDE_AUTOPILOT_MONITORING_THRESHOLD` and `CLAUDE_AUTOPILOT_DELAY` to shift from active work into slower polling guidance.
- At `max turns - 2`, the hook temporarily yields so downstream review hooks can run before the last two turns.
- If `CLAUDE_AUTOPILOT_STOP_FILE` exists, the hook releases immediately so external wrappers can stop the loop cleanly.

## Installed settings behavior

The installer safely updates `.claude/settings.json` to:

- append a repo-local `SessionStart` hook pointing to `"$CLAUDE_PROJECT_DIR"/.claude/hooks/session-start.sh`
- prepend a repo-local `Stop` hook pointing to `"$CLAUDE_PROJECT_DIR"/.claude/hooks/autopilot-keep-running.sh`
- preserve unrelated hooks such as `bun-check.sh` and `codex-review.sh`
- avoid duplicate autopilot entries on re-run
- set default env values only when missing:
  - `AUTOPILOT_KEEP_RUNNING_DISABLED=0`
  - `CLAUDE_AUTOPILOT_MAX_TURNS=20`

## Reset and stop controls

After installation, use the repo-local command:

- `/autopilot_reset` to reset the current session turn counter
- `/autopilot_reset stop` to stop autopilot on the next turn
- `/autopilot_reset status` to inspect the current session
- `/autopilot_reset status-all` to inspect all tracked sessions

That reset control is installed into the target repo as `.claude/commands/autopilot_reset.md` and should clear turn, stop, blocked, completed, idle, and state files when resetting a session.

## Validation checklist

After install, verify:

1. The repo contains the installed `.claude/hooks/` and `.claude/commands/` files.
2. `.claude/settings.json` points to repo-local hook paths.
3. Re-running the installer does not duplicate hook entries.
4. The hook scripts are executable.
5. Unrelated existing hooks remain intact.
6. Autopilot runtime files appear under `/tmp/claude-autopilot-*` when the hooks run, including turn and idle/state tracking files during active sessions.
7. Invalid target `.claude/settings.json` files fail with a clear error instead of being overwritten.
8. The bundle still installs correctly when this repo is copied into a fresh workspace with no external skill checkout present.

See `references/devsh-testing.md` for a remote sandbox validation workflow.
