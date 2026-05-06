# Architecture

## Why this design

PolinShield needs to:
- Run on macOS without admin privileges (mostly)
- Survive across reboots and quits
- Show live status without requiring the user to open it
- Be auditable so security-conscious users can verify it
- Be small enough to ship without a Developer ID account

The design choices below come from those constraints.

## High-level

```
┌─────────────────────────────────────────────────────────────────────┐
│                       PolinShield.app                                │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────────┐      │
│  │  SwiftUI front-end   │         │  Bash defense engine     │      │
│  │  (~700 LOC Swift)    │ ──run─▶ │  (Resources/scripts/)    │      │
│  │                      │         │                          │      │
│  │  - MenuBarExtra      │ ◀─stdout│  scan-malware.sh         │      │
│  │  - Dashboard window  │         │  install-*.sh            │      │
│  │  - Welcome wizard    │         │  check-force-pushes.sh   │      │
│  └──────────────────────┘         └──────────────────────────┘      │
│             │                                                        │
│             │ writes:                                                │
│             ▼                                                        │
│  ~/Library/Application Support/PolinShield/                          │
│    ├── scan-history.json                                             │
│    ├── force-push-history.json                                       │
│    └── force-push-check.log                                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

External persistence (set up by install-*.sh, runs even when app closed):
  ├── ~/.npmrc                                          (npm hardening)
  ├── /etc/hosts                                        (DNS block)
  ├── ~/.git-hooks/pre-commit                           (git hook)
  ├── ~/Library/LaunchAgents/dev.polinshield.scan.plist
  └── ~/Library/LaunchAgents/dev.polinshield.force-push.plist
```

## Two-layer separation: Swift UI + Bash engine

The actual defense logic lives in **plain bash scripts** under `Resources/scripts/`. The Swift app is a UI shell that runs them and parses their output.

This is intentional:

1. **Auditable.** A security-conscious user can read the bash scripts in plain text. The Swift binary is opaque, but the part that does anything risky to your system is not.
2. **Portable.** Every script also runs standalone:
   ```bash
   bash /Applications/PolinShield.app/Contents/Resources/scripts/scan-malware.sh ~/Desktop
   ```
   You can run them from cron, CI, or another tool.
3. **Hackable.** Adding a new IOC pattern means editing one bash script — no Swift recompile needed (though for it to ship in releases, the source script must be updated).
4. **Robust.** If the Swift app crashes, the LaunchAgents still run the scan and force-push detector. PolinShield can be uninstalled while the defenses keep working (until you also remove the LaunchAgents).

## Why MenuBarExtra (and macOS 14+)

`MenuBarExtra` is the SwiftUI API for status bar items. It's only available on macOS 13+, and several SwiftUI features we use (`ContentUnavailableView`, `.background.secondary`, `Table` selection bindings) are macOS 14+.

We chose macOS 14+ as the floor because:
- It's been out since September 2023 (>2 years at time of writing)
- The features it gives us simplify the code by ~30%
- Targeting macOS 13 would mean writing fallbacks for ~10 different APIs

## File layout

```
polinshield/
├── Package.swift                Swift Package Manager manifest
├── Makefile                     Build system (no Xcode project needed)
├── Sources/PolinShield/
│   ├── PolinShieldApp.swift     @main entry, scenes, app delegate
│   ├── DefenseEngine.swift      Singleton ObservableObject (state + shell runner)
│   ├── MenuBarView.swift        Click-down menu bar dropdown
│   ├── DashboardView.swift      Full window: 5 tabs (Overview/Defenses/Scans/FP/About)
│   └── WelcomeView.swift        First-run 3-step wizard
├── Resources/
│   ├── Info.plist               LSUIElement=true, bundle metadata
│   └── scripts/                 Defense engine — these get copied to .app/Contents/Resources/scripts/
│       ├── scan-malware.sh             Layer 5: disk scan
│       ├── install-npm-block.sh        Layer 1: npm hardening
│       ├── install-hosts-block.sh      Layer 2: /etc/hosts (uses sudo -S)
│       ├── install-git-hook.sh         Layer 3: pre-commit hook
│       ├── install-force-push-watcher.sh  Layer 4: GitHub poller LaunchAgent
│       ├── install-daily-scan.sh       Layer 5 LaunchAgent (calls scan-malware.sh at 9am)
│       └── check-force-pushes.sh       Layer 4: on-demand force-push check
├── docs/                        GitHub Pages site + markdown docs
│   ├── index.html               Landing page
│   ├── THREAT.md                Technical writeup of PolinRider
│   ├── INSTALL.md               Install guide
│   └── ARCHITECTURE.md          This file
├── .github/workflows/
│   ├── build.yml                CI on PRs
│   └── release.yml              Auto-DMG on tag push
├── Casks/polinshield.rb         Homebrew cask formula
├── README.md
└── LICENSE                      MIT
```

