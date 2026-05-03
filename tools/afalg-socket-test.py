#!/usr/bin/env python3
"""Non-exploit AF_ALG reachability test for CopyFail Guard.

Creates and closes an AF_ALG socket. It does not bind, splice, touch files,
or attempt exploitation. Use it to validate seccomp profiles block AF_ALG.
"""
import errno
import socket
import sys

AF_ALG = getattr(socket, "AF_ALG", 38)

try:
    s = socket.socket(AF_ALG, socket.SOCK_SEQPACKET, 0)
except PermissionError as exc:
    print(f"BLOCKED: socket(AF_ALG) denied by policy ({exc})")
    sys.exit(0)
except OSError as exc:
    if exc.errno in {errno.EAFNOSUPPORT, errno.EPROTONOSUPPORT, errno.EINVAL}:
        print(f"UNSUPPORTED: AF_ALG is not available in this runtime ({exc})")
        sys.exit(2)
    print(f"ERROR: unexpected socket(AF_ALG) failure: {exc}")
    sys.exit(3)
else:
    s.close()
    print("PERMITTED: socket(AF_ALG) succeeded. Seccomp AF_ALG block is NOT active for this process.")
    sys.exit(10)
