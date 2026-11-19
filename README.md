# Aldia

Citizens report street problems with a photo. A verifier checks each photo. A portal shows all reports on a map
so a government can act on them. Working name until the MVP.

Goal of the MVP: prove to a government that verified photo reports work. Rewards for citizens (taxes, discounts on
public bills) and other open topics are decided together with the first government that accepts the MVP.

Product reference: the **portal** follows FixMyStreet, the **app** follows SeeClickFix; Aldia is both, in Spanish, for
Guatemala, plus photo verification. We take flows and ideas, not code (licenses):
[reference](documentation/research/reference-fixmystreet-seeclickfix.md).

| Folder | Content | Stack | Owner |
|---|---|---|---|
| `app/` | Citizen app | Flutter / Dart | Fernando, Helmut |
| `portal/` | Government portal, map of all reports | JavaScript, Vite, Leaflet | Isa |
| `backend/api/` | Reports API | Python 3.12, FastAPI, PostgreSQL | Lorenz |
| `backend/verifier/` | Photo verifier (stub until a model exists) | Python 3.12, FastAPI, Pillow | Lorenz |
| `documentation/` | API contract, decisions, research, setup | Markdown | Helmut |

## Quick start

```bash
mise install                     # pinned Node, Python, uv, Flutter (.mise.toml)
cp .env.example .env             # then set POSTGRES_PASSWORD (local only, never committed)
make up                          # db + verifier + api + portal in Docker
# portal http://localhost:8080 · API docs http://localhost:8000/docs
make check                       # lint and tests for all four areas
```

Testing guide (automated checks, manual QA, demo checklist): [documentation/testing.md](documentation/testing.md).
Android Studio, Xcode and running the app: [documentation/dev-setup.md](documentation/dev-setup.md).
API contract (the single source of truth for all three codebases): [documentation/api-contract.md](documentation/api-contract.md).

Branches: `main` (stable) and `develop` (work). Open feature branches from `develop` and merge back by pull request.
Never commit secrets, environment files or personal photos. Install the git hooks once per clone:
`bash scripts/install-githooks.sh`.

## License

Proprietary, all rights reserved ([LICENSE](LICENSE)). The code and documents are visible for collaboration only:
nobody may copy, run, modify, redistribute or use them, and especially not commercially, without the written permission
of all the authors.
