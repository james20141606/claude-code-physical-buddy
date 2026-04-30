#!/usr/bin/env python3
"""
Claude Code Stop hook — pushes per-session and today's token totals to
the buddy bridge so the device's PET stats page shows real activity.

Runs at the end of every assistant turn.  Reads:
  - The transcript_path passed in by Claude Code (current session only)
  - All ~/.claude/projects/<dir>/<sessionid>.jsonl on disk for "today"
    cumulative across every project

POSTs to bridge:
  {
    "tokens_today": <today output_tokens across all projects>,
    "msg":          "<short status: msgs / tools this session>",
    "running":      0/1,
    "completed":    true,
  }

Fails open: any exception → exit 0 silent so it never blocks Claude Code.
"""

import json
import os
import sys
import urllib.request
import urllib.error
import glob
from datetime import datetime, timezone, timedelta

BRIDGE_URL = os.environ.get("BUDDY_BRIDGE_URL", "http://127.0.0.1:5151/state")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
LOCAL_TZ = datetime.now(timezone.utc).astimezone().tzinfo


def tally(path: str, today_str: str) -> tuple[int, int, int]:
    """Returns (session_output, today_output, n_assistant_msgs)."""
    sess_out = today_out = n = 0
    try:
        with open(path) as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                msg = d.get("message")
                if not isinstance(msg, dict) or "usage" not in msg:
                    continue
                u = msg["usage"]
                tok = u.get("output_tokens", 0)
                sess_out += tok
                n += 1
                ts = d.get("timestamp", "")
                if ts.startswith(today_str):
                    today_out += tok
    except FileNotFoundError:
        pass
    except Exception:
        pass
    return sess_out, today_out, n


def main():
    raw = sys.stdin.read()
    try:
        event = json.loads(raw) if raw.strip() else {}
    except Exception:
        event = {}

    # Today's date in the LOCAL timezone — matches how the user thinks
    # about "today" rather than UTC midnight.
    now_local = datetime.now(LOCAL_TZ)
    today_str = now_local.strftime("%Y-%m-%d")

    # Current session breakdown
    transcript = event.get("transcript_path")
    sess_out = sess_n = 0
    if transcript:
        sess_out, _, sess_n = tally(transcript, today_str)

    # Today's output across every Claude Code project
    today_out_all = 0
    try:
        for f in glob.glob(os.path.join(PROJECTS_DIR, "*", "*.jsonl")):
            _, t, _ = tally(f, today_str)
            today_out_all += t
    except Exception:
        pass

    # Short status line. Buddy's data.h truncates msg to 23 chars.
    msg = f"{sess_n}msg {sess_out//1000 if sess_out >= 1000 else sess_out}{'K' if sess_out >= 1000 else ''}tk"[:23]

    body = {
        "tokens_today": today_out_all,
        "msg":          msg,
        "running":      0,        # turn just ended
        "completed":    True,     # triggers the celebrate animation
    }

    try:
        req = urllib.request.Request(
            BRIDGE_URL,
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=2).read()
    except Exception:
        # Bridge offline? Don't bother Claude Code about it.
        pass


if __name__ == "__main__":
    main()
