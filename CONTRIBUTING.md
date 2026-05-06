# Contributing to PolinShield

Thanks for considering a contribution. PolinShield is a small, focused tool — the bar for changes is "does this make my Mac measurably safer against npm supply-chain attacks, without surprising me."

## Quick start

```bash
git clone https://github.com/Louay24/polinshield.git
cd polinshield
make app           # builds .build/PolinShield.app
open .build/PolinShield.app
```

You'll need:
- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 6.x

## How to contribute

### 🐛 Reporting a new IOC

This is the most useful contribution. If you spot a new variant of PolinRider/openclaw or a similar attack, [open an issue](https://github.com/Louay24/polinshield/issues/new) with:

- The IOC string / domain / file path you found
- Where you found it (anonymized if needed)
- Approximate date of infection
- Whether the IOC is already detected by PolinShield (run a scan and check)

We'll add it to the bash detectors in the next release.

### ✏️ Code changes

1. **Open an issue first** if it's a non-trivial change. We don't want anyone wasting time on a PR that won't be merged.
2. **Fork** the repo and create a feature branch: `git checkout -b feat/your-thing`.
3. **Make your change.** Keep it small. One concern per PR.
4. **Test it** by running `make app && open .build/PolinShield.app` and clicking around.
5. **Open a PR** with a clear description of what changed and why.

### 📝 Docs

Everything in `docs/` and the README is fair game. Typo fixes, clarifications, and new sections are all welcome.

## What we DO accept

- New IOC patterns
- Better detection scripts
- New defense layers (after issue discussion)
- UI/UX improvements
- Bug fixes
- Better docs and threat intel writeups
- Performance improvements
- New tests (we don't have many)

## What we DON'T accept

- **Telemetry / analytics / crash reporting** — PolinShield is privacy-preserving by design.
- **Auto-update mechanisms that aren't Homebrew/DMG** — auto-updaters are themselves a supply-chain attack vector.
- **Cloud features** — no "PolinShield Cloud", no central dashboard.
- **Anything that requires running as root** — defenses are user-level only.
- **Anything that makes the binary much larger** — we want this to stay small enough to audit and ship freely.

## Code style

- Swift: follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/), use `// MARK: -` for sections.
- Bash: `set -uo pipefail`, prefer `[ ... ]` over `[[ ... ]]` for portability when the difference doesn't matter.
- 2-space indent for bash, 4-space for Swift.

## Testing a release before publishing

```bash
make dmg
hdiutil attach .build/PolinShield-X.Y.Z.dmg
# drag PolinShield.app to /Applications
# launch, run through welcome wizard, install all defenses
hdiutil detach /Volumes/PolinShield*
```

Then verify each defense is in place:

```bash
grep ignore-scripts ~/.npmrc
grep auth-con-firm /etc/hosts
git config --global core.hooksPath
launchctl list | grep dev.polinshield
```

## Release process (maintainers only)

```bash
# Update version in Makefile, Casks/polinshield.rb, Sources/PolinShield/DashboardView.swift
git commit -am "chore: bump to vX.Y.Z"
git tag vX.Y.Z
git push origin main vX.Y.Z
# GitHub Actions builds and uploads the DMG to Releases automatically
# After release, update Casks/polinshield.rb sha256 and push
```

## Code of Conduct

Be respectful. We're all here because someone got hurt by malware and we want to help.

## License

By contributing, you agree your contribution is licensed under MIT.
