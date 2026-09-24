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
    // with: show, tab, pinned, pollSeconds, notifyNodeDown, reminderHours,
    // mapWindow[, corner]
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
    readonly property alias mapItem: mapView
    property alias settingsQuery: settingsPage.query
    property string mapLabId: ""
    property bool searchOpen: false
    property string query: ""
    property var expanded: ({})
    property var confirm: null // lab awaiting a confirmation (stop / clean / force / redeploy)
    property string confirmMode: "stop"
    // Throughput per link: byte counters of the last two snapshots (--details).
    property var prevSnapshot: null
    property var rates: ({})
    onSnapshotChanged: {
        // The same observation again (a re-parse) keeps the last rates.
        if (prevSnapshot && snapshot && prevSnapshot.observedAt === snapshot.observedAt)
            return;
        rates = Labs.linkRates(prevSnapshot, snapshot);
        prevSnapshot = snapshot;
    }

    readonly property var pins: cfg && cfg.pinned ? cfg.pinned : []
    readonly property string filter: cfg && cfg.tab ? cfg.tab : "all"
    readonly property var counts: Labs.countsFor(snapshot, cfg ? cfg.show : "both", query)
    readonly property bool showChips: Labs.normShow(cfg ? cfg.show : "both") === "both" && counts.containerlab > 0 && counts.netlab > 0
    readonly property var model: Labs.rowsFor(snapshot, {
        show: cfg ? cfg.show : "both",
        filter: showChips ? filter : "all",
        query: query,
        expanded: expanded,
        pins: pins,
        onlyMine: cfg ? !!cfg.onlyMine : false
    })
    readonly property var totals: Labs.totalsOf(Labs.visibleLabs(snapshot, Labs.normShow(cfg ? cfg.show : "both"), "").filter(l => !(cfg && cfg.onlyMine && l.mine === false)))
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
            h += popup.rowHeight(model.rows[i].type);
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

    function rowHeight(type) {
        return type === "lab" ? 38 : type === "undeployed" ? 34 : 30;
    }

    function toggleExpanded(id, now) {
        var e = Object.assign({}, expanded);
        e[id] = !now;
        expanded = e;
    }

    function labAction(lab, name) {
        if (name === "toggle")
            toggleExpanded(lab.id, model.byKey["L" + lab.id].expanded);
        else if (name === "map")
            openMap(lab.id, cfg && cfg.mapWindow);
        else if (name === "open")
            run(Labs.openArgs(lab));
        else if (name === "pin")
            cfg.pinned = Labs.togglePin(pins, lab.id);
        else if (name === "copy-path")
            clipboard.put(lab.topologyFile || lab.dir);
        else if (name === "copy-name")
            clipboard.put(lab.name);
        else if (name === "stop" || name === "clean" || name === "force" || name === "redeploy") {
            confirmMode = name;
            confirm = lab;
        } else if (name === "save")
            run(Labs.labOpArgs(lab, "save"));
        else if (name === "deploy")
            run(Labs.deployArgs(lab));
    }

    // One entry point for every context menu (the popup's and map windows').
    function menuAction(target, action) {
        if (target.link)
            linkAction(target.lab, target.link, action);
        else if (target.node)
            nodeAction(target.lab, target.node, action);
        else
            labAction(target.lab, action);
    }

    function confirmText(lab, mode) {
        if (!lab)
            return "";
        var k8s = lab.via === "k8s", nl = lab.managedBy === "netlab";
        var what = {
            "stop": nl ? "netlab down " : k8s ? "Delete topology " : "Destroy ",
            "clean": nl ? "netlab down --cleanup (delete generated files) " : "Destroy and delete lab files of ",
            "force": "Force clean up (broken lab) ",
            "redeploy": nl ? "netlab restart " : "Redeploy (fresh nodes, configs reset) "
        }[mode] || "";
        return what + lab.name + (k8s ? " (" + lab.namespace + ")?" : "?");
    }

    function runConfirmed() {
        // The backend re-checks the fingerprint against a fresh snapshot.
        if (confirmMode === "redeploy")
            run(Labs.labOpArgs(confirm, "redeploy"));
        else
            run(Labs.stopArgs(confirm, confirmMode));
        confirm = null;
        refreshLater.restart();
    }

    // The map as a popup page, or in its own window (one per lab, raised if open).
    property var mapWindows: ({})
    function openMap(labId, inWindow) {
        if (!inWindow) {
            mapLabId = labId;
            page = "map";
            return;
        }
        var w = mapWindows[labId];
        if (!w) {
            w = mapWindowComponent.createObject(popup, {
                popup: popup,
                labId: labId
            });
            mapWindows[labId] = w;
            w.Component.destruction.connect(() => delete popup.mapWindows[labId]);
        }
        w.show();
        w.raise();
        w.requestActivate();
    }

    Component {
        id: mapWindowComponent
        MapWindow {}
    }

    function nodeAction(lab, node, name) {
        var copies = {
            "copy-ip": node.ipv4 || node.ipv6,
            "copy-name": node.name,
            "copy-container": node.container,
            "copy-mac": node.mac,
            "copy-image": node.image,
            "copy-kind": node.kind,
            "copy-id": node.containerId
        };
        if (copies[name] !== undefined)
            clipboard.put(copies[name] || "");
        else if (name === "start" || name === "stop" || name === "restart") {
            run(Labs.nodeOpArgs(lab, node, name));
            refreshLater.restart();
        } else if (name.indexOf("web:") === 0)
            Qt.openUrlExternally(Labs.webUrl(node, parseInt(name.slice(4), 10)));
        else
            run(Labs.shellArgs(lab, node, name));
    }

    function linkAction(lab, link, name) {
        if (name === "copy-link")
            clipboard.put(Labs.linkText(link, null).split(" · ")[0]);
        else if (name === "capture-a" || name === "capture-z") {
            var a = name === "capture-a";
            var node = (lab.nodes || []).filter(n => n.name === (a ? (link.endA || link.a) : (link.endZ || link.z)))[0];
            if (node)
                run(Labs.captureArgs(lab, node, a ? link.aIf : link.zIf));
        }
    }

    // Right-click on a map link: copy its ends, capture either end.
    function linkMenu(lab, link, x, y, into) {
        var items = [
            {
                icon: "copy",
                text: "Copy endpoints",
                action: "copy-link"
            }
        ];
        var byName = {};
        (lab.nodes || []).forEach(n => byName[n.name] = n);
        var ws = snapshot && snapshot.tools && snapshot.tools.wireshark;
        [["a", link.endA || link.a, link.aIf], ["z", link.endZ || link.z, link.zIf]].forEach(e => {
            var n = byName[e[1]];
            if (ws && n && n.capture && n.running && e[2])
                items.push({
                    icon: "activity",
                    text: "Capture " + e[1] + ":" + e[2] + " in Wireshark",
                    action: "capture-" + e[0]
                });
        });
        var m = into || menu;
        m.target = {
            lab: lab,
            link: link
        };
        m.popup(x, y, items);
    }

    function labMenu(lab, x, y) {
        var acts = lab.actions || [];
        if (acts.indexOf("deploy") >= 0) {
            // An undeployed topology from the lab folders.
            menu.target = {
                lab: lab
            };
            menu.popup(x, y, [
                {
                    icon: "play",
                    text: lab.managedBy === "netlab" ? "Deploy (netlab up)" : "Deploy",
                    action: "deploy"
                },
                {
                    icon: "external-link",
                    text: "Open (app / VS Code)",
                    action: "open"
                },
                {
                    separator: true
                },
                {
                    icon: "copy",
                    text: "Copy topology path",
                    action: "copy-path"
                }
            ]);
            return;
        }
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
        if (acts.indexOf("save") >= 0)
            items.push({
                icon: "save",
                text: lab.managedBy === "netlab" ? "Save configs (netlab collect)" : "Save configs",
                action: "save"
            });
        if (acts.indexOf("redeploy") >= 0)
            items.push({
                icon: "repeat",
                text: lab.managedBy === "netlab" ? "Restart lab (netlab restart)…" : "Redeploy…",
                action: "redeploy"
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
        if (acts.indexOf("clean") >= 0)
            items.push({
                icon: "square",
                text: lab.managedBy === "netlab" ? "Stop and delete files…" : "Destroy and delete files…",
                action: "clean",
                danger: true
            });
        if (acts.indexOf("force") >= 0)
            items.push({
                icon: "square",
                text: "Force clean up (broken)…",
                action: "force",
                danger: true
            });
        menu.target = {
            lab: lab
        };
        menu.popup(x, y, items);
    }

    // `into`: another ContextMenu (the map window's); default the popup's own.
    function nodeMenu(lab, node, x, y, into) {
        var a = node.access || [];
        var ops = node.ops || [];
        var items = [];
        // The fix-it first: a down node offers Start (and why: its logs).
        if (ops.indexOf("start") >= 0)
            items.push({
                icon: "play",
                text: "Start " + node.name,
                action: "start"
            });
        if (ops.indexOf("restart") >= 0)
            items.push({
                icon: "rotate-ccw",
                text: "Restart",
                action: "restart"
            });
        if (ops.indexOf("stop") >= 0)
            items.push({
                icon: "square",
                text: "Stop",
                action: "stop"
            });
        if (items.length)
            items.push({
                separator: true
            });
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
        if (a.indexOf("telnet") >= 0)
            items.push({
                icon: "terminal",
                text: "Console (telnet)",
                action: "telnet"
            });
        if (a.indexOf("logs") >= 0)
            items.push({
                icon: "scroll-text",
                text: "Logs",
                action: "logs"
            });
        // Web UIs only for labs on this machine: a remote host's mgmt network isn't reachable from here.
        if (!lab.remote && node.running && (node.ipv4 || node.ipv6))
            (node.webPorts || []).forEach(p => items.push({
                    icon: "globe",
                    text: "Open " + Labs.webUrl(node, p),
                    action: "web:" + p
                }));
        if (items.length && !items[items.length - 1].separator)
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
        if (node.containerId)
            items.push({
                icon: "copy",
                text: "Copy container ID",
                action: "copy-id"
            });
        if (node.mac)
            items.push({
                icon: "copy",
                text: "Copy MAC  " + node.mac,
                action: "copy-mac"
            });
        if (node.image)
            items.push({
                icon: "copy",
                text: "Copy image",
                action: "copy-image"
            });
        if (node.kind)
            items.push({
                icon: "copy",
                text: "Copy kind  " + node.kind,
                action: "copy-kind"
            });
        var m = into || menu;
        m.target = {
            lab: lab,
            node: node
        };
        m.popup(x, y, items);
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
            IconButton {
                visible: popup.page === "map"
                theme: popup.theme
                icon: "external-link"
                tip: "Open in a window"
                onClicked: {
                    popup.openMap(popup.mapLabId, true);
                    popup.page = "list";
                }
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
                        text: popup.confirmText(popup.confirm, popup.confirmMode)
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
                        text: popup.confirmMode === "redeploy" ? "redeploy" : "stop lab"
                        baseColor: Qt.rgba(0.97, 0.44, 0.44, 0.3)
                        onClicked: popup.runConfirmed()
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
                    height: popup.rowHeight(type)
                    sourceComponent: !entry ? null : type === "lab" ? labRowC : type === "node" ? nodeRowC : type === "header" ? headerRowC : undeployedRowC

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
                    // "Not deployed (3)": the lab-folder topologies, collapsible.
                    Component {
                        id: headerRowC
                        Item {
                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 4
                                radius: 6
                                color: headerMouse.containsMouse ? popup.theme.hover : "transparent"
                            }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 2
                                x: 6
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: rowLoader.entry.expanded ? "chevron-down" : "chevron-right"
                                    size: 13
                                    color: popup.theme.sub
                                }
                                Text {
                                    text: rowLoader.entry.title.toUpperCase() + "  " + rowLoader.entry.count
                                    color: popup.theme.sub
                                    font.pixelSize: popup.theme.smallSize
                                    font.letterSpacing: 1
                                    font.bold: true
                                }
                            }
                            MouseArea {
                                id: headerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popup.toggleExpanded("undeployed", rowLoader.entry.expanded)
                            }
                        }
                    }
                    Component {
                        id: undeployedRowC
                        UndeployedRow {
                            theme: popup.theme
                            lab: rowLoader.entry.lab
                            menuAnchor: popup
                            onDeploy: popup.labAction(lab, "deploy")
                            onMenuRequested: (x, y) => popup.labMenu(lab, x, y)
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
                rates: popup.mapLab ? (popup.rates[popup.mapLab.id] || ({})) : ({})
                onNodeMenu: (node, x, y) => popup.nodeMenu(popup.mapLab, node, x, y)
                onLinkMenu: (link, x, y) => popup.linkMenu(popup.mapLab, link, x, y)
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
                    tools: popup.snapshot && popup.snapshot.tools ? popup.snapshot.tools : null
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
        onTriggered: action => popup.menuAction(target, action)
    }
}
