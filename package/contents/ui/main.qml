import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "../code/Labs.js" as Labs
import "../code/Theme.js" as Theme
import "shared"

PlasmoidItem {
    id: root

    property var snapshot: null
    property double lastOkAt: 0
    property bool failing: false
    property var tracker: Labs.newTracker()

    // What the panel counts and notifications cover: the labs the user chose to see.
    readonly property var shown: Labs.shownSnapshot(snapshot, Plasmoid.configuration.show, Plasmoid.configuration.onlyMine)
    readonly property var totals: shown ? shown.totals : null
    readonly property var pins: Plasmoid.configuration.pinned || []
    readonly property var pinnedSegs: Labs.pinnedSegments(snapshot, pins)
    readonly property string toolsDir: decodeURIComponent(Qt.resolvedUrl("../tools/").toString().replace(/^file:\/\//, ""))

    // In a panel or the system tray: icon + popup (Plasma draws the popup
    // background, colours follow the Plasma scheme). On the desktop: the glass
    // card itself, like Glassy System Monitor.
    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge, PlasmaCore.Types.RightEdge].indexOf(Plasmoid.location) !== -1 || Plasmoid.formFactor === PlasmaCore.Types.Horizontal || Plasmoid.formFactor === PlasmaCore.Types.Vertical

    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    Plasmoid.backgroundHints: inPanel ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground
    // System tray: shown when a lab needs attention, tucked into the overflow
    // when nothing is running.
    Plasmoid.status: root.totals && root.totals.attention > 0 ? PlasmaCore.Types.NeedsAttentionStatus : (root.totals && root.totals.labs > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus)

    // Shared components take colours from here rather than importing Kirigami.
    readonly property var theme: inPanel ? plasmaTheme : Theme.glass()
    readonly property var plasmaTheme: ({
            text: Kirigami.Theme.textColor,
            sub: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6),
            card: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05),
            cardSolid: Kirigami.Theme.backgroundColor,
            badge: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08),
            hover: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25),
            border: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12),
            ok: Kirigami.Theme.positiveTextColor,
            warn: Kirigami.Theme.neutralTextColor,
            bad: Kirigami.Theme.negativeTextColor,
            clab: "#4aa8ff",
            netlab: "#aa66ff",
            fontSize: Kirigami.Theme.defaultFont.pixelSize > 0 ? Kirigami.Theme.defaultFont.pixelSize : 13,
            smallSize: Kirigami.Theme.smallFont.pixelSize > 0 ? Kirigami.Theme.smallFont.pixelSize : 11
        })

    function tool(args) {
        return "sh " + Labs.q(root.toolsDir + "run") + " " + args.map(Labs.q).join(" ");
    }

    function refresh() {
        var args = ["snapshot"];
        // Memory + netlab per-node state are slow to collect; only while open.
        if (root.expanded)
            args.push("--details");
        args = args.concat(Labs.sourceArgs(Plasmoid.configuration.show, Plasmoid.configuration.labFolders));
        var cmd = root.tool(args);
        snapshotSource.disconnectSource(cmd);
        snapshotSource.connectSource(cmd);
    }

    function notifyChanges(snap) {
        var r = Labs.trackEvents(root.tracker, snap, {
            notifyNodeDown: Plasmoid.configuration.notifyNodeDown,
            reminderHours: Plasmoid.configuration.reminderHours
        });
        root.tracker = r.tracker;
        for (var i = 0; i < r.events.length; i++)
            root.runAction(["notify", r.events[i].title, r.events[i].body]);
    }

    function runAction(args) {
        var cmd = root.tool(args);
        actionSource.disconnectSource(cmd);
        actionSource.connectSource(cmd);
    }

    Plasma5Support.DataSource {
        id: snapshotSource
        engine: "executable"
        onNewData: function (src, data) {
            disconnectSource(src);
            var snap = Labs.parse(data["stdout"]);
            if (snap === null) {
                // Keep showing the last good state, marked stale.
                root.failing = true;
                return;
            }
            root.snapshot = snap;
            root.lastOkAt = Date.now();
            root.failing = false;
            root.notifyChanges(Labs.shownSnapshot(snap, Plasmoid.configuration.show, Plasmoid.configuration.onlyMine));
        }
    }

    // Remote hosts page: list / add (ssh, netlab-ui) / remove through the backend;
    // a clab-api-server login asks for its password in a terminal.
    property var connections: []
    property string connStatus: ""
    property bool connBusy: false

    function loadConnections() {
        connSource.connectSource(root.tool(["connections"]));
    }

    function addConnection(conn) {
        if (conn.type === "clab-api") {
            var args = ["login", conn.name, conn.url, conn.username || "", "--terminal"];
            if (conn.insecure)
                args.push("--insecure");
            root.runAction(args);
            root.connStatus = "log in in the terminal window, then refresh";
            return;
        }
        root.connBusy = true;
        root.connStatus = "";
        connSource.connectSource(root.tool(["add", JSON.stringify(conn)]));
    }

    function removeConnection(name) {
        connSource.connectSource(root.tool(["logout", name, "--forget"]));
    }

    Plasma5Support.DataSource {
        id: connSource
        engine: "executable"
        onNewData: function (src, data) {
            disconnectSource(src);
            var out = null;
            try {
                out = JSON.parse(data["stdout"]);
            } catch (e) {}
            if (Array.isArray(out)) {
                root.connections = out;
                return;
            }
            if (out && out.message !== undefined) {
                root.connBusy = false;
                root.connStatus = out.message;
            }
            root.loadConnections();
            root.refresh();
        }
    }

    Plasma5Support.DataSource {
        id: actionSource
        engine: "executable"
        onNewData: src => disconnectSource(src)
    }

    // Slow while collapsed, quick while someone is looking at the popup.
    Timer {
        id: stopRefresh
        interval: 4000
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.expanded ? 5000 : Plasmoid.configuration.pollSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onExpandedChanged: {
        if (expanded)
            root.refresh();
    }

    Connections {
        target: Plasmoid.configuration
        function onShowChanged() {
            root.refresh();
        }
        function onLabFoldersChanged() {
            root.refresh();
        }
    }

    toolTipMainText: "CLAB Widget"
    toolTipSubText: root.pinnedSegs.length > 0 ? root.pinnedSegs.map(Labs.segmentText).join("\n") : Labs.summaryText(root.totals)

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: compactRow.implicitWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: 4

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                // The package file, so it also shows before the hicolor copy is installed.
                source: Qt.resolvedUrl("../" + Theme.appIcon(Plasmoid.configuration.appIcon, Plasmoid.configuration.show, 64))
                active: compact.containsMouse
            }

            // Pinned labs ("● fabric 6/7"), or else the lab count + attention dot.
            PinnedSegments {
                visible: root.pinnedSegs.length > 0
                theme: root.theme
                segments: root.pinnedSegs
                fontSize: root.theme.fontSize
            }

            PlasmaComponents.Label {
                visible: root.pinnedSegs.length === 0 && root.totals !== null && root.totals.labs > 0
                text: root.totals ? root.totals.labs : ""
            }

            Rectangle {
                visible: root.pinnedSegs.length === 0 && root.totals !== null && root.totals.attention > 0
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: Kirigami.Theme.negativeTextColor
            }
        }
    }

    // The shared popup: fixed header (search / refresh / settings), filter chips,
    // virtualized lab list, map page, settings page. Right-click anything.
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 38, pop.implicitHeight)
        // On the desktop it's the card itself (resizable), not a popup.
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        Popup {
            id: pop
            anchors.fill: parent
            theme: root.theme
            snapshot: root.snapshot
            lastOkAt: root.lastOkAt
            failing: root.failing
            cfg: Plasmoid.configuration
            framed: !root.inPanel
            // Preferred size only; on the desktop the body then fills whatever
            // size the user resizes the widget to.
            maxBodyHeight: Kirigami.Units.gridUnit * 30
            onRun: args => {
                root.runAction(args);
                if (args[0] === "stop")
                    stopRefresh.restart();
            }
            onRefreshRequested: root.refresh()
            extraTitle: "Remote hosts"
            extraPage: Component {
                ConnectionsPage {
                    showHeader: false
                    passwordLogin: false
                    theme: root.theme
                    connections: root.connections
                    status: root.connStatus
                    busy: root.connBusy
                    onAddRequested: (conn, _password) => root.addConnection(conn)
                    onRemoveRequested: name => root.removeConnection(name)
                    onDone: pop.page = "list"
                    Component.onCompleted: root.loadConnections()
                }
            }
        }
    }
}
