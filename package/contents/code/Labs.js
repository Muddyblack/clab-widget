// Presentation helpers shared by the Plasma and Quickshell frontends.
// The backend snapshot already decides lifecycle/attention; this only turns it
// into text and colours.
.pragma library

// POSIX single-quote a string for the /bin/sh command lines both frontends run.
function q(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function lifecycleColor(theme, lifecycle) {
    switch (lifecycle) {
    case "running":
        return theme.ok;
    case "partial":
    case "starting":
        return theme.warn;
    case "stopped":
        return theme.bad;
    default:
        return theme.sub;
    }
}

function lifecycleText(lab) {
    switch (lab.lifecycle) {
    case "running":
        return lab.nodesKnown ? lab.running + "/" + lab.total + " up" : "running";
    case "partial":
        return lab.running + "/" + lab.total + " up";
    case "stopped":
        return "all " + lab.total + " down";
    case "starting":
        return lab.status || "starting";
    default:
        return lab.status || "unknown";
    }
}

// "netlab · via containerlab", "containerlab", "netlab · libvirt"
function badgeText(lab) {
    if (lab.managedBy !== "netlab")
        return lab.managedBy;
    var p = (lab.providers || []).join(", ");
    if (p === "")
        return "netlab";
    return "netlab · " + (p === "containerlab" ? "via clab" : p);
}

function summaryText(totals) {
    if (!totals || totals.labs === 0)
        return "No labs running";
    var s = totals.labs + (totals.labs === 1 ? " lab" : " labs") + " · " + totals.running + "/" + totals.nodes + " nodes";
    if (totals.attention > 0)
        s += " · " + totals.attention + " need attention";
    return s;
}

function bytes(n) {
    if (n === null || n === undefined)
        return "";
    if (n >= 1073741824)
        return (n / 1073741824).toFixed(1) + " GiB";
    return Math.round(n / 1048576) + " MiB";
}

// "2.1 GiB" / "≥ 1.4 GiB" (some nodes unmeasured) / "" (no data or no details).
function memoryText(lab) {
    if (lab.memoryBytes === null || lab.memoryBytes === undefined)
        return "";
    return (lab.memoryCoverage === "partial" ? "≥ " : "") + bytes(lab.memoryBytes);
}

function ago(ms) {
    if (!ms)
        return "never";
    var s = Math.max(0, Math.round((Date.now() - ms) / 1000));
    if (s < 5)
        return "just now";
    if (s < 60)
        return s + "s ago";
    if (s < 3600)
        return Math.floor(s / 60) + "m ago";
    return Math.floor(s / 3600) + "h ago";
}

// Parse backend stdout; null on garbage so callers keep the last good snapshot.
function parse(text) {
    try {
        var snap = JSON.parse(text);
        return snap && snap.schemaVersion === 1 ? snap : null;
    } catch (e) {
        return null;
    }
}

function sourceName(key) {
    return key.indexOf("remote:") === 0 ? key.slice(7) : key;
}

// Human hints for sources that are unavailable or failing.
function sourceNotices(snap) {
    var out = [];
    if (!snap)
        return out;
    if (snap.error)
        out.push(snap.error);
    var src = snap.sources || {};
    for (var key in src) {
        var st = src[key];
        if (st.error)
            out.push(sourceName(key) + ": " + st.error);
        else if (!st.available)
            out.push(sourceName(key) + " not found on PATH");
    }
    return out;
}

// ── Notifications ────────────────────────────────────────────────────────────
//
// Decides which snapshot changes deserve a desktop notification. Pure: takes the
// previous tracking state and returns the next one plus the events to show, so
// both frontends (and tests/labs.test.js) share the exact same rules.
//
//   - a node seen running, then down on two consecutive polls → "node down"
//   - a node seen running, then missing from its (still present) lab on two
//     consecutive polls → "node disappeared" (container removed)
//   - a source (tool or remote host) that worked, then fails on two
//     consecutive polls → "host unreachable" (once, until it recovers)
//   - a lab up for longer than opts.reminderHours → one reminder per deployment
//     (off when reminderHours is 0; never destroys anything)
//
// One flaky poll never notifies, and nothing is reported on the first
// snapshot, so starting the widget next to an already-broken lab stays quiet.
var CONFIRM_POLLS = 2;

function newTracker() {
    return {
        primed: false,
        wasUp: {},
        downCount: {},
        goneCount: {},
        sourceOk: {},
        sourceFail: {},
        reminded: {}
    };
}

function trackEvents(tracker, snap, opts) {
    var t = tracker || newTracker();
    var next = newTracker();
    next.primed = true;
    var events = [];
    var labs = snap && snap.labs ? snap.labs : [];
    var labIds = {};
    var seen = {};

    function emit(ok, title, body, labId) {
        if (ok && t.primed)
            events.push({
                title: title,
                body: body,
                labId: labId || ""
            });
    }

    for (var i = 0; i < labs.length; i++) {
        var lab = labs[i];
        labIds[lab.id] = lab;
        for (var j = 0; j < lab.nodes.length; j++) {
            var node = lab.nodes[j];
            var key = lab.id + "/" + node.name;
            seen[key] = true;
            if (node.running) {
                next.wasUp[key] = true;
                continue;
            }
            var count = (t.downCount[key] || 0) + 1;
            next.downCount[key] = count;
            if (t.wasUp[key] && count < CONFIRM_POLLS)
                next.wasUp[key] = true; // still waiting for confirmation
            else if (t.wasUp[key])
                emit(opts.notifyNodeDown, node.name + " is down", lab.name + ": " + (node.status || node.state) + " (" + lab.running + "/" + lab.total + " nodes up)", lab.id);
        }

        if (t.reminded[lab.id]) {
            next.reminded[lab.id] = true;
        } else if (opts.reminderHours > 0 && lab.uptimeSeconds !== null && lab.uptimeSeconds !== undefined && lab.uptimeSeconds >= opts.reminderHours * 3600) {
            next.reminded[lab.id] = true;
            emit(true, lab.name + " is still running", "Up for " + duration(lab.uptimeSeconds) + (lab.memoryBytes ? ", using " + memoryText(lab) : "") + ". Tear it down if you're done.", lab.id);
        }
    }

    // Nodes that were up and are now missing while their lab is still listed.
    // A whole lab vanishing is a teardown, not an incident: no event.
    for (var k in t.wasUp) {
        if (seen[k])
            continue;
        var labId = k.slice(0, k.lastIndexOf("/"));
        var owner = labIds[labId];
        if (!owner)
            continue;
        var gone = (t.goneCount[k] || 0) + 1;
        if (gone < CONFIRM_POLLS) {
            next.goneCount[k] = gone;
            next.wasUp[k] = true;
        } else {
            emit(opts.notifyNodeDown, k.slice(k.lastIndexOf("/") + 1) + " disappeared", owner.name + ": the node's container is gone (" + owner.running + "/" + owner.total + " nodes up)", labId);
        }
    }

    // Tools / remote hosts: only ones that have worked before can "go down".
    var sources = snap && snap.sources ? snap.sources : {};
    for (var s in sources) {
        var st = sources[s];
        var failing = st.error !== "" && st.error !== undefined;
        if (!failing) {
            if (st.available)
                next.sourceOk[s] = true;
            continue;
        }
        var fails = (t.sourceFail[s] || 0) + 1;
        next.sourceFail[s] = fails;
        if (t.sourceOk[s] && fails < CONFIRM_POLLS)
            next.sourceOk[s] = true;
        else if (t.sourceOk[s])
            emit(opts.notifySources !== false, sourceName(s) + " unreachable", st.error);
    }

    return {
        tracker: next,
        events: events
    };
}

function duration(s) {
    if (s < 3600)
        return Math.max(1, Math.round(s / 60)) + " min";
    if (s < 86400)
        return Math.floor(s / 3600) + " h";
    return Math.floor(s / 86400) + " d " + Math.floor((s % 86400) / 3600) + " h";
}

// ── Topology preview layout ──────────────────────────────────────────────────
//
// Positions for a small read-only map, in a w×h box with `pad` margin:
//   1. positions saved by clab-ui (annotations) when every node has one,
//      scaled to fit — the map then looks like the editor canvas;
//   2. otherwise tiers by role (super-spine → spine → leaf/router → hosts);
//   3. a circle when every node shares one tier (e.g. all default "pe").
var ROLE_TIER = {
    "super-spine": 0,
    "spine": 1,
    "dcgw": 1,
    "controller": 1,
    "cloud": 0,
    "leaf": 2,
    "pe": 2,
    "switch": 2,
    "bridge": 2,
    "pon": 2,
    "rgw": 2,
    "server": 3,
    "client": 3,
    "ue": 3
};

function layoutNodes(nodes, w, h, pad) {
    var out = {};
    var n = nodes.length;
    if (n === 0)
        return out;
    var i;

    var allPlaced = true;
    for (i = 0; i < n; i++)
        if (!nodes[i].position)
            allPlaced = false;
    if (allPlaced) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (i = 0; i < n; i++) {
            var p = nodes[i].position;
            minX = Math.min(minX, p.x);
            maxX = Math.max(maxX, p.x);
            minY = Math.min(minY, p.y);
            maxY = Math.max(maxY, p.y);
        }
        var spanX = Math.max(1, maxX - minX), spanY = Math.max(1, maxY - minY);
        var scale = Math.min((w - 2 * pad) / spanX, (h - 2 * pad) / spanY);
        var offX = (w - spanX * scale) / 2, offY = (h - spanY * scale) / 2;
        for (i = 0; i < n; i++)
            out[nodes[i].name] = {
                x: offX + (nodes[i].position.x - minX) * scale,
                y: offY + (nodes[i].position.y - minY) * scale
            };
        return out;
    }

    var tiers = {};
    var tierKeys = [];
    for (i = 0; i < n; i++) {
        var t = ROLE_TIER[nodes[i].role];
        if (t === undefined)
            t = 2;
        if (!tiers[t]) {
            tiers[t] = [];
            tierKeys.push(t);
        }
        tiers[t].push(nodes[i].name);
    }
    tierKeys.sort();

    if (tierKeys.length === 1 && n > 2) {
        var r = Math.min(w, h) / 2 - pad;
        for (i = 0; i < n; i++) {
            var a = -Math.PI / 2 + 2 * Math.PI * i / n;
            out[nodes[i].name] = {
                x: w / 2 + r * Math.cos(a),
                y: h / 2 + r * Math.sin(a)
            };
        }
        return out;
    }

    for (var k = 0; k < tierKeys.length; k++) {
        var row = tiers[tierKeys[k]];
        var y = tierKeys.length === 1 ? h / 2 : pad + k * (h - 2 * pad) / (tierKeys.length - 1);
        for (var j = 0; j < row.length; j++)
            out[row[j]] = {
                x: pad + (j + 0.5) * (w - 2 * pad) / row.length,
                y: y
            };
    }
    return out;
}

