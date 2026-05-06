# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in PolinShield, please **do not open a public issue**. Instead:

1. Email **security reports** to the maintainer (see GitHub profile for current contact)
2. Or use [GitHub's private vulnerability reporting](https://github.com/Louay24/polinshield/security/advisories/new)

Please include:
- A description of the issue
- Steps to reproduce
- Affected version(s)
- The impact (what an attacker could do)

We'll respond within 7 days. If the issue is confirmed, we'll work on a fix and credit you in the release notes (unless you prefer to remain anonymous).

## What counts as a vulnerability

- Anything that lets an attacker bypass the 5 defense layers from outside the system
- Anything that lets an attacker tamper with PolinShield's installed defenses
- Privilege escalation in the install scripts
- The app phoning home to a domain that's not `api.github.com`
- Hardcoded credentials, secrets, or backdoors

## What does NOT count

- "PolinShield can be uninstalled with `rm`" — this is by design.
- "User can bypass the pre-commit hook with `--no-verify`" — this is by design (so you can ship legit code containing IOC strings, e.g. a security tool).
- "PolinShield doesn't catch malware variant X" — open a regular issue, not a security report.
- "I can read PolinShield's source" — yes, that's the whole point.

## Supported versions

We patch the latest minor release. Older versions don't get security patches — please update.

## Trust model

PolinShield assumes:

1. **Your Mac is not already compromised** at install time. If a malicious process is already running as your user, it can disable PolinShield. The point of installing early is that you set defenses *before* infection, not as cleanup.
2. **`api.github.com` is trustworthy.** PolinShield uses the GitHub Events API for force-push detection. If GitHub is compromised, we can't help.
3. **`/etc/hosts` is respected by your network stack.** Some VPNs / DNS-over-HTTPS configurations bypass `/etc/hosts`. If you use those, the C2-block layer is reduced; the other 4 layers still work.

PolinShield does NOT trust:

- Any npm package (defense layer 1 blocks them all)
- Any new commit (layer 3 scans every staged file)
- Any unexpected force-push (layer 4 alerts immediately)

## Cryptographic signatures

The released `.dmg` files are signed with an ad-hoc codesign signature. We don't currently have an Apple Developer ID, so we can't notarize. If you want to verify a release came from us, check that:

1. The release was tagged on the `main` branch by the maintainer's GitHub account
2. The Actions log shows the build came from that tag's commit SHA
3. The SHA256 in the release notes matches what you downloaded

This isn't as good as Developer ID + notarization, but it's better than nothing.

If a kind soul wants to donate an Apple Developer ID for the project, please open an issue.
