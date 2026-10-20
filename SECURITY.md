# Security

## Current status

Squat for Mac 0.9.3 is the published public preview. Review findings and test evidence are release inputs, not a guarantee that every defect has been found. There is no externally certified security assessment or published support SLA.

Normal time tracking and camera counting run locally. Camera permission is requested when starting a camera session. The normal runtime does not need Accessibility, Screen Recording, microphone access, an AI API key, or an AI account password. See [PRIVACY.md](PRIVACY.md) for data locations and intentional sharing.

## Reporting a concern

For a suspected vulnerability, use [GitHub private vulnerability reporting](https://github.com/rin999999334/squat-for-mac/security/advisories/new). Do not publish security details in a public issue. Do not attach credentials, personal databases, real conversations or camera recordings. Ordinary feedback can go through [the contact form](https://forms.gle/1ZvABbbDHBRJsd529).

A dedicated security email and support SLA have not been established. No response time is promised.

## Installation and permissions

The present local build uses ad hoc signing, not a Developer ID identity, and is not notarized by Apple. A valid local signature verifies bundle consistency; it does not establish a verified developer identity or prove the app is malware-free.

Download only from a release location the maintainer has actually published. The public preview is available from [GitHub Releases](https://github.com/rin999999334/squat-for-mac/releases/tag/v0.9.3). Follow [Apple's explanation of opening apps safely](https://support.apple.com/102445). Only consider an app-specific exception after verifying its origin and accepting the risk. Never disable Gatekeeper or System Integrity Protection, and do not remove quarantine as a blanket installation workaround.

The app does not register a login item, install privileged helpers, install an AI plugin, or download updates by itself. Users obtain each new version from GitHub Releases. When a newer downloaded copy is opened, it can replace the older Applications copy only after explicit confirmation. It validates the downloaded bundle and a staged copy, rejects a linked target, keeps a temporary backup during replacement, and restores the old app if final validation fails. If macOS does not allow writing to Applications, it leaves the old app unchanged and shows manual instructions.

## Known boundaries

- App-local records are not encrypted by the app. Other software with access to your macOS account may read them.
- The current app is not distributed as an App Store sandboxed product. A camera entitlement and the macOS camera consent dialog are not equivalent to full sandboxing.
- Temporary share files and clipboard contents can outlive the share sheet. Sharing is a deliberate disclosure.
- A locally rebuilt app may prompt for camera permission again if its signing identity changes.

See the [sanitized audit overview](docs/AUDIT.md) and [remaining acceptance checks](docs/KNOWN_ISSUES.md). Machine-readable internal review evidence is not shipped with user data.

## Maintainer release checks

For a stable release, complete the outstanding [release checklist](docs/RELEASE_PLAN.md), including Developer ID signing, notarization, supported-hardware acceptance and code-license selection. For each release, inspect the committed history and archive, exclude personal data and credentials, and verify third-party notices. The current public preview discloses these outstanding gates. Do not describe the current build as “Apple verified,” “fully audited,” or “completely secure.”
