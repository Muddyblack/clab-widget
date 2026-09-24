import QtQuick
import QtQuick.Layouts

// Editable list of folders (settings "Lab folders"): each with a remove
// button, and a path field to add one. Plain QtQuick, like the other controls.
ColumnLayout {
    id: list

    property var theme
    property var folders: []
    signal changed(var folders)

    spacing: 4

    Repeater {
        model: list.folders

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Icon {
                name: "network"
                size: 13
                color: list.theme.sub
            }
            Text {
                Layout.fillWidth: true
                text: modelData
                color: list.theme.text
                font.pixelSize: list.theme.smallSize + 1
                elide: Text.ElideMiddle
            }
            IconButton {
                theme: list.theme
                icon: "x"
                tip: "Remove"
                size: 22
                onClicked: list.changed(list.folders.filter((f, i) => i !== index))
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: field.implicitHeight + 10
            radius: 5
            color: list.theme.card
            border.width: 1
            border.color: field.activeFocus ? list.theme.sub : list.theme.border

            TextInput {
                id: field
                anchors.fill: parent
                anchors.margins: 5
                color: list.theme.text
                font.pixelSize: list.theme.fontSize
                clip: true
                selectByMouse: true
                onAccepted: add.clicked()

                Text {
                    visible: field.text === "" && !field.activeFocus
                    text: "~/labs"
                    color: list.theme.sub
                    font: field.font
                }
            }
        }
        ActionButton {
            id: add
            theme: list.theme
            primary: true
            icon: "plus"
            text: "add"
            onClicked: {
                var f = field.text.trim();
                if (f === "" || list.folders.indexOf(f) >= 0)
                    return;
                list.changed(list.folders.concat([f]));
                field.text = "";
            }
        }
    }
}
