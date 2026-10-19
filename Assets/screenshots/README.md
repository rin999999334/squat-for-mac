# Demo screenshots

All images show **demo data**, not the owner’s usage or exercise history. They were captured from the app’s own native views with its existing synthetic preview fixtures. The UI was not redrawn or composited. No camera session, actual workout, chat message, personal records, or global screen capture was used.

- `home-demo.png`: native Home view, synthetic 15 exercise days, target 9 reps, 30 reps on the fixture day.
- `detail-demo.png`: native Detail view, synthetic calendar and 258 total reps.
- `settings-demo.png`: native English Settings; fixture switches are OFF. This is a UI example, not a recommended tracking setup.
- `today-card-demo.png`: native Today image export, synthetic 30 reps.
- `total-card-demo.png`: native Total image export, synthetic 18 elapsed days, best streak 5 days, 258 reps.
- `menu-demo.png`: actual native menu summary view in a functional harness with dummy durations; not a capture of real usage. It shows ChatGPT/Codex and Claude separately. The menu canvas is white for legibility.

The first five use the app’s built-in capture/export paths in a temporary copy with the preview bundle ID, no personal storage/profile key, the preview-only preferences suite, and a randomly created temporary SQLite database. The production app and user’s existing review app were not modified. The synthetic preview suite is separate from real profile preferences. The menu view uses the same source class with dummy settings/usage objects.

`DEMO_CAPTURE.json` records image dimensions, hashes, and capture metadata. Captures report `cameraRunning: false`, `workoutActive: false`, full content opacity, and no transition in progress. These images are visual UI evidence, not proof of real camera accuracy, notification delivery, or hook integration.

The `--h--m` entries are the app’s actual display when the fixture contains no time measurements. They were not replaced with invented usage numbers.
