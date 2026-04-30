#!/usr/bin/env python3
"""
Claude Code PreToolUse hook — asks the Core2 buddy for approval before
running a tool, via the local bridge.py HTTP endpoint.

Wire it up in .claude/settings.json (see settings.example.json).

Behavior:
  - On hook fire, reads Claude Code's tool-call event from stdin.
  - POSTs {tool, hint} to BUDDY_BRIDGE_URL (default localhost:5151).
  - Bridge displays prompt on Core2, blocks until A or B is pressed.
  - "allow" -> emit hookSpecificOutput allowing the tool without
              Claude Code's own permission prompt.
  - "deny"  -> emit hookSpecificOutput denying the tool.
  - Bridge unreachable / offline / timeout -> visible WARNING to
              stderr and exit 0 so the tool falls back to Claude
              Code's normal permission flow.

Environment:
  BUDDY_BRIDGE_URL   POST endpoint  (default http://127.0.0.1:5151/notify)
  BUDDY_TIMEOUT      seconds to wait for a button press (default 60)
  BUDDY_STRICT       if "1", fail closed (deny) instead of falling
                     through when the bridge is unreachable
"""

import json
import os
import sys
import urllib.request
import urllib.error

BRIDGE_URL = os.environ.get("BUDDY_BRIDGE_URL", "http://127.0.0.1:5151/notify")
TIMEOUT = int(os.environ.get("BUDDY_TIMEOUT", "60"))
STRICT = os.environ.get("BUDDY_STRICT", "0") == "1"


# ANSI colours — show up in any normal terminal, harmless if redirected
RED = "\033[1;31m"
YEL = "\033[1;33m"
NC  = "\033[0m"


def warn(msg: str):
    """Print a high-visibility warning to stderr that the user
    can't miss in their Claude Code transcript."""
    sys.stderr.write(f"\n{YEL}━━━ buddy bridge: {msg}{NC}\n")
    sys.stderr.write(f"{YEL}    falling back to Claude Code's own prompt{NC}\n\n")
    sys.stderr.flush()


def alarm(msg: str):
    sys.stderr.write(f"\n{RED}━━━ buddy bridge: {msg}{NC}\n\n")
    sys.stderr.flush()


def _hint(tool: str, tool_input: dict) -> str:
    """Compress the tool input into a short hint readable on the device."""
    if tool == "Bash":
        return (tool_input.get("command") or "")[:80]
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return (tool_input.get("file_path") or "")[:80]
    if tool == "Read":
        return (tool_input.get("file_path") or "")[:80]
    if tool == "WebFetch":
        return (tool_input.get("url") or "")[:80]
    if tool == "Grep":
        return (tool_input.get("pattern") or "")[:80]
    return json.dumps(tool_input)[:80]


def _emit_decision(decision: str, reason: str):
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }))


def _fallback(reason: str):
    if STRICT:
        alarm(f"{reason} — STRICT mode, denying")
        _emit_decision("deny", f"buddy bridge unreachable: {reason}")
    else:
        warn(reason)
        # exit 0 with no stdout → Claude Code shows its normal prompt
        sys.exit(0)


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)
    try:
        event = json.loads(raw)
    except Exception:
        sys.exit(0)

    tool = event.get("tool_name") or event.get("tool") or "tool"
    tool_input = event.get("tool_input") or {}
    hint = _hint(tool, tool_input)

    body = json.dumps({"tool": tool, "hint": hint, "timeout": TIMEOUT}).encode()
    req = urllib.request.Request(
        BRIDGE_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT + 5) as resp:
            ans = json.loads(resp.read())
    except urllib.error.URLError as e:
        return _fallback(f"bridge unreachable ({e.reason}); is it running?")
    except Exception as e:
        return _fallback(f"bridge call failed ({e})")

    decision = ans.get("decision", "")
    if decision == "offline":
        # Bridge is up but no Core2 connected — common when the device
        # is asleep, out of range, or paired to Claude Desktop instead.
        return _fallback("Core2 not connected to bridge (device offline)")
    if decision == "allow":
        _emit_decision("allow", "approved on buddy device")
    elif decision == "deny":
        _emit_decision("deny", "denied on buddy device")
    else:
        return _fallback(f"unexpected response: {ans}")


if __name__ == "__main__":
    main()
