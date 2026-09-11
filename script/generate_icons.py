#!/usr/bin/env python3
"""Rebuild macOS icon resources using the checked-in Waypoint master and Apple tools."""
import json
import pathlib
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
icons = root / 'Resources/Icons'
master = icons / 'Waypoint-master.png'
iconset = icons / 'AppIcon.iconset'
catalog = icons / 'Assets.xcassets'
appicon = catalog / 'AppIcon.appiconset'
iconset.mkdir(parents=True, exist_ok=True)
appicon.mkdir(parents=True, exist_ok=True)
images = []
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        pixels = size * scale
        filename = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        output = iconset / filename
        subprocess.run(['/usr/bin/sips', '-z', str(pixels), str(pixels), str(master),
                        '--out', str(output)], check=True, stdout=subprocess.DEVNULL)
        shutil.copy2(output, appicon / filename)
        images.append({'filename': filename, 'idiom': 'mac',
                       'scale': f'{scale}x', 'size': f'{size}x{size}'})
info = {'author': 'xcode', 'version': 1}
(catalog / 'Contents.json').write_text(json.dumps({'info': info}, indent=2) + '\n')
(appicon / 'Contents.json').write_text(json.dumps({'images': images, 'info': info}, indent=2) + '\n')
subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(iconset),
                '-o', str(icons / 'AppIcon.icns')], check=True)
print(f'Created 10 macOS PNG representations, asset catalog, and {icons / "AppIcon.icns"}')
