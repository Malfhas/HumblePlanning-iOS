# Security policy

## Supported versions

Security fixes are released for the latest version of the app. Administrators can require a minimum app version on their server.

| Version | Supported |
| --- | --- |
| 1.0.x | ✅ |
| < 1.0 | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities in public issues, discussions or pull requests.**

Report them privately through GitHub: [Report a vulnerability](https://github.com/Malfhas/HumblePlanning-iOS/security/advisories/new) (*Security* tab → *Report a vulnerability*). If you cannot use GitHub, write to **contact@indumia.com** with `[security]` in the subject.

A vulnerability of the server (`/api/mobile` and every other route) belongs to the [server's security policy](https://github.com/Malfhas/HumblePlanning/security/policy). When in doubt, report it here: we forward it.

Please include the app version (sign-in screen, or *Settings → About*), the iOS version and the device, the version of the server if it matters, a description of the vulnerability and its impact, the steps to reproduce it, and any suggestion for a fix.

## What to expect

- An acknowledgement within 5 business days.
- An assessment of the report, and regular updates until it is resolved.
- A fix released as a new version.
- A published security advisory once the fix is available, crediting you unless you prefer to stay anonymous.

We ask you to give us a reasonable time to release a fix before any public disclosure, and at most 90 days from your report. Please do not access, modify or delete data that does not belong to you, and do not degrade the service of a server you do not own (including the public demo).

## Scope

In scope: the app, the builds published by the maintainer, and how the app stores and sends data (session, offline copy, push token, QR code sign-in).

Out of scope: vulnerabilities that require a jailbroken or already compromised device, or a compromised server or administrator account; unsupported versions; builds that were not published by the maintainer; issues caused by a configuration that the documentation advises against; and reports from automated scanners without a demonstrated impact.

## Hardening recommendations

- Serve the Humble Planning server over HTTPS: the app refuses any other address.
- Keep a passcode on the device. Signing out, or revoking the device from the web profile, deletes the data kept on it.
- Administrators: set a minimum app version after a security release, and give the "Use the mobile app" permission only to the roles that need it.
