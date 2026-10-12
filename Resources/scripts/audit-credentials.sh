#!/usr/bin/env bash
# PolinShield: audit every GitHub credential reachable from this Mac.
# Output, one line per item:  STATUS|what we found, in plain words|link to fix it (optional)
# STATUS: bad (act now) | warn (review) | ok | todo (manual check the API cannot do)
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; export PATH

[ -f "$HOME/.git-credentials" ] && echo "bad|Your GitHub token is saved in a plain text file (~/.git-credentials). Delete that file and sign in again.|"
grep -qs 'oauth_token:' "$HOME/.config/gh/hosts.yml" && echo "warn|Your gh token is stored in a plain file (~/.config/gh/hosts.yml). Run: gh auth login, and keep the token in the keychain.|"

local_fps=""
for f in "$HOME"/.ssh/*.pub; do [ -f "$f" ] && local_fps+="$(ssh-keygen -lf "$f" 2>/dev/null | awk '{print $2}')"$'\n'; done

accounts=$(gh auth status 2>&1 | sed -nE 's/.*account ([A-Za-z0-9-]+).*/\1/p' | sort -u)
if [ -z "$accounts" ]; then echo "ok|No GitHub account is signed in on this Mac.|"; exit 0; fi
for a in $accounts; do
  tok=$(gh auth token --user "$a" 2>/dev/null) || continue
  scopes=$(GH_TOKEN=$tok gh api -i /user 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')
  echo "ok|Signed in as $a on this Mac.|"
  case ",$scopes," in *delete_repo*|*admin:org*|*workflow*)
    echo "warn|$a's login token can edit workflows and delete repos. Normal for the guard setup, but a stolen copy would be very damaging, so revoke apps you do not recognise.|https://github.com/settings/applications";; esac
  # SSH keys registered on GitHub that this Mac does not have = added by someone else, or stale.
  GH_TOKEN=$tok gh api /user/keys --jq '.[]|[.title,.created_at,.key]|@tsv' 2>/dev/null | while IFS=$'\t' read -r title created key; do
    fp=$(printf '%s\n' "$key" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
    printf '%s' "$local_fps" | grep -qxF "$fp" || echo "bad|$a has an SSH key called '$title' (added ${created:0:10}) that is NOT on this Mac. Delete it unless you added it yourself.|https://github.com/settings/keys"
  done
  for o in $(GH_TOKEN=$tok gh api /user/orgs --jq '.[].login' 2>/dev/null); do
    n=$(GH_TOKEN=$tok gh api "/orgs/$o/personal-access-tokens?per_page=100" --jq 'length' 2>/dev/null) && [ "${n:-0}" -gt 0 ] && echo "warn|$n access token(s) can reach the $o organisation. Remove any you do not recognise.|https://github.com/organizations/$o/settings/personal-access-tokens"
  done
done
echo "todo|Check 1: revoke any OAuth app you do not recognise (GitHub CLI, VS Code, and so on). Only you can see this list.|https://github.com/settings/applications"
echo "todo|Check 2: end any login session you do not recognise.|https://github.com/settings/sessions"
exit 0
