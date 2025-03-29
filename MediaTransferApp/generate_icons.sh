#!/bin/bash

# Create temporary directory for icons
mkdir -p AppIcon.appiconset
mkdir -p temp_icons

# Copy base icon
cp MediaTransferApp/icon_1024.svg temp_icons/Icon-1024.svg

# Convert SVG to PNG and remove alpha channel
sips -s format png temp_icons/Icon-1024.svg --out temp_icons/Icon-1024.png
sips -s formatOptions png no-alpha temp_icons/Icon-1024.png --out temp_icons/Icon-1024.png

# Array of icon sizes
sizes=("20x20" "29x29" "40x40" "58x58" "60x60" "76x76" "80x80" "87x87" "120x120" "152x152" "167x167" "180x180" "1024x1024")

# Generate icons for each size
for size in "${sizes[@]}"
do
    dimension="${size%x*}"
    sips -z "$dimension" "$dimension" temp_icons/Icon-1024.png --out "temp_icons/$dimension.png"
done

# Move generated icons
mv temp_icons/*.png AppIcon.appiconset/

# Clean up temporary files
rm -rf temp_icons

echo "All app icons have been generated with exact dimensions!" 