# pslrm-bump-action

pslrm-bump-action is a GitHub Action for repositories that use [pslrm](https://github.com/krymtkts/pslrm).

It updates a project lockfile `psreq.lock.psd1` with pslrm.
When the lockfile changes, it opens or updates a pull request.

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

## Versioning

pslrm-bump-action and pslrm use independent version numbers.
Release notes document which pslrm version each action release uses.
