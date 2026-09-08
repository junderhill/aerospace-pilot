#!/usr/bin/env python3
import json
import os
import sys
if os.environ.get('GITHUB_ACTIONS') != 'true':
    print('BLOCKED: this is not a hosted GitHub Actions run.')
    sys.exit(3)
print(json.dumps({key: os.environ.get(key) for key in ['GITHUB_RUN_ID', 'GITHUB_SHA', 'GITHUB_REPOSITORY']}, indent=2))
