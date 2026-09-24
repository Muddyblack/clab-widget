import QtQuick
import QtQuick.Layouts

// Settings section, as in the studio: uppercase title with an icon, then one
// rounded card holding the rows (SettingRow draws the hairlines between them).
ColumnLayout {
    id: section

    property var theme
    property string title
    property string icon
    default property alias rows: body.data

    spacing: 8

    RowLayout {
        spacing: 7
        Icon {
            visible: section.icon !== ""
            name: section.icon
            size: 13
            color: section.theme.sub
        }
        Text {
            text: section.title.toUpperCase()
            color: section.theme.sub
            font.pixelSize: section.theme.smallSize
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 4
        radius: 14
        color: section.theme.card
        border.width: 1
        border.color: section.theme.border

        ColumnLayout {
            id: body
            x: 14
            y: 2
            width: parent.width - 28
            spacing: 0
        }
    }
}
