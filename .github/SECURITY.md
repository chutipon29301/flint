# Security Policy

## Supported versions

Flint is under active development. Only the **latest released version** receives
security fixes.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, use one of these private channels:

- Open a [private security advisory](https://github.com/chutiponh/flint/security/advisories/new)
  (preferred), or
- Email **chutipon.h@meesolution.com** with the details.

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce (or a proof of concept)
- Any relevant version / environment details

You can expect an initial response within **7 days**. Once the issue is
confirmed, a fix will be prioritized and you'll be credited in the release notes
unless you prefer to remain anonymous.

## Scope

Flint runs entirely on-device with **no network dependency** and requires no
account. Relevant areas include local input handling (malformed clipboard/file
input must never crash a tool), the optional Accessibility permission used for
paste-back, and the auto-update mechanism.
