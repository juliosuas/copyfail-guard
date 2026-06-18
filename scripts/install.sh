#!/usr/bin/env sh
set -eu

repo="${COPYFAIL_GUARD_REPO:-https://github.com/juliosuas/copyfail-guard.git}"
ref="${COPYFAIL_GUARD_REF:-main}"
dest="${COPYFAIL_GUARD_DEST:-/opt/copyfail-guard}"
bin="/usr/local/bin/copyfail-guard"

if [ "$(id -u)" -ne 0 ]; then
  echo "[x] Root required. Re-run with sudo." >&2
  exit 3
fi

if command -v git >/dev/null 2>&1; then
  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --tags --prune origin
    git -C "$dest" checkout "$ref"
    if [ "$ref" = "main" ]; then
      git -C "$dest" pull --ff-only origin main
    fi
  else
    mkdir -p "$(dirname "$dest")"
    git clone --depth 1 --branch "$ref" "$repo" "$dest"
  fi
else
  echo "[x] git is required for install.sh" >&2
  exit 69
fi

chmod 0755 "$dest/bin/copyfail-guard.sh"
ln -sf "$dest/bin/copyfail-guard.sh" "$bin"
echo "[+] Installed: $bin"
echo "[i] Source: $repo ($ref)"
echo "[i] Try: sudo copyfail-guard status"
