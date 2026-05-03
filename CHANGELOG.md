# Changelog

## v0.1.0 - Initial defensive release

- Host inspection for `algif_aead` availability, loaded state, built-in state, and persistent modprobe blocks.
- Host mitigation through `/etc/modprobe.d/99-copyfail-guard.conf` plus safe unload attempt.
- Verification and rollback commands.
- Docker/Podman/Kubernetes seccomp profile generation.
- `seccomp-patch BASE OUT` to preserve an existing runtime baseline while denying `socket(AF_ALG)`.
- Non-exploit AF_ALG reachability test in `tools/afalg-socket-test.py`.
- Multi-distro CI smoke tests and ShellCheck.
