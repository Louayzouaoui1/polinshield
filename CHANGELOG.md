# Changelog

All notable changes to PolinShield will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] — 2026-05-06

Initial public release.

### Added
- Native macOS menu bar app with live status (🛡️ green / ⚠️ yellow / 🚨 red)
- Five-layer defense system:
  - Layer 1: npm/pnpm `ignore-scripts=true`
  - Layer 2: DNS-block known C2 domains via `/etc/hosts`
  - Layer 3: Global git pre-commit hook
  - Layer 4: Hourly GitHub force-push detector
  - Layer 5: Daily 9am malware scan
- Welcome wizard with infection check + one-click install
- Dashboard with Overview, Defenses, Scan History, Force-Pushes, About tabs
- macOS notifications for any detection
- Persistent scan and force-push history
- Universal binary (Apple Silicon + Intel)
- Homebrew cask formula
- GitHub Actions auto-release on tag

### IOCs detected
- Source signature: `rmcej%otb%`
- Payload prefix: `global['!']='`
- Persistence paths: `~/openclaw-app`, `~/.openclaw`, `~/.node_modules`
- Process pattern: `node -e global['_V']=`
- C2 servers: `auth-con-firm.vercel.app`, `auth-rho-dun.vercel.app`
- Forbidden files: `config.bat`, `temp_auto_push.bat`, `temp_interactive_push.bat`

[1.0.0]: https://github.com/Louay24/polinshield/releases/tag/v1.0.0
