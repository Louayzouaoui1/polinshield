#!/usr/bin/env bash
# PolinShield: Layer 3 - Global git pre-commit hook
set -uo pipefail

mkdir -p "$HOME/.git-hooks"
cat > "$HOME/.git-hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# PolinShield pre-commit hook
set -e
SIGNATURES=(
  "rmcej%otb%"
  "global\['!'\]='"
  "auth-con-firm.vercel.app"
  "auth-rho-dun.vercel.app"
  "aHR0cHM6Ly9hdXRoLWNvbi1maXJtLnZlcmNlbC5hcHAvYXBp"
)
FILES=$(git diff --cached --name-only --diff-filter=ACM)
[ -z "$FILES" ] && exit 0

FOUND=0
for sig in "${SIGNATURES[@]}"; do
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if grep -lE "$sig" "$f" >/dev/null 2>&1; then
      echo "🚨 [PolinShield] Malware signature in: $f"
      FOUND=1
    fi
  done <<< "$FILES"
done

FORBIDDEN=("config.bat" "temp_auto_push.bat" "temp_interactive_push.bat")
while IFS= read -r f; do
  base=$(basename "$f")
  for fb in "${FORBIDDEN[@]}"; do
    [ "$base" = "$fb" ] && { echo "🚨 [PolinShield] Forbidden file: $f"; FOUND=1; }
  done
done <<< "$FILES"

while IFS= read -r f; do
  base=$(basename "$f")
  if [ "$base" = ".env" ] || [[ "$base" =~ ^\.env\.(local|production|development)$ ]]; then
    echo "🚨 [PolinShield] Don't commit $f"
    FOUND=1
  fi
done <<< "$FILES"

if [ "$FOUND" = "1" ]; then
  echo ""
  echo "💀 Commit blocked by PolinShield. Bypass: git commit --no-verify"
  exit 1
fi
HOOK
chmod +x "$HOME/.git-hooks/pre-commit"
git config --global core.hooksPath "$HOME/.git-hooks"
echo "✓ Global pre-commit hook installed"
