#!/bin/bash
# autossh wrapper that keeps the candy reverse-tunnel alive across drops.
# Use this INSTEAD of `ssh candy` when you want the tunnel to survive
# network blips, server reboots, or your laptop sleeping.
#
# Install autossh once:  brew install autossh
#
# Usage:
#   ./autossh-candy.sh          # opens an interactive shell on candy
#   ./autossh-candy.sh -d       # runs in background (no interactive shell;
#                                 just maintains the tunnel)
#
# Stop the background daemon:
#   pkill -f "autossh.*candy"
#
# Notes
# - The reverse tunnel is the same `RemoteForward 5151 localhost:5151`
#   already in ~/.ssh/config under `Host candy`.
# - autossh adds `ServerAlive` keepalives + monitor port so it can
#   reliably notice a dead session and respawn ssh.
# - Requires a working KRB5 ticket; we set KRB5CCNAME=FILE:/tmp/krb5cc_buddy
#   so this works from non-interactive contexts (subprocesses) too.

set -e
DAEMON=0
[ "$1" = "-d" ] && DAEMON=1

if ! command -v autossh >/dev/null 2>&1; then
  echo "autossh not installed — run: brew install autossh"
  exit 1
fi

export AUTOSSH_GATETIME=0       # consider startup successful immediately
export AUTOSSH_POLL=30          # poll connection every 30s
export AUTOSSH_PORT=20000       # autossh's own monitor port (choose unused)

# Use the FILE krb cache if it exists; falls back to default otherwise.
[ -f /tmp/krb5cc_buddy ] && export KRB5CCNAME=FILE:/tmp/krb5cc_buddy

SSH_OPTS=(
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ExitOnForwardFailure=yes
)

if [ "$DAEMON" -eq 1 ]; then
  # background daemon — no interactive shell, just hold the tunnel
  echo "starting autossh daemon for 'candy' (tunnel localhost:5151 ↔ remote:5151)"
  nohup autossh -M 0 -f -N "${SSH_OPTS[@]}" candy
  echo "started. check with:  pgrep -af 'autossh.*candy'"
else
  # foreground interactive
  exec autossh -M 0 "${SSH_OPTS[@]}" candy
fi
