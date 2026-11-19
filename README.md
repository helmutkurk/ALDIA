# Aldia

Citizens report street problems with a photo. A verifier checks each photo. A portal shows all reports on a map
so a government can act on them. Working name until the MVP.

Goal of the MVP: prove to a government that verified photo reports work. Rewards for citizens (taxes, discounts on
public bills) and other open topics are decided together with the first government that accepts the MVP.

| Folder | Content | Owner |
|---|---|---|
| `app/` | Citizen app (Flutter / Dart) | Fernando, Helmut |
| `portal/` | Government portal with a map of all reports (JavaScript) | Isa |
| `backend/api/` | Reports API | Lorenz |
| `backend/verifier/` | Photo verifier: training, models, costs | Lorenz |
| `documentation/` | Decisions, research, meetings | Helmut |

Branches: `main` (stable) and `develop` (work). Open feature branches from `develop` and merge back by pull request.
Never commit secrets, environment files or personal photos. Install the git hooks once per clone:
`bash scripts/install-githooks.sh`.

No license has been chosen yet. All rights stay with the authors until the team decides.
