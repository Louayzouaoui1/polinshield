#!/usr/bin/env bash
# PolinShield: Layer 4 - Hourly force-push watcher
set -uo pipefail

DIR="$HOME/Library/Application Support/PolinShield"
mkdir -p "$DIR"

cat > "$DIR/check-force-pushes.sh" <<'WATCH'
#!/usr/bin/env bash
# Detect force-pushes on your GitHub account in the last window.
#
# GitHub no longer populates the `size`/`forced` fields on PushEvents, so we ask the
# compare API instead: if HEAD is not a descendant of the previous SHA (behind_by > 0),
# history was rewritten — i.e. a force-push.
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

LOG="$HOME/Library/Application Support/PolinShield/force-push-check.log"
SINCE_FILE="$HOME/Library/Application Support/PolinShield/.last-fp-check"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SINCE=$(cat "$SINCE_FILE" 2>/dev/null || date -u -v -1H +%Y-%m-%dT%H:%M:%SZ)

# Read the token locally: `gh auth status` makes a network call and so reports the
# token as invalid when launchd fires on wake, before Wi-Fi reassociates.
# On any failure below we exit WITHOUT advancing SINCE_FILE, so the window is
# re-checked next run rather than silently skipped.
gh auth token >/dev/null 2>&1 || { echo "[$NOW] no gh token — window kept" >> "$LOG"; exit 1; }
USER=$(gh api /user --jq .login 2>/dev/null) || { echo "[$NOW] gh unreachable — window kept" >> "$LOG"; exit 1; }

events=""
for attempt in 1 2 3; do
  events=$(gh api "/users/$USER/events?per_page=100" 2>/dev/null)
  [ -n "$events" ] && break
  [ "$attempt" -lt 3 ] && sleep 30
done
[ -z "$events" ] && { echo "[$NOW] no event data after 3 attempts — window kept" >> "$LOG"; exit 1; }

candidates=$(printf '%s' "$events" | jq -r --arg since "$SINCE" '
  map(select(.type == "PushEvent" and .created_at >= $since))
  | .[] | [.created_at, .repo.name, (.payload.ref // ""), (.payload.before // ""), (.payload.head // "")] | @tsv
' 2>/dev/null)

forced=""
while IFS=$'\t' read -r t repo ref before head; do
  [ -z "$repo" ] || [ -z "$before" ] || [ -z "$head" ] && continue
  # Brand-new branch: a create, not a rewrite.
  case "$before" in 0000000000000000000000000000000000000000) continue ;; esac
  behind=$(gh api --method GET "repos/$repo/compare/$before...$head" 2>/dev/null | jq -r '.behind_by // 0' 2>/dev/null)
  if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
    forced+="$t ${repo}/${ref#refs/heads/} ${before:0:8} -> ${head:0:8}
"
  fi
done <<<"$candidates"

if [ -n "$forced" ]; then
  echo "[$NOW] Force-pushes since $SINCE:" >> "$LOG"
  printf '%s' "$forced" >> "$LOG"
  count=$(printf '%s' "$forced" | grep -c '^.')
  # Name the repos/branches in the notification itself; first 3, then "+N more".
  targets=$(printf '%s' "$forced" | awk 'NF{print $2}' | head -3 | paste -sd ',' - | sed 's/,/, /g')
  [ "$count" -gt 3 ] && targets="$targets +$((count - 3)) more"
  osascript -e "display notification \"${targets//\"/\\\"}\" with title \"🚨 Force-push: PolinShield\" sound name \"Sosumi\"" 2>/dev/null || true
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
