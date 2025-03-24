#!/bin/bash

# Maak een tijdelijke directory voor de iconen
mkdir -p Assets.xcassets/AppIcon.appiconset
mkdir -p temp_icons

# Genereer de verschillende formaten
sizes=(
    "20x20"
    "29x29"
    "40x40"
    "58x58"
    "60x60"
    "76x76"
    "80x80"
    "87x87"
    "120x120"
    "152x152"
    "167x167"
    "180x180"
    "1024x1024"
)

# Kopieer de basis icoon naar de juiste locatie
cp icon_1024.svg temp_icons/Icon-1024.svg

# Converteer SVG naar PNG voor de basis en verwijder alpha kanaal
sips -s format png temp_icons/Icon-1024.svg --out temp_icons/Icon-1024.png
sips -s formatOptions png no-alpha temp_icons/Icon-1024.png --out temp_icons/Icon-1024.png

# Genereer de verschillende formaten
for size in "${sizes[@]}"; do
    if [ "$size" != "1024x1024" ]; then
        width=${size%x*}
        height=${size#*x}
        sips -z $width $height temp_icons/Icon-1024.png --out "temp_icons/$width.png"
        sips -s formatOptions png no-alpha "temp_icons/$width.png" --out "temp_icons/$width.png"
    else
        cp temp_icons/Icon-1024.png "temp_icons/1024.png"
        sips -s formatOptions png no-alpha "temp_icons/1024.png" --out "temp_icons/1024.png"
    fi
done

# Verplaats de iconen naar de juiste locatie
mv temp_icons/*.png Assets.xcassets/AppIcon.appiconset/

# Verwijder de tijdelijke directory
rm -rf temp_icons 