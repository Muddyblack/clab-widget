import QtQuick
import QtQuick.Layouts
import "../package/contents/code/Labs.js" as Labs
import "../package/contents/code/Theme.js" as Theme
import "../package/contents/ui/shared"

// Popup of the desktop tray app (Windows, macOS, any Linux desktop): the
// shared Popup plus a remote-hosts page; `backend` is the Python bridge in app.py.
Rectangle {
    id: root

    property var snapshot: null
    property double lastOkAt: 0
    property bool failing: false
    property var tracker: Labs.newTracker()
    property var connections: []
    property string connStatus: ""
    property bool connBusy: false

    readonly property var shown: Labs.shownSnapshot(snapshot, cfg.show)

    width: 500
    implicitHeight: pop.implicitHeight + 8
    height: implicitHeight
    // The glass card is drawn by the Popup (framed); the window is transparent.
    color: "transparent"

    readonly property var theme: Theme.glass()

    // Settings, persisted by the backend as desktop.json. Same keys as the
    // Quickshell config, minus placement.
    QtObject {
        id: cfg
        property int pollSeconds: 30
        property string show: "both"
        property string tab: "all"
        property var pinned: []
        property bool notifyNodeDown: true
        property int reminderHours: 0
        property string surfaceStyle: "tint"
        property string appIcon: "clab"
        property bool frosted: true

        function save() {
            backend.saveSettings(JSON.stringify({
                pollSeconds: cfg.pollSeconds,
                show: cfg.show,
                tab: cfg.tab,
                pinned: cfg.pinned,
                notifyNodeDown: cfg.notifyNodeDown,
                reminderHours: cfg.reminderHours,
                surfaceStyle: cfg.surfaceStyle,
                appIcon: cfg.appIcon,
                frosted: cfg.frosted
            }));
        }
        onPollSecondsChanged: save()
        onShowChanged: {
            save();
            backend.setAppIcon(Theme.appIconVariant(cfg.appIcon, cfg.show));
            root.refresh();
        }
        onTabChanged: save()
        onPinnedChanged: {
            save();
            root.publishTray();
        }
        onNotifyNodeDownChanged: save()
        onReminderHoursChanged: save()
        onSurfaceStyleChanged: save()
        onAppIconChanged: {
            save();
            backend.setAppIcon(Theme.appIconVariant(cfg.appIcon, cfg.show));
        }
        onFrostedChanged: save()
    }

    function refresh() {
        var args = ["snapshot"];
        if (!backend)
            return;
        if (backend.popupVisible)
            args.push("--details");
        backend.refresh(JSON.stringify(args.concat(Labs.sourceArgs(cfg.show))));
    }

    // Tray tooltip + dot: the pinned labs when there are any, else the totals.
    function publishTray() {
        var segs = Labs.pinnedSegments(root.snapshot, cfg.pinned);
        if (segs.length === 0) {
            var t = Labs.shownSnapshot(root.snapshot, cfg.show);
            if (t)
                backend.setTrayState(JSON.stringify(t.totals), Labs.summaryText(t.totals));
            return;
        }
        var present = segs.filter(s => s.present).length;
        var bad = segs.filter(s => ["partial", "stopped", "gone"].indexOf(s.lifecycle) >= 0).length;
        backend.setTrayState(JSON.stringify({
            labs: present,
            attention: bad
        }), segs.map(Labs.segmentText).join("  ·  "));
    }

    function runAction(args) {
        backend.action(JSON.stringify(args));
    }

    Connections {
        target: backend
        function onSnapshotReady(text) {
            var snap = Labs.parse(text);
            if (snap === null) {
                root.failing = true;
                return;
            }
            root.snapshot = snap;
            root.lastOkAt = Date.now();
            root.failing = false;
            var shown = Labs.shownSnapshot(snap, cfg.show);
            root.publishTray();
            var r = Labs.trackEvents(root.tracker, shown, {
                notifyNodeDown: cfg.notifyNodeDown,
                reminderHours: cfg.reminderHours
            });
            root.tracker = r.tracker;
            for (var i = 0; i < r.events.length; i++)
                backend.notify(r.events[i].title, r.events[i].body);
        }
        function onRefreshFailed() {
            root.failing = true;
        }
        function onPopupVisibleChanged() {
            if (backend.popupVisible)
                root.refresh();
        }
        function onLoginFinished(ok, message) {
            root.connBusy = false;
            root.connStatus = message;
            root.connections = JSON.parse(backend.connectionsJson());
            if (ok)
                root.refresh();
        }
    }

    Timer {
        // `backend` is gone during shutdown; bindings must not trip over it.
        interval: backend && backend.popupVisible ? 5000 : cfg.pollSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: stopRefresh
        interval: 4000
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        // --render --page settings|connections|map (screenshots)
        if (initialPage === "connections")
            pop.page = "extra";
        else if (initialPage !== "labs")
            pop.page = initialPage;
        var s = JSON.parse(backend.loadSettings());
        for (var k in s)
            if (cfg[k] !== undefined)
                cfg[k] = s[k];
        root.connections = JSON.parse(backend.connectionsJson());
    }

    // The shared popup (same as Plasma and Quickshell) + the remote-hosts page.
    Popup {
        id: pop
        objectName: "popup"
        anchors.fill: parent
        framed: true
        theme: root.theme
        snapshot: root.snapshot
        lastOkAt: root.lastOkAt
        failing: root.failing
        cfg: cfg
        maxBodyHeight: 560
        extraTitle: "Remote hosts"
        extraPage: Component {
            ConnectionsPage {
                showHeader: false
                theme: root.theme
                connections: root.connections
                status: root.connStatus
                busy: root.connBusy
                onAddRequested: (conn, password) => {
                    root.connBusy = true;
                    root.connStatus = "";
                    backend.addConnection(JSON.stringify(conn), password);
                }
                onRemoveRequested: name => {
                    backend.removeConnection(name);
                    root.connections = JSON.parse(backend.connectionsJson());
                    root.refresh();
                }
                onDone: pop.page = "list"
            }
        }
        onRun: args => {
            root.runAction(args);
            if (args[0] === "stop")
                stopRefresh.restart();
        }
        onRefreshRequested: root.refresh()
    }
}
