# Security Policy

CopyFail Guard is a defensive mitigation utility. It intentionally does not include exploit code, privilege-escalation proof-of-concepts, or weaponized vulnerability checks.

## Supported versions

| Version | Supported |
|---|---|
| `main` | Yes |
| tagged releases | Best effort |

## Reporting a security issue

If you find a security issue in this project, please open a private advisory on GitHub or contact the maintainer directly through the repository owner profile.

Please include:

- affected command or file
- host/container runtime details
- exact CopyFail Guard commit or release
- reproduction steps that do **not** include exploit payloads
- expected vs actual behavior

## Scope

In scope:

- unsafe file writes or symlink handling
- incorrect mitigation/rollback behavior
- seccomp profile corruption
- misleading verification output
- documentation that could cause unsafe production rollout

Out of scope:

- requests for exploit code
- proving exploitability of a third-party kernel build
- bypasses requiring root on the host
- unrelated hardening requests outside `algif_aead` / `AF_ALG`

## Design principles

- Patch and reboot remain the definitive fix.
- Mitigation must be reversible and auditable.
- Container seccomp guidance should preserve existing baseline policy where possible.
- Validation must be non-exploit and safe to run in production-like environments.
