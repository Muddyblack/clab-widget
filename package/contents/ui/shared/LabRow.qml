import QtQuick
import QtQuick.Layouts
import "../../code/Labs.js" as Labs
import "../../code/Theme.js" as Theme

// One lab, one line: ▸ ● name 📌 · [owner] @host  6/7  1.2 GiB  [map open pin] ⋮
// Click toggles its nodes; right-click / ⋮ opens the full menu.
Rectangle {
    id: row

    property var theme
    property var lab
    property bool expanded: false
    property bool pinned: false
    property Item menuAnchor // item the context menu is positioned in
    signal toggled
    signal action(string name)
    signal menuRequested(real x, real y)

    readonly property bool hasMap: (lab.links || []).length > 0 || lab.nodes.length > 1
    readonly property var acts: lab.actions || []

    implicitHeight: 36
    radius: 8
    color: mouse.containsMouse ? theme.hover : (expanded ? theme.card : "transparent")

    // Owner accent (containerlab blue / netlab purple), like the monitor's
    // section colours.
    Rectangle {
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 14
        radius: 1.5
        color: Theme.accent(row.theme, row.lab.managedBy)
        opacity: 0.9
    }

    function openMenu(mx, my) {
        var p = row.mapToItem(row.menuAnchor, mx, my);
        row.menuRequested(p.x, p.y);
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => m.button === Qt.RightButton ? row.openMenu(m.x, m.y) : row.toggled()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 4
        spacing: 7

        Icon {
            name: row.expanded ? "chevron-down" : "chevron-right"
            size: 14
            color: row.theme.sub
            opacity: row.lab.nodes.length > 0 ? 1 : 0.3
        }

        Rectangle {
            Layout.preferredWidth: 9
            Layout.preferredHeight: 9
            radius: 4.5
            color: Labs.lifecycleColor(row.theme, row.lab.lifecycle)
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: Math.min(implicitWidth, 90)
            text: row.lab.name
            color: row.theme.text
            opacity: 0.9
            font.pixelSize: row.theme.fontSize
            font.bold: true
            font.letterSpacing: 0.3
            elide: Text.ElideRight
        }

        Icon {
            visible: row.pinned
            name: "pin"
            size: 12
            color: row.theme.ok
        }

        Image {
            visible: row.lab.via !== "k8s"
            Layout.preferredWidth: 15
            Layout.preferredHeight: 15
            sourceSize: Qt.size(30, 30)
            fillMode: Image.PreserveAspectFit
            source: Qt.resolvedUrl("../../icons/" + row.lab.managedBy + ".svg")
            opacity: 0.9
        }
        // clabernetes: containerlab on Kubernetes (the helm wheel stands for k8s).
        Icon {
            visible: row.lab.via === "k8s"
            name: "ship-wheel"
            size: 14
            color: Theme.accent(row.theme, row.lab.managedBy)
        }

        Text {
            visible: !!row.lab.host
            text: "@" + (row.lab.host || "")
            color: row.theme.sub
            font.pixelSize: row.theme.smallSize
        }

        // The headline reading: "6/7" bold in the state colour (text for
        // labs without node counts, e.g. netlab still starting).
        Text {
            // A long status (a clabernetes error) elides here, not the lab name.
            Layout.maximumWidth: row.width * 0.38
            elide: Text.ElideRight
            text: row.lab.nodesKnown && row.lab.total > 0 ? row.lab.running + "/" + row.lab.total : Labs.lifecycleText(row.lab)
            color: Labs.lifecycleColor(row.theme, row.lab.lifecycle)
            font.pixelSize: row.lab.nodesKnown && row.lab.total > 0 ? row.theme.fontSize + 1 : row.theme.smallSize
            font.bold: row.lab.nodesKnown && row.lab.total > 0
        }

        Text {
            visible: text !== "" && !mouse.containsMouse
            text: Labs.memoryText(row.lab)
            color: row.theme.sub
            font.pixelSize: row.theme.smallSize
        }

        // Quick actions, shown while hovering the row.
        Row {
            visible: mouse.containsMouse || hoverKeep.hovered
            spacing: 1

            IconButton {
                theme: row.theme
                icon: "network"
                tip: "Map"
                size: 24
                visible: row.hasMap
                onClicked: row.action("map")
            }
            IconButton {
                theme: row.theme
                icon: "external-link"
                tip: "Open"
                size: 24
                visible: row.acts.indexOf("open") >= 0
                onClicked: row.action("open")
            }
            IconButton {
                theme: row.theme
                icon: row.pinned ? "pin-off" : "pin"
                tip: row.pinned ? "Unpin from panel" : "Pin to panel"
                size: 24
                onClicked: row.action("pin")
            }

            HoverHandler {
                id: hoverKeep
            }
        }

        IconButton {
            theme: row.theme
            icon: "ellipsis-vertical"
            tip: "More"
            size: 24
            onClicked: row.openMenu(x + width / 2, y + height)
        }
    }
}
