#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from verify import ROOT, aggregate, missing_environment, run_check, source_digest, test_count

class HarnessTests(unittest.TestCase):
    def test_swift_testing_suite_counts_are_recorded(self):
        self.assertEqual(test_count('Test run with 34 tests in 4 suites passed after 0.100 seconds.'), 34)
        self.assertEqual(test_count('Test run with 2 tests passed after 0.01 seconds.'), 2)
        self.assertEqual(test_count('Ran 8 tests in 0.82s'), 8)
        self.assertIsNone(test_count('Test run with 34 tests in 4 suites failed after 0.1 seconds.'))

    def test_failure_and_blocked_are_not_signoff(self):
        self.assertEqual(aggregate([{'status':'passed'}, {'status':'failed'}]), 'failed')
        self.assertEqual(aggregate([{'status':'passed'}, {'status':'blocked'}]), 'blocked')
        self.assertEqual(aggregate([{'status':'skipped'}]), 'blocked')
        self.assertEqual(aggregate([]), 'blocked')

    def test_missing_desktop_is_explicit(self):
        self.assertIsNotNone(missing_environment('desktop', {}))
        self.assertIsNone(missing_environment('desktop', {'PILOT_DESKTOP_TEST_SESSION':'1'}))

    def test_deliberate_failure_propagates(self):
        with tempfile.TemporaryDirectory() as folder:
            result = run_check({'id':'failure', 'environment':'macos', 'command':[sys.executable, '-c', 'raise SystemExit(7)']}, pathlib.Path(folder), {})
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['exitCode'], 7)

    def test_blocked_exit_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            result = run_check({'id':'blocked', 'environment':'macos', 'command':[sys.executable, '-c', 'raise SystemExit(3)']}, pathlib.Path(folder), {})
            self.assertEqual(result['status'], 'blocked')

    def test_required_dependency_cannot_be_skipped(self):
        with tempfile.TemporaryDirectory() as folder:
            result = run_check({'id':'dependent', 'environment':'macos', 'requires':['build'], 'command':['/does/not/exist']}, pathlib.Path(folder), {'build':'failed'})
            self.assertEqual(result['status'], 'blocked')

    def test_source_digest_includes_dirty_source_and_excludes_artifacts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root/'a.swift').write_text('one')
            before = source_digest(root)
            (root/'artifacts').mkdir(); (root/'artifacts/log').write_text('noise')
            self.assertEqual(source_digest(root), before)
            (root/'a.swift').write_text('two')
            self.assertNotEqual(source_digest(root), before)

    def test_script_failure_from_other_cwd_and_spaced_path(self):
        import subprocess
        with tempfile.TemporaryDirectory(prefix='Pilot contract ') as folder:
            root = pathlib.Path(folder)/'project with spaces'
            shutil.copytree(ROOT/'script', root/'script')
            fake = root/'failing swift'
            fake.write_text('#!/bin/sh\nexit 42\n'); fake.chmod(0o755)
            env = dict(os.environ, PILOT_SWIFT=str(fake))
            for name in ['build.sh', 'test.sh']:
                result = subprocess.run([str(root/'script'/name)], cwd=folder, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 42, result.stderr)

    def test_manifest_has_cumulative_named_coverage(self):
        manifest = json.loads((ROOT/'verification/phases.json').read_text())
        ids = [c['id'] for c in manifest['checks']]
        self.assertEqual(len(ids), len(set(ids)))
        coverage = {r for c in manifest['checks'] for r in c['acceptance']}
        for phase in range(1, 4):
            for requirement in range(1, 6):
                self.assertIn(f'P{phase}.{requirement}', coverage)

if __name__ == '__main__':
    unittest.main(verbosity=2)
