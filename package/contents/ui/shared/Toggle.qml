import QtQuick
import QtQuick.Layouts

// Label + switch, the studio's 36 × 21 pill: brand gradient when on, a
// springy 15 px knob. Plain QtQuick: no QQC2 style is guaranteed under
// Quickshell.
RowLayout {
    id: toggle

    property var theme
    property string text: ""
    property bool checked: false
    signal toggled(bool checked)

    readonly property color brand: toggle.theme.clab || toggle.theme.ok

    spacing: 10

    Text {
        visible: toggle.text !== ""
        Layout.fillWidth: true
        text: toggle.text
        color: toggle.theme.text
        font.pixelSize: toggle.theme.fontSize
        wrapMode: Text.Wrap
    }

    Rectangle {
        implicitWidth: 36
        implicitHeight: 21
        radius: height / 2
        color: toggle.checked ? toggle.brand : Qt.rgba(1, 1, 1, 0.12)
        border.width: toggle.checked ? 0 : 1
        border.color: toggle.theme.border
        gradient: toggle.checked ? onGradient : null

        Gradient {
            id: onGradient
            GradientStop {
                position: 0
                color: Qt.lighter(toggle.brand, 1.25)
            }
            GradientStop {
                position: 1
                color: toggle.brand
            }
        }

        Rectangle {
            width: 15
            height: 15
            radius: 7.5
            y: 3
            x: toggle.checked ? 18 : 3
            color: toggle.checked ? "#07111f" : "#e8edf5"
            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutBack
                    easing.overshoot: 2
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
