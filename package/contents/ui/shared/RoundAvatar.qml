// Circular avatar with an initials fallback.
import QtQuick
import QtQuick.Effects

Item {
    id: avatar

    required property var theme
    property string source: ""
    property string login: ""

    readonly property bool ready: picture.status === Image.Ready && avatar.source !== ""

    implicitWidth: 32
    implicitHeight: 32

    Image {
        id: picture

        anchors.fill: parent
        source: avatar.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        sourceSize.width: 128
        sourceSize.height: 128
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: width / 2
        color: "black"
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: picture
        maskEnabled: true
        maskSource: mask
        visible: avatar.ready
    }

    Rectangle {
        id: fallback
        anchors.fill: parent
        radius: width / 2
        visible: !avatar.ready
        color: avatar.theme.badge ? avatar.theme.badge : Qt.rgba(0, 0, 0, 0.25)
        border.width: 1
        border.color: avatar.theme.border ? avatar.theme.border : Qt.rgba(1, 1, 1, 0.12)

        Text {
            anchors.centerIn: parent
            text: avatar.login.length ? avatar.login.substring(0, 1).toUpperCase() : "M"
            color: avatar.theme.text
            font.pixelSize: Math.max(9, Math.round(parent.height * 0.42))
            font.bold: true
        }
    }
}
