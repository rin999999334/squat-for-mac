"""Standard-library CLI tests using synthetic files under one temporary folder."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).resolve().parent.parent / "scripts/build_cache.py"


class BuildCacheChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="squat cache checks ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for relative, content in {
            "Sources/SquatForMac/App.swift": b"// synthetic Swift input\n",
            "Sources/SquatForMac/Resources/Fonts/font.ttf": b"font\x00bytes",
            "Sources/SquatForMac/Resources/ja.lproj/InfoPlist.strings": "camera = カメラ;".encode(),
            "Info.plist": b"synthetic plist",
            "SquatForMac.entitlements": b"synthetic entitlements",
            "scripts/build.sh": b"synthetic build",
            "scripts/preview.sh": b"synthetic preview",
            "scripts/build_cache.py": b"synthetic helper input",
        }.items():
            self.write(relative, content)
        self.app = self.root / "output/Squat.app"
        self.executable = self.app / "Contents/MacOS/SquatForMac"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(b"not an executable; synthetic bundle bytes")
        self.executable.chmod(0o755)
        (self.app / "Contents/Info.plist").write_bytes(b"bundle metadata")
        resource = self.app / "Contents/Resources/data.bin"
        resource.parent.mkdir()
        resource.write_bytes(b"bundled asset")
        self.cache = self.root / ".build/cache.json"

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        path.chmod(0o644)
        return path

    def cli(self, *arguments):
        return subprocess.run([sys.executable, str(HELPER), *map(str, arguments)], capture_output=True, text=True)

    def fingerprint(self, **changes):
        values = {"mode": "production", "identity": "-", "target": "arm64-apple-macosx13.0", "toolchain": "synthetic Swift and SDK"}
        values.update(changes)
        arguments = ["inputs", "--root", self.root]
        for key, value in values.items():
            arguments.extend(("--" + key, value))
        result = self.cli(*arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"\A[0-9a-f]{64}\n\Z")
        return result.stdout.strip()

    def record(self, fingerprint, **changes):
        return self.cli("record", "--cache", changes.get("cache", self.cache), "--fingerprint", fingerprint,
                        "--app", changes.get("app", self.app))

    def matches(self, fingerprint, **changes):
        result = self.cli("matches", "--cache", changes.get("cache", self.cache), "--fingerprint", fingerprint,
                          "--app", changes.get("app", self.app))
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")
        return result.returncode == 0

    def test_record_and_match_round_trip(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint).returncode, 0)
        self.assertTrue(self.matches(fingerprint))
        saved = json.loads(self.cache.read_text())
        self.assertEqual(saved["input_sha256"], fingerprint)
        self.assertRegex(saved["app_sha256"], r"\A[0-9a-f]{64}\Z")
        self.assertEqual(list(self.cache.parent.glob("*.tmp")), [])

    def test_source_content_change(self):
        before = self.fingerprint()
        self.write("Sources/SquatForMac/App.swift", b"// changed source\n")
        self.assertNotEqual(before, self.fingerprint())

    def test_source_addition(self):
        before = self.fingerprint()
        self.write("Sources/SquatForMac/New.swift", b"// another source")
        self.assertNotEqual(before, self.fingerprint())

    def test_nested_resource_change_addition_and_removal(self):
        before = self.fingerprint()
        resource = self.write("Sources/SquatForMac/Resources/Fonts/font.ttf", b"changed font")
        changed = self.fingerprint()
        self.assertNotEqual(before, changed)
        extra = self.write("Sources/SquatForMac/Resources/new/nested/image.png", b"image")
        added = self.fingerprint()
        self.assertNotEqual(changed, added)
        extra.unlink()
        self.assertNotEqual(added, self.fingerprint())
        resource.unlink()
        self.assertNotEqual(changed, self.fingerprint())

    def test_selected_metadata_and_scripts_change(self):
        for relative in ("Info.plist", "SquatForMac.entitlements", "scripts/build.sh", "scripts/preview.sh", "scripts/build_cache.py"):
            with self.subTest(relative=relative):
                path = self.root / relative
                original = path.read_bytes()
                before = self.fingerprint()
                path.write_bytes(original + b" changed")
                self.assertNotEqual(before, self.fingerprint())
                path.write_bytes(original)

    def test_file_modes_are_inputs_but_mtime_is_not(self):
        path = self.root / "Sources/SquatForMac/App.swift"
        before = self.fingerprint()
        info = path.stat()
        os.utime(path, ns=(info.st_atime_ns, info.st_mtime_ns + 100_000_000))
        self.assertEqual(before, self.fingerprint())
        path.chmod(0o640)
        self.assertNotEqual(before, self.fingerprint())

    def test_mode_identity_target_and_toolchain_are_separate_inputs(self):
        before = self.fingerprint()
        for change in ({"mode": "preview"}, {"identity": "fixed certificate fingerprint"},
                       {"target": "x86_64-apple-macosx13.0"}, {"toolchain": "different Swift or SDK"}):
            with self.subTest(change=change):
                self.assertNotEqual(before, self.fingerprint(**change))

    def test_root_before_subcommand_is_supported(self):
        after = self.fingerprint()
        result = self.cli("--root", self.root, "inputs", "--mode", "production", "--identity", "-",
                          "--target", "arm64-apple-macosx13.0", "--toolchain", "synthetic Swift and SDK")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), after)

    def test_missing_inputs_fail_without_traceback(self):
        (self.root / "Info.plist").unlink()
        result = self.cli("inputs", "--root", self.root, "--mode", "production", "--identity", "-", "--target", "test", "--toolchain", "test")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)

    def test_input_file_and_directory_symlinks_are_rejected(self):
        resources = self.root / "Sources/SquatForMac/Resources"
        for target in (resources / "Fonts/font.ttf", resources / "Fonts"):
            with self.subTest(target=target):
                link = resources / "linked-input"
                link.symlink_to(target, target_is_directory=target.is_dir())
                result = self.cli("inputs", "--root", self.root, "--mode", "preview", "--identity", "-", "--target", "test", "--toolchain", "test")
                self.assertEqual(result.returncode, 1)
                self.assertNotIn("Traceback", result.stderr)
                link.unlink()

    def test_symlinked_source_directory_is_rejected(self):
        source = self.root / "Sources"
        renamed = self.root / "real-sources"
        source.rename(renamed)
        source.symlink_to(renamed, target_is_directory=True)
        result = self.cli("inputs", "--root", self.root, "--mode", "preview", "--identity", "-", "--target", "test", "--toolchain", "test")
        self.assertEqual(result.returncode, 1)

    def test_directory_with_swift_extension_is_not_a_source_file(self):
        (self.root / "Sources/SquatForMac/invalid.swift").mkdir()
        result = self.cli("inputs", "--root", self.root, "--mode", "production", "--identity", "-", "--target", "test", "--toolchain", "test")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)

    def test_missing_and_changed_fingerprint_cache_miss(self):
        fingerprint = self.fingerprint()
        self.assertFalse(self.matches(fingerprint))
        self.assertEqual(self.record(fingerprint).returncode, 0)
        self.assertFalse(self.matches("0" * 64))
        self.assertFalse(self.matches("invalid"))

    def test_corrupt_cache_is_a_quiet_miss(self):
        fingerprint = self.fingerprint()
        self.cache.parent.mkdir()
        for contents in ("{broken JSON", "null", "[]", '{"schema":99}', "x" * 20_000):
            with self.subTest(contents=contents[:30]):
                self.cache.write_text(contents)
                self.assertFalse(self.matches(fingerprint))

    def test_changed_or_missing_output_is_a_miss(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint).returncode, 0)
        original = self.executable.read_bytes()
        self.executable.write_bytes(b"tampered bundle")
        self.assertFalse(self.matches(fingerprint))
        self.executable.write_bytes(original)
        self.assertTrue(self.matches(fingerprint))
        self.executable.unlink()
        self.assertFalse(self.matches(fingerprint))

    def test_unexpected_output_and_mode_changes_are_a_miss(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint).returncode, 0)
        extra = self.app / "unexpected.txt"
        extra.write_text("not in the original bundle")
        self.assertFalse(self.matches(fingerprint))
        extra.unlink()
        self.assertTrue(self.matches(fingerprint))
        self.executable.chmod(0o644)
        self.assertFalse(self.matches(fingerprint))

    def test_output_directory_modes_and_empty_entries_are_covered(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint).returncode, 0)
        empty = self.app / "empty"
        empty.mkdir()
        self.assertFalse(self.matches(fingerprint))
        empty.rmdir()
        self.assertTrue(self.matches(fingerprint))
        self.app.chmod(0o700)
        self.assertFalse(self.matches(fingerprint))

    def test_bundle_root_and_descendant_symlinks_are_rejected(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint).returncode, 0)
        linked_app = self.root / "linked.app"
        linked_app.symlink_to(self.app, target_is_directory=True)
        self.assertEqual(self.record(fingerprint, app=linked_app).returncode, 1)
        self.assertFalse(self.matches(fingerprint, app=linked_app))
        (self.app / "Contents/linked-file").symlink_to(self.executable)
        self.assertFalse(self.matches(fingerprint))
        self.assertEqual(self.record(fingerprint).returncode, 1)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "FIFO test requires a POSIX filesystem")
    def test_special_file_rejection_does_not_replace_good_cache(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint).returncode, 0)
        previous = self.cache.read_bytes()
        os.mkfifo(self.app / "fifo")
        result = self.record(fingerprint)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(self.cache.read_bytes(), previous)
        self.assertFalse(self.matches(fingerprint))

    def test_cache_inside_bundle_and_symlinked_cache_are_rejected(self):
        fingerprint = self.fingerprint()
        self.assertEqual(self.record(fingerprint, cache=self.app / "cache.json").returncode, 1)
        self.assertFalse((self.app / "cache.json").exists())
        external = self.root / "original-cache.json"
        external.write_text("preserve this file")
        self.cache.parent.mkdir()
        self.cache.symlink_to(external)
        self.assertEqual(self.record(fingerprint).returncode, 1)
        self.assertFalse(self.matches(fingerprint))
        self.assertEqual(external.read_text(), "preserve this file")


if __name__ == "__main__":
    unittest.main()
