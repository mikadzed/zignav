#!/bin/bash
# scripts/create-icon.sh
# Creates ZigNav app icon (.icns) from a base PNG

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$PROJECT_DIR/resources"
ICONSET_DIR="$RESOURCES_DIR/ZigNav.iconset"
BASE_ICON="$RESOURCES_DIR/icon-base.png"

# Check if base icon exists
if [ ! -f "$BASE_ICON" ]; then
    echo "Base icon not found at $BASE_ICON"
    echo ""
    echo "Attempting to generate a placeholder icon..."

    # Try using Python to create a simple icon
    python3 << 'PYTHON_SCRIPT'
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("PIL/Pillow not installed. Install with: pip3 install Pillow")
    print("Or create a 1024x1024 PNG manually at resources/icon-base.png")
    sys.exit(1)

# Create a 1024x1024 image with a dark background
size = 1024
img = Image.new('RGBA', (size, size), (45, 55, 72, 255))  # Dark gray-blue
draw = ImageDraw.Draw(img)

# Draw rounded rectangle background
margin = 80
corner_radius = 180
rect = [margin, margin, size - margin, size - margin]

# Draw the rounded rectangle (simplified - just a regular rect with circles at corners)
draw.rounded_rectangle(rect, radius=corner_radius, fill=(74, 144, 217, 255))  # Blue

# Draw the letter "Z"
# Try to use a system font, fall back to default if not available
font_size = 600
try:
    # Try common macOS fonts
    for font_name in ['/System/Library/Fonts/Helvetica.ttc',
                      '/System/Library/Fonts/SFNSDisplay.ttf',
                      '/Library/Fonts/Arial.ttf']:
        if os.path.exists(font_name):
            font = ImageFont.truetype(font_name, font_size)
            break
    else:
        font = ImageFont.load_default()
except:
    font = ImageFont.load_default()

# Calculate text position to center it
text = "Z"
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_height = bbox[3] - bbox[1]
x = (size - text_width) / 2 - bbox[0]
y = (size - text_height) / 2 - bbox[1] - 20  # Slight adjustment for visual centering

# Draw the letter
draw.text((x, y), text, fill=(255, 255, 255, 255), font=font)

# Save the image
output_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           'resources', 'icon-base.png')
img.save(output_path, 'PNG')
print(f"Created base icon at {output_path}")
PYTHON_SCRIPT

    if [ $? -ne 0 ]; then
        echo ""
        echo "Could not generate icon automatically."
        echo "Please create a 1024x1024 PNG icon and save it as:"
        echo "  $BASE_ICON"
        exit 1
    fi
fi

echo "Creating iconset from $BASE_ICON..."

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Generate all required sizes using sips
# macOS iconset requires these specific sizes
for size in 16 32 128 256 512; do
    double=$((size * 2))

    echo "  Generating ${size}x${size}..."
    sips -z $size $size "$BASE_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1

    echo "  Generating ${size}x${size}@2x..."
    sips -z $double $double "$BASE_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done

echo "Converting iconset to icns..."
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/ZigNav.icns"

# Cleanup
rm -rf "$ICONSET_DIR"

echo ""
echo "Successfully created $RESOURCES_DIR/ZigNav.icns"
