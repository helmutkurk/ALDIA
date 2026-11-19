# Contributing

## Branch model

```
feat/<area>-<topic>  ──PR (squash)──▶  develop  ──PR "release: sprint N" (merge commit)──▶  main
```

- `main`: stable, one release per sprint. Nobody pushes to it directly.
- `develop`: integration branch. Nobody pushes to it directly; everything arrives through a pull request.
- Work branches start from the latest `develop` and are deleted after the merge.

### Branch names

`<type>/<area>-<short-topic>`, lowercase, digits, `-`, `.`, `_`.

| Type | Use |
|---|---|
| `feat/` | new behavior |
| `fix/` | bug fix |
| `docs/` | documentation only |
| `chore/`, `refactor/`, `test/`, `ci/` | maintenance |
| `hotfix/` | urgent fix; PR into `main` and then back into `develop` |

Areas: `app`, `portal`, `api`, `verifier`, `docs`, `infra`. Examples: `feat/app-report-flow`,
`feat/portal-dashboard`, `fix/api-bbox-filter`, `docs/decision-payments`.

## Daily flow (feature branch into `develop`)

```bash
git switch develop && git pull
git switch -c feat/portal-report-page
# work, small commits
make check                              # lint and tests of every area you touched
git push -u origin feat/portal-report-page
gh pr create --base develop             # or use the GitHub page; the template guides the description
```

1. Open the PR against **`develop`**. Title: Conventional Commits, for example `feat(portal): report page`.
2. CI must be green and one teammate (the code owner of the folder) must approve.
3. Merge with **Squash and merge**; the squashed message is the PR title. Delete the branch.
4. Keep PRs small (one topic, under about 400 changed lines). Do not mix areas unless the API contract changes.
5. If you change the API, update `documentation/api-contract.md` and every affected codebase in the same PR
   (or open linked PRs and say so).

## Sprint release (`develop` into `main`)

At the end of each sprint the integrator (Helmut) opens one PR **`develop` → `main`**:

```bash
gh pr create --base main --head develop --title "release: sprint N" --body-file .github/PULL_REQUEST_TEMPLATE/release.md
```

- Use the release template: list what shipped, link the merged PRs, state the checks run and the demo status.
- CI green, `make check` passes locally, demo on a clean `make up` works.
- Merge with **Create a merge commit** (keeps the sprint boundary in history). Tag it: `git tag sprint-N && git push origin sprint-N`.
- Then make sure `develop` contains `main` (fast-forward) so the branches do not drift.

## Hotfixes

`hotfix/<area>-<topic>` from `main`, PR into `main`, then a PR (or merge) of `main` into `develop`.

## Commits and PR titles

Conventional Commits: `type(scope): summary` with types `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`,
`release`. Commits and PRs are authored by the person who does the work; no agent attribution lines.
CI checks the PR title and the branch name.

## Quality bar

- `make check` passes (API and verifier: ruff, mypy, pytest; portal: eslint, prettier, vitest, build;
  app: `flutter analyze`, `flutter test`).
- New behavior has a test. UI text in Spanish, code and docs in English.
- Never commit secrets, environment files, keys or real photos of people. Do not add a dependency without saying why
  in the PR; do not edit lockfiles by hand.
- The repository is public: no strategy, budget, customer notes or personal data.

## Ownership

Code owners per folder are in `.github/CODEOWNERS`. Ask the owner before changing another folder.

Repository settings that enforce this flow (branch protection, merge methods) are listed in
`documentation/github-setup.md`.
