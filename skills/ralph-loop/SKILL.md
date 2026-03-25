---
name: ralph-loop
description: Keep Codex auto-continuing on the same bounded task until a completion signal appears in the assistant output or a maximum iteration count is reached. Use when the user asks for a Ralph Loop, asks Codex to keep going until done, or wants to prevent premature stopping on a task that should stay in the current workspace.
allowed-tools:
  - Bash
---

# Ralph Loop

Use this skill with an explicit mention such as:

`$ralph-loop Fix the failing tests and stop only when they pass`

Optional conventions in the user message:

- `--max-iterations N`
- `--completion-promise TEXT`
- `--magic-word TEXT`

Defaults:

- max iterations: `50`
- completion promise: `DONE`
- continuation magic word: `RALPH_AUTO_CONTINUE`
- completion signal written in the assistant message: `<promise>DONE</promise>`
- continuation signal for non-final turns: `<ralph-continue>RALPH_AUTO_CONTINUE</ralph-continue>`

## What this skill does

This skill writes a workspace-local state file at `.codex/ralph-loop-state.json`.
A user-scope Stop-hook dispatcher in `~/.codex/hooks.json` reads that state file
after each assistant response. If the completion signal is missing and the max
iteration limit has not been reached, the Stop hook blocks the turn and feeds a
continuation prompt back to Codex. The continuation prompt keeps the loop in
automatic mode, tells Codex not to ask whether it should continue, and carries
an explicit continuation signal keyed off the configured magic word.

This is a simple utility loop. It is not a replacement for higher-level
orchestration systems such as cmux Autopilot.

## User-scope install

Install the skill bundle and home Stop-hook helpers into `~/.codex/` with:

```bash
bash scripts/install-user-scope.sh
```

Optional flags:

- `--codex-home /absolute/path/to/.codex`
- `--mode copy|symlink`

Install behavior:

- installs the skill bundle into `~/.codex/skills/ralph-loop`
- installs `~/.codex/hooks/ralph-loop-stop.sh`
- installs `~/.codex/hooks/managed-stop-dispatch.sh`
- enables `codex_hooks = true` in `~/.codex/config.toml`
- preserves an existing cmux-managed `~/.codex/hooks.json` if it already points
  to `cmux-stop-dispatch.sh`

If cmux already owns the home Stop hook, Ralph Loop still works after install by
letting the cmux dispatcher fall back to the home Ralph hook.

## Procedure

1. Parse the user request after `$ralph-loop`.
2. Resolve:
   - the task prompt
   - `max_iterations`
   - `completion_promise`
   - `magic_word`
3. Resolve the active task workspace path first.
4. Run `scripts/start-loop.sh` from this skill directory and pass the workspace
   explicitly with `--workspace`.
4. Confirm the state file exists at `.codex/ralph-loop-state.json`.
5. Work the task normally in the current workspace.
6. While another turn is still required, keep auto-continuing and include the
   continuation signal in non-final assistant messages.
7. When the task is actually complete, include the exact completion signal in
   the final assistant message.

## Required command

Run this helper from the skill root:

```bash
bash scripts/start-loop.sh \
  --workspace "/absolute/path/to/current/workspace" \
  --max-iterations 50 \
  --completion-promise DONE \
  --magic-word RALPH_AUTO_CONTINUE \
  --prompt "TASK GOES HERE"
```

If the user supplied explicit values, pass those instead of the defaults. Do not
rely on the helper's current working directory; always pass the workspace path
explicitly.

## Continuation rules

- Stay on the same task across continuation prompts.
- Continue from the current workspace state; do not restart from scratch.
- Prefer concrete progress each iteration: inspect, edit, verify, repeat.
- Do not ask the user whether to keep going while the loop is active.
- If another turn is still required, include the exact continuation signal:

```text
<ralph-continue>RALPH_AUTO_CONTINUE</ralph-continue>
```

- If the user chose a different magic word, substitute it into the tag.
- Use the loop for bounded tasks. If the user is really asking for broad
  orchestration, background supervision, or multi-agent management, stop and use
  a different workflow instead.

## Conflict boundaries

- `$ralph-loop` and `$loop` are not substitutes.
- `ralph-loop` owns same-session continuation through the Stop hook.
- `loop` owns recurring fresh-session scheduling and should not install or edit
  Stop hooks.
- cmux autopilot uses the same Stop-hook channel as Ralph Loop, so only one
  home dispatcher should own `~/.codex/hooks.json` at a time.
- When cmux owns the home dispatcher, Ralph Loop should install only its home
  stop hook and let the cmux dispatcher delegate to it.

## Completion

When you are done, emit the exact completion signal:

```text
<promise>DONE</promise>
```

If the user chose a different completion promise, emit that exact tag instead.

## Cancel or inspect

- Cancel the loop:

```bash
bash scripts/start-loop.sh --workspace "/absolute/path/to/current/workspace" --cancel
```

- Show the current state:

```bash
bash scripts/start-loop.sh --workspace "/absolute/path/to/current/workspace" --show
```

## Verification

To verify the hook logic without launching a nested Codex session:

```bash
bash scripts/test-stop-hook.sh
bash scripts/test-managed-stop-dispatch.sh
bash scripts/test-install-user-scope.sh
```
