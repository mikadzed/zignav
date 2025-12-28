#!/bin/bash
# scripts/build-bundle.sh
# Build ZigNav app bundle for distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Building ZigNav app bundle..."
zig build bundle -Doptimize=ReleaseSafe

echo ""
echo "App bundle created at: zig-out/ZigNav.app"
echo ""
echo "To install, copy to /Applications:"
echo "  cp -r zig-out/ZigNav.app /Applications/"
echo ""
echo "Or run: ./scripts/install.sh"
echo ""
echo "Note: You may need to right-click and 'Open' on first launch"
echo "since the app is not code signed."
