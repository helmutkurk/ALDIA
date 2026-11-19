@AGENTS.md

# Claude Code specifics

- Hooks in `.claude/settings.json`: `guard-bash.sh` (blocks secrets access, push to main, force push, `curl | sh`),
  `protect-files.sh` (blocks key files and environment files), `prompt-guard.sh` (blocks pasted keys).
- Plan before multi-file changes; small commits; show the validation command and its result.
- Personal overrides go in `.claude/settings.local.json` (git-ignored).
