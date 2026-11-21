#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Patches openskimmer/sdr/soapy.py. Idempotent: every patch is skipped if it is already in.

1. Evaluation range (SKIM_RANGE_KHZ / SKIM_EXCLUDE_KHZ). OpenSkimmer already honours a source's
   coverage_hz property; the SoapySDR source just does not provide one. The patch derives it
   from the two environment variables.
2. Driver label (cosmetic). "soapy@driver=airspyhf,serial=..." opens the right device, but the
   log said "driver=sdrplay" because that is the default of the constructor. The patch takes the
   name from the device arguments instead.

Usage: patch_soapy.py PATH/TO/soapy.py"""
import sys

RANGE_CODE = '''    @property
    def coverage_hz(self):
        """Evaluation range from environment variables (absolute kHz):
        SKIM_RANGE_KHZ    evaluate only this range, e.g. 7000-7200
        SKIM_EXCLUDE_KHZ  leave these ranges out, e.g. 7074-7082,7047-7051.5"""
        rng = os.environ.get("SKIM_RANGE_KHZ", "").strip()
        exc = os.environ.get("SKIM_EXCLUDE_KHZ", "").strip()
        if not rng and not exc:
            return None
        c, half = self._center_frequency, self._sample_rate / 2
        lo, hi = -half, half
        if rng:
            a, b = (float(v) * 1000 - c for v in rng.split("-"))
            lo, hi = max(lo, a), min(hi, b)
        cuts = sorted(tuple(float(v) * 1000 - c for v in e.split("-"))
                      for e in exc.split(",") if e.strip())
        out, pos = [], lo
        for a, b in cuts:
            if b <= pos or a >= hi:
                continue
            if a > pos:
                out.append((pos, a))
            pos = max(pos, b)
        if pos < hi:
            out.append((pos, hi))
        return out

'''

LABEL_OLD = "        self._driver = driver\n        self._device_args = device_args\n"
LABEL_NEW = LABEL_OLD + '''        for _part in (device_args or "").split(","):   # label: name the driver from the device arguments
            if _part.strip().startswith("driver="):
                self._driver = _part.split("=", 1)[1].strip()
'''


def patch_range(s):
    if "def coverage_hz" in s and "SKIM_RANGE_KHZ" in s:
        return s, "already in"
    if "import os\n" not in s:
        if "import logging\n" not in s:
            sys.exit("soapy.py: 'import logging' not found, patch aborted")
        s = s.replace("import logging\n", "import logging\nimport os\n", 1)
    anchor = "    def connect(self) -> None:\n"
    if anchor not in s:
        sys.exit("soapy.py: 'def connect' not found, patch aborted (OpenSkimmer changed?)")
    return s.replace(anchor, RANGE_CODE + anchor, 1), "applied"


def patch_label(s):
    if "_part.strip().startswith(\"driver=\")" in s:
        return s, "already in"
    if LABEL_OLD not in s:
        return s, "skipped (code changed, cosmetic only)"
    return s.replace(LABEL_OLD, LABEL_NEW, 1), "applied"


path = sys.argv[1]
src = open(path).read()
src, r1 = patch_range(src)
src, r2 = patch_label(src)
if r1 == "applied" or r2 == "applied":
    open(path, "w").write(src)
print("soapy.py: evaluation range %s, driver label %s" % (r1, r2))
