import QtQuick
import QtQuick.Layouts
import "../../code/Labs.js" as Labs

// One node under its expanded lab: role icon + state, name, kind/state/memory,
// IP (click to copy); hover shows ssh / shell / logs (node.access), a down
// node always shows Start (node.ops); right-click opens the menu (restart…).
Rectangle {
    id: item

    property var theme
    property var node
    property Item menuAnchor
    property bool copied: false
    readonly property var access: node.access || []
    readonly property var ops: node.ops || []
    signal action(string name)
    signal copyRequested(string text)
    signal menuRequested(real x, real y)

    implicitHeight: 30
    radius: 6
    color: mouse.containsMouse ? theme.hover : "transparent"

    function openMenu(mx, my) {
        var p = item.mapToItem(item.menuAnchor, mx, my);
        item.menuRequested(p.x, p.y);
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.RightButton
        onClicked: m => item.openMenu(m.x, m.y)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 26
        anchors.rightMargin: 4
        spacing: 8

        Item {
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18

            Image {
                anchors.fill: parent
                source: Labs.fileUrl(item.node.icon)
                sourceSize: Qt.size(36, 36)
                asynchronous: true
                opacity: item.node.running ? 1 : 0.4
            }
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -2
                width: 7
                height: 7
                radius: 3.5
                color: item.node.running ? item.theme.ok : item.theme.bad
                border.width: 1.5
                border.color: item.theme.cardSolid
            }
        }

        Text {
            Layout.preferredWidth: 104
            text: item.node.name
            color: item.theme.text
            font.pixelSize: item.theme.fontSize - 1
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: {
                var p = [item.node.kind];
                if (!item.node.running)
                    p.push(item.node.state);
                if (item.node.memoryBytes !== undefined && item.node.memoryBytes !== null)
                    p.push(Labs.bytes(item.node.memoryBytes));
                return p.join(" · ");
            }
            color: item.node.running ? item.theme.sub : item.theme.bad
            font.pixelSize: item.theme.smallSize
            elide: Text.ElideRight
        }

        Text {
            readonly property string addr: item.node.ipv4 || item.node.ipv6 || ""
            // Fixed, right-aligned column so IPs of different lengths line up.
            Layout.preferredWidth: 112
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: item.copied ? "copied" : (addr || "—")
            color: item.copied ? item.theme.ok : (ipMouse.containsMouse && addr ? item.theme.text : item.theme.sub)
            font.pixelSize: item.theme.smallSize
            // A real family per platform: a missing generic name makes Qt
            // scan every font for an alias (slow, and a warning on macOS).
            font.family: Qt.platform.os === "osx" ? "Menlo" : Qt.platform.os === "windows" ? "Consolas" : "monospace"

            MouseArea {
                id: ipMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.addr !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    item.copyRequested(parent.addr);
                    item.copied = true;
                    copiedReset.restart();
                }
            }
            Timer {
                id: copiedReset
                interval: 1200
                onTriggered: item.copied = false
            }
        }

        // The fix-it: a down node's Start, always visible.
        IconButton {
            visible: item.ops.indexOf("start") >= 0
            theme: item.theme
            icon: "play"
            tip: "Start " + item.node.name
            size: 24
            onClicked: item.action("start")
        }

        // Fixed width (room for all three), so the IP column lines up whether a
        // node offers ssh or not.
        Row {
            Layout.preferredWidth: 3 * 24 + 2
            layoutDirection: Qt.RightToLeft
            spacing: 1
            opacity: mouse.containsMouse || keep.hovered ? 1 : 0.0

            IconButton {
                theme: item.theme
                icon: "scroll-text"
                tip: "Logs"
                size: 24
                visible: item.access.indexOf("logs") >= 0
                onClicked: item.action("logs")
            }
            IconButton {
                theme: item.theme
                icon: "square-terminal"
                tip: "Shell (docker exec)"
                size: 24
                visible: item.access.indexOf("exec") >= 0
                onClicked: item.action("exec")
            }
            IconButton {
                theme: item.theme
                icon: "terminal"
                tip: item.access.indexOf("connect") >= 0 ? "netlab connect" : "SSH"
                size: 24
                visible: item.access.indexOf("ssh") >= 0 || item.access.indexOf("connect") >= 0
                onClicked: item.action(item.access.indexOf("connect") >= 0 ? "connect" : "ssh")
            }
            HoverHandler {
                id: keep
            }
        }
    }
}
