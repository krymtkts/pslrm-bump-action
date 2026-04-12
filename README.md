# pslrm-bump-action

pslrm-bump-action is a GitHub Action for repositories that use [pslrm](https://github.com/krymtkts/pslrm).

It updates a project lockfile `psreq.lock.psd1` with pslrm.
When the lockfile changes, it opens or updates a pull request.

Use this action in scheduled or manually triggered dependency bump workflows.
It keeps the caller workflow focused on checkout, permissions, and scheduling.

## What It Does

- Runs pslrm as part of a dependency bump workflow.
- Keeps the caller workflow focused on scheduling and permissions.
- Bootstraps bundled pslrm and updates the target lockfile.
- Reports whether the lockfile changed.
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
- The action updates `psreq.lock.psd1` for that project.
- The token passed to `github-token` must be able to push a branch and create or update pull requests.
- `target-powershell-edition: desktop` requires a Windows runner.

The project root is the directory that contains `psreq.psd1`.

## Behavior

On each run, the action:

1. Boots a bundled, fixed version of `pslrm`.
2. Resolves the target project root from `project-path`.
3. Runs `Update-PSLResource` for that project.
4. Fails if files other than `psreq.lock.psd1` changed under the target project.
5. Exposes `changed=true|false`.
6. If `changed=true`, creates or updates a bump branch and pull request.

When the action needs a pull request:

- The action derives the bump branch name from the changed dependency names.
- The action derives the commit message from the updated lockfile.
- It also derives the pull request title and body from the updated lockfile.
- The action resolves the base branch from the checked-out branch first.
- If needed, it falls back to GitHub workflow context.

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

## Inputs

| Input                       | Required | Default | Description                                                                                                                |
| --------------------------- | -------- | ------- | -------------------------------------------------------------------------------------------------------------------------- |
| `project-path`              | No       | `.`     | Path to the target project root or a path below it. The action resolves the directory that contains `psreq.psd1`.          |
| `target-powershell-edition` | No       | `core`  | PowerShell edition used to run the action. Use `core` for `pwsh` or `desktop` for Windows PowerShell.                      |
| `github-token`              | Yes      | none    | Token used for branch push and pull request operations. Use a PAT when you want follow-up GitHub Actions workflows to run. |

## Outputs

| Output    | Description                                          |
| --------- | ---------------------------------------------------- |
| `changed` | `true` when the lockfile changed, otherwise `false`. |

## Token Guidance

Use a token that can push branches and create or update pull requests.

> [!IMPORTANT]
> Use a PAT when you want follow-up GitHub Actions workflows to run.
> That PAT should grant `contents: write` and `pull-requests: write` on the target repository.

You can pass `GITHUB_TOKEN` to update the lockfile and create or update the bump pull request.
In that case, grant the workflow write permissions.
For example, that often means `contents: write` and `pull-requests: write`.

A PAT can create a branch and pull request that trigger downstream GitHub Actions workflows.
The default `GITHUB_TOKEN` does not trigger follow-up workflow runs in this branch-push flow.

If you want follow-up GitHub Actions workflows to run, store a PAT in a secret.
For example, use `PSLRM_BUMP_TOKEN`.

## Versioning

pslrm-bump-action and pslrm use independent version numbers.
Release notes document which pslrm version each action release uses.

Use tag-based references for normal consumption.
Use `@v0` for the preview series after the preview tag becomes available.

Until then, another repository can reference a branch or commit SHA.
Use that for prerelease validation.
Do not treat it as the long-term public contract.
