import QtQuick
import "../../package/contents/code/Labs.js" as Labs
import "../../package/contents/code/Theme.js" as Theme
import "../../package/contents/ui/shared"

// Off-screen render of the shared Popup, for visual checks and timings:
//   QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1 QT_QPA_PLATFORM=offscreen \
//     qml tests/render/Render.qml -- PAGE LAB SNAP.json OUT.png [QUERY]
// PAGE: list | map | settings[-labs|-alerts|-look|-placement|-info] | menu (lab right-click menu) | nodemenu | hosts (remote hosts page, sample
// connections). LAB: lab name to expand / show on the map ("-" = none).
// Without the qml tool: python3 tests/render/run.py tests/render/Render.qml PAGE LAB SNAP.json OUT.png
// Writes parse / row-model / render times to OUT.png.timing.txt.
Rectangle {
    id: root
    width: 520
    // The map gets a fixed canvas; other pages are as tall as the popup's content.
    height: page === "map" ? 720 : Math.min(1180, Math.max(260, pop.implicitHeight + 28))
    // A wallpaper-ish backdrop so the translucent glass card reads as it would.
    gradient: Gradient {
        GradientStop {
            position: 0
            color: "#2b1d4e"
        }
        GradientStop {
            position: 1
            color: "#0d2a3a"
        }
    }

    readonly property var args: Qt.application.arguments
    readonly property int n: args.length
    readonly property bool hasQuery: args[n - 1].indexOf(".png") < 0
    readonly property string page: args[n - (hasQuery ? 5 : 4)]
    readonly property string labName: args[n - (hasQuery ? 4 : 3)]
    readonly property string snapPath: args[n - (hasQuery ? 3 : 2)]
    readonly property string outPath: args[n - (hasQuery ? 2 : 1)]

    // Timings go to OUT.png.timing.txt (console output isn't reliable here).
    property string timings: ""
    function note(line) {
        timings += line + "\n";
    }
    function saveTimings() {
        var x = new XMLHttpRequest();
        x.open("PUT", "file://" + outPath + ".timing.txt");
        x.send(timings);
    }

    QtObject {
        id: cfg
        property int pollSeconds: 30
        property string show: "both"
        property string tab: "all"
        property var pinned: []
        property bool notifyNodeDown: true
        property int reminderHours: 8
        property string corner: "top-right"
        property string surfaceStyle: "tint"
        property bool frosted: true
    }

    Popup {
        id: pop
        anchors.fill: parent
        anchors.margins: 14
        framed: true
        theme: Theme.glass()
        cfg: cfg
        maxBodyHeight: root.page === "map" ? 600 : (root.page.indexOf("settings") === 0 ? 1060 : 640)
        lastOkAt: Date.now()
        extraTitle: "Remote hosts"
        extraPage: Component {
            ConnectionsPage {
                showHeader: false
                theme: Theme.glass()
                connections: [
                    {
                        name: "lab-box",
                        type: "ssh",
                        host: "me@lab-box"
                    },
                    {
                        name: "k3s",
                        type: "k8s",
                        context: "k3s",
                        namespace: "c9s-srl02"
                    },
                    {
                        name: "dc-server",
                        type: "clab-api",
                        url: "https://dc-server:8090",
                        username: "me",
                        group: "dc-server"
                    },
                    {
                        name: "dc-server-netlab",
                        type: "netlab-ui",
                        url: "http://dc-server:8000",
                        group: "dc-server"
                    }
                ]
            }
        }
    }

    Component.onCompleted: {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + snapPath);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var t0 = Date.now();
            var snap = Labs.parse(xhr.responseText);
            var t1 = Date.now();
            pop.snapshot = snap;
            var t2 = Date.now();
            root.note("parse " + (t1 - t0) + " ms, rows+sync " + (t2 - t1) + " ms, rows " + pop.model.rows.length);
            // A second identical snapshot = a normal refresh.
            var t3 = Date.now();
            pop.snapshot = Labs.parse(xhr.responseText);
            root.note("refresh (parse+rows+sync) " + (Date.now() - t3) + " ms");
            if (root.hasQuery) {
                pop.searchOpen = true;
                pop.query = root.args[root.n - 1];
            }
            if (root.labName !== "-") {
                var lab = snap.labs.filter(l => l.name === root.labName)[0];
                if (root.page === "menu") {
                    pop.labMenu(lab, 250, 110);
                } else if (root.page === "nodemenu") {
                    pop.toggleExpanded(lab.id, false);
                    var bad = lab.nodes.filter(nd => !nd.running)[0] || lab.nodes[0];
                    pop.nodeMenu(lab, bad, 230, 260);
                } else if (root.page === "map") {
                    pop.mapLabId = lab.id;
                    pop.page = "map";
                } else {
                    var t4 = Date.now();
                    pop.toggleExpanded(lab.id, false);
                    root.note("expand " + lab.name + ": " + (Date.now() - t4) + " ms, rows " + pop.model.rows.length);
                    var t5 = Date.now();
                    pop.snapshot = Labs.parse(xhr.responseText);
                    root.note("refresh with it expanded: " + (Date.now() - t5) + " ms");
                }
            }
            if (root.page.indexOf("settings") === 0) {
                pop.page = "settings";
                if (root.page.indexOf("-") > 0)
                    pop.settingsTab = root.page.split("-")[1];
            }
            if (root.page === "hosts")
                pop.page = "extra";
            shot.start();
        };
        xhr.send();
    }

    Timer {
        id: quitLater
        interval: 300
        onTriggered: Qt.quit()
    }

    Timer {
        id: shot
        interval: 1500
        onTriggered: {
            var t = Date.now();
            root.grabToImage(function (r) {
                root.note("first render+grab " + (Date.now() - t) + " ms");
                r.saveToFile(root.outPath);
                root.saveTimings();
                quitLater.start();
            });
        }
    }
}
