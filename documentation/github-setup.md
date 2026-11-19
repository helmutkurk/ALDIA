# GitHub settings that enforce the flow

These are repository settings (not files), so a repository admin applies them once in
Settings on GitHub. They match `CONTRIBUTING.md`.

## General → Pull requests

- Allow **squash merging** (default message: pull request title) and **merge commits**.
- Disable **rebase merging**.
- Enable **Automatically delete head branches**.
- Enable **Always suggest updating pull request branches**.

## Branches → protection rules (or a ruleset)

| Rule | `develop` | `main` |
|---|---|---|
| Require a pull request before merging | yes | yes |
| Required approvals | 1 | 1 (the integrator) |
| Require review from code owners | yes | yes |
| Dismiss stale approvals on new commits | yes | yes |
| Require status checks to pass | `api`, `verifier`, `portal`, `app`, `rules`, `security` | same |
| Require branches to be up to date | yes | no (the sprint PR is `develop` itself) |
| Require linear history | yes (squash only) | no (merge commits mark sprints) |
| Block force pushes and deletions | yes | yes |
| Allow admins to bypass | no | no |

Merge method per target: feature PRs into `develop` use **Squash and merge**; the sprint PR into `main` uses
**Create a merge commit**.

## Actions → General

- Workflow permissions: **Read repository contents** only.
- Do not allow actions from outside the repository except those pinned by commit SHA.

## Rename

Repository name: `ALDIA` (Settings → General → Repository name). GitHub redirects the old name; update local clones with
`git remote set-url origin https://github.com/<owner>/ALDIA.git`.
