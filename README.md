<div align="center">

# 🛡️ PolinShield

**Native macOS menu bar defense against npm supply-chain malware.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-007AFF?logo=apple)](https://www.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6-FA7343?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Louayzouaoui1/polinshield?include_prereleases)](https://github.com/Louayzouaoui1/polinshield/releases)
[![Build](https://github.com/Louayzouaoui1/polinshield/actions/workflows/build.yml/badge.svg)](https://github.com/Louayzouaoui1/polinshield/actions/workflows/build.yml)

[Install](#install) ·
[How it works](#how-it-works) ·
[The threat](docs/THREAT.md) ·
[Architecture](docs/ARCHITECTURE.md) ·
[Website](https://louayzouaoui1.github.io/polinshield)

</div>

---

PolinShield protects macOS dev machines against the **PolinRider supply-chain campaign** — an active, DPRK-attributed attack that has compromised **1,951+ public GitHub repositories belonging to 1,047+ unique owners** as of April 2026, with the scope **doubling every ~5 weeks**.

> ⚠️ **This is not theoretical.** PolinRider is a confirmed Lazarus-cluster operation tracked by [OpenSourceMalware](https://github.com/OpenSourceMalware/PolinRider). It has operationally merged with the **TasksJacker** and **Contagious Interview** campaigns. Read the [full threat writeup](docs/THREAT.md).

## What it stops

PolinRider attacks JavaScript developers via **four parallel injection vectors**, all converging on the same obfuscated payload:

1. **Config-file injection** — appends payload to `postcss.config.*`, `tailwind.config.*`, `eslint.config.*`, `next.config.*`, `vite.config.*`, `webpack.config.js`, etc.
2. **Malicious npm packages** — including `tailwindcss-style-animate`, `tailwind-mainanimation`, and others in the Tailwind/PostCSS ecosystem. Successful spread: Neutralinojs (8,400+ stars) was compromised, infecting hundreds of downstream users.
3. **`.vscode/tasks.json`** — `curl | bash` payloads pointing at attacker-controlled Vercel C2 servers.
4. **Fake `.woff2` font files** — payload hidden in binary assets, executed via Node.

Once on a dev's machine, the malware:

- Spawns a hidden `node -e global['_V']=...` process
- Removes `.env*` from `.gitignore` so secrets would leak
- Drops `temp_auto_push.bat` — a Windows batch file that **silently rewrites git commits with falsified timestamps**, force-pushing payloads to every branch the victim can write to
- Phones home to `auth-con-firm.vercel.app`, `auth-rho-dun.vercel.app`, `default-configuration.vercel.app`, and other Vercel-hosted C2 domains

Two distinct obfuscator variants are active in the wild (`rmcej%otb%` and `Cot%3t=shtP`), and OSM has documented **at least one re-infection** of a previously-cleaned victim. PolinShield detects both.

PolinShield blocks this attack pattern at five independent layers, so even if one fails, the others still catch it.

## Install

### Homebrew

```bash
brew install --cask louayzouaoui1/tap/polinshield
```

### Direct download

[**↓ Latest Release (.dmg)**](https://github.com/Louayzouaoui1/polinshield/releases/latest)

### Build from source

```bash
git clone https://github.com/Louayzouaoui1/polinshield.git
cd polinshield
make install     # builds, signs, installs to /Applications
```

Requires macOS 14+ and Swift 6. See [INSTALL.md](docs/INSTALL.md) for details and Gatekeeper bypass instructions.

## How it works

PolinShield is a SwiftUI menu bar app that orchestrates 5 plain-bash defense layers. The bash scripts are auditable in plain text under [`Resources/scripts/`](Resources/scripts/) — you can run them standalone, inspect them, or copy them into your own tooling.

| # | Layer | Mechanism | Why |
|--:|---|---|---|
| 1 | **Block npm install scripts** | `ignore-scripts=true` in `~/.npmrc` and `~/.config/pnpm/global-config` | Stops postinstall malware before it ever runs. The single most effective defense. |
| 2 | **DNS-block C2 servers** | Add known attacker domains to `/etc/hosts` as `0.0.0.0` | Even if reinfected, malware can't phone home or fetch new instructions. |
| 3 | **Git pre-commit hook** | Global hook at `~/.git-hooks/pre-commit` checking for IOC strings, forbidden filenames, and accidentally-staged `.env` files | Infected files can't reach a remote, even if other layers fail locally. |
| 4 | **Hourly force-push detector** | LaunchAgent calling the GitHub Events + compare APIs every 3600s | Catches active campaigns within an hour. The notification names the repo and branch, so you know what to check. |
| 5 | **Daily malware scan** | LaunchAgent running at 9am daily | Backstop — searches Desktop for IOC patterns and persistence paths. |

### Force-push detection (layer 4)

PolinRider spreads by **force-pushing** rewritten history to every branch you can
write to. This layer catches that within the hour.

**Setup — two commands:**

```bash
brew install gh          # the GitHub CLI does the API calls
gh auth login            # log in as yourself; needs the default 'repo' scope
```

That's it. Open PolinShield → **Install** on "Hourly force-push detector". Without
`gh` authenticated, this layer is silent — the menu bar shows ⚠️ yellow.

**How it detects a force-push.** A normal push adds commits on top of what was there.
A force-push replaces history, so the new HEAD no longer contains the old commit.
PolinShield asks GitHub to compare the two:

```
GET /users/<you>/events          → every push in the last hour
GET /repos/<repo>/compare/<before>...<head>
    behind_by > 0                → old HEAD is gone ⇒ history was rewritten ⇒ alert
```

Brand-new branches (`before` is all zeros) are creates, not rewrites, and are ignored.

> **Note:** GitHub no longer populates the `size`/`forced` fields on PushEvents, so
> anything still checking `payload.size == 0` silently detects nothing. The compare
> check above is what actually works.

**What the alert looks like.** The notification names the repos, so you can act
without opening anything:

```
🚨 GitHub Force-Push Alert
Louay24/opti-lens-magic/toumi-optique, tryloop-org/grafana-monitoring-stack/main
```

Beyond three, it appends `+N more`. Full history lives in the dashboard.

**If the network is down** (launchd fires on wake, before Wi-Fi reconnects), the check
retries 3×, then exits without moving its watch window forward — so that hour gets
re-checked on the next run instead of being skipped. It fails closed: a missed check
is never reported as "all clear".

**Verify it works:**

```bash
# Run the installed check by hand — exit 0 and no alert means no force-pushes
bash ~/Library/Application\ Support/PolinShield/check-force-pushes.sh; echo "exit=$?"

# Confirm the hourly agent is loaded
launchctl print gui/$(id -u)/dev.polinshield.force-push | grep -E "state|last exit code"
```

`last exit code = 0` means the last run completed. A non-zero code means it couldn't
reach GitHub and will retry.

### What you see

Always-visible status icon in the menu bar:

| Icon | Meaning |
|---|---|
| 🛡️ Green | All defenses active, last scan clean |
| ⚠️ Yellow | One or more defenses missing |
| 🚨 Red | Active infection indicators detected |

Click for a dropdown showing each defense's state, last scan summary, and quick actions. Open the dashboard for full scan/force-push history.

## Privacy & trust

PolinShield is built around the assumption that **you shouldn't have to trust me** to use it.

- **MIT licensed**, fully open source
- **No telemetry**, no analytics, no error reporting
- **No auto-update** — updates come via Homebrew or manual DMG re-download
- **No background daemon as root** — all persistence is at user level
- **Read-only GitHub calls**, made by the GitHub CLI on your machine: `GET /users/<you>/events` once an hour, plus one `GET /repos/.../compare/...` per push found in that hour (usually zero). Nothing is sent anywhere else, and nothing is written to your repos.
- The actual defenses are **bash scripts you can read and audit**, not opaque Swift code.

The Swift binary is ~400 KB. The full source is ~700 lines of Swift + ~250 lines of bash. Auditable in an afternoon.

## Documentation

- 📖 **[The threat: PolinRider technical writeup](docs/THREAT.md)** — IOCs, attack chain, why detection is hard, full timeline
- 🛠️ **[Installation guide](docs/INSTALL.md)** — Install, first-run setup, verification, uninstall
- 🏗️ **[Architecture](docs/ARCHITECTURE.md)** — How the SwiftUI front-end and bash engine fit together
- 🤝 **[Contributing](CONTRIBUTING.md)** — How to report new IOCs and submit changes
- 🔒 **[Security policy](SECURITY.md)** — How to report vulnerabilities

## Trade-offs you should know

- **`ignore-scripts=true` breaks packages that need install scripts** (`sharp`, `node-canvas`, native bindings). To install those: `npm install --foreground-scripts <pkg>` after auditing.
- **Force-push detection requires the GitHub CLI** authenticated as your user (`brew install gh && gh auth login`). Without it, layer 4 is silent — the menu bar shows ⚠️ yellow rather than pretending you're covered. It only sees pushes the API reports for your account, so pushes to repos you don't own aren't covered.
- **Ad-hoc signed.** First launch on each Mac may need a right-click → Open to bypass Gatekeeper. We don't have an Apple Developer ID. If you'd like to donate one, [open an issue](https://github.com/Louayzouaoui1/polinshield/issues).

## FAQ

### Is the malware still active in the wild?

Yes — and growing. As of the most recent OSM dossier update (April 2026), the campaign is **doubling every ~5 weeks**. New variants and C2 domains are appearing regularly. PolinShield's IOC list is updated as new ones are reported — see [issues](https://github.com/Louayzouaoui1/polinshield/issues) and the [OSM canonical dossier](https://github.com/OpenSourceMalware/PolinRider).

### Why a menu bar app and not a CLI?

Two reasons. First, the malware works because developers don't notice it; making protection visible in the menu bar is itself a defense — you'll spot a yellow ⚠️ shield long before you'd notice an extra config file. Second, GUIs are easier for non-security-focused teammates to install and verify.

### Will PolinShield slow down my machine?

No. The Swift app uses ~10 MB of RAM. The hourly force-push check is a single GitHub API call. The daily scan is a `grep -r` on `~/Desktop` (typically <30 seconds).

### Does PolinShield protect against [other npm attack X]?

The 5 layers are pattern-based, not specific to PolinRider. Layer 1 (`ignore-scripts`) blocks **any** postinstall malware. Layer 3's pre-commit hook can be extended with new IOCs. Layer 4 catches **any** unexpected force-push regardless of payload. So while PolinShield is named after PolinRider, it generalizes to most current npm supply-chain attack patterns.

### Why "PolinShield"?

Because it shields you from PolinRider. We're not very imaginative.

## Status

PolinShield is **v1.0.0**. The defenses are battle-tested (I built this after my own infection, and they survived an active malware reinfection during testing). The UI is functional but spartan. Improvements welcome.

## Credits

- Built by [@Louayzouaoui1](https://github.com/Louayzouaoui1) after a confirmed PolinRider infection in May 2026.
- The threat dossier and IOC research is the work of the **[OpenSourceMalware](https://github.com/OpenSourceMalware/PolinRider)** team — please support their work, follow their feed, and report new variants there.
- Inspired by realizing that the npm install-script attack surface is the modern equivalent of running random `.exe` files from email.

## License

[MIT](LICENSE) — use it, fork it, audit it, redistribute it.

---

<div align="center">

**Found PolinShield useful? Star ⭐ this repo so other developers find it.**

[Report an issue](https://github.com/Louayzouaoui1/polinshield/issues) · [Suggest an IOC](https://github.com/Louayzouaoui1/polinshield/issues/new) · [Read the threat writeup](docs/THREAT.md)

</div>
