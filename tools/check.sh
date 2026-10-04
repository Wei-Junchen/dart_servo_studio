#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
flutter=${FLUTTER:-.tools/flutter/bin/flutter}
if [[ ! -x "$flutter" ]]; then flutter=$(command -v flutter); fi
"$flutter" analyze
"$flutter" test
"$flutter" build linux --release