// ── What to show ─────────────────────────────────────────────────────────────
//
// The "show" setting: "both" (one list), "tabs" (containerlab | netlab tabs),
// "containerlab" or "netlab" only. "netlab" still reads containerlab: a netlab
// lab on containerlab takes its node list from there.
// ("tabs" was a separate mode; the filter chips replaced it, see normShow.)
var SHOW_MODES = [
    {
        id: "both",
        label: "containerlab + netlab"
    },
    {
        id: "containerlab",
        label: "only containerlab"
    },
    {
        id: "netlab",
        label: "only netlab"
    }
];

function sourceArgs(show) {
    return show === "containerlab" ? ["--no-netlab"] : [];
}

// tab: "containerlab" | "netlab", used only when show === "tabs".
function visibleLabs(snap, show, tab) {
    var labs = snap && snap.labs ? snap.labs : [];
    var want = show === "netlab" ? "netlab" : (show === "tabs" ? tab : "");
    if (want === "")
        return labs;
    return labs.filter(function (lab) {
        return lab.managedBy === want;
    });
}

function totalsOf(labs) {
    var t = {
        labs: labs.length,
        nodes: 0,
        running: 0,
        attention: 0
    };
    for (var i = 0; i < labs.length; i++) {
        t.nodes += labs[i].total;
        t.running += labs[i].running;
        if (labs[i].lifecycle === "partial" || labs[i].lifecycle === "stopped")
            t.attention++;
    }
    return t;
}

