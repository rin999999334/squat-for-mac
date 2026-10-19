<p align="center"><img src="Assets/AppIcon.png" width="128" alt="Squat for Mac icon"></p>

# Squat for Mac

**Turn time spent with AI into a small movement break.**

A local macOS menu bar app that tracks active time in ChatGPT/Codex and Claude, reminds you to move, and counts a short exercise session using your camera.

[日本語](README.ja.md) · [User guide](docs/USER_GUIDE.md) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Audit](docs/AUDIT.md) · [Known issues](docs/KNOWN_ISSUES.md)

> **0.9.2 · public preview for Apple Silicon.** Download the app below. Developer ID signing and Apple notarization are not available yet; read the first-launch instructions. Source-code licensing is still undecided, so this is not an open-source licensed release.

## Download

[Download Squat for Mac 0.9.2 — Apple Silicon ZIP](https://github.com/rin999999334/squat-for-mac/releases/download/v0.9.2/Squat-for-Mac-0.9.2-arm64.zip) · [Release notes](https://github.com/rin999999334/squat-for-mac/releases/tag/v0.9.2) · [First-launch instructions](docs/DOWNLOAD.md)

Download the ZIP, double-click to extract it, drag **Squat for Mac.app** into **Applications** in Finder, then open the app. No GitHub account is required to download.

## Preview

**Demo data.** These are captures of the native app, using synthetic dates and exercise records.

<p align="center"><img src="Assets/screenshots/home-demo.png" width="300" alt="Home with demo exercise records and a 9-rep target"></p>

<p align="center"><img src="Assets/screenshots/detail-demo.png" width="720" alt="Detail calendar with demo records totaling 258 reps"></p>

[Settings](Assets/screenshots/settings-demo.png) · [Today card](Assets/screenshots/today-card-demo.png) · [Total card](Assets/screenshots/total-card-demo.png) · [Menu summary — dummy durations](Assets/screenshots/menu-demo.png) · [Capture details](Assets/screenshots/README.md)

## What it does

- Counts foreground use of the selected native ChatGPT/Codex and Claude apps. When both are open, only the active app counts; their times feed one shared reminder interval.
- Shows today's ChatGPT/Codex and Claude times separately in the menu bar, with the active AI time remaining until the next reminder.
- Offers 30, 60, 90, 120, or 180 minutes between reminders. If you skip a break, one countdown reminder becomes due at the next interval or 45 minutes after the first reminder, whichever comes first.
- Counts camera-based up/down movements toward a target of 1–30 reps, with positioning guidance and recalibration.
- Keeps daily records, a contribution calendar, and Today/Total cards you can save or share.
- Supports Japanese and English, optional Desk time tracking, and adjustable soft sounds.

Camera processing runs on your Mac. Video is neither recorded nor uploaded. Normal use does not require Accessibility access. There is no account, telemetry service, or cloud sync in this app. See [what is stored and when information leaves the app](PRIVACY.md).

## Try the local build

The current build has been prepared on **Apple Silicon**. The declared deployment target is macOS 13; Intel builds and the full range of supported macOS versions have not been verified on hardware.

With Apple's command-line developer tools available, from the repository root:

```sh
./scripts/build.sh
open "dist/Squat for Mac.app"
```

The build is signed locally with an ad hoc signature by default. This is **not Developer ID signing or Apple notarization**. A downloaded build may be blocked by Gatekeeper. Follow [Apple's app-opening guidance](https://support.apple.com/102445) and the [installation notes](docs/USER_GUIDE.md#install-and-open); do not disable macOS protections.

1. Open Settings and enable the AI apps you want to count.
2. Enable notifications, choose an interval, and keep the default time-based timing mode.
3. Choose **Go Squat** and allow Camera access when you are ready to exercise.

The app stays in the menu bar when its window is closed. **Quit** stops tracking. It does not register itself to launch at login.

## Limits to know before trying it

| Feature | Current behavior |
| --- | --- |
| AI time | Native app foreground time; browser tabs and background generation are not measured as AI use. ChatGPT and Codex share one total. |
| Next reminder | Remaining **active AI time**, not a clock counting down while you use another app. It pauses while idle, asleep, locked, or exercising. |
| Send-triggered reminder | Experimental Codex integration only. Ordinary ChatGPT/Claude send or response-completion detection is not supported. The bundled helper currently targets the review receiver; this integration is unavailable in the public preview. Use time mode. |
| Exercise recognition | Face-position movement is a counting aid, not a verified assessment of squat technique. Lighting, framing, and other people can affect counting. |
| Social sharing | Save/add the PNG manually on X or Instagram; the app does not automatically upload or publish it. macOS sharing is also available. |
| Data | Stored locally, with no cloud sync or built-in export/import workflow. Keep your own backup before replacing a build. |

Read the [user guide and FAQ](docs/USER_GUIDE.md) for permission prompts, partial workouts, data locations, and troubleshooting.

## Feedback and project status

Report ordinary feedback through [Contact us](https://forms.gle/1ZvABbbDHBRJsd529). For a suspected vulnerability, follow [SECURITY.md](SECURITY.md); do not post private data or exploit details in a public issue.

If Squat for Mac is useful to you, a ⭐ Star or a shared link helps others discover it. Feedback is welcome. See the [release plan](docs/RELEASE_PLAN.md) for the remaining work toward a stable release.

Project-code rights remain reserved; no redistribution or modification license has been selected. Included third-party assets retain their own licenses: [Third-party notices](THIRD_PARTY_NOTICES.md).
