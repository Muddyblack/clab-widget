import QtQuick
import QtQuick.Layouts

// Remote hosts (all frontends): list, remove, add. The password goes straight
// to the server's /login; only the returned token is stored. Without a
// password field here (passwordLogin false: Plasma, Quickshell) a
// clab-api-server login asks in a terminal window instead.
ColumnLayout {
    id: page

    property var theme
    property var connections: []
    property string status: ""
    property bool busy: false
    // Inside the shared Popup its header already has the title and a back arrow.
    property bool showHeader: true
    property bool passwordLogin: true
    // containerlab's own Windows setup is WSL2: offer it there.
    property bool offerWsl: Qt.platform.os === "windows"
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
        text: "No remote hosts yet. containerlab and netlab run on Linux: add the lab machine over ssh (key login, needs python3 there), or its clab-api-server (containerlab tools api-server start) / netlab-ui server. Add as many machines as you like."
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
                visible: modelData.type !== "ssh" && modelData.type !== "wsl" && modelData.type !== "k8s"
                sourceSize: Qt.size(32, 32)
                source: visible ? Qt.resolvedUrl("../../icons/" + (modelData.type === "netlab-ui" ? "netlab" : "containerlab") + ".svg") : ""
            }
            Icon {
                visible: modelData.type === "ssh" || modelData.type === "wsl" || modelData.type === "k8s"
                name: modelData.type === "k8s" ? "ship-wheel" : "terminal"
                size: 16
                color: page.theme.text
            }

            Text {
                Layout.fillWidth: true
                text: modelData.type === "k8s" ? modelData.name + "  ·  kubernetes " + (modelData.context || "(current context)") + (modelData.namespace ? " / " + modelData.namespace : "") : modelData.type === "wsl" ? modelData.name + "  ·  WSL " + (modelData.distro || "(default distro)") : modelData.type === "ssh" ? modelData.name + "  ·  ssh " + modelData.host + (modelData.port ? ":" + modelData.port : "") : modelData.name + "  ·  " + modelData.url + (modelData.username ? "  ·  " + modelData.username : "")
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
            model: (page.offerWsl ? [
                    {
                        id: "wsl",
                        label: "WSL"
                    }
                ] : []).concat([
                {
                    id: "ssh",
                    label: "ssh"
                },
                {
                    id: "k8s",
                    label: "Kubernetes (clabernetes)"
                },
                {
                    id: "clab-api",
                    label: "clab-api-server"
                },
                {
                    id: "netlab-ui",
                    label: "netlab-ui"
                }
            ])

            ActionButton {
                theme: page.theme
                text: (form.type === modelData.id ? "● " : "") + modelData.label
                onClicked: form.type = modelData.id
            }
        }
    }

    GridLayout {
        id: form
        property string type: page.offerWsl ? "wsl" : "ssh"
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
            text: form.type === "wsl" ? "distro" : form.type === "ssh" ? "host" : form.type === "k8s" ? "context" : "url"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: urlField
            placeholder: form.type === "k8s" ? "optional: k3s-lab (else kubectl's current context)" : form.type === "wsl" ? "optional: Ubuntu (else the default distro)" : form.type === "ssh" ? "me@lab-server  or an ~/.ssh/config alias" : (form.type === "netlab-ui" ? "http://lab-server:8000" : "https://lab-server:8090")
        }

        Text {
            visible: form.type === "k8s"
            text: "namespace"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: namespaceField
            visible: form.type === "k8s"
            placeholder: "optional: c9s-srl (else all namespaces)"
        }

        Text {
            visible: form.type === "k8s"
            text: "kubeconfig"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: kubeconfigField
            visible: form.type === "k8s"
            placeholder: "optional: /etc/rancher/k3s/k3s.yaml (else ~/.kube/config)"
        }

        Text {
            visible: form.type === "ssh"
            text: "port"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: portField
            visible: form.type === "ssh"
            placeholder: "22"
        }

        Text {
            visible: form.type === "ssh"
            text: "key file"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: identityField
            visible: form.type === "ssh"
            placeholder: "optional: ~/.ssh/id_ed25519 (else ssh-agent / ssh config)"
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
            visible: form.type === "clab-api" && page.passwordLogin
            text: "password"
            color: page.theme.sub
            font.pixelSize: page.theme.smallSize
        }
        Field {
            id: passField
            visible: form.type === "clab-api" && page.passwordLogin
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
            text: page.busy ? "…" : (form.type === "clab-api" ? (page.passwordLogin ? "log in & add" : "log in (terminal)") : (form.type === "ssh" || form.type === "wsl" || form.type === "k8s" ? "test & add" : "add"))
            onClicked: {
                if (page.busy || nameField.text === "" || (urlField.text === "" && form.type !== "wsl" && form.type !== "k8s"))
                    return;
                var conn = {
                    name: nameField.text.trim(),
                    type: form.type
                };
                if (form.type === "k8s") {
                    if (urlField.text.trim() !== "")
                        conn.context = urlField.text.trim();
                    if (namespaceField.text.trim() !== "")
                        conn.namespace = namespaceField.text.trim();
                    if (kubeconfigField.text.trim() !== "")
                        conn.kubeconfig = kubeconfigField.text.trim();
                } else if (form.type === "wsl") {
                    if (urlField.text.trim() !== "")
                        conn.distro = urlField.text.trim();
                } else if (form.type === "ssh") {
                    conn.host = urlField.text.trim();
                    var port = parseInt(portField.text.trim(), 10);
                    if (port > 0 && port !== 22)
                        conn.port = port;
                    if (identityField.text.trim() !== "")
                        conn.identity = identityField.text.trim();
                } else {
                    conn.url = urlField.text.trim();
                }
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
        visible: form.type === "k8s"
        text: "containerlab topologies on Kubernetes (k8s, k3s, kind) through clabernetes, read with kubectl: nodes, links, map, kubectl exec / logs, delete. Open goes to Kubus when it's installed."
        color: page.theme.sub
        font.pixelSize: page.theme.smallSize
        wrapMode: Text.Wrap
    }

    Text {
        Layout.fillWidth: true
        visible: form.type === "wsl"
        text: "containerlab inside WSL2 on this PC (containerlab's Windows setup): the widget runs its status script in the distro (python3 there), with shells, stop and VS Code WSL."
        color: page.theme.sub
        font.pixelSize: page.theme.smallSize
        wrapMode: Text.Wrap
    }

    Text {
        Layout.fillWidth: true
        visible: form.type === "ssh"
        text: "Runs the widget's status script there (python3, nothing to install): both tools, map, memory, node shells, stop, VS Code Remote-SSH. Needs key login (ssh-copy-id)."
        color: page.theme.sub
        font.pixelSize: page.theme.smallSize
        wrapMode: Text.Wrap
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