// Snapshot narrowed to what the user chose to see (panel counts, notifications).
// Tabs still count everything: both tabs are "shown".
function shownSnapshot(snap, show) {
    if (!snap || show === "tabs" || show === "both" || show === "containerlab")
        return snap;
    var labs = visibleLabs(snap, show, "");
    var out = {};
    for (var k in snap)
        out[k] = snap[k];
    out.labs = labs;
    out.totals = totalsOf(labs);
    return out;
}

// Full map geometry for a given width: positions plus the height, icon size
// and whether labels fit. Scales from a 3-node lab to a 100+-node fabric:
// tiers wrap into several rows once nodes would sit closer than MIN_SPACING,
// the height grows with the rows (capped; the popup scrolls), icons shrink and
// labels turn into hover-only when they would overlap.
var MIN_SPACING = 30;
var LABEL_SPACING = 56;
var MAX_MAP_HEIGHT = 480;

// maxHeight: cap for an inline map (default 480); the map page passes
// Infinity and lets the view scroll/zoom instead.
function mapLayout(nodes, w, maxHeight) {
    var cap = maxHeight === undefined ? MAX_MAP_HEIGHT : maxHeight;
    var pad = 22;
    var n = nodes.length;
    var out = {
        pos: {},
        height: 140,
        size: 26,
        labels: true,
        spacing: 80 // smallest gap between neighbours (label/zoom decisions)
    };
    if (n === 0)
        return out;
    var i;
    var inner = Math.max(1, w - 2 * pad);

    var allPlaced = true;
    for (i = 0; i < n; i++)
        if (!nodes[i].position)
            allPlaced = false;
    if (allPlaced) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (i = 0; i < n; i++) {
            minX = Math.min(minX, nodes[i].position.x);
            maxX = Math.max(maxX, nodes[i].position.x);
            minY = Math.min(minY, nodes[i].position.y);
            maxY = Math.max(maxY, nodes[i].position.y);
        }
        var aspect = Math.max(1, maxY - minY) / Math.max(1, maxX - minX);
        out.height = Math.max(140, Math.min(cap, inner * aspect + 2 * pad));
        var spacing = Math.sqrt(inner * (out.height - 2 * pad) / n);
        out.size = Math.max(12, Math.min(26, spacing * 0.6));
        out.labels = spacing >= LABEL_SPACING;
        out.spacing = spacing;
        out.pos = layoutNodes(nodes, w, out.height, pad);
        return out;
    }

    // Rows: each tier, wrapped at perRow; one tier > 12 nodes = a grid.
    var perRow = Math.max(1, Math.floor(inner / MIN_SPACING));
    var tiers = {}, keys = [];
    for (i = 0; i < n; i++) {
        var t = ROLE_TIER[nodes[i].role];
        if (t === undefined)
            t = 2;
        if (!tiers[t]) {
            tiers[t] = [];
            keys.push(t);
        }
        tiers[t].push(nodes[i].name);
    }
    keys.sort();
    if (keys.length === 1 && n > 2 && n <= 12) {
        out.height = 180;
        out.pos = layoutNodes(nodes, w, out.height, pad);
        return out;
    }
    var rows = [];
    for (var k = 0; k < keys.length; k++) {
        var tier = tiers[keys[k]];
        var limit = keys.length === 1 ? Math.min(perRow, Math.ceil(Math.sqrt(n * 2))) : perRow;
        // Even rows (11/11/10, not 14/14/4) so no tier ends in a stray stub.
        var chunk = Math.ceil(tier.length / Math.ceil(tier.length / limit));
        for (var s = 0; s < tier.length; s += chunk)
            rows.push(tier.slice(s, s + chunk));
    }
    var minSpace = Infinity;
    for (var r = 0; r < rows.length; r++)
        minSpace = Math.min(minSpace, inner / rows[r].length);
    out.labels = minSpace >= LABEL_SPACING;
    out.spacing = minSpace;
    out.size = Math.max(12, Math.min(26, minSpace * 0.7));
    var gap = out.labels ? 50 : Math.max(26, out.size + 12);
    out.height = Math.max(140, Math.min(cap, 2 * pad + (rows.length - 1) * gap));
    var step = rows.length > 1 ? (out.height - 2 * pad) / (rows.length - 1) : 0;
    for (r = 0; r < rows.length; r++)
        for (var j = 0; j < rows[r].length; j++)
            out.pos[rows[r][j]] = {
                x: pad + (j + 0.5) * inner / rows[r].length,
                y: rows.length === 1 ? out.height / 2 : pad + r * step
            };
    return out;
}

