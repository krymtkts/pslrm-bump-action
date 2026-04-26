# Changelog

This file records all notable changes to this project.

This changelog uses the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
This project starts in the `v0` preview series.

## [Unreleased]

## [0.0.1-alpha]

### Added

- Add a preview GitHub Action that updates `psreq.lock.psd1` with `pslrm`.
- Add automation for branch, commit, push, and pull request handling around lockfile updates.
- Add inputs for project selection, PowerShell edition selection and GitHub token.
- Add outputs so caller workflows can inspect the run outcome and bump state.

### Notes

- The current preview targets one project per action run.
- The target project uses `psreq.psd1` and `psreq.lock.psd1`.
- The current preview focuses on lockfile update plus pull request creation.
- Multi-project orchestration is not implemented in the current preview.
- Action releases and pinned `pslrm` versions have separate version tracks.

---

[Unreleased]: https://github.com/krymtkts/pslrm-bump-action/commits/main
[0.0.1-alpha]: https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha
