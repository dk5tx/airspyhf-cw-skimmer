#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests src/skim with a fake SoapySDRUtil and a fake openskimmer (no hardware needed).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); SRC=$HERE/../src
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A=$T/bin/airspyhf-cw-skimmer
mkdir -p "$A/skim.d" "$A/openskimmer/.venv/bin" "$T/stub"
cp "$SRC/skim" "$A/skim"; cp "$SRC/bands.conf" "$A/skim.d/"
printf 'rx1\taaaaaaaaaaaaaaaa\t3.34\nrx2\tbbbbbbbbbbbbbbbb\t-\n' >"$A/skim.d/devices.conf"
printf 'MY_CALL=TE5T\n' >"$A/skim.d/skim.conf"
ln -s airspyhf-cw-skimmer/skim "$T/bin/skim"      # like the installer: a link in bin
ln -s skim "$T/bin/skim-40m"
cat >"$A/openskimmer/.venv/bin/openskimmer" <<'X'
#!/bin/sh
echo "ARGS: $*"; echo "RANGE=$SKIM_RANGE_KHZ EXCL=$SKIM_EXCLUDE_KHZ"
X
chmod +x "$A/skim" "$A/openskimmer/.venv/bin/openskimmer"
plug() { printf '#!/bin/sh\nfor s in %s; do printf "  serial = %%s\\n" $s; done\n' "$*" >"$T/stub/SoapySDRUtil"; chmod +x "$T/stub/SoapySDRUtil"; }
export PATH=$T/stub:$PATH
fails=0
expect() { # description, expected-rc, pattern, args...
  local d=$1 rc=$2 pat=$3; shift 3
  local out; out=$("$T/bin/skim" "$@" 2>&1); local r=$?
  if [ "$r" = "$rc" ] && grep -q -- "$pat" <<<"$out"; then echo "ok    $d"; else echo "FAIL  $d (rc=$r)"; echo "$out" | sed 's/^/      /'; fails=$((fails+1)); fi
}
plug aaaaaaaaaaaaaaaa
expect "named receiver, normal"        0 "band-offset 7030000=-23" 40m rx1
expect "no name, single receiver"      0 "serial=aaaaaaaaaaaaaaaa:7030000/192000" 40m
expect "contest window"                0 "RANGE=7000-7100 EXCL=7047-7051.5,7074-7082" 40m rx1 contest
expect "contest falls back to normal"  0 "RANGE=144000-144150" 2m contest
expect "384 kS/s on 160 m contest"     0 "1940000/384000" 160m rx1 contest
expect "extra options pass through"    0 "--workers process" 40m rx1 --workers process
expect "callsign from skim.conf"       0 "my-call TE5T" 40m rx1
expect "receiver not attached"         1 "not attached" 40m rx2
"$T/bin/skim-40m" rx1 >/dev/null 2>&1 && echo "ok    skim-40m symlink" || { echo "FAIL  skim-40m symlink"; fails=$((fails+1)); }
plug bbbbbbbbbbbbbbbb
expect "uncalibrated receiver warns"   0 "not calibrated" 2m rx2
expect "offset 0 when uncalibrated"    0 "band-offset 144075000=0" 2m rx2
plug aaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb
expect "two attached, no name"         1 "several HF+" 40m
plug cccccccccccccccc
expect "unregistered receiver"         0 "unregistered" 40m
expect "add registers it"              0 "added rx3" add rx3
grep -q 'rx3.cccccccccccccccc' "$A/skim.d/devices.conf" && echo "ok    devices.conf updated" || { echo "FAIL  devices.conf not updated"; fails=$((fails+1)); }
expect "add refuses reserved name"     1 "reserved" add 40m dddddddddddddddd
plug ""
expect "nothing attached"              1 "no Airspy HF+" 40m
printf 'MY_CALL=N0CALL\n' >"$A/skim.d/skim.conf"; plug aaaaaaaaaaaaaaaa
expect "refuses N0CALL"                1 "no callsign" 40m rx1
out=$(SKIM_CALL=SK1M "$T/bin/skim" 40m rx1 2>&1); grep -q "my-call SK1M" <<<"$out" && echo "ok    SKIM_CALL override" || { echo "FAIL  SKIM_CALL override"; fails=$((fails+1)); }
exit $((fails ? 1 : 0))
