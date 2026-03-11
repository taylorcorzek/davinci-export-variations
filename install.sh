#!/bin/bash
# Install Corzek DaVinci Resolve scripts
# Usage: bash install.sh

BASE="https://raw.githubusercontent.com/taylorcorzek/davinci-export-variations/main"
DEST="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Deliver"

SCRIPTS=("ExportVariations.lua" "RoundClipFPS.lua")

echo "Installing Corzek DaVinci scripts..."

for SCRIPT in "${SCRIPTS[@]}"; do
    curl -fsSL "$BASE/$SCRIPT" -o "$DEST/$SCRIPT"
    if [ $? -eq 0 ]; then
        echo "  ✓ $SCRIPT"
    else
        echo "  ✗ $SCRIPT failed — try running with sudo: sudo bash install.sh"
    fi
done

echo ""
echo "Done. Restart DaVinci Resolve and find the scripts under:"
echo "  Workspace > Scripts > Deliver"
