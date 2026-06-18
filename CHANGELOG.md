# Changelog

## Unreleased

No unreleased changes.

## v0.3.0 - Adoption, community validation, and release readiness

- Added contribution, support, pull-request, issue-template, and Dependabot metadata to make maintenance expectations clearer.
- Added a fleet rollout guide plus Ansible and GitHub Actions examples for safer adoption.
- Added a Makefile for local smoke and lint checks.
- Added `--version` alias for easier scripting.
- Added `COPYFAIL_GUARD_REF` support to `scripts/install.sh` for pinned installs.
- Aligned seccomp validation documentation with `tools/afalg-socket-test.py` exit code `10` for permitted AF_ALG socket creation.
- Made the GitHub Actions seccomp validation example explicitly require `BLOCKED` output plus exit code `0`.
- Added community validation docs and a compatibility-report issue template to encourage reproducible field reports.
- Ignored local agent skill installs so `.agents/` and `skills-lock.json` do not get committed accidentally.
- Added sample output and release checklist documentation to make adoption and tagged releases easier to verify.
- Hardened CI with run concurrency, job timeouts, and non-interactive openSUSE GPG key handling.

## v0.2.0 - Safe assessment and UX release

- Added `assess` for non-exploit exposure assessment with clear verdicts, next actions, and fleet-friendly exit codes.
- Added `--json` output for `assess` and `doctor` to support fleet automation, SIEM capture, and change-management evidence.
- Added `doctor` to check required and optional dependencies before incident-response work.
- Added `version` command.
- Documented why the project does not ship an exploit proof of concept.
- Added `docs/safe-assessment.md` for the exposure-assessment model and automation semantics.
- Updated README to clearly separate mitigation from final remediation.

## v0.1.0 - Initial defensive release

- Host inspection for `algif_aead` availability, loaded state, built-in state, and persistent modprobe blocks.
- Host mitigation through `/etc/modprobe.d/99-copyfail-guard.conf` plus safe unload attempt.
- Verification and rollback commands.
- Docker/Podman/Kubernetes seccomp profile generation.
- `seccomp-patch BASE OUT` to preserve an existing runtime baseline while denying `socket(AF_ALG)`.
- Non-exploit AF_ALG reachability test in `tools/afalg-socket-test.py`.
- Multi-distro CI smoke tests and ShellCheck.
