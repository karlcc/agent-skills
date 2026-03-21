---
name: ralph-loop
description: Keep Codex iterating on a task until a completion promise is detected or max iterations reached. Use when told to "ralph loop", "keep working", or "iterate until done".
argument-hint: "<prompt> [--max-iterations N] [--completion-promise TEXT]"
user-invocable: true
---

## When to use

Use this skill when the user wants Codex to keep working on a task iteratively
until a specific completion condition is met. This is useful for:
- Deep iterative development (build, test, fix cycles)
- Complex refactoring that requires multiple passes
- Tasks where the agent tends to stop prematurely

## Inputs / context to gather

1. **PROMPT**: The task description (required, via `$ARGUMENTS`)
2. **--max-iterations**: Maximum number of iterations before stopping (default: 50)
3. **--completion-promise**: Text that signals task completion (default: "DONE")

## Procedure

1. Parse arguments from `$ARGUMENTS`
2. Create `.codex/ralph-loop-state.json` with:
   - `active: true`
   - `prompt`: the original user prompt
   - `iteration: 0`
   - `max_iterations`: from arg or default 50
   - `completion_promise`: from arg or default "DONE"
   - `started_at`: current ISO timestamp
3. The Stop hook (`scripts/stop-hook.sh`) is registered in your config.toml
4. Work on the task normally
5. When your turn would end, the Stop hook intercepts:
   - If completion promise found in your output → stop allowed
   - If max iterations reached → stop allowed
   - Otherwise → stop blocked, you receive the original prompt again

## Completion Signal

When you have finished the task, output:

<promise>DONE</promise>

## Efficiency plan

- Work methodically: plan → implement → test → fix in each iteration
- Don't repeat the same approach if it failed
- Use the iteration count in the block message to track progress
- Signal completion as soon as the core task is verifiably done

## Verification checklist

- [ ] `.codex/ralph-loop-state.json` exists and is valid JSON
- [ ] Stop hook returns valid `StopOutcome` JSON
- [ ] Completion promise detection works
