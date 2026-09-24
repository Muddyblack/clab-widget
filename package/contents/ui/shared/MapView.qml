import QtQuick
import "../../code/Labs.js" as Labs

// Topology map page: pan (drag), zoom (wheel around the cursor, pinch, or the
// host's buttons via zoomBy()/fit()), hover highlights a node's links, click /
// right-click a node for its menu. Hover a link for its ends, state and
// throughput (`rates`, from the host); right-click it to copy or capture.
//
// Built for 700+ nodes: above DENSE nodes are painted straight onto a canvas
// (no item per node), links live on one static canvas that only repaints when
// the lab or zoom changes, and hover only repaints a small overlay canvas.
Item {
    id: view

    property var theme
    property var lab
    property Item menuAnchor
    // {linkKey: {rx, tx, end}} bit/s, from Labs.linkRates().
    property var rates: ({})
    signal nodeMenu(var node, real x, real y)
    signal linkMenu(var link, real x, real y)

    // Lab nodes + endpoints outside the lab (host / macvlan / mgmt-net).
    readonly property var graph: Labs.mapGraph(lab)
    readonly property int dense: 150
    readonly property bool isDense: graph.nodes.length > dense
    // Layout width chosen so the laid-out map has about the viewport's shape:
    // n nodes at ~30 px spacing and ~26 px row gap, so "fit" shows a readable
    // block instead of a tall thin column. Small labs just use the view width.
    readonly property real logicalW: {
        var n = graph.nodes.length;
        if (width <= 0 || height <= 0)
            return 200;
        var perRow = Math.sqrt(n * (width / height) * (26 / 30));
        return Math.max(width, perRow * 30 + 44);
    }
    readonly property var geo: Labs.mapLayout(graph.nodes, logicalW, Infinity)
    readonly property var byName: {
        var m = {};
        for (var i = 0; i < graph.nodes.length; i++)
            m[graph.nodes[i].name] = graph.nodes[i];
        return m;
    }
    readonly property real maxZoom: Math.max(1, Math.min(4, 4096 / Math.max(logicalW, geo.height)))
    // Zoom that shows the whole map (can be > 1 for small labs).
    readonly property real fitZoom: Math.max(0.15, Math.min(maxZoom, Math.min(width / logicalW, height / geo.height) * 0.95))
    readonly property real minZoom: Math.min(1, fitZoom)
    property real zoom: 1
    property string hovered: ""
    property int hoveredLink: -1
    property point hoverAt: Qt.point(0, 0)
    readonly property bool showLabels: geo.spacing * zoom >= 56
    // Dense maps get small tiles (about half the gap between neighbours).
    readonly property real nodeSize: isDense ? Math.max(4, Math.min(24, geo.spacing * zoom * 0.5)) : Math.max(5, Math.min(30, geo.size * zoom))
    // Tile shade per tier, so spine/leaf/server rows stay readable without icons.
    readonly property var tierShade: ({
            "super-spine": "#5b8cff",
            "spine": "#3b7bff",
            "dcgw": "#3b7bff",
            "leaf": "#005aff",
            "pe": "#005aff",
            "switch": "#005aff",
            "server": "#1e40af",
            "client": "#1e40af"
        })
    property string fittedLab: ""

    function fit() {
        zoom = fitZoom;
        flick.contentX = 0;
        flick.contentY = 0;
    }

    // Zoom by `factor` keeping the content point under (vx, vy) in place.
    function zoomBy(factor, vx, vy) {
        var px = vx === undefined ? flick.width / 2 : vx;
        var py = vy === undefined ? flick.height / 2 : vy;
        var nz = Math.max(minZoom, Math.min(maxZoom, zoom * factor));
        var k = nz / zoom;
        var cx = (flick.contentX + px) * k - px;
        var cy = (flick.contentY + py) * k - py;
        zoom = nz;
        flick.contentX = Math.max(0, Math.min(cx, flick.contentWidth - flick.width));
        flick.contentY = Math.max(0, Math.min(cy, flick.contentHeight - flick.height));
    }

    function nodeAt(x, y) {
        var best = "", bestD = Math.max(10, nodeSize * 0.7);
        for (var name in geo.pos) {
            var p = geo.pos[name];
            var d = Math.abs(p.x * zoom - x) + Math.abs(p.y * zoom - y);
            if (d < bestD) {
                bestD = d;
                best = name;
            }
        }
        return best;
    }

    // Link under (x, y) in stage coordinates, or -1 (within ~5 px of its line).
    function linkAt(x, y) {
        var ls = graph.links, pos = geo.pos, best = -1, bestD = 5;
        for (var i = 0; i < ls.length; i++) {
            var a = pos[ls[i].a], b = pos[ls[i].z];
            if (!a || !b)
                continue;
            var ax = a.x * zoom, ay = a.y * zoom, bx = b.x * zoom, by = b.y * zoom;
            var dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
            var t = len2 > 0 ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) : 0;
            var d = Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
            if (d < bestD) {
                bestD = d;
                best = i;
            }
        }
        return best;
    }

    onGeoChanged: base.requestPaint()
    onRatesChanged: base.requestPaint()
    onHoveredLinkChanged: overlay.requestPaint()
    onZoomChanged: base.requestPaint()
    onHoveredChanged: overlay.requestPaint()
    onLabChanged: {
        // A newly opened lab starts fitted; refreshes of the same lab keep zoom/pan.
        if (lab.id !== undefined && lab.id !== fittedLab && width > 0) {
            fittedLab = lab.id;
            Qt.callLater(fit);
        }
        base.requestPaint();
        overlay.requestPaint();
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, view.logicalW * view.zoom)
        contentHeight: Math.max(height, view.geo.height * view.zoom)
        boundsBehavior: Flickable.StopAtBounds
        interactive: !pinch.active

        Item {
            id: content
            width: flick.contentWidth
            height: flick.contentHeight

            // The map itself, centred when it is smaller than the view.
            Item {
                id: stage
                x: Math.max(0, (content.width - base.width) / 2)
                y: Math.max(0, (content.height - base.height) / 2)
                width: base.width
                height: base.height

                // Links (+ all nodes when dense). Repaints on lab/zoom change only.
                Canvas {
                    id: base
                    width: view.logicalW * view.zoom
                    height: view.geo.height * view.zoom
                    renderTarget: Canvas.FramebufferObject
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var z = view.zoom, pos = view.geo.pos, ls = view.graph.links;
                        var many = ls.length > 60;
                        ctx.lineWidth = many ? Math.max(0.5, 0.8 * Math.min(z, 2)) : 1.5;
                        ctx.strokeStyle = view.theme.sub;
                        ctx.globalAlpha = many ? 0.16 : 0.5;
                        // Like clab-ui: link state known (backend, --details)
                        // → green up / red down; unknown → neutral grey.
                        var plain = [], up = [], broken = [];
                        for (var i = 0; i < ls.length; i++) {
                            var a = pos[ls[i].a], b = pos[ls[i].z];
                            if (!a || !b)
                                continue;
                            var na = view.byName[ls[i].a], nb = view.byName[ls[i].z];
                            if (!(na && na.running && nb && nb.running) || ls[i].up === false)
                                broken.push([a, b]);
                            else
                                (ls[i].up === true ? up : plain).push([a, b]);
                        }
                        function stroke(segs) {
                            ctx.beginPath();
                            for (var k = 0; k < segs.length; k++) {
                                ctx.moveTo(segs[k][0].x * z, segs[k][0].y * z);
                                ctx.lineTo(segs[k][1].x * z, segs[k][1].y * z);
                            }
                            ctx.stroke();
                        }
                        stroke(plain);
                        ctx.strokeStyle = view.theme.ok;
                        ctx.globalAlpha = many ? 0.3 : 0.7;
                        stroke(up);
                        // Live traffic: busier up-links drawn thicker (log scale).
                        for (i = 0; i < ls.length; i++) {
                            var r = view.rates[ls[i].key || Labs.linkKey(ls[i])];
                            var pa = pos[ls[i].a], pb = pos[ls[i].z];
                            if (!r || ls[i].up !== true || r.rx + r.tx <= 1000 || !pa || !pb)
                                continue;
                            ctx.lineWidth = Math.min(6, 1 + Math.log((r.rx + r.tx) / 1000) / Math.LN10);
                            ctx.beginPath();
                            ctx.moveTo(pa.x * z, pa.y * z);
                            ctx.lineTo(pb.x * z, pb.y * z);
                            ctx.stroke();
                        }
                        ctx.lineWidth = many ? Math.max(0.5, 0.8 * Math.min(z, 2)) : 1.5;
                        // Down links (or touching a down node): dashed red, on top.
                        ctx.globalAlpha = 0.85;
                        ctx.strokeStyle = view.theme.bad;
                        ctx.setLineDash([4, 3]);
                        stroke(broken);
                        ctx.setLineDash([]);
                        if (!view.isDense)
                            return;
                        // Dense: nodes as small tiles in clab-ui blue, down ones red.
                        var s = view.nodeSize;
                        ctx.globalAlpha = 1;
                        ctx.font = Math.max(9, view.theme.smallSize - 1) + "px sans-serif";
                        ctx.textAlign = "center";
                        var labelled = [];
                        for (var n = 0; n < view.graph.nodes.length; n++) {
                            var node = view.graph.nodes[n], p = pos[node.name];
                            if (!p)
                                continue;
                            ctx.fillStyle = node.external ? view.theme.sub : node.running ? (view.tierShade[node.role] || "#005aff") : Qt.rgba(0.97, 0.44, 0.44, 0.9);
                            ctx.fillRect(p.x * z - s / 2, p.y * z - s / 2, s, s);
                            if (view.showLabels || !node.running)
                                labelled.push(node);
                        }
                        // Names after all tiles (the next row would cover them),
                        // down nodes last, each with a dark outline.
                        labelled.sort((x, y) => (x.running ? 0 : 1) - (y.running ? 0 : 1));
                        ctx.lineWidth = 3;
                        ctx.strokeStyle = "rgba(10, 14, 24, 0.85)";
                        for (n = 0; n < labelled.length; n++) {
                            var ln = labelled[n], lp = pos[ln.name];
                            ctx.strokeText(ln.label || ln.name, lp.x * z, lp.y * z + s / 2 + 11);
                            ctx.fillStyle = ln.running ? view.theme.sub : view.theme.bad;
                            ctx.fillText(ln.label || ln.name, lp.x * z, lp.y * z + s / 2 + 11);
                        }
                    }
                }

                // Hover: the node's links + its name. Cheap to repaint.
                Canvas {
                    id: overlay
                    anchors.fill: base
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var z = view.zoom, pos = view.geo.pos, ls = view.graph.links, h = view.hovered;
                        var hl = view.hoveredLink >= 0 ? ls[view.hoveredLink] : null;
                        if (hl && pos[hl.a] && pos[hl.z]) {
                            ctx.strokeStyle = view.theme.text;
                            ctx.globalAlpha = 0.95;
                            ctx.lineWidth = 3;
                            ctx.beginPath();
                            ctx.moveTo(pos[hl.a].x * z, pos[hl.a].y * z);
                            ctx.lineTo(pos[hl.z].x * z, pos[hl.z].y * z);
                            ctx.stroke();
                        }
                        if (h === "")
                            return;
                        ctx.strokeStyle = view.theme.text;
                        ctx.globalAlpha = 0.9;
                        ctx.lineWidth = 1.6;
                        ctx.beginPath();
                        for (var i = 0; i < ls.length; i++) {
                            if (ls[i].a !== h && ls[i].z !== h)
                                continue;
                            var a = pos[ls[i].a], b = pos[ls[i].z];
                            if (a && b) {
                                ctx.moveTo(a.x * z, a.y * z);
                                ctx.lineTo(b.x * z, b.y * z);
                            }
                        }
                        ctx.stroke();
                    }
                }

                // Sparse labs: real clab-ui icons as items.
                Repeater {
                    model: view.isDense ? [] : view.graph.nodes

                    Item {
                        readonly property var p: view.geo.pos[modelData.name] || ({
                                x: 0,
                                y: 0
                            })
                        x: p.x * view.zoom - view.nodeSize / 2
                        y: p.y * view.zoom - view.nodeSize / 2
                        width: view.nodeSize
                        height: view.nodeSize

                        // Endpoint outside the lab (host / macvlan / mgmt-net): a small ring.
                        Rectangle {
                            visible: modelData.external === true
                            anchors.centerIn: parent
                            width: parent.width * 0.55
                            height: width
                            radius: width / 2
                            color: view.theme.cardSolid
                            border.width: 1.5
                            border.color: view.theme.sub
                        }
                        Image {
                            visible: modelData.external !== true
                            anchors.fill: parent
                            source: modelData.external ? "" : Labs.fileUrl(modelData.icon)
                            sourceSize: Qt.size(64, 64)
                            asynchronous: true
                            opacity: modelData.running ? 1 : 0.4
                        }
                        Rectangle {
                            visible: !modelData.running
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: -2
                            width: Math.max(6, view.nodeSize / 3.2)
                            height: width
                            radius: width / 2
                            color: view.theme.bad
                        }
                        Text {
                            visible: view.showLabels || !modelData.running || view.hovered === modelData.name
                            anchors.top: parent.bottom
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label || modelData.name
                            color: modelData.running ? view.theme.sub : view.theme.bad
                            font.pixelSize: view.theme.smallSize - 1
                        }
                    }
                }

                // The hovered link: its ends, state and throughput.
                Rectangle {
                    readonly property var link: view.hoveredLink >= 0 ? view.graph.links[view.hoveredLink] : null
                    visible: link !== null && link !== undefined && view.hovered === ""
                    x: Math.max(0, Math.min(view.hoverAt.x + 12, stage.width - width - 4))
                    y: Math.max(0, view.hoverAt.y - height - 8)
                    width: linkText.implicitWidth + 12
                    height: linkText.implicitHeight + 6
                    radius: 4
                    color: view.theme.cardSolid
                    border.width: 1
                    border.color: link && link.up === false ? view.theme.bad : view.theme.border

                    Text {
                        id: linkText
                        anchors.centerIn: parent
                        text: parent.link ? Labs.linkText(parent.link, view.rates[parent.link.key || Labs.linkKey(parent.link)]) : ""
                        color: view.theme.text
                        font.pixelSize: view.theme.smallSize
                    }
                }

                // Name of the hovered node when labels are hidden (dense or zoomed out).
                Rectangle {
                    readonly property var p: view.hovered !== "" ? view.geo.pos[view.hovered] : null
                    visible: p !== null && p !== undefined && (!view.showLabels || view.isDense)
                    x: p ? p.x * view.zoom + view.nodeSize / 2 + 4 : 0
                    y: p ? p.y * view.zoom - height / 2 : 0
                    width: hoverText.implicitWidth + 10
                    height: hoverText.implicitHeight + 4
                    radius: 4
                    color: view.theme.cardSolid
                    border.width: 1
                    border.color: view.theme.border

                    Text {
                        id: hoverText
                        anchors.centerIn: parent
                        text: {
                            var n = view.byName[view.hovered];
                            return n ? (n.label || n.name) + "  ·  " + n.kind + (n.ipv4 ? "  ·  " + n.ipv4 : "") : "";
                        }
                        color: view.theme.text
                        font.pixelSize: view.theme.smallSize
                    }
                }
            }

            HoverHandler {
                onPointChanged: {
                    var x = point.position.x - stage.x, y = point.position.y - stage.y;
                    view.hovered = view.nodeAt(x, y);
                    view.hoverAt = Qt.point(x, y);
                    view.hoveredLink = view.hovered === "" ? view.linkAt(x, y) : -1;
                }
                onHoveredChanged: if (!hovered) {
                    view.hovered = "";
                    view.hoveredLink = -1;
                }
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (ev, button) => {
                    var x = ev.position.x - stage.x, y = ev.position.y - stage.y;
                    var name = view.nodeAt(x, y);
                    var g = content.mapToItem(view.menuAnchor, ev.position.x, ev.position.y);
                    if (name !== "" && !view.byName[name].external) {
                        view.nodeMenu(view.byName[name], g.x, g.y);
                        return;
                    }
                    var li = name === "" ? view.linkAt(x, y) : -1;
                    if (li >= 0)
                        view.linkMenu(view.graph.links[li], g.x, g.y);
                }
            }
        }
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => {
            var p = flick.mapFromItem(view, ev.x, ev.y);
            view.zoomBy(ev.angleDelta.y > 0 ? 1.15 : 1 / 1.15, p.x, p.y);
        }
    }

    PinchHandler {
        id: pinch
        target: null
        property real last: 1
        onActiveChanged: last = 1
        onActiveScaleChanged: {
            view.zoomBy(activeScale / last, centroid.position.x, centroid.position.y);
            last = activeScale;
        }
    }
}
