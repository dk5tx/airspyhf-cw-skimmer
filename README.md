# airspyhf-cw-skimmer

Installer, launcher and calibration tools for running a CW skimmer on Linux with an
**Airspy HF+** and [OpenSkimmer](https://github.com/khkremer/OpenSkimmer) (by K5KHK).

This is an unofficial add-on. It is not affiliated with OpenSkimmer, the Reverse Beacon
Network or Airspy. OpenSkimmer is downloaded from its own repository during installation;
nothing of it is redistributed here.

## What it does

- **One-shot installer** for Debian / Ubuntu / Linux Mint: apt packages, the SoapySDR plugin
  for the HF+ (built in a temporary directory), OpenSkimmer in a virtualenv, callsign databases.
  Everything lives in one folder, `~/bin/airspyhf-cw-skimmer`; only the links `skim` and `skim-cal`
  are placed in `~/bin`. Nothing else is left in your home directory.
- **`skim BAND [RECEIVER] [normal|contest]`**: starts OpenSkimmer with the right center
  frequency, sample rate, evaluation range and clock correction for that band and receiver.
- **Two band presets**: *normal* decodes only the CW segment, *contest* adds a bit more
  (e.g. the SSB part of 160/80 m in a CW contest) but leaves out the usual digimode windows.
  On 2 m both stop at 144.150 MHz. All windows are in a plain text file you can edit.
- **Several receivers, each with its own clock correction.** The HF+ has no clock
  correction in the SoapySDR plugin, so `skim` applies `-ppm * center` as a frequency offset.
- **`skim-cal RECEIVER`**: measures a receiver's clock error automatically from WWV (10 MHz)
  and RWM (9996 kHz) and stores it. Needs only an antenna that hears 10 MHz.
- **Receiver detection by serial number**: with a single HF+ attached you do not even have
  to name it.

## Requirements

- Linux Mint 22 / Ubuntu 24.04 or similar (Python 3.9+), sudo rights for the installation
- An Airspy HF+ (Discovery or Dual) and an antenna
- Internet access for the installation (apt, GitHub)

## Install

1. **Attach the receiver(s) first.** The installer enters the serial numbers of the attached
   HF+ units into `devices.conf`. A unit plugged in later is added with `skim add NAME`.
2. Clone and run (not into `~/bin/airspyhf-cw-skimmer`, see below):

```sh
git clone https://github.com/dk5tx/airspyhf-cw-skimmer.git ~/git/airspyhf-cw-skimmer
cd ~/git/airspyhf-cw-skimmer
SKIM_CALL=YOURCALL bash install.sh
```

   `sudo` is needed for the apt packages. The SoapyAirspyHF plugin and OpenSkimmer are built
   on the machine, which takes a few minutes and needs internet access.
3. **Callsign.** Without `SKIM_CALL` the installer writes `MY_CALL=N0CALL` into `skim.conf`,
   and `skim` then stops with "no callsign set". Change it later in
   `~/bin/airspyhf-cw-skimmer/skim.d/skim.conf`. A callsign per receiver can be put in
   `devices.conf` (4th column); it takes precedence.
4. **Log out and in once** (membership of the `plugdev` group), and unplug and re-plug the
   receiver (udev rule).
5. **Calibrate each receiver once**, see [Calibration](#calibration).

The clone is only the source. The installer copies everything to
`~/bin/airspyhf-cw-skimmer` and refuses to run from inside that folder.
Without a checkout, `tools/make-standalone.sh` builds a single self-extracting file (`dist/`).

`bash install.sh --files-only` refreshes only the scripts and defaults (no apt, no build).
Existing settings are never overwritten; new defaults appear as `*.new` next to them.
An older flat layout (`~/bin/openskimmer`, `~/bin/skim.d`) is moved into the folder automatically.

## Use

```sh
skim list                    # attached and known receivers, bands
skim add rx1                 # register the attached receiver under a name
skim-cal rx1                 # measure its clock error once (about a minute)
skim 40m rx1                 # CW segment of 40 m
skim 20m rx1 contest         # contest window
skim 40m rx1 --workers process   # options after the first "-" go to openskimmer
skim update                  # update OpenSkimmer, MASTER.SCP and patt3ch.lst
```

Spots are served as a telnet DX cluster on port 7300 (`telnet localhost 7300`); the
waterfall is at `http://localhost:7380`. Two receivers can run side by side if the second gets
its own ports: `skim 2m rx2 --telnet-port 7301 --web-port 7390`.

Optional short forms `skim-40m rx1`, `skim-2m rx2 contest`, ... are created by
`bash install.sh --band-links`.

### Settings (`~/bin/airspyhf-cw-skimmer/skim.d/`)

| File | Purpose |
|---|---|
| `skim.conf` | your callsign (`MY_CALL`) and the channel limit |
| `devices.conf` | receivers: name, serial number, clock error (ppm), optional callsign |
| `bands.conf` | center frequency, sample rate, range and digimode exclusions per band and mode |

## Calibration

Every HF+ has its own reference-clock error (typically a few ppm). The SoapySDR plugin cannot
correct it, so on 40 m a 3 ppm error already shifts all frequencies by about 20 Hz, which
matters for the spots. `skim-cal` measures the error from two time-signal stations:

- **WWV** (Fort Collins) on 10 000 kHz and **RWM** (Moscow) on 9 996 kHz. Both carriers are
  stable to far better than 0.01 ppm. The recording is centered on 10 002 kHz at 192 kS/s, so the
  carriers appear at -2000 Hz (WWV) and -6000 Hz (RWM). The distance of the measured lines from
  these nominal positions gives the shift `d` in Hz, and `ppm = d / 10.002`.
- Both stations are evaluated together. The estimate is the shift at which the *weaker* of the
  two lines is strongest. That is robust against a fixed interferer that happens to sit near
  one of the two frequencies. If only one station is usable and a second line is less than 6 dB
  weaker, the result is rejected as ambiguous instead of being guessed.
- RWM sends its carrier only in minutes :00-:08 and :30-:38. `skim-cal` therefore waits for
  second :20 or :50 and records 45 s. `--now` skips the wait, `--wwv-only` ignores RWM.
- The result is written to `devices.conf` and appended to `cal.log`. `skim` converts it to a
  frequency offset (`-ppm * center / 1e6`, rounded to Hz) for the band in use.

**You need usable reception on 10 MHz at least once per receiver.** Any antenna that hears
WWV or RWM is enough. It does not have to be the antenna you skim with, and one calibration
holds as long as you use the same receiver (it ages slowly; repeat it now and then, and after
big temperature changes). 10 MHz is best in the evening and at night. If the antenna cannot hear
it, calibrate at home and carry the value along: the number belongs to the receiver, not to the
antenna.

```sh
skim-cal rx1             # about a minute, receiver must not be in use
```

Without a stored value `skim` warns and uses 0 ppm. Stop a running skimmer first; two programs
cannot share one receiver. `devices.conf` is not part of this repository, so a freshly
installed machine always has to measure again, even for a receiver you already calibrated
elsewhere. You can also copy the file or the single ppm value over.

Error messages: `no usable WWV signal` means the antenna, the time of day or the band is
at fault. `WWV line is ambiguous` means a second line is almost as strong; try again at another time,
or with a better antenna. A warning that RWM and WWV disagree points to a poor signal.

## Notes on the windows

- The HF+ is flat to about +-62 kHz around the center at 192 kS/s and about -136 ... +140 kHz
  at 384 kS/s (measured with one unit). The presets use 384 kS/s on 160 m, 80 m and, in the
  contest set, 15 m and 10 m; this costs roughly 10 % more CPU.
- If a window contains many strong SSB or FT8 signals, OpenSkimmer runs out of decoder
  channels (`signal tracker is FULL`). That is why the ranges are limited to CW segments.
- **The band edges are written from memory** (IARU Region 1 band plan, WSJT-X defaults).
  Please check them and adapt `bands.conf` to your region.
- On 2 m the HF+ needs help against strong broadcast and TV transmitters, typically a
  bandpass filter and a preamplifier in front of it.

## Feeding the Reverse Beacon Network

Not part of this repository. OpenSkimmer prints spots in the CW Skimmer format, which the
RBN Aggregator accepts; see the OpenSkimmer documentation (`docs/aggregator-on-linux.md`).
Check the quality of your spots before you upload anything, and ask the RBN team about their
requirements for new skimmers.

## Tests

```sh
bash tests/run.sh      # needs bash, python3 and numpy; no hardware, network or sudo
```

The tests cover the launcher (with a fake `SoapySDRUtil` and `openskimmer`), the installer's
file handling, the `soapy.py` patch and the calibration estimator (synthetic I/Q data).

## Status

The launcher, the calibration and the installer have been used with Airspy HF+ units on
Linux Mint 22.3 (the installer on one machine so far, including the apt and build steps).
Other distributions and the standalone installer are less tested. Please report problems as issues.

## License

GPL-3.0-or-later, see `LICENSE`. OpenSkimmer, SoapySDR and the Airspy libraries have their
own licenses.
