# Support

CopyFail Guard is an open-source defensive utility, not an emergency incident-response service.

## Best places to ask

- Open a GitHub issue for reproducible bugs, documentation gaps, distro compatibility problems, and seccomp runtime questions.
- Use a private GitHub security advisory for security issues in this project.
- Use your vendor advisory, package inventory, and reboot evidence to confirm final remediation for CVE-2026-31431.

## What to include

Please include:

- CopyFail Guard version or commit
- command run and exact output
- distro, kernel release, and container runtime if relevant
- whether you ran as root
- whether `algif_aead` is available, loaded, built in, or blocked
- sanitized seccomp profile snippets for `seccomp-patch` issues

## What this project cannot do

- confirm exploitability of a specific third-party kernel build
- provide exploit code or weaponized tests
- replace vendor kernel patching and reboot
- debug unrelated Linux hardening issues outside `algif_aead` and `AF_ALG`
