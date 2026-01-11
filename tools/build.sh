#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

dart run tools/bump_build_number.dart

cd mobile_app
flutter build "$@"
