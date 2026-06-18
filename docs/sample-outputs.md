# Sample outputs

These examples show the shape of CopyFail Guard output. Values such as hostnames, kernel releases, and distro names are illustrative.

## Doctor

```text
Required:
[+] bash found: /usr/bin/bash
[+] grep found: /usr/bin/grep
[+] awk found: /usr/bin/awk
[+] mktemp found: /usr/bin/mktemp
[+] install found: /usr/bin/install
[+] uname found: /usr/bin/uname

Linux host tools:
[+] modinfo found: /usr/sbin/modinfo
[+] modprobe found: /usr/sbin/modprobe
[+] lsmod found: /usr/sbin/lsmod
[+] rmmod found: /usr/sbin/rmmod

Doctor verdict: ready.
```

## Exposed Modular Host

```text
Verdict: EXPOSED_AUTOLOAD_POSSIBLE
Exit code: 10

Reasons:
  - algif_aead is available and can likely be autoloaded

Next actions:
  - Run: sudo ./bin/copyfail-guard.sh mitigate --yes

Reminder: CopyFail Guard mitigates exposure. The durable resolution is patched kernel + reboot.
```

## Interim Mitigated Host

```text
Verdict: INTERIM_MITIGATED_PATCH_STILL_REQUIRED
Exit code: 1

Reasons:
  - algif_aead is available but not loaded, and persistent modprobe block is active

Next actions:
  - Keep patch/reboot plan; mitigation is not a permanent fix
```

## Built-In Module Host

```text
Verdict: EXPOSED_BUILTIN_REBOOT_REQUIRED
Exit code: 12

Reasons:
  - algif_aead appears built into this kernel; modprobe.d/rmmod cannot disable it

Next actions:
  - Install vendor patched kernel and reboot
  - Use seccomp to deny socket(AF_ALG) for untrusted containers/CI while patching
```

## Protected Container

```text
BLOCKED: socket(AF_ALG) denied by policy ([Errno 1] Operation not permitted)
```

`BLOCKED` with exit code `0` is the expected result for a container launched with the AF_ALG-deny seccomp profile.

## Unprotected Container

```text
PERMITTED: socket(AF_ALG) succeeded. Seccomp AF_ALG block is NOT active for this process.
```

`PERMITTED` exits with code `10`. It does not prove exploitation, but it proves the relevant socket family is reachable for that process.

## JSON Assessment Shape

```json
{
  "tool": "copyfail-guard",
  "command": "assess",
  "cve": "CVE-2026-31431",
  "module": "algif_aead",
  "verdict": "EXPOSED_AUTOLOAD_POSSIBLE",
  "exit_code": 10,
  "safe_assessment": true,
  "exploit_attempted": false,
  "final_resolution": "vendor patched kernel + reboot",
  "reasons": [
    "algif_aead is available and can likely be autoloaded"
  ],
  "next_actions": [
    "Run: sudo ./bin/copyfail-guard.sh mitigate --yes"
  ]
}
```

Fleet automation should key off `verdict` and `exit_code`, then preserve the full JSON as change-management evidence.
