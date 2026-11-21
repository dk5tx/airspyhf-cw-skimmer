#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs all tests. Needs bash, python3 and numpy (for the calibration test).
cd "$(dirname "$0")/.." || exit 1
rc=0
for f in install.sh src/skim src/skim-cal tools/make-standalone.sh; do bash -n "$f" || rc=1; done
python3 -m py_compile src/cal.py src/patch_soapy.py || rc=1; rm -rf src/__pycache__
bash tests/test_launcher.sh || rc=1
bash tests/test_install.sh || rc=1
python3 tests/test_patch.py || rc=1
python3 tests/test_cal.py || rc=1
[ $rc = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $rc
