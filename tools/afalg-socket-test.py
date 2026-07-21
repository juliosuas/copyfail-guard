#!/usr/bin/env python3
"""Non-exploit AF_ALG reachability test for CopyFail Guard.

Creates and closes an AF_ALG socket. It does not bind, splice, touch files,
or attempt exploitation. Use it to validate seccomp profiles block AF_ALG.
"""
import errno
import socket
import sys

AF_ALG = getattr(socket, "AF_ALG", 38)


def probe(socket_factory=socket.socket):
    """Return the operator-facing result and documented process exit code."""
    try:
        afalg_socket = socket_factory(AF_ALG, socket.SOCK_SEQPACKET, 0)
    except PermissionError as exc:
        return f"BLOCKED: socket(AF_ALG) denied by policy ({exc})", 0
    except OSError as exc:
        if exc.errno in {errno.EAFNOSUPPORT, errno.EPROTONOSUPPORT, errno.EINVAL}:
            return f"UNSUPPORTED: AF_ALG is not available in this runtime ({exc})", 2
        return f"ERROR: unexpected socket(AF_ALG) failure: {exc}", 3

    afalg_socket.close()
    return (
        "PERMITTED: socket(AF_ALG) succeeded. Seccomp AF_ALG block is NOT active for this process.",
        10,
    )


def main():
    message, code = probe()
    print(message)
    return code


if __name__ == "__main__":
    sys.exit(main())
