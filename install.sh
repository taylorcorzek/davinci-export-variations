#!/bin/bash
# Install ExportVariations script for DaVinci Resolve
# Usage: bash install.sh

DEST="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Deliver/ExportVariations.lua"
SRC="https://raw.githubusercontent.com/taylorcorzek/davinci-export-variations/main/ExportVariations.lua"

echo "Installing ExportVariations for DaVinci Resolve..."
curl -fsSL "$SRC" -o "$DEST"

if [ $? -eq 0 ]; then
    echo "Done. Restart DaVinci Resolve and find it under:"
    echo "  Workspace > Scripts > Deliver > ExportVariations"
else
    echo "Install failed. Try running with sudo:"
    echo "  sudo bash install.sh"
fi
