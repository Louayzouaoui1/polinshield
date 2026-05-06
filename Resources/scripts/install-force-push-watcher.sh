#!/usr/bin/env bash
# PolinShield: Layer 4 - Hourly force-push watcher
set -uo pipefail

DIR="$HOME/Library/Application Support/PolinShield"
mkdir -p "$DIR"

cat > "$DIR/check-force-pushes.sh" <<'WATCH'
#!/usr/bin/env bash
set -uo pipefail
LOG="$HOME/Library/Application Support/PolinShield/force-push-check.log"
SINCE_FILE="$HOME/Library/Application Support/PolinShield/.last-fp-check"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SINCE=$(cat "$SINCE_FILE" 2>/dev/null || date -u -v -1H +%Y-%m-%dT%H:%M:%SZ)
USER=$(gh api /user --jq .login 2>/dev/null) || { echo "$NOW" > "$SINCE_FILE"; exit 0; }

forced=$(gh api "/users/$USER/events?per_page=100" 2>/dev/null | SINCE="$SINCE" python3 -c "
import json, sys, os
events = json.load(sys.stdin)
since = os.environ['SINCE']
for e in events:
    if e.get('type') != 'PushEvent': continue
    if e.get('created_at','') < since: continue
    p = e['payload']
    if p.get('size',0) == 0 and p.get('before') != p.get('head'):
        print(f\"{e['created_at']} {e['repo']['name']}/{p.get('ref','').replace('refs/heads/','')}\")
")

if [ -n "$forced" ]; then
  echo "[$NOW] Force-pushes since $SINCE:" >> "$LOG"
  echo "$forced" >> "$LOG"
  count=$(echo "$forced" | wc -l | tr -d ' ')
  osascript -e "display notification \"$count force-push(es) detected\" with title \"PolinShield\" sound name \"Sosumi\"" 2>/dev/null || true
fi
echo "$NOW" > "$SINCE_FILE"
WATCH
chmod +x "$DIR/check-force-pushes.sh"

cat > "$HOME/Library/LaunchAgents/dev.polinshield.force-push.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.polinshield.force-push</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin "$DIR/check-force-pushes.sh"</string>
  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST

launchctl unload "$HOME/Library/LaunchAgents/dev.polinshield.force-push.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/dev.polinshield.force-push.plist"
echo "✓ Force-push watcher loaded"
