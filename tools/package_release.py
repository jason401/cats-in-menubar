#!/usr/bin/env python3
"""Package an existing verified app and notices; never publish, install or re-sign it."""
import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True, help='Release label, e.g. v0.1.0')
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'v?\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', args.version):
        parser.error('Use a version label such as v0.1.0 or v0.1.0-review')
    root = Path(__file__).resolve().parents[1]
    app = args.app.resolve()
    if app.is_symlink() or not app.is_dir():
        parser.error('--app must be an existing app directory')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != 'local.catsinmenubar':
        parser.error('Unexpected bundle identifier')
    revision = info.get('CatsSourceRevision', '')
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        parser.error('App is missing its full source revision')
    command('git', '-C', str(root), 'cat-file', '-e', revision + '^{commit}')
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    executable = app / 'Contents/MacOS' / info.get('CFBundleExecutable', '')
    archs = command('/usr/bin/lipo', '-archs', str(executable)).split()
    labels = {('arm64',): 'arm64', ('x86_64',): 'x86_64',
              ('arm64', 'x86_64'): 'universal', ('x86_64', 'arm64'): 'universal'}
    arch = labels.get(tuple(archs))
    if not arch:
        parser.error('Unexpected app architecture: ' + ' '.join(archs))
    for name in ['THIRD_PARTY_NOTICES.md', 'Apache-2.0.txt', 'Cats/coats.json']:
        if not (app / 'Contents/Resources' / name).is_file():
            parser.error('Missing app resource: ' + name)
    notices = ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'LICENSES/Apache-2.0.txt', 'docs/INSTALL.md']
    for name in notices:
        if not (root / name).is_file():
            parser.error('Missing release notice: ' + name)
    # The source tree is never copied wholesale: no .git, keychain, logs or caches.
    for item in app.rglob('*'):
        if item.is_symlink():
            parser.error('Unexpected symlink in app: ' + str(item.relative_to(app)))
        if item.name == '.git' or item.suffix.lower() in {'.pem', '.p12', '.pfx', '.key', '.mobileprovision'}:
            parser.error('Unexpected private/development file in app: ' + str(item.relative_to(app)))
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    filename = f'Cats-in-Menubar-{args.version}-macOS-{arch}.zip'
    archive = out / filename
    checksums = out / 'SHA256SUMS.txt'
    notes = out / 'RELEASE_NOTES.md'
    for target in [archive, checksums, notes]:
        if target.exists():
            parser.error('Refusing to overwrite ' + str(target))
    with tempfile.TemporaryDirectory(prefix='cats-release-') as temp:
        stage = Path(temp) / f'Cats-in-Menubar-{args.version}'
        stage.mkdir()
        shutil.copytree(app, stage / app.name)
        for name in notices:
            relative = 'INSTALL.md' if name == 'docs/INSTALL.md' else name
            dest = stage / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / name, dest)
        command('/usr/bin/codesign', '--verify', '--deep', '--strict', str(stage / app.name))
        command('/usr/bin/ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr',
                str(stage), str(archive))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksums.write_text(digest + '  ' + filename + '\n')
    minimum = info.get('LSMinimumSystemVersion', '14.0')
    notes.write_text(f'''# Cats in Menubar {args.version}

Tiny cats for your Mac's menu bar, with toys, coat/size choices, a local system dashboard and optional scroll direction controls.

## Download

- **{filename}** — prebuilt {arch} app for macOS {minimum}+. **This ZIP is all you need to install the app.**
- **SHA256SUMS.txt** — optional integrity check. Not needed to install or run the app; not publisher authentication.
- Source: https://github.com/jason401/cats-in-menubar/tree/{revision}

Source revision: `{revision}`. App bundle version: `{info.get('CFBundleShortVersionString', 'unknown')}` ({info.get('CFBundleVersion', 'unknown')}).

Unzip, quit any running copy, and drag the app to Applications. Read the included INSTALL.md and grant Accessibility when requested. This app is locally signed, **not Apple Developer ID signed or notarized**. Review https://support.apple.com/en-us/102445 before using Open Anyway; do not bypass malware or tampering warnings or disable Gatekeeper globally.

**Prebuilt users: turn off update checks in Settings → General → Updates and install later release ZIPs manually.** The current source-building updater pins the installed signing identity and cannot use a different key created on your Mac. Source-built users can use stable-channel updates with their own persistent local signing key. No runtime/update code was changed for this distribution.

MIT © 2026 jason401 for original contributions. Scroll direction derives from Scroll Reverser (Apache-2.0); notices and license copies are included. Created with AI assistance. No warranty.

Maintainer: confirm exact-revision test results and first-run testing before publishing. Packaging alone does not certify the app as safe or tested.
''')
    print(f'Created {archive}\nCreated {checksums}\nCreated {notes}\nSource revision: {revision}')


if __name__ == '__main__':
    main()
