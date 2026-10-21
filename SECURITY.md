# Security policy

This project is experimental and not ready for use with real vehicles (see the warning in the [README](README.md)). Security reports are still very welcome, and they matter more here than in most projects.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately through GitHub: open the **Security** tab of this repository and choose **Report a vulnerability**.

Include what you found, how to reproduce it, and what an attacker could do with it. You will get an acknowledgement as soon as the maintainer can respond; this is a hobby project, so please allow some time. Please give us a chance to fix the problem before disclosing it publicly.

## What counts

Because this project controls vehicle hardware, we are especially interested in:

*   Anything that lets the app send commands without a valid pairing or bond, or weakens the BLE pairing flow.
*   Handling of MQTT credentials or other secrets (storage, logging, accidental inclusion in builds).
*   Ways to make the app send commands the user did not intend.
*   Debug-only code paths (such as the HTTP transport) reachable in release builds.

Only the latest `main` is supported; there are no maintained older releases yet.
