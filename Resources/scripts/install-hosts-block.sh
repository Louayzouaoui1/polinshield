#!/usr/bin/env bash
# PolinShield: Layer 2 - DNS-block C2 servers via /etc/hosts
# Usage: install-hosts-block.sh <sudo-password>
set -uo pipefail
PASS="${1:-}"

if [ -z "$PASS" ]; then
  echo "ERROR: sudo password required"
  exit 1
fi

if grep -q "auth-con-firm.vercel.app" /etc/hosts 2>/dev/null; then
  echo "✓ Already blocked"
  exit 0
fi

# Use sudo with -S to read password from stdin
echo "$PASS" | sudo -S sh -c "cat >> /etc/hosts <<EOF

# PolinShield: block PolinRider/openclaw C2 servers - $(date +%Y-%m-%d)
0.0.0.0 auth-con-firm.vercel.app
0.0.0.0 auth-rho-dun.vercel.app
EOF" 2>/dev/null

echo "$PASS" | sudo -S dscacheutil -flushcache 2>/dev/null
echo "$PASS" | sudo -S killall -HUP mDNSResponder 2>/dev/null

# Verify
if grep -q "auth-con-firm.vercel.app" /etc/hosts 2>/dev/null; then
  echo "✓ C2 servers blocked"
else
  echo "ERROR: failed to update /etc/hosts (wrong password?)"
  exit 1
fi
