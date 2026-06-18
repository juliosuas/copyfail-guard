# Release checklist

Use this checklist before cutting a tagged CopyFail Guard release.

## 1. Confirm scope

- Changelog has a release section with user-facing changes.
- README quick-start instructions match the release tag.
- New commands, flags, exit codes, and file paths are documented.
- No exploit code, destructive validation, or unsafe rollout guidance was added.

## 2. Run local checks

```bash
make test
make lint
git diff --check
```

Optional Linux host checks:

```bash
sudo ./bin/copyfail-guard.sh doctor
sudo ./bin/copyfail-guard.sh assess
sudo ./bin/copyfail-guard.sh verify
```

## 3. Check GitHub Actions

- ShellCheck passes.
- Smoke matrix passes across Ubuntu, Debian, Fedora, AlmaLinux, Amazon Linux, and openSUSE.
- Dependabot PRs that only update GitHub Actions are reviewed or intentionally deferred.

## 4. Tag

```bash
git switch main
git pull --ff-only
git tag -a vX.Y.Z -m "CopyFail Guard vX.Y.Z"
git push origin vX.Y.Z
```

## 5. Publish release notes

Release notes should include:

- short summary
- safety model reminder: mitigation, not cure
- important command changes
- validation performed
- upgrade/install example using the tag
- link to security policy and community validation guide

## 6. Post-release

- Open or update a compatibility-report collection issue.
- Ask for distro/runtime field reports, not exploit testing.
- Verify README badges and release links render correctly.
- Keep the previous release tag available for pinned installs.
