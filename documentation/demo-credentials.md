# Development demo accounts

There are no published or fixed demo passwords. Staff accounts replace the old shared token.

From `backend/api/`, use the same database/photo configuration as the API, set `ENV=dev`,
then run `uv run alembic upgrade head` and `uv run python scripts/seed_demo.py` directly
in a private terminal. Only exact `ENV=dev` creates these accounts:

| Username | Role |
|---|---|
| `operador` | `operator` |
| `supervisor` | `supervisor` |

The seed prints a different cryptographically random password once for each new account.
Do not save this output in repository logs, chat, screenshots or shared CI output. Rerunning
the seed preserves existing passwords; purging/resetting demo reports does not reset users.
If the initial password was lost, create an admin using the CLI and reset it through the
admin API. Do not delete real accounts to recover a demo password.

Bootstrap an administrator with `uv run python -m app.cli create-admin --username admin`.
It prompts twice without echo; non-interactive usage reads one password line from stdin
(pipe from a secret manager). Passwords must contain 12–1024 characters and never go in argv.

Open the portal, expand **Modo personal**, enter username/password and use **Iniciar sesión**.
The server supplies the role. Use **Cerrar sesión** when finished. Accounts expire after
12 hours per session; five failed logins lock an account for 15 minutes.

Production defaults to Secure cookies and disables both demo accounts and token fallback.
The legacy panel is visible only when `/api/auth/config` reports `dev_tokens: true`, requiring
`ENV=dev` plus `AUTH_DEV_TOKENS=true` on the API. It remains a development compatibility path.
