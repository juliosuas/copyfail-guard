# Fleet rollout guide

This guide helps teams use CopyFail Guard across Linux fleets without turning an incident-response helper into a blind production change.

## 1. Pick rollout groups

Start with a small, representative sample:

- one non-production host per distro/kernel family
- one container host or Kubernetes node pool
- one CI runner class if you run untrusted jobs
- one high-value production host only after non-production validation

Track hosts where `algif_aead` appears built in separately. Those hosts need patched kernel plus reboot; host module mitigation cannot disable built-in code.

## 2. Capture readiness

```bash
copyfail-guard doctor
copyfail-guard doctor --json
```

Record missing tools before rollout. `python3` is required for JSON output, seccomp profile patching, and the AF_ALG reachability test.

## 3. Assess before changing state

```bash
sudo copyfail-guard assess --json
```

Treat these exit code classes as rollout gates:

| Code | Meaning | Rollout action |
|---|---|---|
| `0` | Low obvious local exposure | Continue vendor patch verification |
| `1` | Interim mitigation active | Keep patch/reboot plan open |
| `10` | Exposed | Apply mitigation where modular, then verify |
| `11` | Partially mitigated | Reboot or unload safely, then verify |
| `12` | Built-in | Patch/reboot required; add seccomp for untrusted workloads |
| `20` | Unknown | Investigate manually before bulk action |

## 4. Apply host mitigation in stages

```bash
sudo copyfail-guard mitigate --yes
sudo copyfail-guard verify
```

Expected host write:

```text
/etc/modprobe.d/99-copyfail-guard.conf
```

If `rmmod algif_aead` fails because the module is in use, keep the persistent block and schedule a reboot after confirming AF_ALG consumers.

## 5. Roll out container hardening separately

Patch the runtime profile already used by the workload:

```bash
copyfail-guard seccomp-patch docker-default.json copyfail-seccomp.json
```

Validate a protected container:

```bash
docker run --rm \
  --security-opt seccomp=./copyfail-seccomp.json \
  -v "$PWD/tools:/tools:ro" \
  python:3.12-alpine \
  python /tools/afalg-socket-test.py
```

The desired result is:

```text
BLOCKED: socket(AF_ALG) denied by policy (...)
```

Restart existing containers or pods with the hardened profile. Seccomp does not change already-running workloads.

## 6. Keep audit evidence

For each rollout group, keep:

- `assess --json` before mitigation
- `verify` after mitigation
- vendor package update evidence
- reboot completion evidence
- seccomp profile path, checksum, and workload list
- exceptions for built-in modules or workloads that require AF_ALG

## 7. Roll back only when intentional

```bash
sudo copyfail-guard rollback --yes
```

Rollback removes only CopyFail Guard's managed modprobe file. It does not reload `algif_aead`; reboot or load the module manually only if you explicitly need AF_ALG AEAD and have accepted the remaining risk.
