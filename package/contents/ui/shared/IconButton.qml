import QtQuick

// Square icon button with a hover tooltip. `active` = toggled on.
Rectangle {
    id: btn

    property var theme
    property string icon
    property string tip: ""
    property bool active: false
    property bool danger: false
    property int size: 26
    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: 6
    color: active ? theme.badge : (mouse.containsMouse ? theme.hover : "transparent")

    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: Math.round(btn.size * 0.58)
        color: btn.danger ? btn.theme.bad : (btn.active || mouse.containsMouse ? btn.theme.text : btn.theme.sub)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    // Tooltip: after a short hover, below the button (inside the popup).
    Rectangle {
        visible: btn.tip !== "" && tipTimer.shown
        z: 100
        anchors.top: parent.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: tipText.implicitWidth + 12
        height: tipText.implicitHeight + 6
        radius: 4
        color: btn.theme.cardSolid
        border.width: 1
        border.color: btn.theme.border

        Text {
            id: tipText
            anchors.centerIn: parent
            text: btn.tip
            color: btn.theme.text
            font.pixelSize: btn.theme.smallSize
        }
    }

    Timer {
        id: tipTimer
        property bool shown: false
        interval: 600
        running: mouse.containsMouse
        onTriggered: shown = true
        onRunningChanged: if (!running)
            shown = false
    }
}
