# Contributing

This repository is a public preview. No project-code license has been selected yet; access to the repository is not a grant of permission to redistribute or relicense its code. Third-party assets keep their own licenses.

Please discuss a feature or substantial behavior change with the owner before implementing it. The app is intentionally small: preserve agreed wording, layout, camera-counting behavior, and local data compatibility. Record newly discovered issues instead of silently adding unrelated features.

## Useful bug reports

Include the app version, macOS version, Mac architecture, selected AI apps, reminder mode, short reproduction steps, expected behavior, and actual behavior. For a timing issue, distinguish daily totals, active AI time until a reminder, and the wall-clock follow-up deadline.

Use synthetic screenshots and minimal examples. Do not attach a personal database, preferences file, prompt, camera recording, token or account credential. See [SECURITY.md](SECURITY.md) for private security reporting.

## Local development

```sh
./scripts/build.sh
```

The normal app is produced at `dist/Squat for Mac.app`. A separate UI review build can be produced with `./scripts/build.sh --preview`; it has a different bundle identifier and data profile. Do not use a real user's profile or database as a fixture. Keep generated app bundles, build caches, databases, private review artifacts and credentials out of commits.

For each change, describe the concrete behavior and its limit, perform the relevant build/tests, and preserve prior records. A simulated or isolated test does not prove real camera behavior, host hook compatibility, or every supported macOS version. Keep real-use validation separate from unit checks.

The owner will decide when to enable public issues, outside pull requests, a contribution license policy, and a public release cadence.
