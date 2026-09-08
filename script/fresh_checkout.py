#!/usr/bin/env python3
"""Build/test a source export with no .build cache, in a path with spaces, from another cwd."""
import os
import pathlib
import shutil
import subprocess
import tempfile
from verify import ROOT, source_files

with tempfile.TemporaryDirectory(prefix='Pilot clean checkout ') as temporary:
    fresh = pathlib.Path(temporary) / 'source with spaces'
    fresh.mkdir()
    for source in source_files():
        destination = fresh / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    env = dict(os.environ, PILOT_AEROSPACE_PATH='/missing/aerospace-for-isolation-test')
    for script in ['bootstrap.sh', 'bootstrap.sh', 'build.sh', 'test.sh']:
        subprocess.run([str(fresh / 'script' / script)], cwd=temporary, env=env, check=True)
    assert (fresh / 'dist/AeroSpace Pilot.app/Contents/Info.plist').is_file()
    print('Fresh source export built and tested with spaces, unrelated cwd, repeated bootstrap and AeroSpace unavailable.')
