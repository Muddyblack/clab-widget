import QtQuick
import QtQuick.Layouts

// Right-click menu, drawn inside the popup (no platform menu, so it looks and
// works the same under Plasma, Quickshell and the tray app).
//   menu.popup(x, y, [{icon, text, action, danger?, separator?}])
// Emits triggered(action); clicking outside or Esc closes it.
Item {
    id: menu

    property var theme
    property var entries: []
    signal triggered(string action)

    anchors.fill: parent
    visible: false
    z: 1000

    function popup(x, y, items) {
        menu.entries = items;
        menu.visible = true;
        panel.x = Math.max(4, Math.min(x, menu.width - panel.width - 4));
        panel.y = Math.max(4, Math.min(y, menu.height - panel.height - 4));
        menu.forceActiveFocus();
    }

    function close() {
        menu.visible = false;
    }

    Keys.onEscapePressed: menu.close()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
    }

    Rectangle {
        id: panel
        width: Math.max(170, col.implicitWidth + 12)
        height: col.implicitHeight + 10
        radius: 8
        color: menu.theme.cardSolid
        border.width: 1
        border.color: menu.theme.border

        ColumnLayout {
            id: col
            x: 5
            y: 5
            width: parent.width - 10
            spacing: 1

            Repeater {
                model: menu.entries

                Item {
                    Layout.fillWidth: true
                    implicitHeight: modelData.separator ? 7 : 28
                    implicitWidth: row.implicitWidth + 16

                    Rectangle {
                        visible: !!modelData.separator
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: 1
                        color: menu.theme.border
                    }

                    Rectangle {
                        visible: !modelData.separator
                        anchors.fill: parent
                        radius: 5
                        color: itemMouse.containsMouse ? menu.theme.hover : "transparent"

                        RowLayout {
                            id: row
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            spacing: 9

                            Icon {
                                name: modelData.icon || ""
                                size: 15
                                color: modelData.danger ? menu.theme.bad : menu.theme.sub
                            }

                            Text {
                                text: modelData.text || ""
                                color: modelData.danger ? menu.theme.bad : menu.theme.text
                                font.pixelSize: menu.theme.fontSize
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                menu.close();
                                menu.triggered(modelData.action);
                            }
                        }
                    }
                }
            }
        }
    }
}
