import QtQuick
import QtQuick.Layouts
import "../../code/Theme.js" as Theme

// A topology from the lab folders that isn't deployed: grey dot, name, owner
// logo, its folder; Deploy on hover, right-click / ⋮ for the menu.
Item {
    id: row

    property var theme
    property var lab
    property Item menuAnchor
    signal deploy
    signal menuRequested(real x, real y)

    function openMenu(mx, my) {
        var p = row.mapToItem(row.menuAnchor, mx, my);
        row.menuRequested(p.x, p.y);
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        radius: 7
        color: mouse.containsMouse || keep.hovered ? row.theme.hover : "transparent"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.RightButton
        onClicked: m => row.openMenu(m.x, m.y)
    }

    RowLayout {
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.leftMargin: 10
        anchors.rightMargin: 4
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: "transparent"
            border.width: 1.5
            border.color: row.theme.sub
        }

        Text {
            Layout.maximumWidth: row.width * 0.42
            text: row.lab.name
            color: row.theme.text
            opacity: 0.75
            font.pixelSize: row.theme.fontSize
            elide: Text.ElideRight
        }

        Image {
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            sourceSize: Qt.size(28, 28)
            source: Qt.resolvedUrl("../../icons/" + row.lab.managedBy + ".svg")
            opacity: 0.7
        }

        Text {
            Layout.fillWidth: true
            text: row.lab.dir
            color: row.theme.sub
            font.pixelSize: row.theme.smallSize
            elide: Text.ElideLeft
        }

        Row {
            spacing: 1
            HoverHandler {
                id: keep
            }
            IconButton {
                theme: row.theme
                icon: "play"
                tip: row.lab.managedBy === "netlab" ? "Deploy (netlab up)" : "Deploy"
                size: 24
                opacity: mouse.containsMouse || keep.hovered ? 1 : 0.0
                onClicked: row.deploy()
            }
            IconButton {
                id: more
                theme: row.theme
                icon: "ellipsis-vertical"
                tip: "More"
                size: 24
                onClicked: {
                    var p = more.mapToItem(row, more.width / 2, more.height);
                    row.openMenu(p.x, p.y);
                }
            }
        }
    }
}
