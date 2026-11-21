#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Clock-error (ppm) estimate from a complex64 I/Q recording containing RWM (9996 kHz) and WWV (10 MHz).

Recording: center 10002000 Hz, 192 kS/s -> RWM at -6000 Hz, WWV at -2000 Hz.
Both stations show the same offset d (the receiver's clock error). We look for the d at which
the WEAKER of the two signals is strongest, so fixed interferers and a single wrong peak drop out.
If RWM is unusable (its carrier is only on part of the time), WWV alone is evaluated, and the
result is rejected when a second line is nearly as strong.

Output line: "RESULT ppm=3.340 d_hz=33.4 mode=both ..."
Sign: a signal that shows up too high (display too high) gives a positive ppm; skim then
applies offset = -ppm * center / 1e6.
"""
import argparse
import sys

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("file")
ap.add_argument("--center", type=float, default=10002000.0)
ap.add_argument("--rate", type=float, default=192000.0)
ap.add_argument("--skip", type=float, default=5.0, help="seconds to discard at the start")
ap.add_argument("--maxd", type=float, default=250.0, help="search range +-Hz")
ap.add_argument("--wwv-only", action="store_true")
a = ap.parse_args()

STATIONS = {"RWM": 9996000.0, "WWV": 10000000.0}
x = np.fromfile(a.file, dtype=np.complex64)
x = x[int(a.skip * a.rate):]
nseg = 2 ** 18
if len(x) < nseg * 4:
    sys.exit("recording too short (%d samples)" % len(x))
win = np.hanning(nseg).astype(np.float32)
hop = nseg // 2
binhz = a.rate / nseg
half = 400.0                                  # window around the expected line
nb = int(half / binhz)
rows = {k: [] for k in STATIONS}
exp = {k: f - a.center for k, f in STATIONS.items()}
for i in range(0, len(x) - nseg + 1, hop):
    spec = np.abs(np.fft.fftshift(np.fft.fft(x[i:i + nseg] * win))) ** 2
    for k in STATIONS:
        c = int(round(exp[k] / binhz)) + nseg // 2
        rows[k].append(spec[c - nb:c + nb + 1])
fax = {k: (np.arange(-nb, nb + 1) + round(exp[k] / binhz)) * binhz for k in STATIONS}
prof = {}
for k in STATIONS:
    P = np.array(rows[k])
    noise = np.median(P, axis=1, keepdims=True)
    snr = 10 * np.log10(P / noise + 1e-12)
    prof[k] = np.percentile(snr, 80, axis=0)   # RWM is keyed: the loud segments count
ds = np.arange(-a.maxd, a.maxd + 0.01, 0.25)


def at(k, d):
    return np.interp(exp[k] + d, fax[k], prof[k])


sR, sW = at("RWM", ds), at("WWV", ds)
iR, iW = int(np.argmax(sR)), int(np.argmax(sW))
joint = np.minimum(sR, sW)
iJ = int(np.argmax(joint))


def refine(s, i):                              # parabola through the maximum
    if 0 < i < len(s) - 1:
        y0, y1, y2 = s[i - 1], s[i], s[i + 1]
        den = y0 - 2 * y1 + y2
        if den < 0:
            return ds[i] + 0.25 * 0.5 * (y0 - y2) / den
    return ds[i]


snrR, snrW, snrJ = sR[iR], sW[iW], joint[iJ]
if a.wwv_only or snrJ < 8.0:
    if snrW < 10.0:
        print("ERROR: no usable WWV signal (%.1f dB). Check antenna, band, time of day." % snrW, file=sys.stderr)
        print("RESULT error=nosignal wwv_snr=%.1f rwm_snr=%.1f" % (snrW, snrR))
        sys.exit(2)
    d, mode, snr = refine(sW, iW), "wwv-only", snrW
    print("Note: RWM not usable (%.1f dB), evaluated WWV only." % snrR, file=sys.stderr)
    other = sW[np.abs(ds - d) > 3.0]
    if other.max() > snrW - 6.0:   # second line almost as strong: ambiguous
        print("ERROR: WWV line is ambiguous (second line only %.1f dB weaker)." % (snrW - other.max()),
              file=sys.stderr)
        print("RESULT error=ambiguous d_hz=%.2f wwv_snr=%.1f" % (d, snrW))
        sys.exit(3)
else:
    d, mode, snr = refine(joint, iJ), "both", snrJ
    dr, dw = refine(sR, iR), refine(sW, iW)
    if abs(dr - dw) > 3.0:
        print("Warning: RWM (%.1f Hz) and WWV (%.1f Hz) disagree." % (dr, dw), file=sys.stderr)
ppm = d / (a.center / 1e6)
print("RESULT ppm=%.3f d_hz=%.2f mode=%s snr_db=%.1f wwv_snr=%.1f rwm_snr=%.1f"
      % (ppm, d, mode, snr, snrW, snrR))
