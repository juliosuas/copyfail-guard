# Contributing to CopyFail Guard

Thanks for helping make defensive Linux operations safer and easier to run.

## Project boundaries

CopyFail Guard is a mitigation and verification project. Contributions should keep these boundaries:

- no exploit code, privilege-escalation proof of concepts, destructive probes, or payloads
- no guidance that encourages skipping vendor kernel patching and reboot
- host writes must stay narrow, auditable, reversible, and documented
- seccomp changes should preserve existing runtime baselines whenever possible
- command output should be useful during an incident, not clever at the expense of clarity

## Local checks

Run the smoke suite before opening a pull request:

```bash
make test
```

If ShellCheck is installed, also run:

```bash
make lint
```

The core script should stay compatible with Bash on common Linux distributions. `python3` is allowed for JSON helpers, seccomp profile patching, and test tooling.

## Pull requests

Good pull requests usually include:

- the operational problem being solved
- the command or document changed
- before/after output when behavior changes
- tests or smoke coverage for command behavior
- rollback or safety notes when host state changes

## Security-sensitive changes

For issues involving unsafe file writes, misleading verification, seccomp corruption, or dangerous rollout guidance, follow [SECURITY.md](SECURITY.md). Do not include exploit payloads in public issues or pull requests.
