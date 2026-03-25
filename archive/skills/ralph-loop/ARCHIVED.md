# Ralph Loop Archive

Archived on `2026-03-26`.

This bundle has been removed from the published `skills/` tree and should not be
installed, recommended, or referenced as an active Codex skill.

## Reason

- The shared same-session Stop-hook loop proved unreliable and unusable in the
  current Codex/macOS setup.
- Keeping it published caused other skills to route users toward a broken path.

## Previous live path

- `skills/ralph-loop`

## Current archive path

- `archive/skills/ralph-loop`

## Local uninstall surface

If an older user-scope install exists, remove these paths:

- `~/.codex/skills/ralph-loop`
- `~/.codex/hooks/ralph-loop-stop.sh`

## Replacement guidance

- For recurring fresh-session scheduling, use `loop`.
- For repo-local Codex continuation hooks, use `autopilot`.
- Do not publish a shared same-session Stop-hook skill again without a new
  design and a clean re-validation pass.
