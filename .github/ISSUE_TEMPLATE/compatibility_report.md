---
name: Compatibility report
about: Share sanitized CopyFail Guard validation output from a distro, runtime, or CI environment.
title: "Compatibility: <distro/runtime> <version>"
labels: documentation
---

## Environment

- Distro / OS:
- Kernel version:
- Runtime tested: host / Docker / Podman / Kubernetes / CI runner / other
- CopyFail Guard commit or release:

## Safe Commands Run

Please paste sanitized output only.

```text
copyfail-guard version
```

```text
copyfail-guard doctor
```

```text
copyfail-guard doctor --json
```

```text
sudo copyfail-guard assess --json
```

```text
sudo copyfail-guard verify
```

```text
python3 tools/afalg-socket-test.py
```

## Runtime / Seccomp Notes

- Default profile or patched profile?
- Was AF_ALG socket creation permitted, blocked, or unsupported?
- Any runtime-specific command needed?

## Redaction Checklist

- [ ] No hostnames
- [ ] No private IP addresses
- [ ] No account names
- [ ] No ticket numbers
- [ ] No internal workload names
- [ ] No full kernel configs
- [ ] No proprietary seccomp baselines
- [ ] No secrets, tokens, or environment values

## Notes

Anything confusing, missing, or worth adding to the docs?
