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

### IOCs detected (per [OSM PolinRider dossier](https://github.com/OpenSourceMalware/PolinRider))
- Source signatures: `rmcej%otb%` (v1) and `Cot%3t=shtP` (v2 — to be added)
- Payload prefix: `global['!']='`
- Process pattern: `node -e global['_V']=`
- C2 servers: `auth-con-firm.vercel.app`, `auth-rho-dun.vercel.app`
- Forbidden files: `temp_auto_push.bat`, `temp_interactive_push.bat`, `config.bat`

### Known limitations / roadmap
- v2 obfuscator variant (`Cot%3t=shtP`) detection not yet in scan rules — issue tracked.
- Additional C2 domains documented by OSM (`default-configuration.vercel.app`, `260120.vercel.app`, etc.) not yet in the `/etc/hosts` block — issue tracked.
- `.vscode/tasks.json` `curl | bash` pattern detection not yet implemented — issue tracked.
- Fake `.woff2` font payload detection not yet implemented — issue tracked.

[1.0.0]: https://github.com/Louay24/polinshield/releases/tag/v1.0.0
