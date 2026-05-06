#!/usr/bin/env bash
# PolinShield: Layer 5 - Daily 9am malware scan
set -uo pipefail

DIR="$HOME/Library/Application Support/PolinShield"
mkdir -p "$DIR"

# Use the embedded scan-malware script. The PolinShield app will be in /Applications.
# This script is called from there.
APP_SCAN="/Applications/PolinShield.app/Contents/Resources/scripts/scan-malware.sh"

cat > "$HOME/Library/LaunchAgents/dev.polinshield.scan.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.polinshield.scan</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>$APP_SCAN</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>9</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>$DIR/scan-out.log</string>
  <key>StandardErrorPath</key><string>$DIR/scan-err.log</string>
</dict></plist>
PLIST

launchctl unload "$HOME/Library/LaunchAgents/dev.polinshield.scan.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/dev.polinshield.scan.plist"
echo "✓ Daily scan scheduled for 9:00 AM"
