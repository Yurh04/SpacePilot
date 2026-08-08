#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_full_xcode() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -z "$developer_dir" || "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
    cat >&2 <<EOF
Release verification requires full Xcode 16+ with XCTest support.
Current developer directory: ${developer_dir:-not set}

Select the Xcode app before running this script:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
EOF
    exit 1
  fi
}

cleanup() {
  pkill -x SpacePilot >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Release verification requires an Apple Silicon Mac" >&2
  exit 1
fi

require_full_xcode

swift test --parallel
swift build -c release
SPACEPILOT_BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify
/usr/bin/codesign --verify --deep --strict dist/SpacePilot.app
/usr/bin/ditto -c -k --keepParent dist/SpacePilot.app dist/SpacePilot.zip

if /usr/sbin/spctl --assess --type execute --verbose dist/SpacePilot.app; then
  echo "Gatekeeper accepted the app bundle"
else
  echo "Gatekeeper did not accept the ad-hoc development signature; Developer ID signing and notarization are still required for distribution"
fi

echo "SpacePilot release checks passed"
