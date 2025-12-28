#!/bin/bash
# scripts/install.sh
# Install ZigNav to /Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/zig-out/ZigNav.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    echo "Run 'zig build bundle' or './scripts/build-bundle.sh' first."
    exit 1
fi

echo "Installing ZigNav to /Applications..."

# Remove existing installation if present
if [ -d "/Applications/ZigNav.app" ]; then
    echo "Removing existing ZigNav installation..."
    rm -rf "/Applications/ZigNav.app"
fi

cp -r "$APP_BUNDLE" /Applications/

echo "Removing quarantine attribute..."
xattr -cr /Applications/ZigNav.app 2>/dev/null || true

echo ""
echo "ZigNav installed to /Applications/ZigNav.app"
echo ""
echo "Before first use, grant these permissions in System Settings:"
echo "  - Privacy & Security > Accessibility"
echo "  - Privacy & Security > Input Monitoring"
echo ""
echo "To launch: open /Applications/ZigNav.app"
