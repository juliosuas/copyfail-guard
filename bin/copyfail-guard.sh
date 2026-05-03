#!/usr/bin/env bash
# copyfail-guard.sh — CVE-2026-31431 "Copy Fail" mitigation helper
# Author: Julio César Suástegui Calderón
# License: MIT

set -Eeuo pipefail
IFS=$'\n\t'

CVE="CVE-2026-31431"
MODULE="algif_aead"
MODPROBE_CONF="/etc/modprobe.d/99-copyfail-guard.conf"
DEFAULT_SECCOMP_OUT="./copyfail-afalg-seccomp.json"
VERSION="0.2.0"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
NO_COLOR="${NO_COLOR:-}"
if [[ -n "$NO_COLOR" || ! -t 1 ]]; then RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; DIM=''; BOLD=''; NC=''; fi

log()  { printf "%b[+]%b %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YELLOW" "$NC" "$*" >&2; }
err()  { printf "%b[x]%b %s\n" "$RED" "$NC" "$*" >&2; }
info() { printf "%b[i]%b %s\n" "$BLUE" "$NC" "$*"; }

usage() {
  cat <<'EOF'
Usage: copyfail-guard <command> [options]

Commands:
  assess                 Safe exposure assessment with machine-friendly exit codes
  status                 Inspect host exposure indicators for CVE-2026-31431
  doctor                 Check local dependencies and runtime readiness
  mitigate               Persistently disable algif_aead and unload it if loaded
  verify                 Verify mitigation is active
  rollback               Remove CopyFail Guard modprobe mitigation
  seccomp-docker [FILE]  Generate emergency AF_ALG-deny seccomp profile
  seccomp-patch BASE OUT Patch an existing seccomp profile to deny AF_ALG
  k8s-example            Print Kubernetes seccomp usage example
  version                Print version
  help                   Show this help

Options:
  --dry-run              Show what would change without writing system files
  --yes                  Non-interactive confirmation for mitigate/rollback
  --no-logo              Do not print ASCII banner
  --json                 Emit JSON for supported commands: assess, doctor

Examples:
  sudo ./bin/copyfail-guard.sh assess
  sudo ./bin/copyfail-guard.sh status
  sudo ./bin/copyfail-guard.sh mitigate --yes
  ./bin/copyfail-guard.sh seccomp-patch docker-default.json copyfail-seccomp.json
  docker run --security-opt seccomp=./copyfail-seccomp.json IMAGE

Notes:
  - This is a mitigation helper, not an exploit checker.
  - assess is a safe exposure check; it does not attempt exploitation.
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
EOF
}

print_banner() {
  [[ "${NO_LOGO:-0}" == "1" ]] && return 0
  printf "%b" "$CYAN$BOLD"; logo; printf "%b" "$NC"
  printf "%b%s%b\n" "$MAGENTA$BOLD" "        @juliosuas" "$NC"
  printf "%b%s%b\n" "$DIM" "        CVE-2026-31431 hardening for Linux fleets" "$NC"
  printf "%b%s%b\n\n" "$GREEN$BOLD" "        Patch fast. Mitigate faster. Verify always." "$NC"
}

need_linux() {
  if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
    err "This command is intended for Linux hosts. Current OS: $(uname -s 2>/dev/null || echo unknown)"
    exit 2
  fi
}

need_root_for_write() {
  [[ "${DRY_RUN:-0}" == "1" ]] && return 0
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

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command not found: $cmd"
    exit 69
  fi
}

