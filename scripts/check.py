"""Standalone checks use isolated defaults/SQLite; never writes real workout history."""
from pathlib import Path
import subprocess
import tempfile
import sys
import os

root = Path(__file__).resolve().parent.parent
src = root / "Sources/SquatForMac"
history = ["WorkoutHistory", "SQLiteWorkoutRepository"]
movement = ["WorkoutPreparation", "FaceDepthLines", "FaceMovementCounter", "SquatCounter"]
checks = {
    "StorageProfileChecks": ["AIActivity", "UsageReminderInterval", "AppSettings", "RefreshExternalLinks", "PreviewConfiguration", "ProgressCalendarModel", "WorkoutHistory", "SQLiteWorkoutRepository"],
    "RefreshMenuUsageChecks": ["RefreshMenuUsage"],
    "RefreshV27Checks": ["AIActivity", "RefreshModels", "RefreshReminderCycle", "UsageReminderInterval"],
    "RefreshSpecificationChecks": ["AIActivity", "RefreshModels"],
    "DownloadedAppInstallerChecks": ["DownloadedAppInstaller"],
    "CounterChecks": ["WorkoutPreparation", "SquatCounter"],
    "FaceCounterChecks": movement[:3],
    "PreparationChecks": movement + ["CameraViewport"],
    "HistoryChecks": history,
    "StreakChecks": history,
    "CalendarChecks": history + ["ContributionCalendar"],
    "AppCoordinatorChecks": history + movement + ["CameraViewport", "FaceFraming", "Camera", "RecognitionIssue", "MoveStore", "AIActivity", "UsageReminderInterval", "AppSettings", "SessionResult", "AppCoordinator"],
}
# Agents add independently testable models; discover only checks that exist.
optional = {
    "RefreshPolishChecks": ["AIActivity", "RefreshModels", "RefreshPolishModels", "RefreshPresentation", "SessionResult"],
    "DesktopAIProfileChecks": ["AIActivity", "DesktopAIProfile"],
    "ReminderControllerChecks": ["AIActivity", "ReminderPolicy", "ReminderRuntime", "UsageReminderInterval", "AppSettings"],
    "FaceFramingChecks": ["FaceDepthLines", "CameraViewport", "FaceFraming"],
    "FramingStoreChecks": history + movement + ["CameraViewport", "FaceFraming", "Camera", "RecognitionIssue", "MoveStore"],
    "SQLiteHistoryChecks": history,
    "CameraOverlayChecks": ["CameraViewport"],
    "ProgressPerformanceChecks": history + ["ProgressCalendarModel", "ProgressDataCache", "ProgressRenderSnapshot"],
    "ProgressRenderingChecks": ["ProgressCalendarModel", "ProgressRenderSnapshot"],
    "UIModelChecks": ["ProgressCalendarModel", "ProgressSelection", "GoalRingModel", "CameraViewport"],
    "HistoryMigrationChecks": history,
    "GoalRingChecks": ["GoalRingModel"],
    "ProgressCalendarChecks": ["ProgressCalendarModel"],
    "UsageReminderChecks": ["SessionResult", "UsageReminderInterval", "UsageTimeTracker", "UsageReminderPolicy", "AIActivity", "ReminderPolicy", "ReminderRuntime"],
    "AIActivityChecks": ["AIActivity", "ReminderPolicy"],
    "ReminderChecks": ["AIActivity", "ReminderPolicy"],
}
for name, units in optional.items():
    if (root / "Tests" / (name + ".swift")).exists(): checks[name] = units
for units in checks.values():
    if "AppSettings" in units and "RefreshExternalLinks" not in units: units.append("RefreshExternalLinks")
selected = sys.argv[1:] or list(checks)
cache = root / ".build/check-module-cache"
cache.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="squat-checks-") as scratch:
    for name in selected:
        if name not in checks: raise SystemExit(f"Unknown check: {name}")
        output = Path(scratch) / name
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-O", "-module-cache-path", str(cache),
                        *[str(src / (unit + ".swift")) for unit in checks[name]],
                        str(root / "Tests" / (name + ".swift")), "-lsqlite3", "-o", str(output)], check=True)
        subprocess.run([str(output)], check=True, env={**os.environ, "TMPDIR": scratch + "/"})
