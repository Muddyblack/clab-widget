import QtQuick

// Small flat text button. Plain QtQuick so Quickshell can use it too.
Rectangle {
    id: button

    property var theme
    property string text: ""
    property string tooltip: ""
    signal clicked

    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 6
    radius: 5
    property color baseColor: "transparent"
    color: mouse.containsMouse ? theme.hover : baseColor
    border.width: 1
    border.color: theme.border

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: theme.text
        font.pixelSize: theme.smallSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
