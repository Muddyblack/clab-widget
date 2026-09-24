import QtQuick

// The studio's buttons: ghost (outlined, muted text that brightens on hover)
// or `primary` (brand fill, dark bold text) for the one main action of a
// form. Optional Lucide `icon`. Plain QtQuick so Quickshell can use it too.
Rectangle {
    id: button

    property var theme
    property string text: ""
    property string tooltip: ""
    property string icon: ""
    property bool primary: false
    property color baseColor: "transparent"
    signal clicked

    readonly property color brand: theme.clab || theme.ok
    readonly property color ink: primary ? "#07111f" : (mouse.containsMouse ? theme.text : theme.sub)

    implicitWidth: label.implicitWidth + 20 + (icon !== "" ? 18 : 0)
    implicitHeight: label.implicitHeight + 10
    radius: 8
    color: primary ? (mouse.containsMouse ? Qt.lighter(brand, 1.12) : brand) : (mouse.containsMouse ? theme.hover : baseColor)
    border.width: primary ? 0 : 1
    border.color: theme.border
    opacity: enabled ? 1 : 0.45

    Row {
        anchors.centerIn: parent
        spacing: 5
        Icon {
            visible: button.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: button.icon
            size: 13
            color: button.ink
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.ink
            font.pixelSize: button.theme.smallSize
            font.weight: button.primary ? Font.DemiBold : Font.Normal
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
