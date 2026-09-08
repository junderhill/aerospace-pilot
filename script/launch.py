#!/usr/bin/env python3
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
import uuid

mode, root = sys.argv[1], pathlib.Path(sys.argv[2])
app = root / 'dist/AeroSpace Pilot.app'
executable = app / 'Contents/MacOS/AeroSpacePilot'
if mode == 'stop':
    output = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
    for row in output.splitlines():
        fields = row.strip().split(None, 1)
        if len(fields) == 2 and (fields[1] == str(executable) or fields[1].startswith(str(executable) + ' ')):
            try:
                os.kill(int(fields[0]), signal.SIGTERM)
            except ProcessLookupError:
                pass
elif mode == 'launch':
    evidence = root / 'artifacts/launch'
    evidence.mkdir(parents=True, exist_ok=True)
    ready = evidence / f'{uuid.uuid4()}.json'
    subprocess.run(['/usr/bin/open', '-n', str(app), '--args', '--ready-file', str(ready)], check=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if ready.exists():
            result = json.loads(ready.read_text())
            if result['bundleID'] != 'uk.jason.aerospace-pilot':
                sys.exit('Wrong bundle identity in app readiness response.')
            os.kill(int(result['pid']), 0)
            print(f"App ready: {result['bundleID']} (PID {result['pid']})")
            sys.exit(0)
        time.sleep(0.1)
    sys.exit('App did not report readiness within 15 seconds.')
else:
    sys.exit('Unknown launch action.')
