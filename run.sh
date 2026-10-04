#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
binary=build/linux/x64/release/bundle/dart_servo_studio
stamp=build/linux/x64/release/bundle/lib/libapp.so
flutter=${FLUTTER:-.tools/flutter/bin/flutter}
if [[ ! -x "$flutter" ]]; then flutter=$(command -v flutter || true); fi
if [[ "${1:-}" == --dev ]]; then
  shift
  [[ -n "$flutter" ]] || { echo '未找到 Flutter SDK，请设置 FLUTTER=/path/to/flutter/bin/flutter' >&2; exit 1; }
  exec "$flutter" run -d linux "$@"
fi
if [[ "${1:-}" == --build ]]; then
  shift
  [[ -n "$flutter" ]] || { echo '未找到 Flutter SDK' >&2; exit 1; }
  "$flutter" build linux --release
elif [[ ! -x "$binary" || ! -f "$stamp" ]] || [[ -n "$(find lib linux/runner pubspec.yaml pubspec.lock -newer "$stamp" -print -quit 2>/dev/null)" ]]; then
  [[ -n "$flutter" ]] || { echo '需要构建，但未找到 Flutter SDK' >&2; exit 1; }
  "$flutter" build linux --release
fi
exec "$binary" "$@"
