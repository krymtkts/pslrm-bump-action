# Changelog

This file records all notable changes to this project.

This changelog uses the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
This project starts in the `v0` preview series.

## [Unreleased]

### Added

- Add `skip-psresourceget-install` input to skip PSResourceGet installation.

### Changed

- Avoid unconditional `Microsoft.PowerShell.PSResourceGet` install. Check if version `1.0.1`+ exists.
- Create bump commits through GitHub's Git Database API so GitHub can mark them as verified.

### Notes

- Documentation now recommends `GITHUB_TOKEN` for most repositories.
  GitHub now allows workflows to run for approved pull requests created by
  `github-actions[bot]`.
  Use a PAT when subsequent workflows must run automatically without human
    approval.

## [0.0.1] - 2026-05-30

### Changed

- Bump `pslrm` version to 0.0.1.

## [0.0.1-alpha] - 2026-05-01

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
[0.0.1]: https://github.com/krymtkts/pslrm-bump-action/compare/v0.0.1-alpha...v0.0.1
[0.0.1-alpha]: https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha
