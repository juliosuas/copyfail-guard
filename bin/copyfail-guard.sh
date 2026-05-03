#!/usr/bin/env bash
# copyfail-guard.sh — CVE-2026-31431 "Copy Fail" mitigation helper
# Author: Julio César Suástegui Calderón
# License: MIT

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="CopyFail Guard"
APP_SLUG="copyfail-guard"
CVE="CVE-2026-31431"
MODULE="algif_aead"
MODPROBE_CONF="/etc/modprobe.d/99-copyfail-guard.conf"
DEFAULT_SECCOMP_OUT="./copyfail-afalg-seccomp.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
NO_COLOR="${NO_COLOR:-}"
if [[ -n "$NO_COLOR" || ! -t 1 ]]; then RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; DIM=''; NC=''; fi

log()  { printf "%b[+]%b %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YELLOW" "$NC" "$*" >&2; }
err()  { printf "%b[x]%b %s\n" "$RED" "$NC" "$*" >&2; }
info() { printf "%b[i]%b %s\n" "$BLUE" "$NC" "$*"; }

usage() {
  cat <<'EOF'
Usage: copyfail-guard <command> [options]

Commands:
  status                 Inspect host exposure indicators for CVE-2026-31431
  mitigate               Persistently disable algif_aead and unload it if loaded
  verify                 Verify mitigation is active
  rollback               Remove CopyFail Guard modprobe mitigation
  seccomp-docker [FILE]  Generate emergency AF_ALG-deny seccomp profile
  seccomp-patch BASE OUT Patch an existing seccomp profile to deny AF_ALG
  k8s-example            Print Kubernetes seccomp usage example
  help                   Show this help

Options:
  --dry-run              Show what would change without writing system files
  --yes                  Non-interactive confirmation for mitigate/rollback
  --no-logo              Do not print ASCII banner

Examples:
  sudo ./bin/copyfail-guard.sh status
  sudo ./bin/copyfail-guard.sh mitigate --yes
  ./bin/copyfail-guard.sh seccomp-patch docker-default.json copyfail-seccomp.json
  docker run --security-opt seccomp=./copyfail-seccomp.json IMAGE

Notes:
  - This is a mitigation helper, not an exploit checker.
  - Patch and reboot remain the correct final fix.
  - Blocking algif_aead should not affect LUKS/dm-crypt, SSH, OpenSSL defaults,
    kTLS, IPsec/XFRM, or normal in-kernel crypto consumers.
EOF
}

logo() {
  cat <<'EOF'
   ______                 ______      _ __   ______                     __
  / ____/___  ____  __  _/ ____/___ _(_) /  / ____/_  ______ __________/ /
 / /   / __ \/ __ \/ / / / /_  / __ `/ / /  / / __/ / / / __ `/ ___/ __  /
/ /___/ /_/ / /_/ / /_/ / __/ / /_/ / / /  / /_/ / /_/ / /_/ / /  / /_/ /
\____/\____/ .___/\__, /_/    \__,_/_/_/   \____/\__,_/\__,_/_/   \__,_/
          /_/    /____/
        CVE-2026-31431 hardening for Linux fleets
EOF
}

print_banner() {
  [[ "${NO_LOGO:-0}" == "1" ]] && return 0
  printf "%b" "$BOLD"; logo; printf "%b" "$NC"
  printf "%s\n\n" "        Patch fast. Mitigate faster. Verify always."
}

need_linux() {
  if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
    err "This command is intended for Linux hosts. Current OS: $(uname -s 2>/dev/null || echo unknown)"
    exit 2
  fi
}

need_root_for_write() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Root privileges required. Re-run with sudo."
    exit 3
  fi
}

confirm() {
  local prompt="$1"
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "%b[dry-run]%b" "$YELLOW" "$NC"
    for arg in "$@"; do printf " %q" "$arg"; done
    printf "\n"
  else
    "$@"
  fi
}

os_release_value() {
  local key="$1"
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  case "$key" in
    PRETTY_NAME) printf '%s' "${PRETTY_NAME:-unknown}" ;;
    ID) printf '%s' "${ID:-unknown}" ;;
    VERSION_ID) printf '%s' "${VERSION_ID:-unknown}" ;;
  esac
}

module_available() {
  modinfo "$MODULE" >/dev/null 2>&1
}

module_loaded() {
  lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$MODULE"
}

