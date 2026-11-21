#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install.sh - turns a Debian/Ubuntu/Linux Mint machine into a CW skimmer with Airspy HF+ receivers
#
#   bash install.sh               install everything (sudo is used for apt and the SoapySDR plugin)
#   bash install.sh --files-only  only refresh the scripts and settings (no apt, git or build)
#
# Everything ends up in ONE folder, ~/bin/airspyhf-cw-skimmer: openskimmer/ (program and
# virtualenv), the scripts and skim.d/ (settings). Only two links, skim and skim-cal, are
# placed in ~/bin. No dotfiles, caches or source trees are left in $HOME (the plugin is
# built in /tmp, which is removed afterwards). Safe to run again: existing bands.conf,
# devices.conf and skim.conf are kept (new defaults are written as *.new).
#
#   --band-links   also create the short forms skim-40m, skim-2m, ... in ~/bin
#
# A flat layout from earlier versions (~/bin/openskimmer, ~/bin/skim.d) is moved into the folder.
#
# Environment: SKIM_PREFIX (default ~/bin), SKIM_CALL (callsign for a new skim.conf)
set -euo pipefail

BIN=${SKIM_PREFIX:-$HOME/bin}
APP=$BIN/airspyhf-cw-skimmer
OSDIR=$APP/openskimmer
CONF=$APP/skim.d
FILES_ONLY=0
BAND_LINKS=0
for opt in "$@"; do
  case "$opt" in
    --files-only) FILES_ONLY=1 ;;
    --band-links) BAND_LINKS=1 ;;
    -h|--help) sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $opt" >&2; exit 2 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || [ -n "${SKIM_ALLOW_ROOT:-}" ] || die "run as a normal user, not with sudo (sudo is called where needed)"

# Source files: next to this script (git checkout) or embedded (standalone build)
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$HERE/src
if [ -d "$SRC" ] && [ "$HERE" -ef "$APP" ]; then
  die "this checkout lives in the install folder ($APP). Program and settings would be installed into your git checkout. Clone the repository somewhere else (e.g. ~/git) and run install.sh from there."
fi
if [ ! -d "$SRC" ]; then
  TMPSRC=$(mktemp -d "${TMPDIR:-/tmp}/skim-src.XXXXXX")
  trap 'rm -rf "$TMPSRC"' EXIT
  sed -n '/^__PAYLOAD_BELOW__$/,$p' "$0" | tail -n +2 | base64 -d | tar xz -C "$TMPSRC" \
    || die "no embedded files found (use a git checkout or the standalone build)"
  SRC=$TMPSRC/src
fi

put_conf() { # name  sourcefile : create, never overwrite
  local f=$CONF/$1
  if [ -e "$f" ]; then
    if cmp -s "$f" "$2"; then :; else cp "$2" "$f.new"; echo "  $1 exists, new default saved as $1.new"; fi
  else
    cp "$2" "$f"
  fi
}

serials() {
  command -v SoapySDRUtil >/dev/null 2>&1 || return 0
  SoapySDRUtil --find="driver=airspyhf" 2>/dev/null \
    | sed -n 's/^[[:space:]]*serial = *\([0-9A-Fa-f]\{6,\}\).*/\1/p' | tr 'A-F' 'a-f' | sort -u
}

# Earlier layout: everything flat in ~/bin. Move settings and program into the folder.
migrate_old_layout() {
  if [ -d "$BIN/skim.d" ] && [ ! -e "$CONF" ]; then
    mkdir -p "$APP"; mv "$BIN/skim.d" "$CONF"; echo "  moved settings to $CONF"
  fi
  if [ -d "$BIN/openskimmer" ] && [ ! -e "$OSDIR" ]; then
    mkdir -p "$APP"; mv "$BIN/openskimmer" "$OSDIR"
    rm -rf "$OSDIR/.venv"   # a virtualenv contains absolute paths and breaks when moved; rebuilt below
    echo "  moved OpenSkimmer to $OSDIR (virtualenv will be rebuilt)"
    if [ $FILES_ONLY = 1 ]; then echo "  NOTE: run install.sh without --files-only to rebuild the virtualenv"; fi
  fi
  local b
  if [ $BAND_LINKS = 0 ]; then   # remove old short-form links
    for b in 160m 80m 40m 30m 20m 17m 15m 12m 10m 2m; do
      if [ -L "$BIN/skim-$b" ] && [ "$(readlink "$BIN/skim-$b")" = skim ]; then rm -f "$BIN/skim-$b"; fi
    done
  fi
}

write_files() {
  migrate_old_layout
  mkdir -p "$BIN" "$APP" "$CONF"
  install -m 755 "$SRC/skim" "$APP/skim"
  install -m 755 "$SRC/skim-cal" "$APP/skim-cal"
  ln -sf "airspyhf-cw-skimmer/skim" "$BIN/skim"
  ln -sf "airspyhf-cw-skimmer/skim-cal" "$BIN/skim-cal"
  install -m 644 "$SRC/cal.py" "$CONF/cal.py"
  install -m 644 "$SRC/patch_soapy.py" "$CONF/patch_soapy.py"
  put_conf bands.conf "$SRC/bands.conf"
  if [ ! -e "$CONF/skim.conf" ]; then
    sed "s/^MY_CALL=N0CALL/MY_CALL=${SKIM_CALL:-N0CALL}/" "$SRC/skim.conf.example" >"$CONF/skim.conf"
  fi
  if [ ! -e "$CONF/devices.conf" ]; then   # register attached receivers as rx1, rx2, ...
    cp "$SRC/devices.conf.example" "$CONF/devices.conf"
    local i=1 s
    for s in $(serials); do printf 'rx%d\t%s\t-\n' "$i" "$s" >>"$CONF/devices.conf"; i=$((i + 1)); done
  fi
  local b
  if [ $BAND_LINKS = 1 ]; then
    for b in 160m 80m 40m 30m 20m 17m 15m 12m 10m 2m; do ln -sf skim "$BIN/skim-$b"; done
  fi
}