// ── Pinned labs ──────────────────────────────────────────────────────────────
//
// Pins are lab ids (path-based, so they survive a redeploy). With pins, the
// pill / panel item shows just those labs; pinned labs also sort first.

function isPinned(pins, id) {
    return (pins || []).indexOf(id) >= 0;
}

function togglePin(pins, id) {
    var out = (pins || []).slice();
    var i = out.indexOf(id);
    if (i >= 0)
        out.splice(i, 1);
    else
        out.push(id);
    return out;
}

// Display name for a pinned lab that isn't in the snapshot (stopped/gone).
function nameFromId(id) {
    var s = String(id).replace(/^remote:[^:]*:/, "");
    var path;
    if (s.indexOf("clab:") === 0)
        path = s.slice(5);
    else if (s.indexOf("netlab:") === 0)
        path = s.slice(s.indexOf(":", 7) + 1);
    else
        path = s;
    var base = path.replace(/\/+$/, "").split("/").pop() || path;
    return base.replace(/\.clab\.ya?ml$/, "").replace(/^name:/, "");
}

// [{id, name, present, running, total, lifecycle}] in pin order.
function pinnedSegments(snap, pins) {
    var labs = snap && snap.labs ? snap.labs : [];
    var out = [];
    for (var i = 0; i < (pins || []).length; i++) {
        var lab = null;
        for (var j = 0; j < labs.length; j++)
            if (labs[j].id === pins[i])
                lab = labs[j];
        out.push(lab ? {
            id: lab.id,
            name: lab.name,
            present: true,
            running: lab.running,
            total: lab.total,
            nodesKnown: lab.nodesKnown,
            lifecycle: lab.lifecycle
        } : {
            id: pins[i],
            name: nameFromId(pins[i]),
            present: false,
            running: 0,
            total: 0,
            nodesKnown: true,
            lifecycle: "gone"
        });
    }
    return out;
}

