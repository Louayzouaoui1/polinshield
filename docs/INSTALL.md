# Installation Guide

PolinShield is a native macOS menu bar app. It does not need an installer — you copy a single `.app` bundle to `/Applications`, launch it, and follow the welcome wizard.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- For force-push detection: [GitHub CLI](https://cli.github.com/) (`brew install gh && gh auth login`)

PolinShield is **400 KB** and uses **no background daemons** other than two user-level LaunchAgents that you can inspect and remove at any time.

## Option 1 — Homebrew (recommended)

```bash
brew install --cask louay24/tap/polinshield
```

Then launch PolinShield from Spotlight or `/Applications`.

## Option 2 — Download DMG

1. Go to [Releases](https://github.com/Louay24/polinshield/releases/latest).
2. Download `PolinShield-X.Y.Z.dmg`.
3. Open the DMG, drag **PolinShield** to your **Applications** folder.
4. Launch PolinShield from `/Applications` or Spotlight.

### First launch (Gatekeeper)

PolinShield is signed with an ad-hoc signature (no Apple Developer account). On first launch, macOS may say *"PolinShield cannot be opened because the developer cannot be verified."*

To bypass:

1. Right-click `PolinShield.app` in `/Applications`
2. Choose **Open**
3. Click **Open** in the dialog

You only need to do this once. macOS remembers the choice.

If you have **System Settings → Privacy & Security** open, you'll also see an "Open Anyway" button there.

## Option 3 — Build from source

```bash
git clone https://github.com/Louay24/polinshield.git
cd polinshield
make install      # builds, signs, and installs to /Applications
```

Requirements: Swift 6, macOS 14 SDK, `make`, `codesign`, `hdiutil` (all included with Xcode Command Line Tools).

To build a DMG only:
```bash
make dmg
ls .build/PolinShield-*.dmg
```

## First-run setup

After launching PolinShield:

1. **Allow Notifications** when macOS prompts (used for malware/force-push alerts).
2. **Click the 🛡️ icon** in your menu bar.
3. **Click "Setup Wizard"** and follow the 3-step flow:
   - **Check** — read-only scan to see if you're already infected.
   - **Install** — all 5 defense layers; you'll be asked for your admin password once (used only to add lines to `/etc/hosts`).
   - **Done** — you'll see a list of post-install manual steps.

## Manual steps after install

PolinShield can install defenses but cannot do these for you:

1. **Rotate your GitHub PAT** at [github.com/settings/tokens](https://github.com/settings/tokens) (if you suspect prior infection)
2. **Rotate npm / GitLab tokens** in `~/.npmrc` (if you have any)
3. **Re-pull team repos** that may have been infected:
   ```bash
   cd <repo> && git fetch --all && git reset --hard origin/<branch>
   ```
4. **Reboot** to flush any in-memory state.

## Verifying the install

```bash
# 1. Check npm hardening
grep ignore-scripts ~/.npmrc

# 2. Check /etc/hosts block
grep auth-con-firm /etc/hosts

# 3. Check git pre-commit hook
git config --global core.hooksPath
ls -l ~/.git-hooks/pre-commit

# 4. Check LaunchAgents
launchctl list | grep dev.polinshield
```

You should see all 4 defenses active.

## Uninstall

```bash
# Stop & remove LaunchAgents
launchctl unload ~/Library/LaunchAgents/dev.polinshield.*.plist 2>/dev/null
rm ~/Library/LaunchAgents/dev.polinshield.*.plist

# Remove pre-commit hook
git config --global --unset core.hooksPath
rm -rf ~/.git-hooks

# Remove npm hardening (optional - you might want to keep this)
sed -i '' '/^ignore-scripts=true/d' ~/.npmrc

# Remove app + data
rm -rf /Applications/PolinShield.app
rm -rf ~/Library/Application\ Support/PolinShield

# Remove /etc/hosts block (optional - you might want to keep these blocked)
# sudo nano /etc/hosts  → manually remove the PolinShield section
```

Or with Homebrew:
```bash
brew uninstall --cask polinshield --zap
```

The `--zap` flag removes app data and LaunchAgents in addition to the app itself.

## Troubleshooting

### "scan-malware.sh not found in app bundle"

The .app is corrupted. Reinstall via Homebrew or re-download the DMG.

### "Force-push detector says nothing found, but I know GitHub had force-pushes"

Make sure `gh` is installed and authenticated:
```bash
brew install gh
gh auth login
```

### Buttons don't do anything

Quit PolinShield from the menu bar dropdown, re-launch from `/Applications`. If it still happens, run the .app directly from Terminal to see logs:
```bash
/Applications/PolinShield.app/Contents/MacOS/PolinShield
```

### "Not opened: developer cannot be verified"

See [First launch (Gatekeeper)](#first-launch-gatekeeper) above.

## Known limitations

- **Apple Silicon-first.** Universal binary is built but most testing is on Apple Silicon.
- **GitHub-only force-push detection.** GitLab/Bitbucket support is not implemented.
- **No central reporting.** PolinShield does not send any telemetry, but that means we don't have campaign-wide statistics.

## Privacy

PolinShield makes exactly **one** type of network request: an authenticated call to `https://api.github.com/users/<your-username>/events` via the `gh` CLI on your machine, once per hour, to detect force-pushes against your account. No data is sent to any other service. No analytics, no error reporting, no auto-updates.

The `/etc/hosts` modification adds entries for known C2 domains and points them at `0.0.0.0`. It does not affect any other DNS resolution.
