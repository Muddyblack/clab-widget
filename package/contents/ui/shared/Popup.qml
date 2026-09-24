import QtQuick
import QtQuick.Layouts
import "../../code/Labs.js" as Labs
import "../../code/Theme.js" as Theme

// The whole popup, shared by the Plasma widget, the Quickshell pill and the
// tray app. Hosts pass data + settings and run what `run(args)` asks for
// (clab-status arguments); everything else happens here.
//
//  ┌ header (never scrolls): icon · summary        search refresh settings ┐
//  │ [confirm bar]  [All | containerlab | netlab]  [search field] [notices] │
//  └ body: lab list (virtualized) | map | settings | host page             ┘
Item {
    id: popup

    property var theme
    property var snapshot: null
    property double lastOkAt: 0
    property bool failing: false
    // Host settings object (JsonAdapter / Plasmoid.configuration / QtObject)
    // with: show, tab, pinned, pollSeconds, notifyNodeDown, reminderHours[, corner]
    property var cfg
    property bool showPlacement: false
    // Quickshell only: the pill / desktop-card mode choice in settings.
    property bool showMode: false
    property real maxBodyHeight: 520
    // Optional host page (the tray app's remote hosts), opened from the header.
    property Component extraPage: null
    property string extraIcon: "server-cog"
    property string extraTitle: ""
    // Draw the glass card (Glassy System Monitor's GlassCard) behind everything:
    // on for the desktop card / Quickshell / tray app, off inside a Plasma
    // panel popup, which has its own background.
    property bool framed: false

    signal run(var args)
    signal refreshRequested

    property string page: "list" // list | map | settings | extra
    // The settings subtab (labs | alerts | look | placement | info).
    property alias settingsTab: settingsPage.currentTab
    property string mapLabId: ""
    property bool searchOpen: false
    property string query: ""
    property var expanded: ({})
    property var confirm: null // lab awaiting "stop" confirmation

    readonly property var pins: cfg && cfg.pinned ? cfg.pinned : []
    readonly property string filter: cfg && cfg.tab ? cfg.tab : "all"
    readonly property var counts: Labs.countsFor(snapshot, cfg ? cfg.show : "both", query)
    readonly property bool showChips: Labs.normShow(cfg ? cfg.show : "both") === "both" && counts.containerlab > 0 && counts.netlab > 0
    readonly property var model: Labs.rowsFor(snapshot, {
        show: cfg ? cfg.show : "both",
        filter: showChips ? filter : "all",
        query: query,
        expanded: expanded,
        pins: pins
    })
    readonly property var totals: Labs.totalsOf(Labs.visibleLabs(snapshot, Labs.normShow(cfg ? cfg.show : "both"), ""))
    readonly property var mapLab: {
        var labs = snapshot ? snapshot.labs : [];
        for (var i = 0; i < labs.length; i++)
            if (labs[i].id === mapLabId)
                return labs[i];
        return null;
    }
    readonly property real listHeight: {
        var h = 0;
        for (var i = 0; i < model.rows.length; i++)
            h += model.rows[i].type === "lab" ? 38 : 30;
        return h;
    }
    readonly property real bodyHeight: {
        if (page === "map")
            return maxBodyHeight;
        if (page === "settings")
            return Math.min(maxBodyHeight, settingsPage.implicitHeight + 8);
        if (page === "extra")
            return Math.min(maxBodyHeight, extraLoader.implicitHeight + 8);
        return Math.min(maxBodyHeight, Math.max(90, listHeight + 4));
    }

    implicitWidth: 500
    // Everything the column below lays out: its margins, 8 px between items,
    // and the chips/notices block only on the list page.
    implicitHeight: 2 * (framed ? 14 : 8) + header.height + 8 + (extras.visible ? extras.implicitHeight + 8 : 0) + bodyHeight

    onModelChanged: Labs.syncModel(rows, model.rows)

    function toggleExpanded(id, now) {
        var e = Object.assign({}, expanded);
        e[id] = !now;
        expanded = e;
    }

    function labAction(lab, name) {
        if (name === "toggle")
            toggleExpanded(lab.id, model.byKey["L" + lab.id].expanded);
        else if (name === "map") {
            mapLabId = lab.id;
            page = "map";
        } else if (name === "open")
            run(Labs.openArgs(lab));
        else if (name === "pin")
            cfg.pinned = Labs.togglePin(pins, lab.id);
        else if (name === "copy-path")
            clipboard.put(lab.topologyFile || lab.dir);
        else if (name === "copy-name")
            clipboard.put(lab.name);
        else if (name === "stop")
            confirm = lab;
    }

    function nodeAction(lab, node, name) {
        if (name === "copy-ip")
            clipboard.put(node.ipv4 || node.ipv6);
        else if (name === "copy-name")
            clipboard.put(node.name);
        else if (name === "copy-container")
            clipboard.put(node.container);
        else
            run(Labs.shellArgs(lab, node, name));
    }

    function labMenu(lab, x, y) {
        var acts = lab.actions || [];
        var open = model.byKey["L" + lab.id] ? model.byKey["L" + lab.id].expanded : false;
        var items = [
            {
                icon: open ? "chevron-down" : "chevron-right",
                text: open ? "Hide nodes" : "Show nodes",
                action: "toggle"
            },
            {
                icon: "network",
                text: "Map",
                action: "map"
            }
        ];
        if (acts.indexOf("open") >= 0)
            items.push({
                icon: "external-link",
                text: lab.via === "k8s" ? "Open in Kubus" : lab.via === "ssh" ? "Open in VS Code (Remote-SSH)" : lab.via === "wsl" ? "Open in VS Code (WSL)" : (lab.remote ? "Open in app" : "Open (app / VS Code)"),
                action: "open"
            });
        items.push({
            icon: Labs.isPinned(pins, lab.id) ? "pin-off" : "pin",
            text: Labs.isPinned(pins, lab.id) ? "Unpin from panel" : "Pin to panel",
            action: "pin"
        }, {
            separator: true
        }, {
            icon: "copy",
            text: "Copy name",
            action: "copy-name"
        });
        if (lab.topologyFile || lab.dir)
            items.push({
                icon: "copy",
                text: "Copy topology path",
                action: "copy-path"
            });
        if (acts.indexOf("stop") >= 0)
            items.push({
                separator: true
            }, {
                icon: "square",
                text: lab.managedBy === "netlab" ? "Stop (netlab down)…" : lab.via === "k8s" ? "Delete topology…" : "Destroy…",
                action: "stop",
                danger: true
            });
        menu.target = {
            lab: lab
        };
        menu.popup(x, y, items);
    }

    function nodeMenu(lab, node, x, y) {
        var a = node.access || [];
        var items = [];
        if (a.indexOf("connect") >= 0)
            items.push({
                icon: "terminal",
                text: "netlab connect",
                action: "connect"
            });
        else if (a.indexOf("ssh") >= 0)
            items.push({
                icon: "terminal",
                text: "SSH",
                action: "ssh"
            });
        if (a.indexOf("exec") >= 0)
            items.push({
                icon: "square-terminal",
                text: "Shell (docker exec)",
                action: "exec"
            });
        if (a.indexOf("logs") >= 0)
            items.push({
                icon: "scroll-text",
                text: "Logs",
                action: "logs"
            });
        if (items.length)
            items.push({
                separator: true
            });
        if (node.ipv4 || node.ipv6)
            items.push({
                icon: "copy",
                text: "Copy IP  " + (node.ipv4 || node.ipv6),
                action: "copy-ip"
            });
        items.push({
            icon: "copy",
            text: "Copy name",
            action: "copy-name"
        });
        if (node.container)
            items.push({
                icon: "copy",
                text: "Copy container name",
                action: "copy-container"
            });
        menu.target = {
            lab: lab,
            node: node
        };
        menu.popup(x, y, items);
    }

    // Clipboard without a platform import: a hidden TextEdit copies its selection.
    TextEdit {
        id: clipboard
        visible: false
        function put(text) {
            clipboard.text = text;
            clipboard.selectAll();
            clipboard.copy();
        }
    }

    ListModel {
        id: rows
    }

    Timer {
        id: refreshLater
        interval: 4000
        onTriggered: popup.refreshRequested()
    }

    Timer {
        running: popup.confirm !== null
        interval: 8000
        onTriggered: popup.confirm = null
    }

    GlassCard {
        anchors.fill: parent
        visible: popup.framed
        material: popup.cfg && popup.cfg.surfaceStyle ? popup.cfg.surfaceStyle : "tint"
        fill: popup.cfg && popup.cfg.bgColor ? popup.cfg.bgColor : Theme.fillFor(material)
        frosted: !popup.cfg || popup.cfg.frosted !== false
        radiusTL: 14
        radiusTR: 14
        radiusBR: 14
        radiusBL: 14
        shadow: "soft"
        color1: popup.theme.clab || "#4aa8ff"
        color2: popup.theme.netlab || "#aa66ff"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: popup.framed ? 14 : 8
        spacing: 8

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 6

            IconButton {
                visible: popup.page !== "list"
                theme: popup.theme
                icon: "arrow-left"
                tip: "Back"
                onClicked: popup.page = "list"
            }

            Image {
                visible: popup.page === "list"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                sourceSize: Qt.size(44, 44)
                source: Qt.resolvedUrl("../../" + Theme.appIcon(popup.cfg ? popup.cfg.appIcon : "clab", popup.cfg ? popup.cfg.show : "both", 64))
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                // Section header, as in Glassy System Monitor: bold title left,
                // the headline reading right in its state colour.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: popup.page === "map" && popup.mapLab ? popup.mapLab.name : popup.page === "settings" ? "Settings" : popup.page === "extra" ? popup.extraTitle : "LABS"
                        color: popup.theme.text
                        opacity: 0.85
                        font.pixelSize: popup.theme.fontSize
                        font.bold: true
                        font.letterSpacing: popup.page === "list" ? 1.2 : 0.3
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: popup.page === "list" && popup.totals.nodes > 0
                        text: popup.totals.running + "/" + popup.totals.nodes
                        color: popup.totals.attention > 0 ? popup.theme.warn : popup.theme.ok
                        font.pixelSize: popup.theme.fontSize + 1
                        font.bold: true
                    }
                }
                Text {
                    // Re-evaluated by the ticker so "12s ago" keeps counting.
                    property int tick: 0
                    Layout.fillWidth: true
                    visible: popup.page === "list" || popup.page === "map"
                    text: popup.page === "map" && popup.mapLab ? popup.mapLab.running + "/" + popup.mapLab.total + " up · " + (popup.mapLab.links || []).length + " links · drag to pan, wheel to zoom" : (popup.totals.labs > 0 ? popup.totals.labs + (popup.totals.labs === 1 ? " lab" : " labs") + (popup.totals.attention > 0 ? " · " + popup.totals.attention + " need attention" : "") + " · " : "") + (popup.failing ? "stale · " : "updated ") + Labs.ago(popup.lastOkAt) + (tick < 0 ? "" : "")
                    color: popup.failing ? popup.theme.warn : popup.theme.sub
                    font.pixelSize: popup.theme.smallSize
                    elide: Text.ElideRight
                    Timer {
                        interval: 5000
                        running: popup.visible
                        repeat: true
                        onTriggered: parent.tick++
                    }
                }
            }

            // Map controls
            IconButton {
                visible: popup.page === "map"
                theme: popup.theme
                icon: "zoom-out"
                tip: "Zoom out"
                onClicked: mapView.zoomBy(1 / 1.3)
            }
            IconButton {
                visible: popup.page === "map"
                theme: popup.theme
                icon: "maximize"
                tip: "Fit"
                onClicked: mapView.fit()
            }
            IconButton {
                visible: popup.page === "map"
                theme: popup.theme
                icon: "zoom-in"
                tip: "Zoom in"
                onClicked: mapView.zoomBy(1.3)
            }

            // List controls
            IconButton {
                visible: popup.page === "list"
                theme: popup.theme
                icon: "search"
                tip: "Search labs and nodes"
                active: popup.searchOpen
                onClicked: {
                    popup.searchOpen = !popup.searchOpen;
                    if (!popup.searchOpen)
                        popup.query = "";
                    else
                        searchInput.forceActiveFocus();
                }
            }
            IconButton {
                visible: popup.page !== "settings" && popup.page !== "extra"
                theme: popup.theme
                icon: "refresh-cw"
                tip: "Refresh"
                onClicked: popup.refreshRequested()
            }
            IconButton {
                visible: popup.extraPage !== null && popup.page === "list"
                theme: popup.theme
                icon: popup.extraIcon
                tip: popup.extraTitle
                onClicked: popup.page = "extra"
            }
            IconButton {
                visible: popup.page === "list"
                theme: popup.theme
                icon: "settings"
                tip: "Settings"
                onClicked: popup.page = "settings"
            }
        }

        ColumnLayout {
            id: extras
            Layout.fillWidth: true
            spacing: 6
            visible: popup.page === "list"

            // Stop confirmation
            Rectangle {
                visible: popup.confirm !== null
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 7
                color: Qt.rgba(0.97, 0.44, 0.44, 0.14)
                border.width: 1
                border.color: popup.theme.bad

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    Text {
                        Layout.fillWidth: true
                        text: popup.confirm ? (popup.confirm.managedBy === "netlab" ? "netlab down " : popup.confirm.via === "k8s" ? "Delete topology " : "Destroy ") + popup.confirm.name + (popup.confirm.via === "k8s" ? " (" + popup.confirm.namespace + ")?" : "?") : ""
                        color: popup.theme.text
                        font.pixelSize: popup.theme.fontSize
                        elide: Text.ElideRight
                    }
                    ActionButton {
                        theme: popup.theme
                        text: "cancel"
                        onClicked: popup.confirm = null
                    }
                    ActionButton {
                        theme: popup.theme
                        text: "stop lab"
                        baseColor: Qt.rgba(0.97, 0.44, 0.44, 0.3)
                        onClicked: {
                            // The backend re-checks the fingerprint against a fresh snapshot.
                            popup.run(["stop", popup.confirm.id, popup.confirm.fingerprint]);
                            popup.confirm = null;
                            refreshLater.restart();
                        }
                    }
                }
            }

            // All | containerlab | netlab (only when both kinds are present)
            Row {
                id: chips
                visible: popup.showChips
                spacing: 6

                Repeater {
                    model: ["all", "containerlab", "netlab"]

                    Rectangle {
                        readonly property bool on: popup.filter === modelData
                        implicitWidth: chipRow.implicitWidth + 16
                        implicitHeight: 26
                        radius: 13
                        color: on ? popup.theme.badge : (chipMouse.containsMouse ? popup.theme.hover : "transparent")
                        border.width: 1
                        border.color: on ? popup.theme.sub : popup.theme.border

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                visible: modelData !== "all"
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.accent(popup.theme, modelData)
                            }
                            Image {
                                visible: modelData !== "all"
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                sourceSize: Qt.size(28, 28)
                                source: modelData !== "all" ? Qt.resolvedUrl("../../icons/" + modelData + ".svg") : ""
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData === "all" ? "All" : modelData) + "  " + popup.counts[modelData]
                                color: parent.parent.on ? popup.theme.text : popup.theme.sub
                                font.pixelSize: popup.theme.smallSize + 1
                            }
                        }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.cfg.tab = modelData
                        }
                    }
                }
            }

            // Search
            Rectangle {
                visible: popup.searchOpen
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 7
                color: popup.theme.card
                border.width: 1
                border.color: searchInput.activeFocus ? popup.theme.sub : popup.theme.border

                Icon {
                    x: 9
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
                    color: popup.theme.sub
                }
                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 30
                    anchors.rightMargin: 30
                    verticalAlignment: TextInput.AlignVCenter
                    color: popup.theme.text
                    font.pixelSize: popup.theme.fontSize
                    clip: true
                    onTextChanged: popup.query = text
                    // A query set from outside (IPC, renders) shows up here too.
                    Connections {
                        target: popup
                        function onQueryChanged() {
                            if (searchInput.text !== popup.query)
                                searchInput.text = popup.query;
                        }
                    }
                    Keys.onEscapePressed: {
                        text = "";
                        popup.searchOpen = false;
                    }
                    Text {
                        visible: parent.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "lab, node, kind or IP"
                        color: popup.theme.sub
                        font: parent.font
                    }
                }
                IconButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text !== ""
                    theme: popup.theme
                    icon: "x"
                    size: 22
                    onClicked: searchInput.text = ""
                }
            }

            Repeater {
                model: Labs.sourceNotices(popup.snapshot)
                Text {
                    Layout.fillWidth: true
                    text: modelData
                    color: popup.theme.warn
                    font.pixelSize: popup.theme.smallSize
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Body ────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: popup.bodyHeight
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                visible: popup.page === "list"
                clip: true
                model: rows
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                cacheBuffer: 400

                delegate: Loader {
                    id: rowLoader
                    required property string key
                    required property string type
                    readonly property var entry: popup.model.byKey[key]
                    width: list.width
                    height: type === "lab" ? 38 : 30
                    sourceComponent: !entry ? null : type === "lab" ? labRowC : nodeRowC

                    Component {
                        id: labRowC
                        Item {
                            LabRow {
                                anchors.fill: parent
                                anchors.topMargin: 2
                                theme: popup.theme
                                lab: rowLoader.entry.lab
                                expanded: rowLoader.entry.expanded
                                pinned: Labs.isPinned(popup.pins, rowLoader.entry.lab.id)
                                menuAnchor: popup
                                onToggled: popup.toggleExpanded(lab.id, expanded)
                                onAction: name => popup.labAction(lab, name)
                                onMenuRequested: (x, y) => popup.labMenu(lab, x, y)
                            }
                        }
                    }
                    Component {
                        id: nodeRowC
                        NodeItem {
                            theme: popup.theme
                            node: rowLoader.entry.node
                            menuAnchor: popup
                            onAction: name => popup.nodeAction(rowLoader.entry.lab, node, name)
                            onCopyRequested: t => clipboard.put(t)
                            onMenuRequested: (x, y) => popup.nodeMenu(rowLoader.entry.lab, node, x, y)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 20
                visible: popup.page === "list" && popup.snapshot !== null && rows.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: popup.query !== "" ? "Nothing matches “" + popup.query + "”." : "Nothing deployed.\nStart one with  containerlab deploy  or  netlab up."
                color: popup.theme.sub
                font.pixelSize: popup.theme.fontSize
            }

            MapView {
                id: mapView
                anchors.fill: parent
                visible: popup.page === "map" && popup.mapLab !== null
                theme: popup.theme
                lab: popup.mapLab || ({
                        nodes: [],
                        links: []
                    })
                menuAnchor: popup
                onNodeMenu: (node, x, y) => popup.nodeMenu(popup.mapLab, node, x, y)
            }

            Flickable {
                anchors.fill: parent
                visible: popup.page === "settings"
                clip: true
                contentHeight: settingsPage.implicitHeight
                SettingsPage {
                    id: settingsPage
                    width: parent.width
                    theme: popup.theme
                    cfg: popup.cfg
                    showPlacement: popup.showPlacement
                    showMode: popup.showMode
                    showHeader: false
                }
            }

            Flickable {
                anchors.fill: parent
                visible: popup.page === "extra"
                clip: true
                contentHeight: extraLoader.implicitHeight
                Loader {
                    id: extraLoader
                    width: parent.width
                    active: popup.extraPage !== null
                    sourceComponent: popup.extraPage
                }
            }
        }
    }

    ContextMenu {
        id: menu
        property var target: null
        theme: popup.theme
        onTriggered: action => {
            if (target.node)
                popup.nodeAction(target.lab, target.node, action);
            else
                popup.labAction(target.lab, action);
        }
    }
}
