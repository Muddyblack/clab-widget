import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../package/contents/code/Labs.js" as Labs
import "../package/contents/code/Theme.js" as Theme
import "../package/contents/ui/shared"

// The Quickshell counterpart of the plasmoid, in two modes (settings):
//   pill    — a glass pill in a corner; click for the popup (default)
//   desktop — the card sits on the desktop layer, always visible (like the
//             audio visualizer's desktop mode)
// All data and actions go through the same tools/run the Plasma widget uses.
// Hyprland blur behind the glass: layerrule = blur, clab-widget-glass
ShellRoot {
    id: root

    property var snapshot: null
    property double lastOkAt: 0
    property bool failing: false
    property var tracker: Labs.newTracker()
    // CLAB_WIDGET_OPEN=1 starts with the popup shown (screenshots, development).
    property bool popupOpen: Quickshell.env("CLAB_WIDGET_OPEN") === "1"

    // What the pill counts and notifications cover: the labs the user chose to see.
    readonly property var shown: Labs.shownSnapshot(snapshot, cfg.show)
    readonly property var totals: shown ? shown.totals : null
    readonly property var pinnedSegs: Labs.pinnedSegments(snapshot, cfg.pinned)
    readonly property string runTool: Qt.resolvedUrl("../package/contents/tools/run").toString().replace(/^file:\/\//, "")
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/clab-widget"
    readonly property bool atTop: cfg.corner.indexOf("top") === 0
    readonly property bool atLeft: cfg.corner.indexOf("left") > 0

    readonly property var theme: Theme.glass()
    readonly property bool desktopMode: cfg.mode === "desktop"

    // ── Settings (~/.config/clab-widget/quickshell.json) ─────────────────────
    FileView {
        id: settingsFile
        path: root.configDir + "/quickshell.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        // First run: no file yet. Create the directory, then write defaults.
        onLoadFailed: firstRun.running = true

        JsonAdapter {
            id: cfg
            property int pollSeconds: 30
            property string show: "both"
            property string tab: "all"
            property var pinned: []
            property bool notifyNodeDown: true
            property int reminderHours: 0
            property string corner: "top-right"
            property string mode: "pill"
            property string surfaceStyle: "tint"
            property string appIcon: "clab"
            property bool frosted: true

            onShowChanged: root.refresh()
            onModeChanged: root.refresh()
        }
    }

    Process {
        id: firstRun
        command: ["mkdir", "-p", root.configDir]
        onExited: settingsFile.writeAdapter()
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    function refresh() {
        if (snapshotProc.running)
            return;
        var args = ["sh", root.runTool, "snapshot"];
        // Memory + netlab per-node state are slow to collect; only while shown.
        if (root.popupOpen || root.desktopMode)
            args.push("--details");
        args = args.concat(Labs.sourceArgs(cfg.show));
        snapshotProc.command = args;
        snapshotProc.running = true;
    }

    function runAction(args) {
        Quickshell.execDetached(["sh", root.runTool].concat(args));
    }

    function notifyChanges(snap) {
        var r = Labs.trackEvents(root.tracker, snap, {
            notifyNodeDown: cfg.notifyNodeDown,
            reminderHours: cfg.reminderHours
        });
        root.tracker = r.tracker;
        for (var i = 0; i < r.events.length; i++)
            root.runAction(["notify", r.events[i].title, r.events[i].body]);
    }

    Process {
        id: snapshotProc
        stdout: StdioCollector {
            onStreamFinished: {
                var snap = Labs.parse(this.text);
                if (snap === null) {
                    root.failing = true;
                    return;
                }
                root.snapshot = snap;
                root.lastOkAt = Date.now();
                root.failing = false;
                root.notifyChanges(Labs.shownSnapshot(snap, cfg.show));
            }
        }
    }

    // Keybinds / scripts, same target and names as ai-usage-widget:
    //   qs ipc -p <repo> call panel toggle      (open | close | refresh | settings | quit)
    //   qs ipc -p <repo> call panel setShow tabs   (both | tabs | containerlab | netlab)
    IpcHandler {
        target: "panel"

        function toggle(): void {
            root.popupOpen = !root.popupOpen;
            if (root.popupOpen)
                root.refresh();
        }
        function open(): void {
            root.popupOpen = true;
            root.refresh();
        }
        function close(): void {
            root.popupOpen = false;
        }
        function refresh(): void {
            root.refresh();
        }
        function settings(): void {
            root.popupOpen = true;
            pop.page = pop.page === "settings" ? "list" : "settings";
        }
        function setShow(mode: string): void {
            cfg.show = mode;
        }
        function setMode(mode: string): void {
            cfg.mode = mode;
        }
        function quit(): void {
            Qt.quit();
        }
    }

    Timer {
        id: stopRefresh
        interval: 4000
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.popupOpen ? 5000 : cfg.pollSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ── Pill ──────────────────────────────────────────────────────────────────
    PanelWindow {
        id: panel
        visible: !root.desktopMode
        anchors {
            top: root.atTop
            bottom: !root.atTop
            left: root.atLeft
            right: !root.atLeft
        }
        margins {
            top: 8
            bottom: 8
            left: 12
            right: 12
        }
        implicitWidth: pill.implicitWidth
        implicitHeight: pill.implicitHeight
        color: "transparent"
        exclusiveZone: 0

        Item {
            id: pill
            implicitWidth: pillRow.implicitWidth + 22
            implicitHeight: 32

            GlassCard {
                anchors.fill: parent
                material: cfg.surfaceStyle
                fill: Theme.fillFor(cfg.surfaceStyle)
                frosted: cfg.frosted
                radiusTL: 10
                radiusTR: 10
                radiusBR: 10
                radiusBL: 10
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: pillMouse.containsMouse || root.popupOpen ? root.theme.hover : "transparent"
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 7

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    sourceSize: Qt.size(32, 32)
                    source: Qt.resolvedUrl("../package/contents/" + Theme.appIcon(cfg.appIcon, cfg.show, 64))
                }

                // Pinned labs, or else the totals.
                PinnedSegments {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pinnedSegs.length > 0
                    theme: root.theme
                    segments: root.pinnedSegs
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pinnedSegs.length === 0
                    width: 7
                    height: 7
                    radius: 3.5
                    color: !root.totals || root.totals.labs === 0 ? root.theme.sub : (root.totals.attention > 0 ? root.theme.bad : root.theme.ok)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pinnedSegs.length === 0
                    text: !root.totals ? "clab" : (root.totals.labs + (root.totals.labs === 1 ? " lab · " : " labs · ") + root.totals.running + "/" + root.totals.nodes)
                    color: root.theme.text
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    root.popupOpen = !root.popupOpen;
                    if (root.popupOpen)
                        root.refresh();
                }
            }
        }
    }

    // ── Popup ─────────────────────────────────────────────────────────────────
    PanelWindow {
        id: popup
        visible: root.popupOpen && !root.desktopMode
        anchors {
            top: root.atTop
            bottom: !root.atTop
            left: root.atLeft
            right: !root.atLeft
        }
        margins {
            top: 44
            bottom: 44
            left: 12
            right: 12
        }
        implicitWidth: 500
        implicitHeight: Math.min((popup.screen ? popup.screen.height : 900) - 90, pop.implicitHeight + 2)
        color: "transparent"
        exclusiveZone: 0
        // Keyboard focus for the search field.
        WlrLayershell.keyboardFocus: root.popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.namespace: "clab-widget-glass"

        Item {
            anchors.fill: parent

            // The shared popup (same as Plasma and the tray app), on glass.
            Popup {
                id: pop
                anchors.fill: parent
                framed: true
                theme: root.theme
                snapshot: root.snapshot
                lastOkAt: root.lastOkAt
                failing: root.failing
                cfg: cfg
                showPlacement: true
                showMode: true
                maxBodyHeight: Math.min(600, (popup.screen ? popup.screen.height : 900) - 220)
                onRun: args => {
                    root.runAction(args);
                    if (args[0] === "stop")
                        stopRefresh.restart();
                }
                onRefreshRequested: root.refresh()
            }
        }
    }

    // ── Desktop card ──────────────────────────────────────────────────────────
    // Mode "desktop": the same card, always visible on the desktop layer
    // (below windows), in the chosen corner.
    PanelWindow {
        id: desk
        visible: root.desktopMode
        anchors {
            top: root.atTop
            bottom: !root.atTop
            left: root.atLeft
            right: !root.atLeft
        }
        margins {
            top: 24
            bottom: 24
            left: 24
            right: 24
        }
        implicitWidth: 480
        implicitHeight: Math.min((desk.screen ? desk.screen.height : 900) - 80, deskPop.implicitHeight + 2)
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "clab-widget-glass"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Popup {
            id: deskPop
            anchors.fill: parent
            framed: true
            theme: root.theme
            snapshot: root.snapshot
            lastOkAt: root.lastOkAt
            failing: root.failing
            cfg: cfg
            showPlacement: true
            showMode: true
            maxBodyHeight: Math.min(560, (desk.screen ? desk.screen.height : 900) - 220)
            onRun: args => {
                root.runAction(args);
                if (args[0] === "stop")
                    stopRefresh.restart();
            }
            onRefreshRequested: root.refresh()
        }
    }
}
