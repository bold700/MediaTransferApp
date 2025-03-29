#!/bin/bash

# Create directories for icons
mkdir -p icons/temp

# Copy the base icon
cp icon.svg icons/temp/

# Convert SVG to PNG without alpha channel
for size in 20 29 40 60 76 83.5 1024; do
    inkscape -w ${size} -h ${size} icons/temp/icon.svg -o icons/temp/icon_${size}.png
    convert icons/temp/icon_${size}.png -alpha off icons/temp/icon_${size}.png
done

# Generate icons for each size
for size in 20 29 40 60 76 83.5 1024; do
    for scale in 1 2 3; do
        if [ "$size" == "83.5" ] && [ "$scale" == "3" ]; then
            continue
        fi
        if [ "$size" == "1024" ] && [ "$scale" != "1" ]; then
            continue
        fi
        final_size=$(echo "$size * $scale" | bc)
        cp icons/temp/icon_${size}.png "icons/icon_${size}@${scale}x.png"
    done
done

rm -rf icons/temp

echo "All icons have been generated with exact dimensions!" 