## Key components

### `DefenseEngine` (ObservableObject)

The singleton that:
- Holds `@Published` state (scan history, force-push history, defense status)
- Runs bash scripts via `Process` and parses their output
- Persists history to `~/Library/Application Support/PolinShield/`
- Triggers macOS notifications via `UNUserNotificationCenter`

It's `@MainActor`-isolated. Shell calls happen on a detached `Task` and post results back to the main actor.

### Script resolver

The Swift code uses a custom resolver (`scriptPath(_:)`) instead of `Bundle.main.url(forResource:withExtension:)` because resources copied via `swift build`'s `.copy("../Resources")` go into a sub-bundle, not the main bundle's flat resource search path.

```swift
func scriptPath(_ name: String) -> String? {
    guard let resPath = Bundle.main.resourcePath else { return nil }
    let candidate = "\(resPath)/scripts/\(name).sh"
    return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
}
```

### Sudo handling

PolinShield needs sudo *once* — to write to `/etc/hosts`. We collect the password in a `SecureField` and pass it via `echo "$PASS" | sudo -S` to the bash script. The password is **not stored** anywhere; the `String` lives only in the SwiftUI `@State` for the modal sheet, then is set to `""` after install.

### LaunchAgents

Two are installed:

`dev.polinshield.scan.plist` — runs `scan-malware.sh` at 9:00 AM daily.

`dev.polinshield.force-push.plist` — runs `check-force-pushes.sh` every 3600 seconds.

Both are user agents (LSPath `~/Library/LaunchAgents/`) — no root required.

## Build system

The `Makefile` does everything via `swift build` + manual `.app` bundle assembly:

```
make build   →  swift build -c release
make app     →  build + assemble Contents/{MacOS,Resources/scripts,Info.plist}
make dmg     →  app + hdiutil create
make install →  app + cp to /Applications + open
```

There is **no `.xcodeproj`** in this repo. This is intentional — Xcode projects are notoriously hard to keep clean in version control (file UUIDs, build setting drift, etc.). Swift Package Manager + Makefile is enough for a single-target macOS app.

## Code signing

We sign with an ad-hoc signature (`codesign -s -`). This means:

- ✅ Launches on the developer's machine
- ✅ Does not require an Apple Developer Program membership ($99/year)
- ⚠️ Requires the right-click → "Open" Gatekeeper bypass on first launch on other machines
- ❌ Cannot be notarized

For wider distribution, a Developer ID would be needed. The Makefile's `codesign` line can be swapped for `--sign "Developer ID Application: Your Name (TEAMID)"` when one is available.

## What PolinShield deliberately doesn't do

- **No telemetry**, no analytics, no crash reporting.
- **No auto-update.** Updates come via Homebrew or manual DMG re-download.
- **No in-app GitHub auth.** It uses your existing `gh` CLI auth — no new tokens to manage.
- **No background daemon as root.** All persistence is at user level.
- **No sandboxing entitlements.** Sandboxing would prevent shelling out to bash, which is the whole point.

## Testing

There are no formal unit tests — the bash defenses can be tested by running them, and the SwiftUI front-end is glue code where automated tests offer little value compared to manually clicking through.

To verify a build works end-to-end:

```bash
make app
open .build/PolinShield.app

# In the menu bar dropdown:
# 1. Run Scan Now → should populate Scan History
# 2. Open Dashboard → Defenses → Install (any non-sudo defense)
# 3. Open Dashboard → Force-Pushes → Check Now → should populate
```

## Contributing a new defense layer

1. Add a case to `Defense.ID` in `DefenseEngine.swift`.
2. Add the metadata (title, description, needsSudo) to `Defense.allDefenses`.
3. Create `Resources/scripts/install-<your-id>.sh`.
4. Add the lookup in `installDefense(_:sudoPassword:)`.
5. Add the detection in `isDefenseInstalled(_:)`.

PRs are welcome. Adding a defense layer is ~50 LOC.
