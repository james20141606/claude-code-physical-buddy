#!/bin/bash
# Deploy buddy_hook.py to a remote host and write its ~/.claude/settings.json.
# Usage:   ./deploy-remote.sh [ssh-host]    (default: candy)
#
# Assumes the SSH alias is configured (see ~/.ssh/config "Host candy").
# Idempotent: re-running won't duplicate hooks.

set -e
HOST="${1:-candy}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo ">> copying buddy_hook.py to $HOST:~/buddy_hook.py"
scp -q "$HERE/buddy_hook.py" "$HOST:buddy_hook.py"

echo ">> updating ~/.claude/settings.json on $HOST"
ssh "$HOST" python3 - <<'PYEOF'
import json, os, pathlib
p = pathlib.Path.home() / ".claude" / "settings.json"
p.parent.mkdir(exist_ok=True)
s = json.loads(p.read_text()) if p.exists() else {}
hooks = s.setdefault("hooks", {})
existing = hooks.get("PreToolUse", [])
already = any(
    "buddy_hook.py" in h.get("command", "")
    for entry in existing
    for h in entry.get("hooks", [])
)
if not already:
    existing.append({
        "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch",
        "hooks": [{
            "type": "command",
            "command": "python3 " + str(pathlib.Path.home() / "buddy_hook.py"),
        }],
    })
    hooks["PreToolUse"] = existing
    p.write_text(json.dumps(s, indent=2))
    print("merged buddy hook into", p)
else:
    print("buddy hook already present at", p)
PYEOF

echo ">> done. test:   ssh $HOST 'cat ~/.claude/settings.json'"
echo ">> remember: ssh in with the 'candy' alias so RemoteForward 5151 is active"
