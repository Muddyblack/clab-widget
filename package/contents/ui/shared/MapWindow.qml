import QtQuick
import QtQuick.Layouts
import QtQuick.Window

// The topology map in its own resizable window (settings "Map in a window",
// or the pop-out button on the map page). Follows the popup's live snapshot
// by lab id, so it keeps updating while the popup is closed.
Window {
    id: win

    property var popup
    property string labId: ""
    readonly property var lab: {
        var labs = popup && popup.snapshot ? popup.snapshot.labs : [];
        for (var i = 0; i < labs.length; i++)
            if (labs[i].id === labId)
                return labs[i];
        return null;
    }
    readonly property var theme: popup.theme

    width: 900
    height: 640
    minimumWidth: 360
    minimumHeight: 260
    // Not tied to the Plasma popup: it stays when the popup closes.
    transientParent: null
    title: (lab ? lab.name : labId) + " · CLAB map"
    color: theme.cardSolid

    onClosing: destroy()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: win.lab ? win.lab.name : win.labId
                    color: win.theme.text
                    font.pixelSize: win.theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: win.lab ? win.lab.running + "/" + win.lab.total + " up · " + (win.lab.links || []).length + " links · drag to pan, wheel to zoom" : "lab is gone"
                    color: win.lab ? win.theme.sub : win.theme.warn
                    font.pixelSize: win.theme.smallSize
                    elide: Text.ElideRight
                }
            }
            IconButton {
                theme: win.theme
                icon: "zoom-out"
                tip: "Zoom out"
                onClicked: map.zoomBy(1 / 1.3)
            }
            IconButton {
                theme: win.theme
                icon: "maximize"
                tip: "Fit"
                onClicked: map.fit()
            }
            IconButton {
                theme: win.theme
                icon: "zoom-in"
                tip: "Zoom in"
                onClicked: map.zoomBy(1.3)
            }
        }

        MapView {
            id: map
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            theme: win.theme
            lab: win.lab || ({
                    nodes: [],
                    links: []
                })
            menuAnchor: menu
            onNodeMenu: (node, x, y) => win.popup.nodeMenu(win.lab, node, x, y, menu)
        }
    }

    ContextMenu {
        id: menu
        property var target: null
        theme: win.theme
        onTriggered: action => win.popup.nodeAction(target.lab, target.node, action)
    }
}
