import QtQuick

// Segmented choice, as in the Glassy System Monitor studio: a sunk track, the
// chosen segment raised. options: [{id, label}]; wraps when it runs out of room.
Rectangle {
    id: seg

    property var theme
    property var options: []
    property string value
    signal activated(string value)

    // One-line width = the segments side by side (a Flow's own implicitWidth
    // depends on its width, so it can't be used here); wraps only when the
    // parent is narrower.
    implicitWidth: {
        var w = 8;
        for (var i = 0; i < segments.count; i++)
            w += (segments.itemAt(i) ? segments.itemAt(i).width : 0) + (i > 0 ? row.spacing : 0);
        return w;
    }
    implicitHeight: row.implicitHeight + 8
    width: parent && parent.width > 0 ? Math.min(implicitWidth, parent.width) : implicitWidth
    height: row.height + 8
    radius: 9
    color: Qt.rgba(0, 0, 0, 0.22)
    border.width: 1
    border.color: theme.border

    Flow {
        id: row
        x: 4
        y: 4
        width: seg.width - 8
        spacing: 2

        Repeater {
            id: segments
            model: seg.options

            Rectangle {
                readonly property bool on: modelData.id === seg.value
                width: label.implicitWidth + 20
                height: label.implicitHeight + 10
                radius: 6
                color: on ? Qt.rgba(1, 1, 1, 0.14) : (area.containsMouse ? seg.theme.hover : "transparent")

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.on ? seg.theme.text : seg.theme.sub
                    font.pixelSize: seg.theme.smallSize
                    font.weight: parent.on ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.activated(modelData.id)
                }
            }
        }
    }
}
