#!/usr/bin/env bash
# PolinShield: Layer 1 - npm/pnpm postinstall block
set -uo pipefail

if ! grep -q "^ignore-scripts=true" "$HOME/.npmrc" 2>/dev/null; then
  printf '\n# PolinShield: block postinstall scripts\nignore-scripts=true\n' >> "$HOME/.npmrc"
  echo "✓ Added ignore-scripts=true to ~/.npmrc"
else
  echo "✓ Already enabled in ~/.npmrc"
fi

mkdir -p "$HOME/.config/pnpm"
if ! grep -q "^ignore-scripts=true" "$HOME/.config/pnpm/global-config" 2>/dev/null; then
  printf 'ignore-scripts=true\n' >> "$HOME/.config/pnpm/global-config"
  echo "✓ Added to pnpm config"
fi
