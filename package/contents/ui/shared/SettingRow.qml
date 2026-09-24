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
    // Stacked controls that take the whole width (lists, fields): the slot's
    // width comes from the row, not from the control.
    property bool fill: false
    // `shown`: the row's own condition; `query`: the settings search. A row
    // shows when both allow it.
    property bool shown: true
    property string query: ""
    // The section's title (set by SettingsSection): "notif" finds its rows too.
    property string context: ""
    readonly property bool matches: query === "" || (context + " " + label + " " + desc).toLowerCase().indexOf(query.toLowerCase()) >= 0
    // Narrow popups stack the control under the label, like the studio.
    readonly property bool narrow: width > 0 && width - slot.implicitWidth - 18 < 190

    visible: shown && matches
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
        columns: row.stacked || row.narrow ? 1 : 2
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
            Layout.alignment: row.stacked || row.narrow ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
            Layout.fillWidth: row.stacked
            implicitWidth: row.fill ? 0 : childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
