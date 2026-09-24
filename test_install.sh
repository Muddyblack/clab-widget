#!/usr/bin/env bash
# Install the working copy as a separate "CLAB Widget (Test)" widget, next to
# (not over) a released install.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
METADATA="$HERE/package/metadata.json"

# Find kpackagetool6 anywhere on PATH (works on NixOS, Arch, Ubuntu, Fedora, etc.)
TOOL="$(command -v kpackagetool6 2>/dev/null || true)"
if [ -z "$TOOL" ] || [ ! -x "$TOOL" ]; then
    echo "error: kpackagetool6 not found in PATH" >&2
    echo "       Install the KDE Plasma SDK for your distro:" >&2
    echo "         NixOS/nix: nix shell nixpkgs#kdePackages.plasma-sdk" >&2
    echo "         Arch:      sudo pacman -S plasma-sdk" >&2
    echo "         Ubuntu:    sudo apt install plasma-sdk" >&2
    echo "         Fedora:    sudo dnf install plasma-sdk" >&2
    exit 1
fi

ID="$(grep -oE '"Id":[[:space:]]*"[^"]+"' "$METADATA" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
NAME="$(grep -oE '"Name":[[:space:]]*"[^"]+"' "$METADATA" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
TEST_ID="${ID}Test"
TEMP_DIR="/tmp/$(basename "$HERE")-test"

rm -rf "$TEMP_DIR"
cp -r "$HERE/package" "$TEMP_DIR"
find "$TEMP_DIR" -name __pycache__ -type d -prune -exec rm -rf {} +

sed -i "s/\"Id\": \"$ID\"/\"Id\": \"$TEST_ID\"/; s/\"Icon\": \"$ID\"/\"Icon\": \"$TEST_ID\"/" "$TEMP_DIR/metadata.json"
sed -i "s/\"Name\": \"$NAME\"/\"Name\": \"$NAME (Test)\"/g" "$TEMP_DIR/metadata.json"

# The app icon (PNG sizes) into the user's icon theme under the test id, so
# the widget explorer shows it.
for f in "$TEMP_DIR/contents/icons/app/${ID}"-*.png; do
    n="${f##*-}"
    n="${n%.png}"
    dir="$HOME/.local/share/icons/hicolor/${n}x${n}/apps"
    mkdir -p "$dir"
    cp "$f" "$dir/$TEST_ID.png"
done

echo "Installing test version of the widget..."
if "$TOOL" -t Plasma/Applet -l 2>/dev/null | grep -q "$TEST_ID"; then
    "$TOOL" -t Plasma/Applet -u "$TEMP_DIR" 2>/dev/null
    echo "Updated existing test install."
else
    "$TOOL" -t Plasma/Applet -i "$TEMP_DIR" 2>/dev/null
    echo "Installed fresh test widget."
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo ""
    echo "warning: python3 is not on PATH; the widget's backend needs it."
    echo "         (NixOS: use the Nix package / nixosModules.default instead, which pins it.)"
fi

echo ""
echo "=== Test Widget Installed! ==="
echo "Add '$NAME (Test)' to your desktop, panel or system tray, or restart plasmashell if already added:"
echo "  plasmashell --replace &"
echo ""
echo "To remove the test version:"
echo "  $TOOL -t Plasma/Applet -r $TEST_ID"
echo "  rm -f $HOME/.local/share/icons/hicolor/*/apps/$TEST_ID.png"
