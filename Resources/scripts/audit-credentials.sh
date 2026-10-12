#!/usr/bin/env bash
# PolinShield: audit every GitHub credential reachable from this Mac.
# "🚨" = act now, "⚠" = review, "✓" = fine.
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; export PATH

[ -f "$HOME/.git-credentials" ] && echo "🚨 Plaintext ~/.git-credentials exists (any process can read the token)"
grep -qs 'oauth_token:' "$HOME/.config/gh/hosts.yml" && echo "⚠ gh token stored in plaintext ~/.config/gh/hosts.yml (use the keyring)"
echo "ℹ git credential.helper: $(git config --global credential.helper || echo none)"

local_fps=""
for f in "$HOME"/.ssh/*.pub; do [ -f "$f" ] && local_fps+="$(ssh-keygen -lf "$f" 2>/dev/null | awk '{print $2}')"$'\n'; done

accounts=$(gh auth status 2>&1 | sed -nE 's/.*account ([A-Za-z0-9-]+).*/\1/p' | sort -u)
[ -z "$accounts" ] && { echo "ℹ no gh accounts signed in"; exit 0; }
for a in $accounts; do
  tok=$(gh auth token --user "$a" 2>/dev/null) || continue
  scopes=$(GH_TOKEN=$tok gh api -i /user 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')
  echo "✓ $a: ${tok:0:4}… scopes=[${scopes:-none/fine-grained}]"
  case ",$scopes," in *delete_repo*|*admin:org*|*workflow*) echo "⚠ $a: token can delete repos / edit workflows / administer orgs; a stolen copy is very damaging";; esac
  # SSH keys registered on GitHub that this Mac does not have = attacker-added or stale.
  GH_TOKEN=$tok gh api /user/keys --jq '.[]|[.title,.created_at,.key]|@tsv' 2>/dev/null | while IFS=$'\t' read -r title created key; do
    fp=$(printf '%s\n' "$key" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
    printf '%s' "$local_fps" | grep -qxF "$fp" || echo "🚨 $a: SSH key '$title' (added ${created:0:10}) is on GitHub but not on this Mac"
  done
  # Fine-grained tokens with org access (visible to org owners only).
  for o in $(GH_TOKEN=$tok gh api /user/orgs --jq '.[].login' 2>/dev/null); do
    n=$(GH_TOKEN=$tok gh api "/orgs/$o/personal-access-tokens?per_page=100" --jq 'length' 2>/dev/null) && [ "${n:-0}" -gt 0 ] && echo "⚠ $o: $n fine-grained token(s) have org access; review at github.com/organizations/$o/settings/personal-access-tokens"
  done
done
echo "ℹ OAuth apps and sessions cannot be read via the API; review github.com/settings/applications and github.com/settings/security by hand"
exit 0
