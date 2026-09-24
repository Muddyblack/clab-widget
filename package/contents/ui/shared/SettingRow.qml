import QtQuick
import QtQuick.Layouts

// One settings row: label + description left, the control right (or below,
// with `stacked`). A hairline above every row but the first.
ColumnLayout {
    id: row

    property var theme
    property string label
    property string desc
    property bool first: false
    property bool stacked: false
    default property alias control: slot.data

    Layout.fillWidth: true
    spacing: 0

    Rectangle {
        visible: !row.first
        Layout.fillWidth: true
        implicitHeight: 1
        color: row.theme.border
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        columns: row.stacked ? 1 : 2
        columnSpacing: 18
        rowSpacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: row.label
                color: row.theme.text
                font.pixelSize: row.theme.fontSize - 1
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                visible: row.desc !== ""
                Layout.fillWidth: true
                text: row.desc
                color: row.theme.sub
                font.pixelSize: row.theme.smallSize
                wrapMode: Text.WordWrap
            }
        }

        Item {
            id: slot
            Layout.alignment: row.stacked ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
            Layout.fillWidth: row.stacked
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
