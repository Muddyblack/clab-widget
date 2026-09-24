import QtQuick
import "../../code/Labs.js" as Labs

// The pinned labs in a panel item / pill: "● fabric 6/7 · ● ospf 3/3".
// A pinned lab that isn't running stays, greyed, as "fabric —".
Row {
    id: segs

    property var theme
    property var segments: []
    property int fontSize: 12

    spacing: 6

    Repeater {
        model: segs.segments

        Row {
            spacing: 5
            anchors.verticalCenter: parent.verticalCenter

            Text {
                visible: index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "·"
                color: segs.theme.sub
                font.pixelSize: segs.fontSize
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: modelData.present ? Labs.lifecycleColor(segs.theme, modelData.lifecycle) : segs.theme.sub
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Labs.segmentText(modelData)
                color: modelData.present ? segs.theme.text : segs.theme.sub
                font.pixelSize: segs.fontSize
            }
        }
    }
}
