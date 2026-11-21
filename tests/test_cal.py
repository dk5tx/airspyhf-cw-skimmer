#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic test of src/cal.py: RWM (keyed) + WWV + fixed interferers + noise; recover the offset."""
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CAL = os.path.join(HERE, "..", "src", "cal.py")
FS = 192000


def make(path, d, rwm, wwv=1.0, interferers=(-5000, -6040, -1950, -2500, -3300), seconds=50, seed=1):
    n = FS * seconds
    t = np.arange(n) / FS
    rng = np.random.default_rng(seed)
    x = (rng.normal(size=n) + 1j * rng.normal(size=n)).astype(np.complex64) * 30
    x += wwv * 90 * np.exp(2j * np.pi * (-2000 + d) * t) * (1 + 0.3 * np.cos(2 * np.pi * 100 * t))
    x += rwm * 90 * np.exp(2j * np.pi * (-6000 + d) * t) * ((t % 30) < 8)
    for f in interferers:
        x += 40 * np.exp(2j * np.pi * f * t)
    x.astype(np.complex64).tofile(path)


def run(path, *args):
    p = subprocess.run([sys.executable, "-I", CAL, path, "--skip", "0", *args], capture_output=True, text=True)
    res = [l for l in p.stdout.splitlines() if l.startswith("RESULT")]
    return p.returncode, (res[0] if res else "")


def ppm_of(res):
    return float(res.split("ppm=")[1].split()[0])


fails = 0
with tempfile.TemporaryDirectory() as td:
    f = os.path.join(td, "t.c64")
    for d in (33.4, -12.0, 0.0, 21.0):
        make(f, d, 1.0)
        rc, res = run(f)
        want = d / 10.002
        ok = rc == 0 and abs(ppm_of(res) - want) < 0.05
        print("both   d=%+6.1f Hz -> %s %s" % (d, res, "ok" if ok else "FAIL (want %.3f)" % want))
        fails += not ok
    make(f, 33.4, 0.0, wwv=0.35)            # RWM absent, fixed interferer as strong as WWV: must refuse
    rc, res = run(f)
    ok = rc == 3 and "ambiguous" in res
    print("no RWM + interferer -> rc=%d %s %s" % (rc, res, "ok" if ok else "FAIL"))
    fails += not ok
    make(f, 28.0, 0.0, interferers=())      # WWV alone and clean: accepted
    rc, res = run(f)
    ok = rc == 0 and abs(ppm_of(res) - 28.0 / 10.002) < 0.05
    print("WWV only, clean     -> rc=%d %s %s" % (rc, res, "ok" if ok else "FAIL"))
    fails += not ok
sys.exit(1 if fails else 0)
