#!/bin/bash
# Build and replace the local development app with a stable Keychain identity.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${CODA_DEV_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p')"
  if [ -z "$IDENTITY" ] || [[ "$IDENTITY" == *$'\n'* ]]; then
    echo 'Set CODA_DEV_SIGN_IDENTITY to one valid Apple Development identity.' >&2
    exit 1
  fi
fi
if [ "$IDENTITY" = '-' ]; then
  echo 'Ad-hoc signing changes Keychain identity between builds; use a development certificate.' >&2
  exit 1
fi
source "$ROOT/Scripts/app-identity.sh"
export CODA_BUILD_BUNDLE_ID="$DEV_BUNDLE_ID"
bash "$ROOT/Scripts/build-app.sh" "${1:-debug}"
python3 - "$ROOT" "$IDENTITY" "$DEV_BUNDLE_ID" <<'PY'
import hashlib
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import time

root, identity, bundle_id = sys.argv[1:]
source = root + '/.build/app/Coda.app'
destination = '/Applications/Coda Dev.app'
process_pattern = '^/Applications/Coda Dev.app/Contents/MacOS/Coda$'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def running():
    return subprocess.run(['pgrep', '-f', process_pattern], stdout=subprocess.DEVNULL).returncode == 0

def executable_hash(bundle):
    # Re-signing changes the Mach-O signature, so compare unsigned copies.
    with tempfile.TemporaryDirectory() as temporary:
        binary = temporary + '/Coda'
        shutil.copy2(bundle + '/Contents/MacOS/Coda', binary)
        run('codesign', '--remove-signature', binary)
        with open(binary, 'rb') as stream:
            return hashlib.sha256(normalize_linkedit(bytearray(stream.read()))).hexdigest()

def normalize_linkedit(data):
    # A larger signature can round __LINKEDIT's vmsize up a page, and
    # --remove-signature does not shrink it back; zero that field only.
    def slice_at(base):
        magic, = struct.unpack_from('<I', data, base)
        if magic != 0xfeedfacf:
            return
        ncmds, = struct.unpack_from('<I', data, base + 16)
        offset = base + 32
        for _ in range(ncmds):
            command, size = struct.unpack_from('<II', data, offset)
            if command == 0x19 and data[offset + 8:offset + 24].rstrip(b'\0') == b'__LINKEDIT':
                struct.pack_into('<Q', data, offset + 32, 0)
            offset += size
    if struct.unpack_from('>I', data, 0)[0] in (0xcafebabe, 0xcafebabf):
        wide = struct.unpack_from('>I', data, 0)[0] == 0xcafebabf
        count, = struct.unpack_from('>I', data, 4)
        for index in range(count):
            entry = 8 + index * (32 if wide else 20)
            base = struct.unpack_from('>Q' if wide else '>I', data, entry + 8)[0]
            slice_at(base)
    else:
        slice_at(0)
    return bytes(data)

with tempfile.TemporaryDirectory(prefix='.coda-dev-', dir='/Applications') as temporary:
    staged = temporary + '/Coda Dev.app'
    backup = temporary + '/previous.app'
    shutil.copytree(source, staged, symlinks=True)
    plist = staged + '/Contents/Info.plist'
    with open(plist, 'rb') as stream:
        info = plistlib.load(stream)
    info.update(CFBundleIdentifier=bundle_id, CFBundleName='Coda Dev',
                CFBundleDisplayName='Coda Dev')
    with open(plist, 'wb') as stream:
        plistlib.dump(info, stream)
    run('codesign', '--force', '--deep', '--sign', identity, staged)
    run('codesign', '--verify', '--deep', '--strict', staged)
    signature = run('codesign', '-d', '-r-', staged, capture_output=True, text=True)
    requirement = signature.stdout + signature.stderr
    if 'anchor apple generic' not in requirement or 'cdhash H' in requirement:
        raise RuntimeError('Signing did not produce a stable certificate requirement')
    expected_hash = executable_hash(source)
    if executable_hash(staged) != expected_hash:
        raise RuntimeError('Staged executable differs from build')
    was_running = running()
    if was_running:
        run('osascript', '-e', 'tell application "' + destination + '" to quit', timeout=20)
        for _ in range(100):
            if not running():
                break
            time.sleep(0.1)
        else:
            raise RuntimeError('Development app did not quit; existing install preserved')
    had_previous = os.path.exists(destination)
    if had_previous:
        os.rename(destination, backup)
    try:
        os.rename(staged, destination)
        run('codesign', '--verify', '--deep', '--strict', destination)
        with open(destination + '/Contents/Info.plist', 'rb') as stream:
            assert plistlib.load(stream)['CFBundleIdentifier'] == bundle_id
        assert executable_hash(destination) == expected_hash
    except BaseException:
        if os.path.exists(destination):
            shutil.move(destination, staged)
        if had_previous:
            os.rename(backup, destination)
        if was_running:
            run('open', destination)
        raise
    if was_running:
        run('open', destination)
    print('Installed Coda Dev; identifier, certificate signature and executable verified.')
    print(requirement.strip())
PY
