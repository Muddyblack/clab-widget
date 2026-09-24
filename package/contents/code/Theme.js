// The glass palette, shared with Glassy System Monitor / the audio visualizer:
// dark translucent card, white text, neon accents. Used by the Quickshell
// pill, the tray app and the Plasma widget on the desktop (in a Plasma panel
// popup the widget follows the Plasma colour scheme instead).
.pragma library

var GLASS_FILL = "#800d0f1a"; // Glassy System Monitor's default bgColor
var SOLID_FILL = "#141726"; // opaque: a translucent fill makes glassy's "solid" a light paper card

// The card fill for a material: dark and opaque for "solid", translucent otherwise.
function fillFor(material) {
    return material === "solid" ? SOLID_FILL : GLASS_FILL;
}

function glass() {
    return {
        text: "#ffffff",
        sub: Qt.rgba(1, 1, 1, 0.55),
        card: Qt.rgba(1, 1, 1, 0.045),
        cardSolid: "#141726",
        badge: Qt.rgba(1, 1, 1, 0.08),
        hover: Qt.rgba(1, 1, 1, 0.08),
        border: Qt.rgba(1, 1, 1, 0.10),
        ok: "#44ddaa",
        warn: "#ffaa22",
        bad: "#ff4444",
        clab: "#4aa8ff",
        netlab: "#aa66ff",
        fontSize: 13,
        smallSize: 11
    };
}

// Owner accent: containerlab blue, netlab purple (the monitor's section colours).
function accent(theme, managedBy) {
    return managedBy === "netlab" ? (theme.netlab || "#aa66ff") : (theme.clab || "#4aa8ff");
}

// App icon choice (settings "Icon"): "clab", "netlab", or "auto" = the netlab
// icon when only netlab labs are shown. Files: icons/app/<prefix>-<size>.png,
// built from assets/icon*.png by tools/make-app-icons.py.
function appIconVariant(choice, show) {
    if (choice === "netlab" || choice === "clab")
        return choice;
    return show === "netlab" ? "netlab" : "clab";
}

// Path relative to package/contents/.
function appIcon(choice, show, size) {
    var prefix = appIconVariant(choice, show) === "netlab" ? "netlab" : "org.muddyblack.clabWidget";
    return "icons/app/" + prefix + "-" + (size || 64) + ".png";
}
