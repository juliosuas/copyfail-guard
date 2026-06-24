# Community validation guide

CopyFail Guard gets more useful when operators share safe, reproducible results
from real hosts and runtimes. Stars help visibility, but compatibility reports
help trust.

## What to report

Useful reports answer one of these questions:

- Does `assess` classify exposure correctly on this distro/kernel family?
- Does `mitigate --yes` write the expected modprobe block and unload `algif_aead` when safe?
- Does `verify` catch loaded, built-in, or unblocked states correctly?
- Does `seccomp-patch` work with this Docker, Podman, Kubernetes, or CI runner profile?
- Does `tools/afalg-socket-test.py` return `BLOCKED` in a protected runtime?

## Safe command set

Use only non-exploit commands:

```bash
copyfail-guard version
copyfail-guard doctor
copyfail-guard doctor --json
sudo copyfail-guard assess --json
sudo copyfail-guard verify
python3 tools/afalg-socket-test.py
```

For container runtime checks:

```bash
copyfail-guard seccomp-patch docker-default.json copyfail-seccomp.json
docker run --rm \
  --security-opt seccomp=./copyfail-seccomp.json \
  -v "$PWD/tools:/tools:ro" \
  python:3.12-alpine \
  python /tools/afalg-socket-test.py
```

Expected protected result:

```text
BLOCKED: socket(AF_ALG) denied by policy (...)
```

## Do not include

- exploit payloads or exploit output
- internal hostnames, private IPs, ticket numbers, usernames, or workload names
- full `/etc` dumps, kernel configs with local identifiers, or proprietary seccomp baselines
- secrets, tokens, CI logs with environment variables, or cloud account details

Kernel version, distro version, command output, and sanitized runtime names are
enough for a useful report.

## Current validation coverage

Automated smoke tests currently cover command syntax, JSON output, seccomp
generation, and profile patching across these container images:

| Environment | Coverage type |
|---|---|
| Ubuntu 24.04 | CI smoke |
| Debian 12 | CI smoke |
| Fedora latest | CI smoke |
| AlmaLinux 9 | CI smoke |
| Amazon Linux 2023 | CI smoke |
| openSUSE Leap 15.6 | CI smoke |

These CI checks do not prove host kernel remediation. Field reports are still
valuable for real hosts, Kubernetes nodes, CI runners, and production seccomp
baselines.

## How to submit

Open a **Compatibility report** issue and include:

- CopyFail Guard version or commit
- distro, kernel, architecture, and runtime
- commands run
- sanitized output
- result summary
- constraints or exceptions

Good reports can become README/docs entries, regression tests, or
runtime-specific examples.

## Safety boundary

Do not submit exploit payloads, privilege-escalation proof, or destructive
tests. This project validates operational exposure and mitigation state only.
Vendor kernel patching and reboot remain the durable fix.
