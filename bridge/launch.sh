#!/bin/bash
# Convenience launcher for buddy-bridge using its bundled venv.
# Usage:  ./launch.sh
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  echo "venv missing — run:  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi
exec .venv/bin/python bridge.py
