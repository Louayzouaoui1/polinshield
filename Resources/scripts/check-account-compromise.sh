#!/usr/bin/env bash
# PolinShield: stolen-credential detector.
# Every push this Mac makes is recorded by the global pre-push hook in push-ledger.log.
# A push GitHub attributes to one of the accounts signed in here that is NOT in the
# ledger came from somewhere else. A force-push or a burst of 3+ such pushes is the
# signature of a stolen token (deleting PATs/SSH keys does not revoke OAuth tokens
# lifted from the Keychain). Output: one "🚨" line per suspicious push.
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; export PATH
DIR="$HOME/Library/Application Support/PolinShield"
LEDGER="$DIR/push-ledger.log"; STATE="$DIR/.last-compromise-check"
mkdir -p "$DIR"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SINCE=$(cat "$STATE" 2>/dev/null || date -u -v -1H +%Y-%m-%dT%H:%M:%SZ)

if [ ! -s "$LEDGER" ]; then
  echo "⚠ push ledger is empty: install the git hook defense first, otherwise every push would look foreign"
  exit 0
fi
accounts=$(gh auth status 2>&1 | sed -nE 's/.*account ([A-Za-z0-9-]+).*/\1/p' | sort -u)
[ -z "$accounts" ] && exit 1

ok=1; found=""
for a in $accounts; do
  tok=$(gh auth token --user "$a" 2>/dev/null) || continue
  events=$(GH_TOKEN=$tok gh api "/users/$a/events?per_page=100" 2>/dev/null)
  [ -z "$events" ] && { ok=0; continue; }
  foreign=""
  while IFS=$'\t' read -r t repo ref before head; do
    [ -z "$head" ] && continue
    grep -q "$head" "$LEDGER" && continue
    forced=""
    case "$before" in 0000000000000000000000000000000000000000) ;; *)
      behind=$(GH_TOKEN=$tok gh api --method GET "repos/$repo/compare/$before...$head" 2>/dev/null | jq -r '.behind_by // 0')
      [ "${behind:-0}" -gt 0 ] 2>/dev/null && forced=" FORCE-PUSH";;
    esac
    foreign+="$t $a $repo/${ref#refs/heads/} ${head:0:8}$forced"$'\n'
  done < <(printf '%s' "$events" | jq -r --arg since "$SINCE" '
    map(select(.type=="PushEvent" and .created_at >= $since))
    | .[] | [.created_at,.repo.name,(.payload.ref//""),(.payload.before//""),(.payload.head//"")] | @tsv')
  [ -z "$foreign" ] && continue
  n=$(printf '%s' "$foreign" | grep -c '^.')
  if [ "$n" -ge 3 ] || printf '%s' "$foreign" | grep -q FORCE-PUSH; then
    printf '%s' "$foreign" | sed 's/^/🚨 Push not made from this Mac: /'
    found=1
  else
    printf '%s' "$foreign" | sed 's/^/⚠ Push not made from this Mac (single, not forced): /'
  fi
done
if [ -n "$found" ]; then
  echo "🚨 Treat the account as compromised: revoke OAuth apps (github.com/settings/applications), sign out all sessions (github.com/settings/security), then re-authenticate"
fi
[ "$ok" = 1 ] && echo "$NOW" > "$STATE"
exit 0
