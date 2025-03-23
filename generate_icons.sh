#!/bin/bash

# Ga naar de juiste directory
cd "$(dirname "$0")"

# Definieer het pad naar de AppIcon.appiconset
ICON_DIR="MediaTransferApp/Assets.xcassets/AppIcon.appiconset"

# Maak een tijdelijke directory
mkdir -p temp_icons

# Converteer SVG naar een grote PNG voor gebruik als bron
magick "$ICON_DIR/icon.svg" -resize 1024x1024 -background none -flatten temp_icons/Icon-1024.png

# Array met alle benodigde formaten
declare -a SIZES=(20 29 40 58 60 76 80 87 120 152 167 180 1024)

# Genereer alle formaten met exacte afmetingen
for size in "${SIZES[@]}"; do
    echo "Generating ${size}x${size} icon..."
    magick temp_icons/Icon-1024.png -resize "${size}x${size}^" -gravity center -extent "${size}x${size}" "$ICON_DIR/Icon-${size}.png"
done

# Verwijder de tijdelijke directory
rm -rf temp_icons

echo "Alle app iconen zijn gegenereerd met exacte afmetingen!" 