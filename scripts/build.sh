#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Windburst"
CONFIG="Release"
CLEAN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build Windburst and copy Windburst.app to the output directory.

Options:
  -c, --config CONFIG   Build configuration: Debug or Release (default: Release)
  --clean               Remove build artifacts before building
  -o, --output DIR      Output directory for Windburst.app (default: build/)
  -h, --help            Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --config Debug
  $(basename "$0") --clean --output dist
EOF
}

OUTPUT_DIR="$ROOT/build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    -o|--output)
      OUTPUT_DIR="$(cd "$2" 2>/dev/null && pwd || echo "$2")"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$CONFIG" != "Debug" && "$CONFIG" != "Release" ]]; then
  echo "Error: config must be Debug or Release (got: $CONFIG)" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and command-line tools." >&2
  exit 1
fi

cd "$ROOT"

if [[ ! -f "Windburst.xcodeproj/project.pbxproj" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "Generating Xcode project..."
    xcodegen generate
  else
    echo "Error: Windburst.xcodeproj missing and xcodegen is not installed." >&2
    exit 1
  fi
elif command -v xcodegen >/dev/null 2>&1; then
  echo "Regenerating Xcode project from project.yml..."
  xcodegen generate
fi

DERIVED_DATA="$OUTPUT_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIG"
APP_NAME="Windburst.app"
APP_OUTPUT="$OUTPUT_DIR/$APP_NAME"

if [[ "$CLEAN" -eq 1 ]]; then
  echo "Cleaning $OUTPUT_DIR..."
  rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

echo "Building $SCHEME ($CONFIG)..."
xcodebuild \
  -project "$ROOT/Windburst.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

BUILT_APP="$PRODUCTS_DIR/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Error: expected app bundle not found at $BUILT_APP" >&2
  exit 1
fi

echo "Copying app bundle to $APP_OUTPUT..."
rm -rf "$APP_OUTPUT"
ditto "$BUILT_APP" "$APP_OUTPUT"

echo ""
echo "Build complete."
echo "  App:    $APP_OUTPUT"
echo "  Binary: $APP_OUTPUT/Contents/MacOS/Windburst"
