import QtQuick

// Tab row as in the Glassy System Monitor studio: icon + label, the current
// tab brighter with an accent underline. Scrolls sideways when it doesn't fit.
Flickable {
    id: bar

    property var theme
    // [{id, label, icon}]
    property var tabs: []
    property string current: ""
    signal activated(string id)

    implicitHeight: 34
    contentWidth: row.width
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.HorizontalFlick

    Row {
        id: row
        spacing: 2

        Repeater {
            model: bar.tabs

            Item {
                id: tab
                required property var modelData
                readonly property bool selected: bar.current === modelData.id
                readonly property bool lit: selected || area.containsMouse
                objectName: "settingsTab_" + modelData.id
                width: content.width + 16
                height: bar.height

                Row {
                    id: content
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    spacing: 6

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: tab.modelData.icon
                        size: 14
                        color: tab.lit ? bar.theme.text : bar.theme.sub
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.label
                        color: tab.lit ? bar.theme.text : bar.theme.sub
                        font.pixelSize: bar.theme.smallSize + 1
                        font.bold: tab.selected
                    }
                }

                Rectangle {
                    x: 8
                    width: parent.width - 16
                    height: 2
                    radius: 1
                    anchors.bottom: parent.bottom
                    color: bar.theme.clab || bar.theme.ok
                    visible: tab.selected
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.activated(tab.modelData.id)
                }
            }
        }
    }
}