modprobe_block_active() {
  local found=1
  if command -v modprobe >/dev/null 2>&1; then
    if modprobe -n -v "$MODULE" 2>/dev/null | grep -Eq 'install[[:space:]]+(/bin/false|/usr/bin/false|false)'; then
      found=0
    fi
  fi
  grep -RhsE "^[[:space:]]*install[[:space:]]+$MODULE[[:space:]]+(/bin/false|/usr/bin/false|false)" /etc/modprobe.d /run/modprobe.d /lib/modprobe.d /usr/lib/modprobe.d >/dev/null 2>&1 && found=0
  return "$found"
}

check_afalg_users() {
  if command -v lsof >/dev/null 2>&1; then
    lsof 2>/dev/null | grep -i 'AF_ALG' || true
  elif command -v ss >/dev/null 2>&1; then
    ss -xa 2>/dev/null | grep -i 'alg' || true
  fi
}

status() {
  need_linux
  print_banner
  info "Host: $(hostname 2>/dev/null || echo unknown)"
  info "OS: $(os_release_value PRETTY_NAME 2>/dev/null || echo unknown)"
  info "Kernel: $(uname -r) ($(uname -m))"
  printf "\n"

  if module_available; then
    warn "$MODULE is available on this kernel. Treat as exposed until patched or mitigated."
  else
    log "$MODULE is not available via modinfo. Exposure may already be reduced or built differently."
  fi

  if module_loaded; then
    warn "$MODULE is currently loaded. Unload after confirming no AF_ALG consumers."
  else
    log "$MODULE is not currently loaded."
  fi

  if modprobe_block_active; then
    log "Persistent modprobe block is active for $MODULE."
  else
    warn "No persistent modprobe block detected for $MODULE."
  fi

  printf "\n%bAF_ALG consumers:%b\n" "$BOLD" "$NC"
  local users
  users="$(check_afalg_users || true)"
  if [[ -n "$users" ]]; then
    printf "%s\n" "$users"
    warn "Review these processes before unloading $MODULE."
  else
    log "No obvious AF_ALG consumers found with available tools."
  fi

  printf "\n%bRecommended order:%b\n" "$BOLD" "$NC"
  printf "  1. Install vendor kernel update containing upstream fix/revert.\n"
  printf "  2. Reboot into patched kernel.\n"
  printf "  3. Until then: sudo %s mitigate --yes\n" "$0"
  printf "  4. For containers/CI: block AF_ALG socket creation with seccomp.\n"
}

mitigate() {
  need_linux; need_root_for_write; print_banner
  warn "This will write $MODPROBE_CONF and try to unload $MODULE if currently loaded."
  confirm "Apply CopyFail Guard mitigation now?" || { warn "Aborted."; exit 1; }

  local content
  content="# Managed by CopyFail Guard for $CVE\n# Blocks vulnerable AF_ALG AEAD frontend until patched kernel is deployed.\ninstall $MODULE /bin/false\nblacklist $MODULE\n"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "%b[dry-run]%b write %s:\n%s" "$YELLOW" "$NC" "$MODPROBE_CONF" "$content"
  else
    umask 022
    printf "%b" "$content" > "$MODPROBE_CONF"
    chmod 0644 "$MODPROBE_CONF"
    log "Wrote $MODPROBE_CONF"
  fi

  if module_loaded; then
    warn "$MODULE is loaded; attempting rmmod."
    if [[ -n "$(check_afalg_users || true)" ]]; then
      warn "AF_ALG consumers detected. rmmod may fail; stop consumers or reboot after applying mitigation."
    fi
    if run_cmd rmmod "$MODULE" 2>/dev/null; then
      log "Unloaded $MODULE"
    else
      warn "Could not unload $MODULE now. Persistent block is installed; reboot or stop AF_ALG consumers."
    fi
  else
    log "$MODULE was not loaded."
  fi

  verify || true
}

verify() {
  need_linux
  print_banner
  local ok=0
  if modprobe_block_active; then
    log "PASS: modprobe blocks $MODULE."
  else
    err "FAIL: modprobe block for $MODULE is not active."
    ok=1
  fi
  if module_loaded; then
    err "FAIL: $MODULE is still loaded. Reboot or stop consumers and run: sudo rmmod $MODULE"
    ok=1
  else
    log "PASS: $MODULE is not loaded."
  fi
  if [[ "$ok" -eq 0 ]]; then
    printf "\n%bShield up.%b $CVE interim mitigation is active. Still patch/reboot ASAP.\n" "$GREEN$BOLD" "$NC"
  fi
  return "$ok"
}

