#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$ROOT_DIR/build/Sakura Switch.app"
TARGET_APP="/Applications/Sakura Switch.app"

if [[ ! -d "$SOURCE_APP" ]]; then
    osascript -e 'display dialog "Sakura Switch.app не найден в build/. Сначала запустите Build-SakuraSwitch.command." buttons {"OK"} default button "OK" with icon caution'
    exit 1
fi

killall SakuraSwitch 2>/dev/null || true

sudo rm -rf "$TARGET_APP"
sudo ditto "$SOURCE_APP" "$TARGET_APP"

open "$TARGET_APP"
