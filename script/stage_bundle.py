#!/usr/bin/env python3
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

root, binaries = map(pathlib.Path, sys.argv[1:])
version = os.environ.get('PILOT_VERSION', '0.1.0')
build_number = os.environ.get('PILOT_BUILD_NUMBER', '1')
codesign_identity = os.environ.get('PILOT_CODESIGN_IDENTITY', '-')
codesign_timestamp = os.environ.get('PILOT_CODESIGN_TIMESTAMP') == '1'
dist = root / 'dist'
dist.mkdir(exist_ok=True)
for product, name, identity in [
    ('AeroSpacePilot', 'AeroSpace Pilot', 'uk.jason.aerospace-pilot'),
    ('PilotWindowFixture', 'Pilot Window Fixture', 'uk.jason.aerospace-pilot.fixture'),
]:
    app = dist / f'{name}.app'
    if app.exists():
        shutil.rmtree(app)
    executable = app / 'Contents/MacOS' / product
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binaries / product, executable)
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    icon_metadata = {}
    if product == 'AeroSpacePilot':
        shutil.copy2(root / 'Resources/Icons/AppIcon.icns', resources / 'AppIcon.icns')
        icon_metadata['CFBundleIconFile'] = 'AppIcon.icns'
    for bundle in binaries.glob('*.bundle'):
        shutil.copytree(bundle, resources / bundle.name, dirs_exist_ok=True)
        # Remove legacy generated root copies; macOS bundles seal resources under Contents.
        if (app / bundle.name).exists():
            shutil.rmtree(app / bundle.name)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': product, 'CFBundleIdentifier': identity,
        'CFBundleName': name, 'CFBundleDisplayName': name, 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': build_number, 'CFBundleShortVersionString': version,
        'LSMinimumSystemVersion': '14.0', 'NSPrincipalClass': 'NSApplication',
        'NSHighResolutionCapable': True,
        **icon_metadata,
        'NSScreenCaptureUsageDescription': 'Show previews of your AeroSpace windows when you request them.',
    }))
    sign_command = ['/usr/bin/codesign', '--force', '--sign', codesign_identity, '--identifier', identity]
    if codesign_identity != '-':
        sign_command.extend(['--options', 'runtime'])
        if codesign_timestamp:
            sign_command.append('--timestamp')
    sign_command.append(str(app))
    subprocess.run(sign_command, check=True)
shutil.copy2(binaries / 'pilot', dist / 'pilot')
shutil.copy2(binaries / 'pilot-desktop-tests', dist / 'pilot-desktop-tests')
for bundle in binaries.glob('*.bundle'):
    shutil.copytree(bundle, dist / bundle.name, dirs_exist_ok=True)
