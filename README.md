# CopyFail Guard

[![CI](https://github.com/juliosuas/copyfail-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/juliosuas/copyfail-guard/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![No exploit code](https://img.shields.io/badge/exploit%20code-not%20included-important)

```text
   ______                 ______      _ __   ______                     __
  / ____/___  ____  __  _/ ____/___ _(_) /  / ____/_  ______ __________/ /
 / /   / __ \/ __ \/ / / / /_  / __ `/ / /  / / __/ / / / __ `/ ___/ __  /
/ /___/ /_/ / /_/ / /_/ / __/ / /_/ / / /  / /_/ / /_/ / /_/ / /  / /_/ /
\____/\____/ .___/\__, /_/    \__,_/_/_/   \____/\__,_/\__,_/_/   \__,_/
          /_/    /____/
```

**Fast, auditable Linux exposure assessment and mitigation for CVE-2026-31431 “Copy Fail” while kernels get patched.**

CopyFail Guard is a defensive operations tool for Linux sysadmins, DevSecOps engineers, platform teams, and incident responders. It helps reduce exposure to the Linux `algif_aead` / `AF_ALG` issue by:

- safely assessing exposure without exploit code
- checking whether `algif_aead` is available, loaded, built-in, or already blocked
- installing a persistent `modprobe.d` block and unloading the module when safe
- adding an AF_ALG-deny rule to Docker, Podman, and Kubernetes seccomp profiles
- validating AF_ALG reachability without shipping exploit code

> Final fix: install your vendor’s patched kernel and reboot.  
> This tool covers the operational gap between disclosure and full fleet patching.

## Why operators can trust it

- **No exploit code:** checks exposure and AF_ALG reachability without page-cache writes, `splice`, setuid changes, privilege escalation, or destructive probes.
- **Auditable host change:** host mitigation writes one managed file, `/etc/modprobe.d/99-copyfail-guard.conf`, and rollback removes only that file.
- **Baseline-preserving seccomp:** `seccomp-patch` adds an AF_ALG denial to an existing Docker/Podman/Kubernetes seccomp profile instead of replacing your runtime hardening.
- **Automation ready:** `assess --json` and documented exit codes support fleet scans, SIEM capture, and change-management evidence.
- **CI covered:** shell syntax, seccomp profile generation, JSON output, and smoke tests run across common Linux distro containers.

## 30-second path

If you are on a Linux host and need a quick answer:

```bash
git clone --depth 1 https://github.com/juliosuas/copyfail-guard.git
cd copyfail-guard
sudo ./bin/copyfail-guard.sh doctor
sudo ./bin/copyfail-guard.sh assess
```

If the verdict is exposed and `algif_aead` is modular:

```bash
sudo ./bin/copyfail-guard.sh mitigate --yes
sudo ./bin/copyfail-guard.sh verify
```

For repeatable installs, pin a release tag:

```bash
git clone --branch v0.2.0 --depth 1 https://github.com/juliosuas/copyfail-guard.git
```


## Am I affected?

Run the safe exposure check first:

```bash
sudo ./bin/copyfail-guard.sh assess
```

How to read the result:

| Verdict family | What it means | What to do |
|---|---|---|
| `EXPOSED_*` | `algif_aead` / AF_ALG appears reachable or loadable | Mitigate now, then patch and reboot |
| `PARTIALLY_MITIGATED_*` | A block exists but the loaded module or reboot state still matters | Reboot or unload safely, then verify |
| `INTERIM_MITIGATED_*` | Local mitigation is active | Keep it, but still patch and reboot |
| `LOW_OBVIOUS_EXPOSURE_*` | Local checks did not find obvious `algif_aead` exposure | Confirm vendor patch status anyway |

If you run untrusted containers, CI jobs, sandboxes, or multi-user workloads, also test whether AF_ALG socket creation is blocked inside that runtime:

```bash
python3 tools/afalg-socket-test.py
```

`PERMITTED` does not prove successful exploitation, but it proves the relevant userspace crypto API is reachable. For defensive operations, that is enough reason to apply the mitigation while you confirm the patched kernel rollout.

## Does this prove vulnerability?

No destructive proof of concept is included. That is a feature, not a gap.

A real Copy Fail exploit proof would need to validate kernel memory/page-cache impact or privilege escalation. Shipping that in a public mitigation repo would make the project less safe and less deployable in production.

CopyFail Guard proves the things operators can safely act on:

- whether the risky component is available, loaded, built-in, or blocked
- whether AF_ALG socket creation is permitted in a target runtime
- whether the host has an interim mitigation in place
- whether the remaining required action is unload, reboot, seccomp, or vendor patching

For final vulnerability status, combine this tool with vendor advisory/package inventory and reboot evidence.

## Resolution model

CopyFail Guard is **mitigation, not cure**. It reduces exposure and verifies interim controls. The durable fix remains vendor patched kernel plus reboot.

The tool is intentionally clone-and-run for incident response: no compiler, kernel headers, exploit code, or third-party package manager is required for the core host workflow. `python3` is needed for `--json` output, `seccomp-patch`, and the non-exploit AF_ALG socket test.

## Quick start

Clone-and-run:

```bash
git clone https://github.com/juliosuas/copyfail-guard.git
cd copyfail-guard
chmod +x bin/copyfail-guard.sh

sudo ./bin/copyfail-guard.sh doctor
sudo ./bin/copyfail-guard.sh assess
sudo ./bin/copyfail-guard.sh mitigate --yes
sudo ./bin/copyfail-guard.sh verify
```

Optional system install:

```bash
git clone https://github.com/juliosuas/copyfail-guard.git
cd copyfail-guard
sudo ./scripts/install.sh
sudo copyfail-guard status
```

The installer supports pinning the source and destination for controlled rollouts:

```bash
sudo env COPYFAIL_GUARD_REF=v0.2.0 ./scripts/install.sh
```

Container / CI hardening:

```bash
./bin/copyfail-guard.sh seccomp-patch docker-default.json copyfail-seccomp.json
docker run --security-opt seccomp=./copyfail-seccomp.json IMAGE
```

Validate that AF_ALG is blocked inside a protected container:

```bash
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

## Why this matters

Copy Fail is a Linux kernel local privilege escalation in the `algif_aead` component of the AF_ALG userspace crypto API. Public advisories describe a page-cache write primitive reachable by unprivileged local users and especially dangerous on shared-kernel systems: Kubernetes nodes, CI/CD runners, multi-tenant hosts, agent sandboxes, and developer boxes.

The correct fix is a vendor kernel update containing the upstream revert/fix and a reboot into the patched kernel. CopyFail Guard is a defensive operations helper for the window before that reboot is complete across the fleet.

## What the tool does

| Area | Command | Purpose |
|---|---|---|
| Safe assessment | `assess` | Give a non-exploit exposure verdict, next actions, and automation-friendly exit code |
| Dependency check | `doctor` | Check required/optional tools and explain runtime limitations |
| Host inspection | `status` | Show OS/kernel, module availability, loaded state, built-in warning, modprobe block, and obvious AF_ALG consumers |
| Host mitigation | `mitigate` | Write `/etc/modprobe.d/99-copyfail-guard.conf` and attempt to unload `algif_aead` |
| Verification | `verify` | Fail clearly if the module is loaded, built-in, or not blocked |
| Rollback | `rollback` | Remove only CopyFail Guard’s managed modprobe file |
| Containers | `seccomp-patch` | Patch an existing seccomp profile to deny `socket(AF_ALG, ...)` while preserving normal socket use |
| Emergency profile | `seccomp-docker` | Generate a targeted AF_ALG-deny profile for emergency use |
| Kubernetes | `k8s-example` | Print a Localhost seccomp pod example |

## Install requirements

Core host commands:

- Linux
- `bash`
- kmod tools: `modinfo`, `modprobe`, `lsmod`, `rmmod` where available
- `grep`, `awk`, `mktemp`, `install`

Optional visibility tools:

- `lsof` or `ss` for AF_ALG consumer checks

Seccomp profile patching:

- `python3` is required for `--json`, `seccomp-patch`, and `tools/afalg-socket-test.py`

No exploit code, compiler, kernel headers, or third-party packages are required.

## Safe assessment vs proof of concept

CopyFail Guard does **not** include an exploit proof of concept. That is intentional. See [Does this prove vulnerability?](#does-this-prove-vulnerability).

Instead, `assess` performs a safe operational check:

- detects whether `algif_aead` appears available, loaded, built-in, or blocked
- distinguishes “interim mitigated” from “actually resolved”
- recommends host mitigation, seccomp, or patch/reboot
- returns exit codes for fleet automation

Automation JSON:

```bash
sudo ./bin/copyfail-guard.sh assess --json
./bin/copyfail-guard.sh doctor --json
```

Exit codes:

| Code | Meaning |
|---|---|
| `0` | Low obvious exposure from local checks |
| `1` | Interim mitigation active, patch/reboot still required |
| `10` | Exposed/mitigation available |
| `11` | Partially mitigated; reboot or unload needed |
| `12` | Built-in module path; patch/reboot required |
| `20` | Unknown assessment state |

## Host mitigation details

`mitigate` writes:

```text
/etc/modprobe.d/99-copyfail-guard.conf
```

with:

```text
# Managed by CopyFail Guard for CVE-2026-31431
install algif_aead /bin/false
blacklist algif_aead
```

Then it attempts:

```bash
sudo rmmod algif_aead
```

If the module is currently in use, `rmmod` may fail. In that case the persistent block remains installed; stop AF_ALG consumers or reboot after applying the mitigation.

The script refuses to overwrite a symlink at its managed modprobe path and writes the file atomically with safe permissions.

## Container and CI hardening

For untrusted workloads, block AF_ALG socket creation with seccomp even while you patch hosts.

Recommended path: patch your existing runtime seccomp baseline instead of replacing it:

```bash
./bin/copyfail-guard.sh seccomp-patch docker-default.json copyfail-seccomp.json
```

Use with Docker:

```bash
docker run --security-opt seccomp=./copyfail-seccomp.json IMAGE
```

Use with Podman:

```bash
podman run --security-opt seccomp=./copyfail-seccomp.json IMAGE
```

Emergency-only path if you do not have a baseline profile:

```bash
./bin/copyfail-guard.sh seccomp-docker ./copyfail-afalg-seccomp.json
```

The generated emergency profile blocks AF_ALG but otherwise allows syscalls. Treat it as a targeted stopgap, not a replacement for Docker’s normal default seccomp hardening.

For Kubernetes, place the profile under the kubelet seccomp root, commonly:

```text
/var/lib/kubelet/seccomp/profiles/copyfail-seccomp.json
```

Then reference it with:

```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/copyfail-seccomp.json
```

See `examples/kubernetes-seccomp-pod.yaml`.

## Safe validation

This project includes a non-exploit AF_ALG reachability test:

```bash
python3 tools/afalg-socket-test.py
```

It only attempts to create and close an `AF_ALG` socket. It does not bind crypto operations, call `splice`, touch setuid binaries, corrupt page cache, or attempt privilege escalation.

Results:

- `BLOCKED` means policy denied AF_ALG for that process.
- `PERMITTED` means AF_ALG socket creation is still allowed for that process.
- `UNSUPPORTED` means AF_ALG is unavailable in that runtime.

## Commands

```text
copyfail-guard assess                 Safe exposure assessment, no exploit attempt
copyfail-guard status                 Inspect host exposure indicators
copyfail-guard doctor                 Check dependencies and runtime readiness
copyfail-guard mitigate               Disable algif_aead persistently and unload it
copyfail-guard verify                 Verify host mitigation is active
copyfail-guard rollback               Remove CopyFail Guard's modprobe mitigation
copyfail-guard seccomp-docker [FILE]  Generate emergency AF_ALG-deny profile
copyfail-guard seccomp-patch BASE OUT Patch existing seccomp profile safely
copyfail-guard k8s-example            Print Kubernetes seccomp example
```

Flags can be placed before or after the command:

```text
--dry-run      Show planned changes without writing files or unloading modules
--yes          Non-interactive confirmation
--no-logo      Disable ASCII banner
--json         Emit JSON for supported commands: assess, doctor
```

## What should not break

In typical configurations, disabling `algif_aead` is not expected to affect:

- LUKS / dm-crypt
- SSH
- OpenSSL, GnuTLS, NSS default builds
- kTLS / in-kernel TLS
- IPsec / XFRM
- normal in-kernel crypto consumers

It may affect applications explicitly configured to use the AF_ALG engine or applications that directly create AF_ALG sockets. Check first:

```bash
sudo lsof | grep AF_ALG || true
ss -xa | grep -i alg || true
```

## Operator documentation

- [Incident response runbook](docs/incident-response-runbook.md)
- [Fleet rollout guide](docs/fleet-rollout.md)
- [Seccomp validation notes](docs/seccomp-validation.md)
- [Safe assessment model](docs/safe-assessment.md)
- [Security policy](SECURITY.md)
- [Support policy](SUPPORT.md)
- [Contributing guide](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Project maturity

- Current scope: defensive assessment, host mitigation for modular `algif_aead`, seccomp hardening for untrusted workloads, and rollback.
- Supported user: operators comfortable with Linux host and container hardening.
- Release style: tagged releases, changelog entries, GitHub Actions smoke tests, and issue templates for reproducible reports.
- Stability promise: avoid exploit behavior, keep host writes narrow, document exit-code semantics, and preserve existing runtime seccomp baselines.

## Limitations

CopyFail Guard does **not**:

- patch your kernel
- prove whether your exact kernel build is exploitable
- ship exploit code
- protect against already-compromised root users
- replace EDR, fleet inventory, vendor advisories, or reboot planning

Host module mitigation works for modular `algif_aead`. If `algif_aead` is built into your kernel, `modprobe.d` and `rmmod` cannot disable it; patch/reboot is mandatory and seccomp should be used for untrusted workloads while patching.

Seccomp protects only workloads launched with the profile. Existing running containers or pods must be restarted with the hardened profile.

## Rollback

```bash
sudo ./bin/copyfail-guard.sh rollback --yes
```

Rollback removes only the file managed by this tool. It does not reload the module. Reboot or manually `modprobe algif_aead` only if you explicitly need it and have accepted the risk or patched the kernel.

## FAQ

### Is this a replacement for patching?

No. Patch and reboot remain the final fix.

### Does this test exploitation?

No. The project intentionally avoids exploit behavior. `tools/afalg-socket-test.py` only checks whether AF_ALG socket creation is reachable.

### Why block AF_ALG in containers even after host mitigation?

Defense in depth. Container and CI workloads are common places where untrusted code runs on a shared kernel. Seccomp makes the first step of this class of attack unreachable for that workload.

### Why patch an existing seccomp profile instead of generating a new one?

Because default runtime profiles contain many hardening decisions. Replacing them with a minimal emergency profile can accidentally remove protections. `seccomp-patch` keeps your baseline and adds the AF_ALG denial.

### Can I use this across a fleet?

Yes. Start with `doctor` and `assess --json`, stage mitigation on a small Linux sample, then roll out host mitigation and seccomp profile changes separately. See [Fleet rollout guide](docs/fleet-rollout.md).

## References

- [NVD: CVE-2026-31431](https://nvd.nist.gov/vuln/detail/CVE-2026-31431)
- [CERT-EU advisory: High Vulnerability in the Linux Kernel ("Copy Fail")](https://cert.europa.eu/publications/security-advisories/2026-005/)
- [CISA Known Exploited Vulnerabilities entry](https://www.cisa.gov/known-exploited-vulnerabilities-catalog?field_cve=CVE-2026-31431)
- [copy.fail public technical advisory](https://copy.fail)
- [Linux stable fix: `crypto: algif_aead - Revert to operating out-of-place`](https://git.kernel.org/stable/c/a664bf3d603dc3bdcf9ae47cc21e0daec706d7a5)

## Author

Built by **Julio César Suástegui Calderón**.

Security engineering, Linux systems, and practical defensive automation.

## License

MIT
