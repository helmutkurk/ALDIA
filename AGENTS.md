# AGENTS.md - rules for coding agents

Claude Code imports this file through `CLAUDE.md`; Codex reads it natively.

## Project
Aldia: citizens send verified photo reports of street problems; a portal shows them on a map for governments.
Folders: `app/` (Flutter), `portal/` (JavaScript), `backend/api/`, `backend/verifier/`, `documentation/`.
Team: Isa (portal), Fernando and Helmut (app), Lorenz (backend, verifier). Decisions: `documentation/decisions/`.

## Rules
- Branches: `main` and `develop` only; work on a feature branch from `develop`, merge by pull request. Never push to
  `main`, never force-push, never rewrite shared history.
- Work only in the folder of your role; ask before changing another one.
- Never read, print or commit environment files (only the example file), keys, tokens or personal photos.
- The repo is public: no strategy, budget, customer notes or private data of real people. Test photos are synthetic
  or taken by team members with consent.
- Ask before adding a dependency. Never edit lockfiles by hand.
- Conventional commits, authored by the human you work for; no agent attribution lines.
- UI text in Spanish; code, docs and commits in English.
- Never disable or route around a blocking hook; report a legitimate block.
