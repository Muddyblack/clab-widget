import QtQuick
import QtQuick.Layouts
import "../package/contents/ui/shared"

// Remote hosts for the desktop app: list, remove, add. The password goes
// straight to the server's /login; only the returned token is stored.
ColumnLayout {
    id: page

    property var theme
    property var connections: []
    property string status: ""
    property bool busy: false
    // Inside the shared Popup its header already has the title and a back arrow.
    property bool showHeader: true
    signal addRequested(var conn, string password)
    signal removeRequested(string name)
    signal done

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        visible: page.showHeader

        Text {
            Layout.fillWidth: true
            text: "Remote hosts"
            color: page.theme.text
            font.pixelSize: page.theme.fontSize + 2
            font.bold: true
        }

        ActionButton {
            theme: page.theme
            text: "done"
            onClicked: page.done()
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.connections.length === 0
        text: "No remote hosts yet. Add a clab-api-server (containerlab tools api-server start) or a netlab-ui server."
        color: page.theme.sub
        font.pixelSize: page.theme.smallSize
        wrapMode: Text.Wrap
    }

    Repeater {
        model: page.connections

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Image {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                sourceSize: Qt.size(32, 32)
                source: Qt.resolvedUrl("../package/contents/icons/" + (modelData.type === "netlab-ui" ? "netlab" : "containerlab") + ".svg")
            }

            Text {
                Layout.fillWidth: true
                text: modelData.name + "  ·  " + modelData.url + (modelData.username ? "  ·  " + modelData.username : "")
                color: page.theme.text
                font.pixelSize: page.theme.smallSize + 1
                elide: Text.ElideRight
            }

            ActionButton {
                theme: page.theme
                text: "remove"
                onClicked: page.removeRequested(modelData.name)
            }
        }
    }

    Text {
        text: "ADD"
        color: page.theme.sub
        font.pixelSize: page.theme.smallSize
        font.letterSpacing: 1
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [
                {
                    id: "clab-api",
                    label: "clab-api-server"
                },
                {
                    id: "netlab-ui",
                    label: "netlab-ui"
                }
            ]

            ActionButton {
                theme: page.theme
                text: (form.type === modelData.id ? "● " : "") + modelData.label
                onClicked: form.type = modelData.id
            }
        }
    }

    GridLayout {
        id: form
        property string type: "clab-api"
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 6

        component Field: Rectangle {
            property alias text: input.text
            property alias echoMode: input.echoMode
            property string placeholder: ""
            Layout.fillWidth: true
            implicitHeight: input.implicitHeight + 10
            radius: 5
            color: page.theme.card
            border.width: 1
            border.color: input.activeFocus ? page.theme.sub : page.theme.border

            TextInput {
                id: input
                anchors.fill: parent
                anchors.margins: 5
                color: page.theme.text
                font.pixelSize: page.theme.fontSize
                clip: true
                selectByMouse: true

                Text {
                    visible: input.text === "" && !input.activeFocus
                    text: parent.parent.placeholder
                    color: page.theme.sub
                    font: input.font
                }
            }
        }

        Text {
            text: "name"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: nameField
            placeholder: "lab-server"
        }

        Text {
            text: "url"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: urlField
            placeholder: form.type === "netlab-ui" ? "http://lab-server:8000" : "https://lab-server:8090"
        }

        Text {
            visible: form.type === "clab-api"
            text: "user"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: userField
            visible: form.type === "clab-api"
            placeholder: "your Linux user on the lab host"
        }

        Text {
            visible: form.type === "clab-api"
            text: "password"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: passField
            visible: form.type === "clab-api"
            echoMode: TextInput.Password
            placeholder: "sent once, never stored"
        }

        Text {
            text: "group"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: groupField
            placeholder: "optional: same value for both servers of one machine"
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Toggle {
            id: insecure
            Layout.fillWidth: true
            visible: form.type === "clab-api"
            theme: page.theme
            text: "Accept self-signed certificate"
            onToggled: c => insecure.checked = c
        }

        ActionButton {
            theme: page.theme
            text: page.busy ? "…" : (form.type === "clab-api" ? "log in & add" : "add")
            onClicked: {
                if (page.busy || nameField.text === "" || urlField.text === "")
                    return;
                var conn = {
                    name: nameField.text.trim(),
                    type: form.type,
                    url: urlField.text.trim()
                };
                if (groupField.text.trim() !== "")
                    conn.group = groupField.text.trim();
                if (form.type === "clab-api") {
                    conn.username = userField.text.trim();
                    conn.insecure = insecure.checked;
                }
                page.addRequested(conn, passField.text);
                passField.text = "";
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.status !== ""
        text: page.status
        color: page.status.indexOf("failed") >= 0 ? page.theme.bad : page.theme.ok
        font.pixelSize: page.theme.smallSize
        wrapMode: Text.Wrap
    }
}
