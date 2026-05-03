# CopyFail Guard

```text
   ______                 ______      _ __   ______                     __
  / ____/___  ____  __  _/ ____/___ _(_) /  / ____/_  ______ __________/ /
 / /   / __ \/ __ \/ / / / /_  / __ `/ / /  / / __/ / / / __ `/ ___/ __  /
/ /___/ /_/ / /_/ / /_/ / __/ / /_/ / / /  / /_/ / /_/ / /_/ / /  / /_/ /
\____/\____/ .___/\__, /_/    \__,_/_/_/   \____/\__,_/\__,_/_/   \__,_/
          /_/    /____/
```

**CopyFail Guard** is a Linux sysadmin helper for quickly mitigating **CVE-2026-31431**, also known as **Copy Fail**, while you roll out patched kernels.

It does three practical things:

1. Inspects whether the vulnerable AF_ALG AEAD frontend (`algif_aead`) is present, loaded, or already blocked.
2. Applies a persistent host mitigation by disabling `algif_aead` through `modprobe.d` and unloading it when safe.
3. Patches an existing Docker/Podman/Kubernetes seccomp profile so it blocks `AF_ALG` socket creation for untrusted containers, CI runners, and sandboxes.

> Patch fast. Mitigate faster. Verify always.

## Why this matters

Copy Fail is a Linux kernel local privilege escalation in the `algif_aead` component of the AF_ALG userspace crypto API. Public advisories describe a page-cache write primitive reachable by unprivileged local users and especially dangerous on shared-kernel systems: Kubernetes nodes, CI/CD runners, multi-tenant hosts, agent sandboxes, and dev boxes.

The proper fix is a vendor kernel update containing the upstream revert/fix and a reboot into the patched kernel. This tool is for the gap between “we know” and “everything is patched.”

## Install

```bash
git clone https://github.com/juliosuas/copyfail-guard.git
cd copyfail-guard
chmod +x bin/copyfail-guard.sh
```

No runtime dependencies beyond standard Linux admin tools (`bash`, `modprobe`, `lsmod`, `rmmod`). `lsof` or `ss` are optional for visibility.

## Quick start

```bash
# Inspect exposure indicators
sudo ./bin/copyfail-guard.sh status

# Apply host mitigation
sudo ./bin/copyfail-guard.sh mitigate --yes

# Confirm mitigation
sudo ./bin/copyfail-guard.sh verify
```

The host mitigation writes:

```text
/etc/modprobe.d/99-copyfail-guard.conf
```

with:

```text
install algif_aead /bin/false
blacklist algif_aead
```

Then it attempts:

```bash
sudo rmmod algif_aead
```

If the module is in use, the persistent block remains installed and the host should be rebooted or AF_ALG consumers should be stopped before unloading.

## Container and CI hardening

For untrusted workloads, block AF_ALG socket creation with seccomp even if you are patching.

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

That generated emergency profile blocks AF_ALG but otherwise allows syscalls, so it should be treated as a targeted stopgap, not a replacement for Docker's normal default seccomp hardening.

For Kubernetes, see:

```bash
./bin/copyfail-guard.sh k8s-example
```

and `examples/kubernetes-seccomp-pod.yaml`.

## Commands

```text
copyfail-guard status                 Inspect host exposure indicators
copyfail-guard mitigate               Disable algif_aead persistently and unload it
copyfail-guard verify                 Verify host mitigation is active
copyfail-guard rollback               Remove CopyFail Guard's modprobe mitigation
copyfail-guard seccomp-docker [FILE]  Generate emergency AF_ALG-deny profile
copyfail-guard seccomp-patch BASE OUT Patch existing seccomp profile safely
copyfail-guard k8s-example            Print Kubernetes seccomp example
```

Common flags:

```text
--dry-run      Show planned changes
--yes          Non-interactive confirmation
--no-logo      Disable ASCII banner
```

## What should not break

Disabling `algif_aead` blocks the userspace AF_ALG AEAD frontend. Public guidance indicates this should **not** affect typical uses of:

- LUKS / dm-crypt
- SSH
- OpenSSL, GnuTLS, NSS default builds
- kTLS / in-kernel TLS
- IPsec / XFRM
- Normal in-kernel crypto consumers

It **may** affect applications explicitly configured to use the AF_ALG engine or applications that directly create AF_ALG sockets. Check first:

```bash
sudo lsof | grep AF_ALG || true
ss -xa | grep -i alg || true
```

## Rollback

```bash
sudo ./bin/copyfail-guard.sh rollback --yes
```

Rollback removes only the file managed by this tool. It does not reload the module. Reboot or manually `modprobe algif_aead` only if you explicitly need it and have accepted the risk or patched the kernel.

## Verification philosophy

This project intentionally does **not** ship exploit code and does not try to “prove vulnerability” by corrupting page cache or touching setuid binaries. That belongs in controlled security labs, not on production fleets.

CopyFail Guard focuses on safe, auditable controls sysadmins can apply quickly.

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