function segmentText(seg) {
    if (!seg.present)
        return seg.name + " —";
    if (!seg.nodesKnown)
        return seg.name + " " + (seg.lifecycle === "running" ? "up" : seg.lifecycle);
    return seg.name + " " + seg.running + "/" + seg.total;
}

// Stable: pinned labs first (in their existing order), then the rest.
function pinnedFirst(labs, pins) {
    var a = [], b = [];
    for (var i = 0; i < labs.length; i++)
        (isPinned(pins, labs[i].id) ? a : b).push(labs[i]);
    return a.concat(b);
}

// ── Flat row model for the virtualized list ──────────────────────────────────
//
// The popup is one ListView over rows: a "lab" row per lab, followed by "node"
// rows when that lab is expanded. Rows carry only a key; delegates look their
// data up in `byKey`, so a refresh re-binds just the visible delegates.
// syncModel() applies the new rows to a ListModel in place (no reset), which
// keeps scroll position and hover state across refreshes — the list stays
// cheap at 700+ nodes because only on-screen delegates exist.

var AUTO_EXPAND_MAX = 30; // problem labs start expanded, unless they are huge

function normShow(show) {
    return show === "tabs" ? "both" : (show || "both");
}

function labMatches(q, lab) {
    return lab.name.toLowerCase().indexOf(q) >= 0 || (lab.host || "").toLowerCase().indexOf(q) >= 0;
}

