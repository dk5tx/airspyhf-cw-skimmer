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

```sh
git clone https://github.com/dk5tx/airspyhf-cw-skimmer.git ~/git/airspyhf-cw-skimmer
cd ~/git/airspyhf-cw-skimmer
SKIM_CALL=YOURCALL bash install.sh
```

Clone the repository anywhere **except** `~/bin/airspyhf-cw-skimmer`: that folder is the install
target, and the installer refuses to run from it.

Log out and in once if the installer added you to the `plugdev` group. Without a checkout,
`tools/make-standalone.sh` builds a single self-extracting file (`dist/`).

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

The launcher and the calibration have been used with an Airspy HF+ on Linux Mint 22.3.
The system part of the installer (apt, plugin build, git) has so far been tested only
partially. Please report problems as issues.

## License

GPL-3.0-or-later, see `LICENSE`. OpenSkimmer, SoapySDR and the Airspy libraries have their
own licenses.
