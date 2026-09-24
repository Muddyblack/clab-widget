import QtQuick
import QtQuick.Layouts

// Label + switch row for the settings page. Plain QtQuick: no QQC2 style
// is guaranteed under Quickshell.
RowLayout {
    id: toggle

    property var theme
    property string text: ""
    property bool checked: false
    signal toggled(bool checked)

    spacing: 10

    Text {
        Layout.fillWidth: true
        text: toggle.text
        color: toggle.theme.text
        font.pixelSize: toggle.theme.fontSize
        wrapMode: Text.Wrap
    }

    Rectangle {
        implicitWidth: 34
        implicitHeight: 18
        radius: 9
        color: toggle.checked ? toggle.theme.ok : toggle.theme.badge
        border.width: 1
        border.color: toggle.theme.border

        Rectangle {
            width: 12
            height: 12
            radius: 6
            y: 3
            x: toggle.checked ? parent.width - width - 3 : 3
            color: "#ffffff"
            Behavior on x {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled(!toggle.checked)
        }
    }
}
