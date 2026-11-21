#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds dist/airspyhf-cw-skimmer-setup.sh: install.sh with src/ embedded, for use without a checkout.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
{ cat install.sh; tar czf - src | base64; } >dist/airspyhf-cw-skimmer-setup.sh
chmod +x dist/airspyhf-cw-skimmer-setup.sh
bash -n dist/airspyhf-cw-skimmer-setup.sh
echo "built dist/airspyhf-cw-skimmer-setup.sh"
