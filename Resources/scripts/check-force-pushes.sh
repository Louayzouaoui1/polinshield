#!/usr/bin/env bash
# PolinShield: force-push check (called from the Swift app and from launchd).
#
# Detection: the GitHub Events API no longer populates the `size`/`forced` flags on
# PushEvents, so we ask the compare API instead — if HEAD is not a descendant of the
# previous SHA (behind_by > 0), history was rewritten, i.e. a force-push.
#
# Output (one line per force-push, consumed by DefenseEngine.parseForcePushOutput):
#   ISO_DATE OWNER/REPO/BRANCH BEFORESHA -> AFTERSHA
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

# Read the token locally rather than `gh auth status`, which makes a network call and
# so reports "token invalid" when launchd fires on wake before Wi-Fi reassociates.
gh auth token >/dev/null 2>&1 || exit 1

USER=$(gh api /user --jq .login 2>/dev/null) || exit 1
SINCE=$(date -u -v -1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)

# Retry: launchd fires on wake, often before the network is up.
events=""
for attempt in 1 2 3; do
  events=$(gh api "/users/$USER/events?per_page=100" 2>/dev/null)
  [ -n "$events" ] && break
  [ "$attempt" -lt 3 ] && sleep 30
done
# Exit non-zero without emitting: the caller keeps its window and retries, so a
# network blip never silently skips an hour of pushes.
[ -z "$events" ] && exit 1

candidates=$(printf '%s' "$events" | jq -r --arg since "$SINCE" '
  map(select(.type == "PushEvent" and .created_at >= $since))
  | .[] | [
      .created_at,
      .repo.name,
      (.payload.ref // ""),
      (.payload.before // ""),
      (.payload.head // "")
    ] | @tsv
' 2>/dev/null)

[ -z "$candidates" ] && exit 0

while IFS=$'\t' read -r t repo ref before head; do
  [ -z "$repo" ] || [ -z "$before" ] || [ -z "$head" ] && continue
  # A brand-new branch has before == 000...0; that is a create, not a rewrite.
  case "$before" in 0000000000000000000000000000000000000000) continue ;; esac
  behind=$(gh api --method GET "repos/$repo/compare/$before...$head" 2>/dev/null \
           | jq -r '.behind_by // 0' 2>/dev/null)
  if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
    echo "$t ${repo}/${ref#refs/heads/} ${before:0:8} -> ${head:0:8}"
  fi
done <<<"$candidates"
