#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
python3 - <<'PY'
from pathlib import Path
import hashlib
import plistlib
import re
import subprocess
import tempfile

root = Path.cwd()
app = root / 'dist/Squat for Mac.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}(?:-[A-Za-z0-9.-]+)?', version):
    raise SystemExit('Invalid distribution version')
if info['CFBundleIdentifier'] != 'local.thinkandmove.mvp':
    raise SystemExit('Refusing to package a preview bundle')
executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
architectures = set(subprocess.check_output(['/usr/bin/lipo', '-archs', str(executable)], text=True).split())
if architectures == {'arm64'}: architecture = 'arm64'
elif architectures == {'x86_64'}: architecture = 'x86_64'
elif architectures == {'arm64', 'x86_64'}: architecture = 'universal'
else: raise SystemExit('Unexpected executable architecture')
for path in app.rglob('*'):
    if path.is_symlink() and not path.resolve().is_relative_to(app.resolve()):
        raise SystemExit('Bundle contains an external symlink')
    if path.suffix.lower() in {'.sqlite', '.sqlite3', '.db', '.p12', '.pem', '.key'}:
        raise SystemExit('Private development data found in bundle')
archive = root / 'dist' / f'Squat-for-Mac-{version}-{architecture}.zip'
with tempfile.TemporaryDirectory(prefix='squat-release-') as scratch:
    snapshot = Path(scratch) / 'Squat for Mac.app'
    subprocess.run(['/usr/bin/ditto', str(app), str(snapshot)], check=True)
    # Finder metadata on Desktop bundles is excluded only from this generated copy.
    subprocess.run(['/usr/bin/xattr', '-dr', 'com.apple.FinderInfo', str(snapshot)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(snapshot)], check=True)
    if hashlib.sha256((snapshot / 'Contents/MacOS' / info['CFBundleExecutable']).read_bytes()).digest() != hashlib.sha256(executable.read_bytes()).digest():
        raise SystemExit('Packaged executable changed while copying')
    temporary = Path(scratch) / archive.name
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(snapshot), str(temporary)], check=True)
    # Only a complete successful archive replaces the previous distribution file.
    staged = archive.with_suffix(archive.suffix + ".tmp")
    staged.write_bytes(temporary.read_bytes())
    staged.replace(archive)
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix(archive.suffix + '.sha256').write_text(f'{checksum}  {archive.name}\n')
print(f'Package: {archive}')
print(f'SHA256: {checksum}')
PY
