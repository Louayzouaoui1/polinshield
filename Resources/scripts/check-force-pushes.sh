#!/usr/bin/env bash
# PolinShield: on-demand force-push check (called from Swift app)
set -uo pipefail
USER=$(gh api /user --jq .login 2>/dev/null) || exit 0
SINCE=$(date -u -v -1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

gh api "/users/$USER/events?per_page=100" 2>/dev/null | SINCE="$SINCE" python3 -c "
import json, sys, os
events = json.load(sys.stdin)
since = os.environ['SINCE']
hits = []
for e in events:
    if e.get('type') != 'PushEvent': continue
    if e.get('created_at','') < since: continue
    p = e['payload']
    if p.get('size',0) == 0 and p.get('before') != p.get('head'):
        hits.append(f\"{e['created_at']} {e['repo']['name']}/{p.get('ref','').replace('refs/heads/','')} {p.get('before','')[:8]} -> {p.get('head','')[:8]}\")
if hits:
    print('Force-pushes since', since)
    for h in hits: print(h)
"
