#!/bin/bash
# buddy-doctor — one-shot diagnostic of the entire buddy chain.
# Run anytime to see what's up vs down.

GREEN='\033[1;32m'; RED='\033[1;31m'; YEL='\033[1;33m'; CYAN='\033[1;36m'; NC='\033[0m'
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; }
warn() { printf "  ${YEL}!${NC} %s\n" "$1"; }
sec()  { printf "\n${CYAN}== %s ==${NC}\n" "$1"; }

sec "Bridge process"
if pgrep -f "bridge\.py" > /dev/null; then
  pid=$(pgrep -f "bridge\.py" | head -1)
  ok  "running (pid $pid)"
else
  fail "NOT running — start with: bridge/launch.sh   or load the launchd plist"
  exit 1
fi

sec "Bridge HTTP"
if status=$(curl -s --max-time 2 http://127.0.0.1:5151/status); then
  ok  "http://127.0.0.1:5151 responsive"
  echo "       $status"
else
  fail "http listener unreachable"
  exit 1
fi

sec "BLE link to Core2"
if echo "$status" | grep -q '"connected": true'; then
  ok  "BLE connected"
else
  fail "BLE NOT connected — bridge is up but no Core2 paired"
  warn "device asleep? out of range? still bonded to Claude Desktop?"
fi

sec "Local Claude Code hook wired"
hook_path=$(python3 -c "import json; s=json.load(open('/Users/bytedance/.claude/settings.json')); ph=s.get('hooks',{}).get('PreToolUse',[]);
for e in ph:
    for h in e.get('hooks',[]):
        if 'buddy_hook.py' in h.get('command',''):
            print(h['command']); break" 2>/dev/null)
if [ -n "$hook_path" ]; then
  ok  "PreToolUse hook present in ~/.claude/settings.json"
  echo "       $hook_path"
else
  fail "hook NOT registered in ~/.claude/settings.json"
fi

sec "End-to-end ping (5s timeout)"
ping_resp=$(curl -s --max-time 8 -X POST -H "Content-Type: application/json" \
  -d '{"tool":"doctor","hint":"ignore","timeout":5}' \
  http://127.0.0.1:5151/notify 2>/dev/null)
if echo "$ping_resp" | grep -q '"decision":"offline"'; then
  fail "bridge says offline (no Core2)"
elif echo "$ping_resp" | grep -q '"decision"'; then
  ok  "round-trip works — got: $ping_resp"
  warn "tip: that prompt also showed on your Core2; it auto-resolved on timeout"
else
  fail "no response from bridge"
fi

sec "Remote SSH tunnel (optional)"
if [ -f /tmp/krb5cc_buddy ] && klist -c FILE:/tmp/krb5cc_buddy >/dev/null 2>&1; then
  ok  "krb5 ticket cache: /tmp/krb5cc_buddy"
else
  warn "no Kerberos ticket — non-interactive ssh won't work; user must kinit"
fi
if KRB5CCNAME=FILE:/tmp/krb5cc_buddy ssh -o BatchMode=yes -o ConnectTimeout=5 candy \
   "curl -s --max-time 3 http://localhost:5151/status" 2>/dev/null | grep -q connected; then
  ok  "remote 'candy' can reach bridge through reverse tunnel"
else
  warn "remote bridge access not verified — either 'candy' is offline or no -R tunnel active"
  warn "OK to ignore if you only use Claude Code locally"
fi

echo
ok "doctor done"
