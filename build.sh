#!/bin/bash
# Build, copy into .app bundle, and ad-hoc sign
set -e
cd "$(dirname "$0")"

echo "Building LootDrop..."
swift build

echo "Packaging .app bundle..."
cp .build/debug/LootDrop LootDrop.app/Contents/MacOS/LootDrop

echo "Signing..."
codesign --force --deep --sign - LootDrop.app

echo "Done. Restart with:"
echo "  pkill -f LootDrop; sleep 1; launchctl unload ~/Library/LaunchAgents/com.erikbethke.lootdrop.plist; launchctl load ~/Library/LaunchAgents/com.erikbethke.lootdrop.plist"
