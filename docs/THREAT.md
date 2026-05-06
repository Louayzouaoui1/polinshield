# The PolinRider / openclaw Supply-Chain Attack — Technical Writeup

> First disclosed publicly on [opensourcemalware.com](https://opensourcemalware.com/blog/polinrider-attack) in March 2026.
> This document is a technical companion to the [PolinShield](../README.md) defense tool, derived from a confirmed infection on a developer's machine in May 2026 that hit **68 GitHub repositories with 200+ malicious force-pushes**.

## Summary

PolinRider is a **supply-chain attack** against JavaScript developers. It enters the victim's machine via a malicious npm package's `postinstall` script (most notably `openclaw` and `openclaw-app`), establishes persistence as a hidden Node.js process, and silently injects payloads into popular config files (`postcss.config.*`, `tailwind.config.*`, etc.) that get **force-pushed to every git remote the user can write to**.

The attack succeeds because:

1. JavaScript build tools execute config files at every dev/build cycle, so the payload runs on every `npm run dev`.
2. The payload is appended after the legitimate config (often with whitespace padding) so editors and PR review tools don't show it.
3. Git force-pushes are silent and the malware times them with the user's own pushes to look like a single normal commit.
4. The campaign's two known C2 servers are hosted on Vercel (a trusted platform), defeating naive domain-reputation filters.

## Indicators of Compromise (IOCs)

### Filesystem
| Path | Description |
|---|---|
| `~/openclaw-app/` | Node.js dropper application |
| `~/.openclaw/` | Config / credentials / state directory |
| `~/.node_modules/` | C2 client (axios + socket.io-client packages) |
| `~/polinrider-scanner.sh` | Bait scanner that variants drop |
| `~/Library/LaunchAgents/com.openclaw*.plist` | Persistence |

### Process pattern
```
node -e global['_V']='A9-XXXX-X';global['r']=require;global['m']=module;(async()=>{...
```
A process whose argv begins with `node -e global['_V']=` and runs continuously. Variants exist (`A8-`, `B-`, etc.).

### Source-code signature (canonical)
```
("rmcej%otb%",2857687)
```
This is the **fixed-string** signature most reliably present in every infected file — the `2857687` constant and `rmcej%otb%` substring are seed values for the runtime decoder.

### Secondary signature
```
global['!']='X-NNNN-N'
```
Where `X` is a single character and `N` are digits. Always at the start of the appended payload.

### Forbidden filenames (committed alongside the payload)
- `config.bat`
- `temp_auto_push.bat`
- `temp_interactive_push.bat`

### .gitignore tampering
The malware **removes** `.env*` from `.gitignore` (so any committed `.env` would leak) and **adds** `config.bat` (so its dropper artifacts don't get accidentally tracked).

### .env C2 dropping
The malware drops `.env` files containing only:
```
AUTH_API_KEY="aHR0cHM6Ly9hdXRoLWNvbi1maXJtLnZlcmNlbC5hcHAvYXBp"
```
This is base64 for `https://auth-con-firm.vercel.app/api`. A second variant uses:
```
AUTH_API_KEY="aHR0cHM6Ly9hdXRoLXJoby1kdW4udmVyY2VsLmFwcC9hcGk="
```
→ `https://auth-rho-dun.vercel.app/api`

### Network IOCs
| Host | Purpose |
|---|---|
| `auth-con-firm.vercel.app` | Primary C2 |
| `auth-rho-dun.vercel.app` | Secondary C2 |

## Targeted file types

The malware appends its payload to these config files (the pattern is "any file Node.js will require during a build"):

- `postcss.config.{js,mjs,cjs}`
- `tailwind.config.{js,mjs,cjs}`
- `eslint.config.{mjs,js}`
- `next.config.{js,mjs,ts}`
- `vite.config.{js,ts,mjs}`
- `babel.config.js`

## Attack chain

```
1. Victim runs:  npm install <pkg>
                 (where <pkg> depends on openclaw/openclaw-app or
                 is a typosquatted name)
                                ↓
2. postinstall script writes:  ~/openclaw-app/    (Node.js dropper)
                               ~/.openclaw/        (state)
                               ~/.node_modules/    (C2 client)
                               ~/Library/LaunchAgents/com.openclaw*.plist
                                ↓
3. LaunchAgent fires on every login:
   spawns: node -e global['_V']='X-NNNN-N';...
                                ↓
4. The Node process:
   a. Watches for git repo activity
   b. On every save/build of postcss.config.* etc., appends payload
   c. On every git push, also force-pushes injected commits
   d. Phones home to auth-con-firm.vercel.app for new payloads
                                ↓
5. Spread:  Force-pushed payloads spread to teammates' machines via:
   - git pull (pulls the infected config)
   - npm run dev (executes the infected config → infects teammate's repos)
```

## Why it's hard to detect

1. **Visual stealth.** The payload is appended on the same line as the closing `};` of the legitimate config, with hundreds of spaces as left-padding. In most editors and GitHub diff views, you'd need to horizontally scroll to see it.
2. **Bundles with real work.** The malware doesn't push standalone — it intercepts your real commits and adds the payload + `.gitignore` mods to them. The commit message and most file changes are legitimately yours.
3. **Hidden process name.** `node -e ...` shows up generically in `ps`, mixed in with esbuild, vite, next dev, etc.
4. **No file modification of the original config text.** The original code is preserved verbatim; the payload is purely *appended*. Reviewers checking "did my code change" see no difference.
5. **Plausible package.** `openclaw` describes itself as "Multi-channel AI gateway" — it's plausible enough that developers install it intentionally.

## Defense priorities (in order of cost-effectiveness)

1. **Block npm postinstall scripts globally** with `ignore-scripts=true`. This single setting would have prevented this entire incident. Trade-off: some legit packages need install scripts (sharp, native libs) — install those with `--foreground-scripts <pkg>` after auditing.
2. **DNS-block the C2 domains** in `/etc/hosts`. Even if reinfected, the malware can't fetch new instructions or upload secrets.
3. **Pre-commit hook** that fails on any IOC string. Stops infected files from reaching the remote.
4. **Force-push monitoring** via the GitHub Events API. Catches active campaigns within an hour without any local agent.
5. **Daily disk scan** for IOCs. Backstop for cases where layers 1–4 fail.

PolinShield implements all five.

## Cleanup checklist (if you've been infected)

1. Kill running malware: `ps aux | grep "node -e global" | grep -v grep | awk '{print $2}' | xargs kill -9`
2. Remove persistence: `rm -rf ~/openclaw-app ~/.openclaw ~/.node_modules ~/polinrider-scanner.sh`
3. Remove LaunchAgents: `rm ~/Library/LaunchAgents/com.openclaw*.plist`
4. Strip the source line from `~/.zshrc`/`~/.bashrc`: `sed -i '' '/openclaw/d' ~/.zshrc`
5. Strip the payload from infected config files (search for `rmcej%otb%`).
6. Delete malware-dropped `.env` files (any containing the C2 base64 strings).
7. Restore `.env*` to `.gitignore` if removed.
8. **Rotate every credential** that was on the machine: GitHub PATs, npm tokens, GitLab tokens, JWT secrets, cloud keys.
9. **Re-pull all team repos cleaned** (because the malware force-pushed payloads to many of them; you need the cleaned versions or you'll re-infect locally).
10. Reboot.

## Credentials at risk

If your `.npmrc` had auth tokens in plaintext (the common case for private GitHub Packages / GitLab npm), the malware had access to them via reading `~/.npmrc`. Tokens to rotate:

- GitHub PATs (`ghp_*`, `gho_*`)
- npm tokens (`npm_*`)
- GitLab tokens (`glpat-*`)
- Any `_authToken` lines in `.npmrc`

If you committed any `.env` files (which the malware tries to enable by tampering `.gitignore`), assume those secrets leaked too.

## Forensic timeline (from the May 2026 confirmed case)

| Date | Event |
|---|---|
| 2026-04-08 | `~/openclaw-app` and `~/.openclaw` created on victim's Mac |
| 2026-04-13 | First infection of a config file in a local git repo |
| 2026-04-30 | First malicious force-push to a remote (one repo) |
| 2026-05-04 → 05 | Mass campaign: 200 force-pushes across 68 repos in ~30 hours |
| 2026-05-05 | Detection by the victim |
| 2026-05-06 | Cleanup complete; PolinShield released |

The 17-day gap between local infection (Apr 13) and active force-pushing (Apr 30) suggests the malware waits / phases. This is consistent with a C2-driven campaign rather than autonomous behavior.

## References

- [opensourcemalware.com — PolinRider Attack](https://opensourcemalware.com/blog/polinrider-attack)
- [Risky Business: GitHub is starting to have a real malware problem](https://news.risky.biz/risky-bulletin-github-is-starting-to-have-a-real-malware-problem/)
- [npm advisory database](https://github.com/advisories) (file an issue if you find a new variant)

## Reporting new variants

If you find a new IOC (signature, C2 domain, persistence path), please [open an issue](https://github.com/Louay24/polinshield/issues/new) on PolinShield. New IOCs are added to the bash defenses on every release.
