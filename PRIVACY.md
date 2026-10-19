# Privacy

Applies to the Squat for Mac 0.9.1 private pre-release source tree, as reviewed on 2026-10-19. This describes this app's implementation, not the privacy practices of ChatGPT, Claude, macOS, or sites you choose to open.

## What runs on your Mac

| Information | Why it is used | Persistence |
| --- | --- | --- |
| Frontmost application identifier | Recognize selected ChatGPT/Codex or Claude use | Daily duration totals by provider are saved; no chronological window-title log is implemented. |
| Seconds since recent keyboard/mouse activity, screen/session state | Pause while idle, asleep, or locked | Used for eligibility; key content and mouse coordinates are not recorded by the time tracker. |
| Camera frames and detected face position | Calibrate and count up/down movement | Frames and face rectangles are processed in memory. Video, photographs, and a face identity template are not saved or transmitted. |
| Workout dates/timestamps, session identifiers, counts and completion state | History, weekly checks and share statistics | Saved in a local SQLite database. |
| Settings and daily AI/Desk durations | Restore preferences and accumulated time | Saved in macOS preferences. |

The normal runtime does not require Accessibility access, Screen Recording, microphone access, or your AI account credentials. Legacy Accessibility-related source exists in the tree; the current app entry point does not enable that observation flow.

No analytics SDK, cloud sync, remote AI request, or app-owned network telemetry is implemented in the current runtime. No model calls or extra AI tokens are needed for time tracking or camera counting.

## What leaves only when you choose it

- **Contact us** opens a Google Form in your browser. Anything you enter is handled by the form owner and Google. The app does not submit the form or attach a diagnostic file automatically.
- **X / Instagram** opens the external site. X receives the GitHub URL through its compose link. The app does not upload your image or publish a post automatically.
- **Copy image / Copy URL** puts the chosen data on the system clipboard. Other apps and any enabled clipboard synchronization may be able to access it.
- **Save / macOS Share** writes the image where you choose or passes the image file and GitHub URL to the sharing service you select. That destination's terms and privacy behavior then apply.

Today/Total cards can reveal exercise habits, dates, usage durations and streak statistics. Preview the card before sharing. Shared images do not include camera frames or conversation text.

## Local files, retention and removal

A standard build stores workout history at:

```text
~/Library/Application Support/Squat/workout.sqlite
```

SQLite may also maintain adjacent `-wal` and `-shm` files. Migrating older history can retain JSON copies in a `Legacy Backups` subfolder and a legacy archive in preferences; those copies are not deleted automatically after migration. Settings and usage totals use the app's preferences domain (`local.thinkandmove.mvp`). The database and preferences are not encrypted by this app; they rely on your macOS account and device protections.

A personal installation migrated from a review build may carry an optional `SquatStorageProfile` value. Its records are stored under:

```text
~/Library/Application Support/Squat for Mac/Profiles/<UUID>/workout.sqlite
```

It retains the matching review preferences suite (`local.thinkandmove.qa.<UUID>`). The UUID is a local storage selector, not a cloud account. Personal records, preferences, profile identifiers, and backups must not be included in a distributable app or repository.

Prepared share PNGs are also written to the app's temporary `SquatReviewV27-Share` folder. The folder is cleared when the share controller is initialized on a later launch; it can remain after closing a share sheet or quitting. Images you explicitly save remain in your chosen location. System backups, clipboard history, and posted copies are outside the app's deletion control.

There is no in-app “erase all data” control yet. To remove local app data, first quit the app, back up anything you need, then remove only the relevant database folder and preferences domain for your installation. Removing just the `.app` does not remove those records. Do not delete unrelated review profiles or shared temporary folders blindly.

## Experimental local plugin

The optional Codex helper uses a local Unix-domain socket and a random token. It forwards bounded event identifiers, a generation identifier and timing metadata, not the prompt text or the AI response. It makes no model request. The host may still provide hook input to the helper process; the helper parses only metadata and does not persist its input.

The socket receiver checks the same macOS user, token and message schema. Reminder delivery additionally requires a current generation and a fresh event; the connection-status indicator by itself does not establish those delivery conditions. These checks do not isolate it from malicious software already running as your user. The bundled helper currently targets a review-specific receiver while the regular app uses another receiver. This integration is not ready for general use; keep time mode for normal use.

[Return to README](README.md) · [Security](SECURITY.md)