install_system() {
  say "System packages (apt)"
  command -v apt-get >/dev/null || die "needs a Debian/Ubuntu based system (apt)"
  sudo apt-get update
  local want="git cmake build-essential pkg-config curl python3 python3-venv python3-pip libsoapysdr-dev soapysdr-tools python3-soapysdr libairspyhf-dev airspyhf"
  local pk ok=() missing=()
  for pk in $want; do
    if apt-cache show "$pk" >/dev/null 2>&1; then ok+=("$pk"); else missing+=("$pk"); fi
  done
  [ ${#missing[@]} -eq 0 ] || echo "  not found in apt (skipped): ${missing[*]}"
  sudo apt-get install -y "${ok[@]}"
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || die "Python 3.9 or newer is required"
}

install_plugin() {
  say "SoapySDR plugin for the Airspy HF+"
  if SoapySDRUtil --info 2>/dev/null | grep -qi airspyhf || \
     find /usr/lib /usr/local/lib -name 'libairspyhfSupport.so' 2>/dev/null | grep -q .; then
    echo "  already installed"
    return
  fi
  local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/soapyhf.XXXXXX")
  git clone --depth 1 https://github.com/pothosware/SoapyAirspyHF.git "$tmp/src"
  cmake -S "$tmp/src" -B "$tmp/build" -DCMAKE_BUILD_TYPE=Release
  make -C "$tmp/build" -j"$(nproc)"
  sudo make -C "$tmp/build" install
  sudo ldconfig
  rm -rf "$tmp"
}

install_udev() {
  say "USB permissions"
  if ! id -nG | tr ' ' '\n' | grep -qx plugdev; then
    sudo usermod -aG plugdev "$USER"
    echo "  added $USER to group plugdev: log out and in again (or reboot) once"
  else
    echo "  plugdev: ok"
  fi
  sudo udevadm control --reload-rules 2>/dev/null || true
  sudo udevadm trigger 2>/dev/null || true
}

install_openskimmer() {
  say "OpenSkimmer in $OSDIR"
  if [ -d "$OSDIR/.git" ]; then
    git -C "$OSDIR" checkout -q -- openskimmer/sdr/soapy.py 2>/dev/null || true
    git -C "$OSDIR" pull --ff-only || echo "  git pull failed, continuing with the existing checkout"
  else
    git clone https://github.com/khkremer/OpenSkimmer.git "$OSDIR"
  fi
  [ -x "$OSDIR/.venv/bin/python" ] || python3 -m venv --system-site-packages "$OSDIR/.venv"
  "$OSDIR/.venv/bin/pip" install --no-cache-dir -q --upgrade pip
  "$OSDIR/.venv/bin/pip" install --no-cache-dir -q -e "$OSDIR"
  python3 -I "$CONF/patch_soapy.py" "$OSDIR/openskimmer/sdr/soapy.py"
  "$OSDIR/.venv/bin/python" -c 'import SoapySDR; print("  SoapySDR python bindings ok, API", SoapySDR.getAPIVersion())' \
    || die "SoapySDR python bindings are not visible in the venv (is python3-soapysdr installed?)"
  say "Callsign databases"
  curl -fsSL -o "$OSDIR/MASTER.SCP" https://www.supercheckpartial.com/MASTER.SCP || echo "  MASTER.SCP: download failed (later: skim update)"
  curl -fsSL -o "$OSDIR/patt3ch.lst" https://data.reversebeacon.net/downloads/patt3ch/patt3ch.lst || echo "  patt3ch.lst: download failed (later: skim update)"
}

check_result() {
  say "Check"
  case ":$PATH:" in *":$BIN:"*) ;; *)
    echo "  note: $BIN is not in PATH yet. Linux Mint adds ~/bin at the next login;"
    echo "  until then: export PATH=\"$BIN:\$PATH\"" ;;
  esac
  if grep -q '^MY_CALL=N0CALL' "$CONF/skim.conf" 2>/dev/null; then
    echo "  TODO: set your callsign in $CONF/skim.conf (MY_CALL=...)"
  fi
  if command -v SoapySDRUtil >/dev/null; then
    echo "  attached HF+ receivers:"; serials | sed 's/^/    /'
  fi
  cat <<'DONE'

Done. Next steps:
  skim list                 show receivers and bands
  skim add rx1              register the attached receiver under a name (if not listed)
  skim-cal rx1              measure its clock error once (10 MHz must be audible)
  skim 40m rx1              CW segment of 40 m
  skim 20m rx1 contest      contest window
Spots: telnet localhost 7300      Waterfall: http://localhost:7380
DONE
}

write_files
if [ $FILES_ONLY = 0 ]; then
  install_system
  install_plugin
  install_udev
  install_openskimmer
fi
check_result
exit 0
__PAYLOAD_BELOW__
