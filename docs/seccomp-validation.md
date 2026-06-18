# Seccomp validation notes

CopyFail Guard blocks the AF_ALG address family at socket creation time:

```text
socket(AF_ALG, ...)
```

On Linux, `AF_ALG` is address family `38`. Docker seccomp profiles express this as an argument comparison on the `socket` syscall:

```json
{
  "names": ["socket"],
  "action": "SCMP_ACT_ERRNO",
  "args": [{ "index": 0, "value": 38, "op": "SCMP_CMP_EQ" }]
}
```

## Preferred production approach

Patch the profile your runtime already uses:

```bash
./bin/copyfail-guard.sh seccomp-patch docker-default.json copyfail-seccomp.json
```

Why this matters:

- Docker’s default profile blocks many risky syscalls unrelated to Copy Fail.
- Replacing it with a minimal emergency profile can accidentally widen container privileges.
- Patching preserves your baseline and adds one targeted denial.

## Test matrix

Validate at least one workload per runtime class:

| Runtime | Test |
|---|---|
| Docker | `docker run --security-opt seccomp=...` |
| Podman | `podman run --security-opt seccomp=...` |
| Kubernetes | Localhost seccomp profile on a test node |
| CI runner | Protected job using the same runner image |

## Expected test script behavior

`tools/afalg-socket-test.py` returns:

| Exit | Meaning |
|---|---|
| `0` | AF_ALG socket creation was blocked |
| `10` | AF_ALG socket creation was permitted |
| `2` | AF_ALG is unsupported in this runtime/kernel |
| `3` | Unexpected socket error; investigate manually |

`0` is the desired result when testing a protected container.
