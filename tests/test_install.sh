#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests install.sh --files-only from the checkout and from the standalone build; no network, no sudo.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$HERE/..
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub"
printf '#!/bin/sh\nprintf "  serial = 0123456789abcdef\\n  serial = fedcba9876543210\\n"\n' >"$T/stub/SoapySDRUtil"; chmod +x "$T/stub/SoapySDRUtil"
export PATH=$T/stub:$PATH SKIM_ALLOW_ROOT=1
fails=0
chk() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=$((fails+1)); fi; }
A=$T/a/airspyhf-cw-skimmer
SKIM_CALL=TE5T SKIM_PREFIX=$T/a bash "$ROOT/install.sh" --files-only >/dev/null 2>&1
chk "scripts in the app folder"              "[ -x $A/skim ] && [ -x $A/skim-cal ] && [ -d $A/skim.d ]"
chk "only two links in bin"                  "[ -L $T/a/skim ] && [ -L $T/a/skim-cal ] && [ \$(ls $T/a | wc -l) = 3 ]"
chk "link resolves to the script"            "[ \"\$(readlink -f $T/a/skim)\" = \"\$(readlink -f $A/skim)\" ]"
chk "callsign written to skim.conf"          "grep -q '^MY_CALL=TE5T' $A/skim.d/skim.conf"
chk "attached receivers registered"          "grep -q 'rx1.0123456789abcdef' $A/skim.d/devices.conf && grep -q 'rx2.fedcba9876543210' $A/skim.d/devices.conf"
sed -i 's/^rx1.*/rx1\t0123456789abcdef\t2.5/' "$A/skim.d/devices.conf"
SKIM_PREFIX=$T/a bash "$ROOT/install.sh" --files-only >/dev/null 2>&1
chk "rerun keeps calibrated devices.conf"    "grep -q '2.5' $A/skim.d/devices.conf"
SKIM_PREFIX=$T/a bash "$ROOT/install.sh" --files-only --band-links >/dev/null 2>&1
chk "--band-links creates short forms"       "[ -L $T/a/skim-40m ] && [ -L $T/a/skim-2m ]"
SKIM_PREFIX=$T/a bash "$ROOT/install.sh" --files-only >/dev/null 2>&1
chk "without the option old short forms go"  "[ ! -e $T/a/skim-40m ]"
# migration from the flat layout of earlier versions
mkdir -p "$T/m/skim.d" "$T/m/openskimmer/.venv" "$T/m/openskimmer/.git"
printf 'tx\t0123456789abcdef\t3.34\n' >"$T/m/skim.d/devices.conf"
printf '#!/bin/sh\n' >"$T/m/skim"; for b in 40m 2m; do ln -s skim "$T/m/skim-$b"; done
SKIM_PREFIX=$T/m bash "$ROOT/install.sh" --files-only >/dev/null 2>&1
M=$T/m/airspyhf-cw-skimmer
chk "migration: settings moved, ppm kept"    "grep -q '3.34' $M/skim.d/devices.conf && [ ! -e $T/m/skim.d ]"
chk "migration: OpenSkimmer moved, venv dropped" "[ -d $M/openskimmer/.git ] && [ ! -e $M/openskimmer/.venv ] && [ ! -e $T/m/openskimmer ]"
chk "migration: skim is a link now"          "[ -L $T/m/skim ] && [ ! -e $T/m/skim-40m ]"
# refuses to install into its own checkout
mkdir -p "$T/c/airspyhf-cw-skimmer"; cp -r "$ROOT/install.sh" "$ROOT/src" "$T/c/airspyhf-cw-skimmer/"
out=$(SKIM_PREFIX=$T/c bash "$T/c/airspyhf-cw-skimmer/install.sh" --files-only 2>&1); rc=$?
chk "refuses to run from the install folder" "[ $rc != 0 ] && grep -q 'lives in the install folder' <<<\"\$out\" && [ ! -e $T/c/skim ]"
bash "$ROOT/tools/make-standalone.sh" >/dev/null 2>&1
SKIM_PREFIX=$T/b bash "$ROOT/dist/airspyhf-cw-skimmer-setup.sh" --files-only >/dev/null 2>&1
B=$T/b/airspyhf-cw-skimmer
chk "standalone install: files identical"    "cmp -s $A/skim $B/skim && cmp -s $A/skim.d/bands.conf $B/skim.d/bands.conf && cmp -s $A/skim.d/cal.py $B/skim.d/cal.py"
chk "no leftovers in /tmp"                   "! ls /tmp 2>/dev/null | grep -q '^skim-src\.'"
rm -rf "$ROOT/dist"
exit $((fails ? 1 : 0))
