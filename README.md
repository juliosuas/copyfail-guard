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

CopyFail Guard helps operators reduce exposure to the Linux `algif_aead` / `AF_ALG` issue by:

- safely assessing exposure without exploit code
- checking whether `algif_aead` is available, loaded, built-in, or already blocked
- installing a persistent `modprobe.d` block and unloading the module when safe
- adding an AF_ALG-deny rule to Docker, Podman, and Kubernetes seccomp profiles
- validating AF_ALG reachability without shipping exploit code

> Final fix: install your vendor’s patched kernel and reboot.  
> This tool covers the operational gap between disclosure and full fleet patching.

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

- `python3` is required for `seccomp-patch`

No exploit code, compiler, kernel headers, or third-party packages are required.

## Safe assessment vs proof of concept

CopyFail Guard does **not** include an exploit proof of concept. That is intentional. A real Copy Fail exploit check would need to exercise dangerous kernel behavior and validate a write primitive or privilege impact, which is not appropriate for a public defensive tool.

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
- [Seccomp validation notes](docs/seccomp-validation.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Usability rating

Current target audience: Linux sysadmins, DevSecOps engineers, platform teams, and incident responders.

- Installation friction: low. Clone-and-run requires no package manager beyond standard Linux tooling; `python3` is only needed for `seccomp-patch`.
- Operator UX: high. `doctor`, `assess`, `mitigate`, `verify`, and `rollback` map to an incident-response flow.
- Casual-user UX: medium. This is kernel/container hardening; the tool keeps language direct, but the domain still requires Linux administration judgment.

Resolution rating: mitigation, not cure. The tool reduces exposure and verifies controls; vendor kernel update + reboot is the final resolution.

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

## References

- NVD: CVE-2026-31431
- CERT-EU advisory: High Vulnerability in the Linux Kernel (“Copy Fail”)
- copy.fail public technical advisory
- Linux upstream fix/revert: `crypto: algif_aead - Revert to operating out-of-place`

## Author

Built by **Julio César Suástegui Calderón**.

Security engineering, Linux systems, and practical defensive automation.

## License

MIT
