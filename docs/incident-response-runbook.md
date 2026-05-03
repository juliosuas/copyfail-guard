# CopyFail Guard incident response runbook

This runbook is for operators responding to CVE-2026-31431 “Copy Fail” exposure on Linux fleets.

## 0. Principle

CopyFail Guard buys time. It does not replace the vendor kernel update and reboot.

Use this sequence:

1. Inventory potentially exposed Linux hosts.
2. Patch kernel packages from the vendor.
3. Reboot into the patched kernel.
4. Until reboot is complete, disable modular `algif_aead` where possible.
5. For containers, CI runners, sandboxes, and untrusted workloads, deny `socket(AF_ALG)` with seccomp.
6. Verify and document residual risk.

## 1. Triage a host

```bash
sudo ./bin/copyfail-guard.sh status
```

Record:

- OS and kernel release
- whether `algif_aead` is available
- whether it is loaded
- whether it appears built into the kernel
- whether an AF_ALG consumer is visible
- whether a persistent modprobe block already exists

### Interpretation

| Finding | Meaning | Action |
|---|---|---|
| `algif_aead` unavailable | Lower obvious exposure | Still patch according to vendor guidance |
| module available, not loaded | Prevent future autoload | Run `mitigate` |
| module loaded | Active attack surface | Review consumers, run `mitigate`, reboot if unload fails |
| built-in | Cannot disable with modprobe/rmmod | Patch/reboot; use seccomp for untrusted workloads |

## 2. Apply host mitigation

```bash
sudo ./bin/copyfail-guard.sh mitigate --yes
```

This writes `/etc/modprobe.d/99-copyfail-guard.conf` and tries to unload `algif_aead`.

If unload fails, keep the persistent block and plan a reboot. Do not force-kill production processes blindly; identify AF_ALG consumers first.

## 3. Verify host state

```bash
sudo ./bin/copyfail-guard.sh verify
```

A passing result means the interim host mitigation is active. It does not mean the kernel is patched.

## 4. Harden containers and CI

Preferred path: patch the existing runtime seccomp baseline.

```bash
./bin/copyfail-guard.sh seccomp-patch docker-default.json copyfail-seccomp.json
docker run --security-opt seccomp=./copyfail-seccomp.json IMAGE
```

Emergency path only:

```bash
./bin/copyfail-guard.sh seccomp-docker ./copyfail-afalg-seccomp.json
```

The emergency profile allows all other syscalls. Use it only when you do not have a baseline profile available.

## 5. Validate seccomp without exploit code

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

## 6. Rollback

Only rollback after you have patched/rebooted or intentionally need AF_ALG AEAD again.

```bash
sudo ./bin/copyfail-guard.sh rollback --yes
```

Rollback removes only CopyFail Guard’s managed modprobe file. It does not reload the module.

## 7. Evidence to keep

For audit/change-management records, keep:

- package update ticket or vendor advisory reference
- reboot completion evidence
- `copyfail-guard status` before mitigation
- `copyfail-guard verify` after mitigation
- container profile path and workloads covered
- exceptions and hosts where `algif_aead` is built in
