import QtQuick
import QtQuick.Layouts

// Label + [-] value [+] for small integer settings.
RowLayout {
    id: stepper

    property var theme
    property string text: ""
    property int value: 0
    property int from: 0
    property int to: 100
    property int step: 1
    property string suffix: ""
    property string zeroText: ""
    signal changed(int value)

    spacing: 6

    Text {
        Layout.fillWidth: true
        text: stepper.text
        color: stepper.theme.text
        font.pixelSize: stepper.theme.fontSize
        wrapMode: Text.Wrap
    }

    ActionButton {
        theme: stepper.theme
        text: "−"
        onClicked: stepper.changed(Math.max(stepper.from, stepper.value - stepper.step))
    }

    Text {
        Layout.preferredWidth: 52
        horizontalAlignment: Text.AlignHCenter
        text: stepper.value === 0 && stepper.zeroText !== "" ? stepper.zeroText : stepper.value + stepper.suffix
        color: stepper.theme.text
        font.pixelSize: stepper.theme.fontSize
    }

    ActionButton {
        theme: stepper.theme
        text: "+"
        onClicked: stepper.changed(Math.min(stepper.to, stepper.value + stepper.step))
    }
}
