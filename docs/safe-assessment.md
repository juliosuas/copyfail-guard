# Safe assessment model

CopyFail Guard deliberately avoids a weaponized proof of concept for CVE-2026-31431 “Copy Fail”.

A real exploitability proof would need to exercise the vulnerable `algif_aead`/AF_ALG path deeply enough to validate kernel memory/page-cache impact. That can be destructive, can cross the line into exploit tooling, and is not acceptable for a public defensive repository.

The project uses a safer model: exposure assessment.

## What `assess` answers

`copyfail-guard assess` answers operational questions:

- Is this a Linux host?
- Is `algif_aead` available?
- Is `algif_aead` loaded?
- Does it appear built into the kernel?
- Is a persistent modprobe block active?
- Is this host only mitigated, or does it still require patch/reboot?

## What `assess` does not answer

It does not prove:

- that a specific kernel build is exploitable
- that exploitation would succeed on this host
- that a vendor patch has been installed
- that the machine is fully remediated

Only vendor advisories, package inventory, and reboot evidence can close that loop.

## Exit codes

| Code | Verdict class | Automation meaning |
|---|---|---|
| `0` | Low obvious exposure | No immediate local `algif_aead` exposure found; still verify patch status |
| `1` | Interim mitigated | Control is active but patch/reboot remains required |
| `10` | Exposed | Apply mitigation and patch plan |
| `11` | Partially mitigated | Persistent block exists but loaded module/reboot state needs attention |
| `12` | Built-in | Host mitigation cannot disable it; patch/reboot required |
| `20` | Unknown | Investigate manually |

## Recommended fleet workflow

```bash
copyfail-guard doctor
copyfail-guard assess
copyfail-guard mitigate --yes
copyfail-guard verify
```

For untrusted workloads:

```bash
copyfail-guard seccomp-patch docker-default.json copyfail-seccomp.json
```

Then validate with the non-exploit socket reachability test:

```bash
python3 tools/afalg-socket-test.py
```

## JSON output

For fleet automation and SIEM/change-management capture:

```bash
copyfail-guard assess --json
copyfail-guard doctor --json
```

`assess --json` includes `safe_assessment: true`, `exploit_attempted: false`, the verdict, exit code, reasons, next actions, and the final-resolution reminder.

## How users know whether it matters

Use three layers of evidence:

1. **Vendor/package evidence** — confirm whether the running kernel version includes the vendor fix for CVE-2026-31431.
2. **Local exposure evidence** — run `copyfail-guard assess` to see whether `algif_aead` is available, loaded, built-in, or blocked.
3. **Runtime reachability evidence** — run `tools/afalg-socket-test.py` in the target container/sandbox/user context to see whether `socket(AF_ALG)` is permitted.

A safe tool cannot honestly promise “exploitable” without crossing into exploit validation. It can, however, prove enough to drive a defensive decision: if the vulnerable component is present or AF_ALG is reachable, mitigate while patch status is confirmed.
