#!/usr/bin/env python3
"""Cumulative gates. Exit 0 = passed, 1 = failed, 3 = blocked; never silently skip."""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXCLUDED = {'.git', '.build', '.swiftpm', 'artifacts', 'dist', '__pycache__'}

def source_files(root=ROOT):
    for directory, folders, files in os.walk(root):
        folders[:] = sorted(f for f in folders if f not in EXCLUDED)
        for name in sorted(files):
            yield pathlib.Path(directory) / name

def source_digest(root=ROOT):
    digest = hashlib.sha256()
    for path in source_files(root):
        digest.update(str(path.relative_to(root)).encode())
        digest.update(b'\0')
        digest.update(path.read_bytes())
        digest.update(b'\0')
    return digest.hexdigest()

def output(command):
    try:
        return subprocess.check_output(command, cwd=ROOT, text=True, stderr=subprocess.STDOUT, timeout=15).strip()
    except (OSError, subprocess.SubprocessError) as error:
        return f'unavailable: {error}'

def aggregate(results):
    if any(item['status'] == 'failed' for item in results):
        return 'failed'
    if not results or any(item['status'] != 'passed' for item in results):
        return 'blocked'
    return 'passed'

def missing_environment(environment, environ=os.environ):
    if environment == 'github-actions' and environ.get('GITHUB_ACTIONS') != 'true':
        return 'Hosted CI execution is not available locally; no remote has been configured or CI result claimed.'
    if 'desktop' in environment and environ.get('PILOT_DESKTOP_TEST_SESSION') != '1':
        return 'Dedicated logged-in desktop test session is not enabled. See README.md desktop testing instructions.'
    return None

def test_count(text):
    counts = re.findall(r'Test run with (\d+) tests?(?: in \d+ suites?)? passed|Ran (\d+) tests?', text)
    return sum(int(a or b) for a, b in counts) if counts else None

def run_check(check, folder, prior):
    result = {'id': check['id'], 'status': 'blocked', 'testCount': None, 'acceptance': check.get('acceptance', [])}
    unmet = [name for name in check.get('requires', []) if prior.get(name) != 'passed']
    reason = missing_environment(check['environment'])
    if unmet:
        result['reason'] = 'Required checks did not pass: ' + ', '.join(unmet)
        return result
    if reason:
        result['reason'] = reason
        return result
    log = folder / f"{check['id']}.log"
    try:
        with log.open('w') as stream:
            completed = subprocess.run(check['command'], cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=check.get('timeout', 300))
        result['exitCode'] = completed.returncode
        result['status'] = 'passed' if completed.returncode == 0 else ('blocked' if completed.returncode == 3 else 'failed')
        text = log.read_text()
        result['testCount'] = test_count(text)
        if result['status'] != 'passed':
            result['reason'] = '\n'.join(text.strip().splitlines()[-8:])
    except (OSError, subprocess.TimeoutExpired) as error:
        result['status'] = 'failed'
        result['reason'] = str(error)
    result['evidence'] = log.name
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', type=int, choices=[1, 2, 3], required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'verification/phases.json').read_text())
    now = datetime.datetime.now(datetime.timezone.utc)
    folder = ROOT / 'artifacts/verification' / f"{now.strftime('%Y%m%dT%H%M%S%fZ')}-phase-{args.phase}"
    folder.mkdir(parents=True)
    report = {
        'schemaVersion': 1, 'phase': args.phase, 'startedAt': now.isoformat(),
        'revision': output(['git', 'rev-parse', 'HEAD']), 'sourceDigest': source_digest(),
        'dirtyState': output(['git', 'status', '--porcelain']),
        'swift': output(['xcrun', 'swift', '--version']), 'macOS': output(['sw_vers']),
        'aerospaceVersions': output([os.environ.get('PILOT_AEROSPACE_PATH', '/opt/homebrew/bin/aerospace'), '--version']),
        'desktopConfiguration': output([str(ROOT / 'dist/pilot'), 'doctor']) if (ROOT / 'dist/pilot').exists() else 'Not built at start',
        'checks': [], 'decisions': manifest['decisions'],
    }
    prior = {}
    for check in manifest['checks']:
        if check['phase'] > args.phase:
            continue
        print(f"Running {check['id']}…", flush=True)
        result = run_check(check, folder, prior)
        report['checks'].append(result)
        prior[check['id']] = result['status']
        print(f"  {result['status']}", flush=True)
    if source_digest() != report['sourceDigest']:
        report['checks'].append({'id': 'source-consistency', 'status': 'failed', 'reason': 'Source changed during verification. Rerun against one source digest.'})
    report['status'] = aggregate(report['checks'])
    report['counts'] = {status: sum(c['status'] == status for c in report['checks']) for status in ['passed', 'failed', 'blocked']}
    (folder / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = [f"# Phase {args.phase}: {report['status']}", '', f"Source digest: `{report['sourceDigest']}`", '', '| Check | Result | Tests | Evidence |', '| --- | --- | --- | --- |']
    for check in report['checks']:
        evidence = f"[log]({check['evidence']})" if 'evidence' in check else '—'
        lines.append(f"| {check['id']} | {check['status']} | {check.get('testCount') or '—'} | {evidence} |")
    for check in report['checks']:
        if check.get('reason'):
            lines += ['', f"## {check['id']}", '', check['reason']]
    (folder / 'report.md').write_text('\n'.join(lines) + '\n')
    print(f"Phase {args.phase}: {report['status']}. Report: {folder / 'report.md'}")
    return {'passed': 0, 'failed': 1, 'blocked': 3}[report['status']]

if __name__ == '__main__':
    sys.exit(main())