// "down" matches every node that isn't running (find the broken ones in a
// 700-node lab); otherwise name, kind, IP, image, state and status.
function nodeMatches(q, node) {
    if (q === "down")
        return !node.running;
    return [node.name, node.kind, node.ipv4, node.ipv6, node.image, node.state, node.status].some(function (v) {
        return v && String(v).toLowerCase().indexOf(q) >= 0;
    });
}

// o: {show, filter ("all"|"containerlab"|"netlab"), query, expanded {id: bool}, pins}
function rowsFor(snap, o) {
    var show = normShow(o.show);
    var labs = snap && snap.labs ? snap.labs : [];
    var counts = {
        all: 0,
        containerlab: 0,
        netlab: 0
    };
    var q = (o.query || "").trim().toLowerCase();
    var rows = [], byKey = {};
    var ordered = pinnedFirst(labs, o.pins || []);

    for (var i = 0; i < ordered.length; i++) {
        var lab = ordered[i];
        if (show !== "both" && lab.managedBy !== show)
            continue;
        var nodes = lab.nodes;
        var labHit = q === "" || labMatches(q, lab);
        if (q !== "" && !labHit) {
            nodes = lab.nodes.filter(function (n) {
                return nodeMatches(q, n);
            });
            if (nodes.length === 0)
                continue;
        }
        counts.all++;
        counts[lab.managedBy] = (counts[lab.managedBy] || 0) + 1;
        if (o.filter && o.filter !== "all" && lab.managedBy !== o.filter)
            continue;

        var user = o.expanded ? o.expanded[lab.id] : undefined;
        var auto = (lab.lifecycle === "partial" || lab.lifecycle === "stopped") && lab.total <= AUTO_EXPAND_MAX;
        // A search that matched nodes (not the lab) always shows them.
        var open = user !== undefined ? user : (auto || (q !== "" && !labHit));
        var key = "L" + lab.id;
        rows.push({
            key: key,
            type: "lab"
        });
        byKey[key] = {
            lab: lab,
            expanded: open,
            shown: nodes.length
        };
        if (!open)
            continue;
        for (var j = 0; j < nodes.length; j++) {
            var nk = "N" + lab.id + "/" + nodes[j].name;
            rows.push({
                key: nk,
                type: "node"
            });
            byKey[nk] = {
                lab: lab,
                node: nodes[j]
            };
        }
    }
    return {
        rows: rows,
        byKey: byKey,
        counts: counts
    };
}

// Make `model` (a ListModel of {key, type}) equal `rows`, touching only what
// changed. O(n) when the order is unchanged (the normal refresh).
function syncModel(model, rows) {
    var want = {};
    for (var i = 0; i < rows.length; i++)
        want[rows[i].key] = true;
    for (i = model.count - 1; i >= 0; i--)
        if (!want[model.get(i).key])
            model.remove(i);
    for (i = 0; i < rows.length; i++) {
        if (i < model.count && model.get(i).key === rows[i].key)
            continue;
        var found = -1;
        for (var j = i + 1; j < model.count; j++)
            if (model.get(j).key === rows[i].key) {
                found = j;
                break;
            }
        if (found >= 0)
            model.move(found, i, 1);
        else
            model.insert(i, rows[i]);
    }
}

// Lab counts per owner for the filter chips (show setting + search applied,
// chip filter not), kept separate from rowsFor to avoid a binding loop.
function countsFor(snap, show, query) {
    var s = normShow(show);
    var q = (query || "").trim().toLowerCase();
    var c = {
        all: 0,
        containerlab: 0,
        netlab: 0
    };
    var labs = snap && snap.labs ? snap.labs : [];
    for (var i = 0; i < labs.length; i++) {
        var lab = labs[i];
        if (s !== "both" && lab.managedBy !== s)
            continue;
        if (q !== "" && !labMatches(q, lab) && !lab.nodes.some(function (n) {
            return nodeMatches(q, n);
        }))
            continue;
        c.all++;
        c[lab.managedBy] = (c[lab.managedBy] || 0) + 1;
    }
    return c;
}