rollback() {
  need_linux; need_root_for_write; print_banner
  warn "This removes only CopyFail Guard's modprobe file: $MODPROBE_CONF"
  confirm "Rollback mitigation?" || { warn "Aborted."; exit 1; }
  if [[ -e "$MODPROBE_CONF" ]]; then
    run_cmd rm -f "$MODPROBE_CONF"
    log "Removed $MODPROBE_CONF"
  else
    warn "$MODPROBE_CONF not found. Nothing to remove."
  fi
  warn "Rollback does not reload $MODULE. Reboot or modprobe manually if you explicitly need AF_ALG AEAD."
}

generate_seccomp() {
  local out="${1:-$DEFAULT_SECCOMP_OUT}"
  cat > "$out" <<'JSON'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32",
    "SCMP_ARCH_AARCH64",
    "SCMP_ARCH_ARM"
  ],
  "syscalls": [
    {
      "names": ["socket"],
      "action": "SCMP_ACT_ERRNO",
      "args": [
        {
          "index": 0,
          "value": 38,
          "op": "SCMP_CMP_EQ"
        }
      ],
      "comment": "Block AF_ALG sockets to mitigate CVE-2026-31431 Copy Fail in containers/CI"
    }
  ]
}
JSON
  log "Wrote emergency Docker/Podman seccomp profile: $out"
  cat <<EOF

Use only if you do not have an existing runtime seccomp baseline:
  docker run --security-opt seccomp=$out IMAGE
  podman run --security-opt seccomp=$out IMAGE

Important: this emergency profile blocks AF_ALG but otherwise allows syscalls.
Senior/default-safe path: use 'seccomp-patch BASE OUT' to merge the AF_ALG denial into your existing Docker/Podman/Kubernetes seccomp profile.
EOF
}

patch_seccomp() {
  local base="${1:-}" out="${2:-}"
  if [[ -z "$base" || -z "$out" ]]; then
    err "Usage: copyfail-guard seccomp-patch BASE_PROFILE OUT_PROFILE"
    exit 64
  fi
  if [[ ! -r "$base" ]]; then
    err "Cannot read base seccomp profile: $base"
    exit 66
  fi
  python3 - "$base" "$out" <<'PY'
import json, sys
base, out = sys.argv[1], sys.argv[2]
with open(base, 'r', encoding='utf-8') as f:
    profile = json.load(f)
rule = {
    "names": ["socket"],
    "action": "SCMP_ACT_ERRNO",
    "args": [{"index": 0, "value": 38, "op": "SCMP_CMP_EQ"}],
    "comment": "CopyFail Guard: block AF_ALG sockets for CVE-2026-31431"
}
profile.setdefault("syscalls", [])
# Put deny rule first; libseccomp evaluates matching rules by syscall and args.
profile["syscalls"] = [r for r in profile["syscalls"] if not (
    "socket" in r.get("names", []) and any(a.get("index") == 0 and a.get("value") == 38 for a in r.get("args", []))
)]
profile["syscalls"].insert(0, rule)
with open(out, 'w', encoding='utf-8') as f:
    json.dump(profile, f, indent=2)
    f.write("\n")
PY
  log "Patched seccomp profile: $out"
  info "Use: docker run --security-opt seccomp=$out IMAGE"
} 

k8s_example() {
  cat <<'EOF'
# Kubernetes example: use a Localhost seccomp profile that blocks AF_ALG sockets.
# 1) Place copyfail-afalg-seccomp.json on each node under the kubelet seccomp root,
#    commonly: /var/lib/kubelet/seccomp/profiles/copyfail-afalg-seccomp.json
# 2) Reference it from pods that run untrusted code:
apiVersion: v1
kind: Pod
metadata:
  name: copyfail-guarded-workload
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/copyfail-afalg-seccomp.json
  containers:
    - name: app
      image: alpine:latest
      command: ["sh", "-c", "echo AF_ALG blocked; sleep 3600"]
EOF
}

main() {
  local cmd="${1:-help}"; shift || true
  DRY_RUN=0; ASSUME_YES=0; NO_LOGO=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --no-logo) NO_LOGO=1 ;;
      -h|--help) cmd="help" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  if [[ ${#positional[@]} -gt 0 ]]; then
    set -- "${positional[@]}"
  else
    set --
  fi

  case "$cmd" in
    status) status ;;
    mitigate) mitigate ;;
    verify) verify ;;
    rollback) rollback ;;
    seccomp-docker) generate_seccomp "${1:-$DEFAULT_SECCOMP_OUT}" ;;
    seccomp-patch) patch_seccomp "${1:-}" "${2:-}" ;;
    k8s-example) k8s_example ;;
    help|--help|-h) print_banner; usage ;;
    *) err "Unknown command: $cmd"; usage; exit 64 ;;
  esac
}

main "$@"