os_release_value() {
  local key="$1"
  [[ -r /etc/os-release ]] || return 1
  # shellcheck source=/dev/null
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

module_builtin() {
  local filename=""
  if command -v modinfo >/dev/null 2>&1; then
    filename="$(modinfo -F filename "$MODULE" 2>/dev/null || true)"
    [[ "$filename" == "(builtin)" ]] && return 0
  fi
  local release
  release="$(uname -r)"
  grep -RhsE "(^|/)$MODULE\.ko(\.(xz|zst|gz))?$|kernel/.*/$MODULE\.ko" \
    "/lib/modules/$release/modules.builtin" \
    "/usr/lib/modules/$release/modules.builtin" >/dev/null 2>&1
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
  grep -RhsE "^[[:space:]]*install[[:space:]]+${MODULE}[[:space:]]+(/bin/false|/usr/bin/false|false)" /etc/modprobe.d /run/modprobe.d /lib/modprobe.d /usr/lib/modprobe.d >/dev/null 2>&1 && found=0
  return "$found"
}

check_afalg_users() {
  if command -v lsof >/dev/null 2>&1; then
    lsof 2>/dev/null | grep -i 'AF_ALG' || true
  elif command -v ss >/dev/null 2>&1; then
    ss -xa 2>/dev/null | grep -i 'alg' || true
  fi
}

doctor() {
  if [[ "${OUTPUT_JSON:-0}" == "1" ]]; then
    local failed=0
    local required_missing=()
    local host_missing=()
    local optional_missing_cmds=()
    for cmd in bash grep awk mktemp install uname; do command -v "$cmd" >/dev/null 2>&1 || { required_missing+=("$cmd"); failed=1; }; done
    for cmd in modinfo modprobe lsmod rmmod; do command -v "$cmd" >/dev/null 2>&1 || host_missing+=("$cmd"); done
    for cmd in python3 lsof ss docker podman; do command -v "$cmd" >/dev/null 2>&1 || optional_missing_cmds+=("$cmd"); done
    python3 - "$failed" "$(uname -s 2>/dev/null || echo unknown)" "${required_missing[*]-}" "${host_missing[*]-}" "${optional_missing_cmds[*]-}" <<'PY'
import json, sys
failed=int(sys.argv[1])
print(json.dumps({
  "tool": "copyfail-guard",
  "command": "doctor",
  "ready": failed == 0,
  "os": sys.argv[2],
  "required_missing": sys.argv[3].split() if sys.argv[3] else [],
  "host_tool_missing": sys.argv[4].split() if sys.argv[4] else [],
  "optional_missing": sys.argv[5].split() if sys.argv[5] else []
}, indent=2))
PY
    return "$failed"
  fi
  print_banner
  local failed=0
  local optional_missing=0
  local required_missing=()
  local host_missing=()
  local optional_missing_cmds=()

  printf "%bRequired:%b\n" "$BOLD" "$NC"
  for cmd in bash grep awk mktemp install uname; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log "$cmd found: $(command -v "$cmd")"
    else
      err "$cmd missing"
      required_missing+=("$cmd")
      failed=1
    fi
  done

  printf "\n%bLinux host tools:%b\n" "$BOLD" "$NC"
  for cmd in modinfo modprobe lsmod rmmod; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log "$cmd found: $(command -v "$cmd")"
    else
      warn "$cmd missing (host mitigation/status may be limited)"
      host_missing+=("$cmd")
      optional_missing=1
    fi
  done

  printf "\n%bOptional:%b\n" "$BOLD" "$NC"
  for cmd in python3 lsof ss docker podman; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log "$cmd found: $(command -v "$cmd")"
    else
      warn "$cmd missing (optional feature may be unavailable)"
      optional_missing_cmds+=("$cmd")
      optional_missing=1
    fi
  done

  if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
    warn "Current OS is $(uname -s 2>/dev/null || echo unknown). Host mitigation commands require Linux; seccomp profile generation can still be used."
  fi

  if [[ "$failed" -eq 0 ]]; then
    printf "\n%bDoctor verdict:%b ready" "$GREEN$BOLD" "$NC"
    [[ "$optional_missing" -eq 1 ]] && printf " with optional limitations"
    printf ".\n"
  fi
  return "$failed"
}

assess() {
  need_linux
  [[ "${OUTPUT_JSON:-0}" == "1" ]] || print_banner
  local verdict="UNKNOWN"
  local code=20
  local reasons=()
  local actions=()

  if [[ "${OUTPUT_JSON:-0}" != "1" ]]; then
    info "Safe assessment mode: no exploit attempt, no page-cache writes, no privilege escalation."
    info "This evaluates exposure and mitigation controls; only vendor patch + reboot resolves the CVE."
    printf "\n"
  fi

  if module_builtin; then
    verdict="EXPOSED_BUILTIN_REBOOT_REQUIRED"
    code=12
    reasons+=("$MODULE appears built into this kernel; modprobe.d/rmmod cannot disable it")
    actions+=("Install vendor patched kernel and reboot")
    actions+=("Use seccomp to deny socket(AF_ALG) for untrusted containers/CI while patching")
  elif module_available; then
    if module_loaded; then
      if modprobe_block_active; then
        verdict="PARTIALLY_MITIGATED_REBOOT_RECOMMENDED"
        code=11
        reasons+=("$MODULE is loaded even though a persistent block is present")
        actions+=("Reboot or stop AF_ALG consumers and unload $MODULE")
      else
        verdict="EXPOSED_MITIGATION_AVAILABLE"
        code=10
        reasons+=("$MODULE is available and currently loaded")
        actions+=("Run: sudo $0 mitigate --yes")
      fi
    else
      if modprobe_block_active; then
        verdict="INTERIM_MITIGATED_PATCH_STILL_REQUIRED"
        code=1
        reasons+=("$MODULE is available but not loaded, and persistent modprobe block is active")
        actions+=("Keep patch/reboot plan; mitigation is not a permanent fix")
      else
        verdict="EXPOSED_AUTOLOAD_POSSIBLE"
        code=10
        reasons+=("$MODULE is available and can likely be autoloaded")
        actions+=("Run: sudo $0 mitigate --yes")
      fi
    fi
  else
    if modprobe_block_active; then
      verdict="LOW_OBVIOUS_EXPOSURE_BLOCK_PRESENT"
      code=0
      reasons+=("$MODULE is not available via modinfo and a persistent block is present")
      actions+=("Confirm vendor patch status through fleet inventory")
    else
      verdict="LOW_OBVIOUS_EXPOSURE_UNCONFIRMED_PATCH_STATUS"
      code=0
      reasons+=("$MODULE is not available via modinfo")
      actions+=("Confirm vendor patch status; absence of this module is not proof of patched kernel")
    fi
  fi

  if [[ "${OUTPUT_JSON:-0}" == "1" ]]; then
    local reasons_json actions_json
    reasons_json="$(printf '%s\n' "${reasons[@]-}" | python3 -c 'import json,sys; print(json.dumps([line.rstrip("\\n") for line in sys.stdin if line.rstrip("\\n")]))')"
    actions_json="$(printf '%s\n' "${actions[@]-}" | python3 -c 'import json,sys; print(json.dumps([line.rstrip("\\n") for line in sys.stdin if line.rstrip("\\n")]))')"
    python3 - "$verdict" "$code" "$reasons_json" "$actions_json" <<'PY'
import json, sys
print(json.dumps({
  "tool": "copyfail-guard",
  "command": "assess",
  "cve": "CVE-2026-31431",
  "module": "algif_aead",
  "verdict": sys.argv[1],
  "exit_code": int(sys.argv[2]),
  "safe_assessment": True,
  "exploit_attempted": False,
  "final_resolution": "vendor patched kernel + reboot",
  "reasons": json.loads(sys.argv[3]),
  "next_actions": json.loads(sys.argv[4])
}, indent=2))
PY
  else
    printf "%bVerdict:%b %s\n" "$BOLD" "$NC" "$verdict"
    printf "%bExit code:%b %s\n" "$BOLD" "$NC" "$code"
    printf "\n%bReasons:%b\n" "$BOLD" "$NC"
    for r in "${reasons[@]-}"; do printf "  - %s\n" "$r"; done
    printf "\n%bNext actions:%b\n" "$BOLD" "$NC"
    for a in "${actions[@]-}"; do printf "  - %s\n" "$a"; done
    printf "\n%bReminder:%b CopyFail Guard mitigates exposure. The durable resolution is patched kernel + reboot.\n" "$YELLOW$BOLD" "$NC"
  fi
  return "$code"
}

version() {
  printf 'CopyFail Guard %s\n' "$VERSION"
}

status() {
  need_linux
  print_banner
  info "Host: $(hostname 2>/dev/null || echo unknown)"
  info "OS: $(os_release_value PRETTY_NAME 2>/dev/null || echo unknown)"
  info "Kernel: $(uname -r) ($(uname -m))"
  printf "\n"

  if module_builtin; then
    err "$MODULE appears built into this kernel. modprobe.d/rmmod cannot disable built-in code. Patch/reboot and use seccomp for untrusted workloads."
  elif module_available; then
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
  if module_builtin; then
    err "$MODULE appears built into this kernel. Host module mitigation cannot unload or block built-in code."
    warn "Use vendor kernel patch/reboot immediately and apply seccomp to containers/CI while patching."
    exit 4
  fi
  warn "This will write $MODPROBE_CONF and try to unload $MODULE if currently loaded."
  confirm "Apply CopyFail Guard mitigation now?" || { warn "Aborted."; exit 1; }

  local content
  content="# Managed by CopyFail Guard for $CVE\n# Blocks vulnerable AF_ALG AEAD frontend until patched kernel is deployed.\ninstall $MODULE /bin/false\nblacklist $MODULE\n"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "%b[dry-run]%b write %s:\n%s" "$YELLOW" "$NC" "$MODPROBE_CONF" "$content"
  else
    umask 022
    mkdir -p "$(dirname "$MODPROBE_CONF")"
    if [[ -L "$MODPROBE_CONF" ]]; then
      err "$MODPROBE_CONF is a symlink; refusing to overwrite. Remove it manually if intentional."
      exit 73
    fi
    local tmp
    tmp="$(mktemp "${MODPROBE_CONF}.tmp.XXXXXX")"
    printf "%b" "$content" > "$tmp"
    install -m 0644 "$tmp" "$MODPROBE_CONF"
    rm -f "$tmp"
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

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    warn "Dry run complete; verification skipped because no changes were applied."
  else
    verify || true
  fi
}

verify() {
  need_linux
  print_banner
  local ok=0
  if module_builtin; then
    err "FAIL: $MODULE appears built into this kernel; modprobe mitigation cannot disable it."
    ok=1
  fi
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
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    warn "Dry run: would write emergency seccomp profile to $out"
    return 0
  fi
  cat > "$out" <<'JSON'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32",
    "SCMP_ARCH_AARCH64",
    "SCMP_ARCH_ARM",
    "SCMP_ARCH_PPC64LE",
    "SCMP_ARCH_S390X",
    "SCMP_ARCH_RISCV64"
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
  need_cmd python3
  if [[ -z "$base" || -z "$out" ]]; then
    err "Usage: copyfail-guard seccomp-patch BASE_PROFILE OUT_PROFILE"
    exit 64
  fi
  if [[ ! -r "$base" ]]; then
    err "Cannot read base seccomp profile: $base"
    exit 66
  fi
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    warn "Dry run: would patch $base and write $out"
    return 0
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
new_syscalls = []
had_unconditional_socket_allow = False
for entry in profile["syscalls"]:
    names = entry.get("names", [])
    if "socket" not in names:
        new_syscalls.append(entry)
        continue
    args = entry.get("args", [])
    is_existing_afalg_rule = any(a.get("index") == 0 and a.get("value") == 38 for a in args)
    if is_existing_afalg_rule:
        continue
    if entry.get("action") == "SCMP_ACT_ALLOW" and not args:
        had_unconditional_socket_allow = True
        remaining = [n for n in names if n != "socket"]
        if remaining:
            kept = dict(entry)
            kept["names"] = remaining
            new_syscalls.append(kept)
        continue
    # Preserve non-trivial socket rules. Operators should validate generated
    # profiles in their runtime because seccomp baselines can be customized.
    new_syscalls.append(entry)

patched = [rule]
if had_unconditional_socket_allow:
    patched.append({
        "names": ["socket"],
        "action": "SCMP_ACT_ALLOW",
        "args": [{"index": 0, "value": 38, "op": "SCMP_CMP_NE"}],
        "comment": "CopyFail Guard: preserve socket() except AF_ALG"
    })
profile["syscalls"] = patched + new_syscalls
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
  local cmd=""
  DRY_RUN=0; ASSUME_YES=0; NO_LOGO=0; OUTPUT_JSON=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --no-logo) NO_LOGO=1 ;;
      --json) OUTPUT_JSON=1; NO_LOGO=1 ;;
      -h|--help) cmd="help" ;;
      assess|status|doctor|mitigate|verify|rollback|seccomp-docker|seccomp-patch|k8s-example|version|help)
        if [[ -z "$cmd" ]]; then cmd="$1"; else positional+=("$1"); fi ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  cmd="${cmd:-help}"
  if [[ ${#positional[@]} -gt 0 ]]; then
    set -- "${positional[@]}"
  else
    set --
  fi

  case "$cmd" in
    assess) assess ;;
    status) status ;;
    doctor) doctor ;;
    mitigate) mitigate ;;
    verify) verify ;;
    rollback) rollback ;;
    seccomp-docker) generate_seccomp "${1:-$DEFAULT_SECCOMP_OUT}" ;;
    seccomp-patch) patch_seccomp "${1:-}" "${2:-}" ;;
    k8s-example) k8s_example ;;
    version) version ;;
    help|--help|-h) print_banner; usage ;;
    *) err "Unknown command: $cmd"; usage; exit 64 ;;
  esac
}

main "$@"
