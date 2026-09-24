#!/bin/sh
# Install the tray app for this user on any Linux desktop that isn't Plasma or
# Quickshell (GNOME, Cinnamon, XFCE, Sway…): a menu entry, the app icon, and
# optionally autostart. Runs from this checkout; nothing is copied but icons.
#
#   desktop/install-linux.sh [--autostart] [--uninstall]
#
# Needs python3 with PySide6: your distro's package (python3-pyside6 /
# pyside6) or `pip install --user PySide6-Essentials`.
# GNOME shows tray icons only with the "AppIndicator and KStatusNotifierItem
# Support" extension (Ubuntu ships it). Without a tray the app opens as a
# normal window instead, and notifications still arrive.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
ID=org.muddyblack.clabWidget
ENTRY="$DATA/applications/$ID.desktop"
AUTOSTART="$CONFIG/autostart/$ID.desktop"

if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$ENTRY" "$AUTOSTART"
    for n in 16 22 32 48 64 128 256; do
        rm -f "$DATA/icons/hicolor/${n}x${n}/apps/$ID.png"
    done
    echo "removed"
    exit 0
fi

PY=$(command -v python3 || true)
if [ -z "$PY" ]; then
    echo "python3 not found" >&2
    exit 1
fi
if ! "$PY" -c "import PySide6" 2>/dev/null; then
    echo "PySide6 missing: install python3-pyside6 (or pyside6) from your distro," >&2
    echo "or run: $PY -m pip install --user PySide6-Essentials" >&2
    exit 1
fi

for n in 16 22 32 48 64 128 256; do
    mkdir -p "$DATA/icons/hicolor/${n}x${n}/apps"
    cp "$ROOT/package/contents/icons/app/$ID-$n.png" "$DATA/icons/hicolor/${n}x${n}/apps/$ID.png"
done

mkdir -p "$(dirname "$ENTRY")"
cat >"$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=CLAB Widget
GenericName=Lab status
Comment=Containerlab & netlab lab status: running labs, down nodes, node shells
Exec="$PY" "$HERE/app.py"
Icon=$ID
Terminal=false
Categories=Network;Development;
Keywords=containerlab;netlab;lab;network;
StartupNotify=false
EOF
echo "menu entry: $ENTRY"

if [ "${1:-}" = "--autostart" ]; then
    mkdir -p "$(dirname "$AUTOSTART")"
    cp "$ENTRY" "$AUTOSTART"
    echo "autostart: $AUTOSTART"
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "$DATA/icons/hicolor" 2>/dev/null || true
echo "done: start \"CLAB Widget\" from the app menu"
