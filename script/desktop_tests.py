#!/usr/bin/env python3
"""Read-only readiness locally; mutation checks only in an explicitly selected test session."""
import argparse
import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--check', required=True, choices=['live-health', 'bundle-launch', 'controlled-windows', 'capture-three-workspaces', 'capture-conditions', 'work-placement', 'profile-relaunch'])
args = parser.parse_args()
if args.check == 'live-health':
    result = subprocess.run([str(ROOT/'dist/pilot'), 'doctor'], capture_output=True, text=True)
    print(result.stdout)
    if result.returncode:
        try:
            state = json.loads(result.stdout)['health']['state']
            if state in ['executableMissing', 'serverUnavailable', 'unresponsive']:
                print('BLOCKED: a reachable AeroSpace installation is required.')
                sys.exit(3)
        except (ValueError, KeyError):
            pass
        print(result.stderr)
        sys.exit(1)
    sys.exit(0)
if os.environ.get('PILOT_DESKTOP_TEST_SESSION') != '1':
    print('BLOCKED: run in a dedicated logged-in account with PILOT_DESKTOP_TEST_SESSION=1. No desktop changes made.')
    sys.exit(3)
if args.check == 'bundle-launch':
    subprocess.run([sys.executable, str(ROOT/'script/launch.py'), 'stop', str(ROOT)], check=True)
    result = subprocess.run([sys.executable, str(ROOT/'script/launch.py'), 'launch', str(ROOT)])
    sys.exit(result.returncode)
result = subprocess.run([str(ROOT/'dist/pilot-desktop-tests'), args.check, str(ROOT)])
sys.exit(result.returncode)
