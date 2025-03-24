#!/bin/bash

# Maak directories aan voor de iconen
mkdir -p AppIcon.appiconset
mkdir -p temp_icons

# Kopieer het basis icoon
cp MediaTransferApp/icon_1024.svg temp_icons/Icon-1024.svg

# Converteer SVG naar PNG zonder alpha channel
sips -s format png temp_icons/Icon-1024.svg --out temp_icons/Icon-1024.png
sips -s formatOptions png no-alpha temp_icons/Icon-1024.png --out temp_icons/Icon-1024.png

# Array met icon groottes
sizes=("20x20" "29x29" "40x40" "58x58" "60x60" "76x76" "80x80" "87x87" "120x120" "152x152" "167x167" "180x180" "1024x1024")

# Genereer iconen voor elke grootte
for size in "${sizes[@]}"
do
    dimension="${size%x*}"
    sips -z "$dimension" "$dimension" temp_icons/Icon-1024.png --out "temp_icons/$dimension.png"
done

# Verplaats de gegenereerde iconen
mv temp_icons/*.png AppIcon.appiconset/

# Ruim tijdelijke bestanden op
rm -rf temp_icons

echo "Alle app iconen zijn gegenereerd met exacte afmetingen!" 