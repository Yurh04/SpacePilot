#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BUILD_CONFIGURATION="${SPACEPILOT_BUILD_CONFIGURATION:-debug}"
APP_NAME="SpacePilot"
BUNDLE_ID="com.yurunhao.SpacePilot"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "$APP_NAME supports Apple Silicon only" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${SPACEPILOT_DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_ICON="$ROOT_DIR/Sources/SpacePilot/Resources/AppIcon.icns"

SWIFT_BUILD_ARGUMENTS=(--package-path "$ROOT_DIR" -c "$BUILD_CONFIGURATION")
if [[ -n "${SPACEPILOT_SCRATCH_PATH:-}" ]]; then
  SWIFT_BUILD_ARGUMENTS+=(--scratch-path "$SPACEPILOT_SCRATCH_PATH")
fi
swift build "${SWIFT_BUILD_ARGUMENTS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
if [[ ! -f "$APP_ICON" ]]; then
  echo "Missing application icon: $APP_ICON" >&2
  exit 1
fi

RESOURCE_BUNDLES=()
while IFS= read -r -d '' candidate; do
  RESOURCE_BUNDLES+=("$candidate")
done < <(find "$BUILD_DIR" -maxdepth 1 -type d -name "${APP_NAME}_*.bundle" -print0)
if [[ "${#RESOURCE_BUNDLES[@]}" -ne 1 ]]; then
  echo "Expected exactly one ${APP_NAME}_*.bundle in $BUILD_DIR; found ${#RESOURCE_BUNDLES[@]}" >&2
  exit 1
fi
RESOURCE_BUNDLE="${RESOURCE_BUNDLES[0]}"
if [[ ! -d "$RESOURCE_BUNDLE/en.lproj" ]] ||
   ! find "$RESOURCE_BUNDLE" -maxdepth 1 -type d -iname "zh-hans.lproj" -print -quit | grep -q .; then
  echo "Localization resource bundle is missing en or zh-Hans resources: $RESOURCE_BUNDLE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/script/Info.plist" "$APP_CONTENTS/Info.plist"
mkdir -p "$APP_RESOURCES"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"
/usr/bin/codesign --force --deep --options runtime --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not launch" >&2
    exit 1
    ;;
  --stage-only|stage-only)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--stage-only]" >&2
    exit 2
    ;;
esac
