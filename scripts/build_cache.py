#!/usr/bin/env python3
"""Content-only build cache. The caller separately verifies the code signature.

No target code is imported or executed. Symlinks and special files are never
accepted as inputs or bundle entries; mtimes and extended attributes are not
part of the digest. Cache metadata stays outside the application bundle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


class CacheError(Exception):
    pass


def _field(digest, value):
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _metadata(digest, value):
    _field(digest, json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def _checked_stat(path):
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode):
        raise CacheError("Symlinks are not valid cache inputs or application entries.")
    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
        raise CacheError("Only regular files and directories are accepted.")
    return info


def _directory(path):
    info = _checked_stat(path)
    if not stat.S_ISDIR(info.st_mode):
        raise CacheError("A required directory is missing or is not a directory.")
    return info


def _checked_subdirectory(root, relative):
    path = root
    _directory(path)
    for part in Path(relative).parts:
        path = path / part
        _directory(path)
    return path


def _entries(path):
    """Enumerate without following links, including empty directories and modes."""
    _directory(path)
    result = [path]
    for child in sorted(path.iterdir(), key=lambda value: value.name):
        info = _checked_stat(child)
        if stat.S_ISDIR(info.st_mode):
            result.extend(_entries(child))
        else:
            result.append(child)
    return result


def _stable_file_identity(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mode, info.st_mtime_ns, info.st_ctime_ns)


def _hash_entry(digest, path, root):
    info = _checked_stat(path)
    relative = path.relative_to(root).as_posix()
    if stat.S_ISDIR(info.st_mode):
        _metadata(digest, {"kind": "directory", "path": relative, "mode": stat.S_IMODE(info.st_mode)})
        return
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _stable_file_identity(before) != _stable_file_identity(info):
            raise CacheError("A cache input changed while it was being read.")
        _metadata(digest, {"kind": "file", "path": relative, "mode": stat.S_IMODE(before.st_mode), "size": before.st_size})
        # The declared length frames raw bytes unambiguously, without loading a
        # complete executable or font into memory.
        digest.update(before.st_size.to_bytes(8, "big"))
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        current = _checked_stat(path)
        if (total != before.st_size or _stable_file_identity(before) != _stable_file_identity(after)
                or _stable_file_identity(after) != _stable_file_identity(current)):
            raise CacheError("A cache input changed while it was being read.")
    finally:
        os.close(descriptor)


def _digest_entries(paths, root, context):
    digest = hashlib.sha256()
    _metadata(digest, {"schema": 1, "context": context})
    for path in sorted(paths, key=lambda value: value.relative_to(root).as_posix()):
        _hash_entry(digest, path, root)
    return digest.hexdigest()


def input_digest(root, mode, identity, target, toolchain):
    root = Path(root).absolute()
    source = _checked_subdirectory(root, "Sources/ThinkAndMove")
    resources = _checked_subdirectory(root, "Sources/ThinkAndMove/Resources")
    _checked_subdirectory(root, "scripts")
    swift = list(source.glob("*.swift"))
    if not swift:
        raise CacheError("No Swift source files were found.")
    if any(not stat.S_ISREG(_checked_stat(path).st_mode) for path in swift):
        raise CacheError("Swift inputs must be regular files.")
    selected = swift + _entries(resources)
    for relative in ("Info.plist", "ThinkAndMove.entitlements", "scripts/build.sh", "scripts/preview.sh", "scripts/build_cache.py"):
        path = root / relative
        if not stat.S_ISREG(_checked_stat(path).st_mode):
            raise CacheError("A required build input is not a regular file.")
        selected.append(path)
    return _digest_entries(selected, root, {"mode": mode, "identity": identity, "target": target, "toolchain": toolchain})


def app_digest(app):
    app = Path(app).absolute()
    return _digest_entries(_entries(app), app, "application-bundle")


def _valid_fingerprint(value):
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise CacheError("A lowercase SHA256 fingerprint is required.")
    return value


def _check_cache_location(cache, app):
    # A cache inside the sealed bundle would change its own output fingerprint.
    resolved_cache = Path(cache).absolute().resolve()
    resolved_app = Path(app).absolute().resolve()
    if os.path.commonpath((str(resolved_cache), str(resolved_app))) == str(resolved_app):
        raise CacheError("Cache metadata must be stored outside the application bundle.")
    cache = Path(cache)
    if cache.is_symlink():
        raise CacheError("A symlink cannot be used as a cache file.")


def cache_matches(cache, fingerprint, app):
    _valid_fingerprint(fingerprint)
    _check_cache_location(cache, app)
    cache = Path(cache)
    info = _checked_stat(cache)
    if not stat.S_ISREG(info.st_mode) or info.st_size > 16 * 1024:
        return False
    saved = json.loads(cache.read_text(encoding="utf-8"))
    if not isinstance(saved, dict) or saved.get("schema") != 1 or saved.get("input_sha256") != fingerprint:
        return False
    expected = _valid_fingerprint(saved.get("app_sha256"))
    return expected == app_digest(app)


def record_cache(cache, fingerprint, app):
    _valid_fingerprint(fingerprint)
    _check_cache_location(cache, app)
    output = app_digest(app)
    cache = Path(cache)
    cache.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="." + cache.name + ".", suffix=".tmp", dir=cache.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump({"schema": 1, "input_sha256": fingerprint, "app_sha256": output}, stream, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, cache)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    commands = parser.add_subparsers(dest="command", required=True)
    inputs = commands.add_parser("inputs")
    # Accept --root both before and after the command for shell/test convenience.
    inputs.add_argument("--root", type=Path, default=argparse.SUPPRESS)
    for field in ("mode", "identity", "target", "toolchain"):
        inputs.add_argument("--" + field, required=True)
    for name in ("matches", "record"):
        command = commands.add_parser(name)
        command.add_argument("--root", type=Path, default=argparse.SUPPRESS)
        command.add_argument("--cache", type=Path, required=True)
        command.add_argument("--fingerprint", required=True)
        command.add_argument("--app", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "inputs":
            print(input_digest(args.root, args.mode, args.identity, args.target, args.toolchain))
        elif args.command == "matches":
            return 0 if cache_matches(args.cache, args.fingerprint, args.app) else 1
        else:
            record_cache(args.cache, args.fingerprint, args.app)
        return 0
    except (OSError, ValueError, TypeError, CacheError, RecursionError) as error:
        # A cache miss is an ordinary branch, rather than a diagnostic failure.
        if args.command != "matches":
            print("Build cache: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
