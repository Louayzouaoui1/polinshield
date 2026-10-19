#!/usr/bin/env bash
# PolinShield: Auto-heal — when on, every scan (in-app and the 9am launchd one)
# kills the implant, sinkholes persistence paths, removes malicious LaunchAgents
# and strips injected payloads, with backups in Application Support/PolinShield/quarantine.
# Turn off:  rm "$HOME/Library/Application Support/PolinShield/auto-heal"
set -uo pipefail
DIR="$HOME/Library/Application Support/PolinShield"
mkdir -p "$DIR" && : > "$DIR/auto-heal" && echo "✓ Auto-heal enabled"
