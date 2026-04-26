# pslrm-bump-action

pslrm-bump-action is a GitHub Action for repositories that use [pslrm](https://github.com/krymtkts/pslrm).

It updates a project lockfile `psreq.lock.psd1` with pslrm.
When the lockfile changes, it opens or updates a pull request.

Use this action in scheduled or manually triggered dependency bump workflows.
It keeps the caller workflow focused on checkout, permissions, and scheduling.

## What It Does

- Runs pslrm as part of a dependency bump workflow.
- Keeps the caller workflow focused on scheduling and permissions.
- Bootstraps the pinned pslrm version from PSGallery and updates the target lockfile.
- Reports the final run result and associated bump branch / pull request identifiers.
- Automates the branch, commit, push, and pull request steps around the lockfile update.

## Project Status

> [!NOTE]
> This project is in preview.
> See [CHANGELOG.md](CHANGELOG.md) for the current scope and release-specific notes.

Current preview scope:

- One target project per action run.
- One lockfile per target project.
- Automatic branch, commit, push, and pull request handling around the lockfile update.
- No multi-project orchestration in a single run.

## Requirements

- Check out the repository with `actions/checkout` before you run this action.
- The target project must contain `psreq.psd1`.
- The token passed to `github-token` must be able to push a branch and create or update pull requests.
- GitHub-hosted runners already include the required PowerShell runtime, `git`, and GitHub CLI(`gh`).
- Self-hosted runners must also provide these command-line tools.
  - `git`.
  - GitHub CLI (`gh`).
  - PowerShell runtime selected by `target-powershell-edition`.
    - `core`: PowerShell (`pwsh`).
    - `desktop`: Windows PowerShell on Windows (`powershell`).
- The runner must be able to reach PSGallery.

The project root is the directory that contains `psreq.psd1`.

## Behavior

On each run, the action:

1. Installs `Microsoft.PowerShell.PSResourceGet`, then installs pinned `pslrm` from PSGallery.
2. Resolves the target project root from `project-path`.
3. Runs `Update-PSLResource` for that project to create or update `psreq.lock.psd1`.
4. Fails if files other than `psreq.lock.psd1` changed under the target project.
5. Exposes `result=no_change|created|updated|noop`.
6. When `result` is not `no_change`, also exposes `bump_branch_name` and `pull_request_number`.

Formatting or line-ending churn in the lockfile does not trigger branch or pull request automation.
In that case, the action emits a warning.
It also reports `result=no_change` because the parsed lockfile dependency data did not change.

When the action needs a pull request:

- The action derives the bump branch name from the changed dependency names.
- The action derives the commit message from the updated lockfile.
- It also derives the pull request title and body from the updated lockfile.
- The action resolves the base branch from the checked-out branch first.
- If needed, it falls back to GitHub workflow context.

Result values mean:

- `no_change`: The parsed lockfile dependency data did not change. Formatting or line-ending churn can still leave `psreq.lock.psd1` modified in Git status.
- `created`: The run created a new bump pull request.
- `updated`: The run updated the existing bump branch or pull request state.
- `noop`: The lockfile changed semantically, but required no external update.

## Usage

Minimal example:

```yaml
name: bump-pslrm-lockfile

on:
  workflow_dispatch:
  schedule:
    - cron: "0 0 * * 1"

permissions:
  contents: read

jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Update lockfile and create pull request
        uses: krymtkts/pslrm-bump-action@v0
        with:
          github-token: ${{ secrets.PSLRM_BUMP_TOKEN }}
```

> [!IMPORTANT]
> Pass a PAT to `github-token` when you want follow-up GitHub Actions workflows to run.
> See [Token Guidance](#token-guidance) for required permissions and `GITHUB_TOKEN` behavior.
> [!NOTE]
> This action does not control workflow concurrency.
> If multiple runs can update the same bump branch, configure `concurrency` in the caller workflow.

Example for a project in a subdirectory:

```yaml
- name: Update lockfile for a nested project
  uses: krymtkts/pslrm-bump-action@v0
  with:
    project-path: src/MyProject
    github-token: ${{ secrets.PSLRM_BUMP_TOKEN }}
```

Example for Windows PowerShell:

```yaml
jobs:
  bump:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: krymtkts/pslrm-bump-action@v0
        with:
          target-powershell-edition: desktop
          github-token: ${{ secrets.PSLRM_BUMP_TOKEN }}
```

Example for consuming outputs:

```yaml
jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Update lockfile and create pull request
        id: bump
        uses: krymtkts/pslrm-bump-action@v0
        with:
          github-token: ${{ secrets.PSLRM_BUMP_TOKEN }}

      - name: Report result
        shell: pwsh
        run: |
          Write-Host "result=${{ steps.bump.outputs.result }}"
          Write-Host "bump_branch_name=${{ steps.bump.outputs.bump_branch_name }}"
          Write-Host "pull_request_number=${{ steps.bump.outputs.pull_request_number }}"
```

## Inputs

| Input                       | Required | Default | Description                                                                                                                |
| --------------------------- | -------- | ------- | -------------------------------------------------------------------------------------------------------------------------- |
| `project-path`              | No       | `.`     | Path to the target project root or a path below it. The action resolves the directory that contains `psreq.psd1`.          |
| `target-powershell-edition` | No       | `core`  | PowerShell edition used to run action steps. Use `core` for `pwsh` or `desktop` for Windows PowerShell on Windows runners. |
| `github-token`              | Yes      | none    | Token used for branch push and pull request operations. Use a PAT when you want follow-up GitHub Actions workflows to run. |

## Outputs

| Output                | Description                                                                 |
| --------------------- | --------------------------------------------------------------------------- |
| `result`              | Final action result. One of `no_change`, `created`, `updated`, or `noop`.   |
| `bump_branch_name`    | Bump branch name associated with the run. Empty when `result=no_change`.    |
| `pull_request_number` | Pull request number associated with the run. Empty when `result=no_change`. |

## Token Guidance

Pass a token that can push branches and create or update pull requests.

> [!IMPORTANT]
> Use a PAT when this action must trigger follow-up GitHub Actions workflows.
> Grant that PAT `contents: write` and `pull-requests: write` on the target repository.

Otherwise, use `GITHUB_TOKEN` for same-repository runs.
Grant the workflow `contents: write` and `pull-requests: write`.
Also enable `Allow GitHub Actions to create and approve pull requests` on the target repository.
`GITHUB_TOKEN` can complete this flow, but it does not trigger follow-up workflows.

You can verify that setting with GitHub CLI:

```powershell
gh api --method GET repos/OWNER/REPO/actions/permissions/workflow
```

The setting is on when `can_approve_pull_request_reviews` is `true`.
You can enable it with:

```powershell
gh api --method PUT repos/OWNER/REPO/actions/permissions/workflow `
  -f default_workflow_permissions=read `
  -F can_approve_pull_request_reviews=true
```

If you use a PAT, store it in a secret and pass that secret to `github-token`.

## Versioning

pslrm-bump-action and pslrm use independent version numbers.
Release notes document which pslrm version each action release uses.

Use tag-based references for normal consumption.
Use `@v0` for the current preview series.

Use a branch or commit SHA when you need unreleased changes before the next preview tag.
Do not treat that prerelease reference as the long-term public contract.
