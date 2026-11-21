#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test of src/patch_soapy.py on a minimal stand-in for openskimmer/sdr/soapy.py."""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCH = os.path.join(HERE, "..", "src", "patch_soapy.py")
STUB = '''import logging
import time


class S:
    _center_frequency = 7030000
    _sample_rate = 192000

    def __init__(self, driver: str = "sdrplay", device_args: str = ""):
        self._driver = driver
        self._device_args = device_args

    def connect(self) -> None:
        pass
'''
fails = 0


def check(name, ok):
    global fails
    print(("ok    " if ok else "FAIL  ") + name)
    fails += not ok


with tempfile.TemporaryDirectory() as td:
    p = os.path.join(td, "soapy.py")
    open(p, "w").write(STUB)
    r1 = subprocess.run([sys.executable, "-I", PATCH, p], capture_output=True, text=True)
    once = open(p).read()
    r2 = subprocess.run([sys.executable, "-I", PATCH, p], capture_output=True, text=True)
    check("first run patches both", r1.returncode == 0 and r1.stdout.count("applied") == 2)
    check("second run changes nothing", r2.returncode == 0 and open(p).read() == once and r2.stdout.count("already in") == 2)
    spec = importlib.util.spec_from_file_location("soapy_stub", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    s = mod.S()
    for k in ("SKIM_RANGE_KHZ", "SKIM_EXCLUDE_KHZ"):
        os.environ.pop(k, None)
    check("no variables -> no restriction", s.coverage_hz is None)
    os.environ["SKIM_RANGE_KHZ"] = "7000-7060"
    check("range only", s.coverage_hz == [(-30000.0, 30000.0)])
    os.environ["SKIM_EXCLUDE_KHZ"] = "7047-7051.5"
    check("range with hole", s.coverage_hz == [(-30000.0, 17000.0), (21500.0, 30000.0)])
    os.environ["SKIM_RANGE_KHZ"] = "6900-7200"       # wider than the passband: clipped to +-96 kHz
    os.environ["SKIM_EXCLUDE_KHZ"] = ""
    check("range clipped to the passband", s.coverage_hz == [(-96000.0, 96000.0)])
    check("driver label from device args", mod.S(device_args="driver=airspyhf,serial=abc")._driver == "airspyhf")
    check("default label unchanged", mod.S()._driver == "sdrplay" and mod.S("rtlsdr")._driver == "rtlsdr")
    # a file that was patched by an earlier version (range only) gets the label patch on the next run
    old = once.replace('''        for _part in (device_args or "").split(","):   # label: name the driver from the device arguments
            if _part.strip().startswith("driver="):
                self._driver = _part.split("=", 1)[1].strip()
''', "")
    open(p, "w").write(old)
    r4 = subprocess.run([sys.executable, "-I", PATCH, p], capture_output=True, text=True)
    check("upgrades an earlier range-only patch", r4.returncode == 0 and "range already in" in r4.stdout and "label applied" in r4.stdout)
    open(p, "w").write("class X:\n    pass\n")
    r3 = subprocess.run([sys.executable, "-I", PATCH, p], capture_output=True, text=True)
    check("refuses an unknown file layout", r3.returncode != 0)
sys.exit(1 if fails else 0)
