#!/bin/bash

# Maak een tijdelijke directory voor de iconen
mkdir -p temp_icons

# Genereer de verschillende formaten
sizes=(
    "20x20"
    "29x29"
    "40x40"
    "60x60"
    "76x76"
    "83.5x83.5"
    "1024x1024"
)

# Kopieer de basis icoon naar de juiste locatie
cp AppIcon.appiconset/Icon-1024.png temp_icons/Icon-1024.png

# Genereer de verschillende formaten
for size in "${sizes[@]}"; do
    if [ "$size" != "1024x1024" ]; then
        sips -z ${size%x*} ${size#*x} temp_icons/Icon-1024.png --out "temp_icons/Icon-${size}.png"
    fi
done

# Verplaats de iconen naar de juiste locatie
mv temp_icons/Icon-20x20.png AppIcon.appiconset/Icon-20x20.png
mv temp_icons/Icon-29x29.png AppIcon.appiconset/Icon-29x29.png
mv temp_icons/Icon-40x40.png AppIcon.appiconset/Icon-40x40.png
mv temp_icons/Icon-60x60.png AppIcon.appiconset/Icon-60x60.png
mv temp_icons/Icon-76x76.png AppIcon.appiconset/Icon-76x76.png
mv temp_icons/Icon-83.5x83.5.png AppIcon.appiconset/Icon-83.5x83.5.png
mv temp_icons/Icon-1024x1024.png AppIcon.appiconset/Icon-1024x1024.png

# Verwijder de tijdelijke directory
rm -rf temp_icons 