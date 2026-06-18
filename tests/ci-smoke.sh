#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

bash -n bin/copyfail-guard.sh
bin/copyfail-guard.sh --no-logo help >/tmp/cfg-help.txt
grep -q 'assess' /tmp/cfg-help.txt
grep -q 'doctor' /tmp/cfg-help.txt
bin/copyfail-guard.sh --no-logo version | grep -q '0.2.0'
bin/copyfail-guard.sh --version | grep -q '0.2.0'
bin/copyfail-guard.sh --no-logo doctor >/tmp/cfg-doctor.txt 2>&1 || true
grep -q 'Doctor verdict' /tmp/cfg-doctor.txt
bin/copyfail-guard.sh doctor --json >/tmp/cfg-doctor.json 2>/tmp/cfg-doctor.err || true
python3 -m json.tool /tmp/cfg-doctor.json >/dev/null
grep -q '"command": "doctor"' /tmp/cfg-doctor.json
grep -Fq "| \`10\` | AF_ALG socket creation was permitted |" docs/seccomp-validation.md
grep -q 'sys.exit(10)' tools/afalg-socket-test.py
grep -q 'COPYFAIL_GUARD_REF' scripts/install.sh
grep -q 'Expected AF_ALG to be blocked' examples/github-actions-seccomp-check.yml
grep -q "grep -q '^BLOCKED:'" examples/github-actions-seccomp-check.yml

bin/copyfail-guard.sh --no-logo seccomp-docker /tmp/copyfail-emergency.json >/tmp/cfg-seccomp.txt
python3 -m json.tool /tmp/copyfail-emergency.json >/dev/null
python3 - <<'PY'
import json
p=json.load(open('/tmp/copyfail-emergency.json'))
rule=p['syscalls'][0]
assert rule['names']==['socket']
assert rule['action']=='SCMP_ACT_ERRNO'
assert rule['args'][0]['index']==0
assert rule['args'][0]['value']==38
PY

cat >/tmp/base-seccomp.json <<'JSON'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {"names": ["read", "write", "socket"], "action": "SCMP_ACT_ALLOW"}
  ]
}
JSON
bin/copyfail-guard.sh --no-logo seccomp-patch /tmp/base-seccomp.json /tmp/copyfail-patched.json >/tmp/cfg-patch.txt
python3 -m json.tool /tmp/copyfail-patched.json >/dev/null
python3 - <<'PY'
import json
p=json.load(open('/tmp/copyfail-patched.json'))
assert p['syscalls'][0]['names']==['socket']
assert p['syscalls'][0]['action']=='SCMP_ACT_ERRNO'
assert p['syscalls'][0]['args'][0]['value']==38
assert p['syscalls'][1]['names']==['socket']
assert p['syscalls'][1]['action']=='SCMP_ACT_ALLOW'
assert p['syscalls'][1]['args'][0]['op']=='SCMP_CMP_NE'
assert 'socket' not in p['syscalls'][2]['names']
PY

bin/copyfail-guard.sh --no-logo --dry-run seccomp-docker /tmp/should-not-exist.json >/tmp/cfg-dry.txt 2>&1
[[ ! -e /tmp/should-not-exist.json ]]

echo "ci-smoke: ok"
