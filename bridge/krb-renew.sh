#!/bin/bash
# Buddy bridge — Kerberos cache auto-renewer.
# Called every 12 h by com.james.buddykinit launchd plist.
#
# Strategy:
#   1. Try `kinit -R` first — cheap, no password needed, works for the
#      ~7-day renewable lifetime after the most recent full kinit.
#   2. If -R fails (renewable expired, KDC complaint, missing cache),
#      fall back to a full kinit using $BUDDY_KRB_USER + $BUDDY_KRB_PASS.
#      Those vars are exported in ~/.zshrc (chmod 600) and read here by
#      sourcing the rc file.  They never appear in this script or in
#      any committed file.
#   3. Both kinit forms request a renewable lifetime via `-r 7d` so the
#      cheap -R path works again over the next week.
#
# On a real failure (KDC unreachable, password rejected) fire a macOS
# notification so the user knows manual intervention is needed.

set -u
CACHE="${BUDDY_KRB_CACHE:-FILE:/tmp/krb5cc_buddy}"
LOG=/tmp/buddykinit.log
NOW() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(NOW)] $*" >> "$LOG"; }
notify() {
  /usr/bin/osascript -e \
    "display notification \"$1\" with title \"Buddy Bridge\" sound name \"Funk\"" \
    >/dev/null 2>&1 || true
}

# ── Step 1: try cheap renewal ──────────────────────────────────────────
if /usr/bin/kinit -c "$CACHE" -R 2>>"$LOG"; then
  log "renewed via -R"
  exit 0
fi

# ── Step 2: fall back to full kinit using stored creds ─────────────────
# Source ~/.zshrc to pick up BUDDY_KRB_USER / BUDDY_KRB_PASS exports.
# We discard stdout so the rc file's other side effects don't leak into
# our log; only -- the kinit call's exit status matters.
if [ -f "$HOME/.zshrc" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$HOME/.zshrc" >/dev/null 2>&1 || true
fi

if [ -z "${BUDDY_KRB_USER:-}" ] || [ -z "${BUDDY_KRB_PASS:-}" ]; then
  log "FAIL — -R didn't work and BUDDY_KRB_USER/PASS not in env"
  notify "Kerberos: renewable expired and no auto-renew creds. Run kinit manually."
  exit 1
fi

# Full kinit. Pipe the password — never log or echo it.
if /usr/bin/printf '%s' "$BUDDY_KRB_PASS" \
   | /usr/bin/kinit -c "$CACHE" -r 7d "$BUDDY_KRB_USER" 2>>"$LOG"; then
  log "full kinit OK (renewable 7d) for $BUDDY_KRB_USER"
  exit 0
fi

log "FAIL — full kinit rejected for $BUDDY_KRB_USER"
notify "Kerberos kinit rejected — password may have changed or KDC unreachable."
exit 1
