// Tests for the shared presentation/notification logic in Labs.js.
// Run: node tests/labs.test.js   (part of `nix flake check`)
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");

// Labs.js is a QML JS library; drop the pragma and expose its functions.
const src = fs.readFileSync(path.join(__dirname, "../package/contents/code/Labs.js"), "utf8").replace(/^\.pragma library$/m, "");
const Labs = new Function(src + "; return { q, parse, summaryText, badgeText, lifecycleText, memoryText, bytes, newTracker, trackEvents, duration, layoutNodes, mapLayout, mapGraph, togglePin, pinnedSegments, segmentText, pinnedFirst, nameFromId, rowsFor, syncModel, visibleLabs, shownSnapshot, sourceArgs, openArgs, shellArgs, fileUrl, nodeOpArgs, labOpArgs, stopArgs, deployArgs, captureArgs, webUrl, linkKey, linkRates, bitRate, linkText };")();

let failed = 0;
function test(name, fn) {
    try {
        fn();
        console.log("ok   " + name);
    } catch (e) {
        failed++;
        console.log("FAIL " + name + "\n     " + e.message);
    }
}

function snap(nodesUp, extra) {
    return {
        schemaVersion: 1,
        labs: [Object.assign({
            id: "clab:/l/a.clab.yml",
            name: "a",
            running: nodesUp.filter(Boolean).length,
            total: nodesUp.length,
            uptimeSeconds: 600,
            nodes: nodesUp.map((up, i) => ({name: "n" + i, running: up, state: up ? "running" : "exited", status: up ? "Up" : "Exited (137)"}))
        }, extra || {})]
    };
}
const opts = {notifyNodeDown: true, reminderHours: 0};

function run(snaps, o) {
    let tracker = Labs.newTracker();
    const all = [];
    for (const s of snaps) {
        const r = Labs.trackEvents(tracker, s, o || opts);
        tracker = r.tracker;
        all.push(r.events);
    }
    return all;
}

test("shell quoting survives single quotes", () => {
    assert.strictEqual(Labs.q("it's"), "'it'\\''s'");
});

test("parse rejects garbage and wrong schema", () => {
    assert.strictEqual(Labs.parse("nope"), null);
    assert.strictEqual(Labs.parse('{"schemaVersion":2}'), null);
    assert.ok(Labs.parse('{"schemaVersion":1,"labs":[]}'));
});

test("node down needs two consecutive polls", () => {
    const ev = run([snap([true, true]), snap([true, false]), snap([true, false])]);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 1]);
    assert.strictEqual(ev[2][0].title, "n1 is down");
});

test("one flaky poll is ignored", () => {
    const ev = run([snap([true]), snap([false]), snap([true]), snap([true])]);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 0, 0]);
});

test("a node that was never up does not notify", () => {
    const ev = run([snap([false]), snap([false]), snap([false])]);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 0]);
});

test("down is reported once, not every poll", () => {
    const ev = run([snap([true]), snap([false]), snap([false]), snap([false])]);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 1, 0]);
});

test("notifyNodeDown off stays quiet", () => {
    const ev = run([snap([true]), snap([false]), snap([false])], {notifyNodeDown: false, reminderHours: 0});
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 0]);
});

test("reminder fires once after the threshold, not on first snapshot", () => {
    const o = {notifyNodeDown: true, reminderHours: 2};
    const young = snap([true], {uptimeSeconds: 3600});
    const old = snap([true], {uptimeSeconds: 3 * 3600});
    const ev = run([young, old, old], o);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 1, 0]);
    assert.match(ev[1][0].body, /Up for 3 h/);
});

test("already-old lab at startup is not nagged", () => {
    const o = {notifyNodeDown: true, reminderHours: 2};
    const old = snap([true], {uptimeSeconds: 5 * 3600});
    assert.deepStrictEqual(run([old, old], o).map(e => e.length), [0, 0]);
});

test("formatting", () => {
    assert.strictEqual(Labs.bytes(1610612736), "1.5 GiB");
    assert.strictEqual(Labs.bytes(536870912), "512 MiB");
    assert.strictEqual(Labs.memoryText({memoryBytes: 1073741824, memoryCoverage: "partial"}), "≥ 1.0 GiB");
    assert.strictEqual(Labs.duration(90000), "1 d 1 h");
    assert.strictEqual(Labs.badgeText({managedBy: "netlab", providers: ["containerlab"]}), "netlab · via clab");
    assert.strictEqual(Labs.summaryText({labs: 0}), "No labs running");
});


test("node disappearing from a live lab notifies after two polls", () => {
    const full = snap([true, true]);
    const shrunk = snap([true]);
    shrunk.labs[0].total = 1;
    const ev = run([full, shrunk, shrunk, shrunk]);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 1, 0]);
    assert.strictEqual(ev[2][0].title, "n1 disappeared");
});

test("whole lab torn down is not an incident", () => {
    const empty = {schemaVersion: 1, labs: []};
    assert.deepStrictEqual(run([snap([true]), empty, empty]).map(e => e.length), [0, 0, 0]);
});

test("source that worked, then fails twice → unreachable once", () => {
    const ok = {schemaVersion: 1, labs: [], sources: {"remote:srv": {available: true, error: ""}}};
    const bad = {schemaVersion: 1, labs: [], sources: {"remote:srv": {available: false, error: "unreachable: timed out"}}};
    const ev = run([ok, bad, bad, bad, ok, bad, bad]);
    assert.deepStrictEqual(ev.map(e => e.length), [0, 0, 1, 0, 0, 0, 1]);
    assert.strictEqual(ev[2][0].title, "srv unreachable");
});

test("source failing from the start stays quiet", () => {
    const bad = {schemaVersion: 1, labs: [], sources: {netlab: {available: false, error: "boom"}}};
    assert.deepStrictEqual(run([bad, bad, bad]).map(e => e.length), [0, 0, 0]);
});


test("layout: saved positions are scaled into the box", () => {
    const pos = Labs.layoutNodes([
        {name: "a", position: {x: 100, y: 0}},
        {name: "b", position: {x: 300, y: 200}}
    ], 220, 220, 10);
    assert.deepStrictEqual(pos.a, {x: 10, y: 10});
    assert.deepStrictEqual(pos.b, {x: 210, y: 210});
});

test("layout: tiers by role, spines above leaves", () => {
    const pos = Labs.layoutNodes([
        {name: "l1", role: "leaf"}, {name: "s1", role: "spine"}, {name: "l2", role: "leaf"}, {name: "h", role: "client"}
    ], 400, 200, 20);
    assert.ok(pos.s1.y < pos.l1.y && pos.l1.y === pos.l2.y && pos.l1.y < pos.h.y);
    assert.ok(pos.l1.x < pos.l2.x);
});

test("layout: single tier becomes a circle, every node inside the box", () => {
    const nodes = ["a", "b", "c", "d", "e"].map(name => ({name, role: "pe"}));
    const pos = Labs.layoutNodes(nodes, 300, 200, 16);
    for (const n of nodes) {
        assert.ok(pos[n.name].x >= 16 && pos[n.name].x <= 284, n.name);
        assert.ok(pos[n.name].y >= 16 && pos[n.name].y <= 184, n.name);
    }
    assert.strictEqual(new Set(Object.values(pos).map(p => p.x.toFixed(1) + p.y.toFixed(1))).size, 5);
});


test("show modes filter by owner", () => {
    const s = {schemaVersion: 1, labs: [
        {managedBy: "containerlab", total: 2, running: 2, lifecycle: "running"},
        {managedBy: "netlab", total: 3, running: 1, lifecycle: "partial"}
    ]};
    assert.strictEqual(Labs.visibleLabs(s, "both", "").length, 2);
    assert.strictEqual(Labs.visibleLabs(s, "tabs", "netlab")[0].managedBy, "netlab");
    assert.strictEqual(Labs.visibleLabs(s, "netlab", "").length, 1);
    assert.deepStrictEqual(Labs.shownSnapshot(s, "netlab").totals, {labs: 1, nodes: 3, running: 1, attention: 1});
    assert.strictEqual(Labs.shownSnapshot(s, "tabs"), s);
    assert.deepStrictEqual(Labs.sourceArgs("containerlab"), ["--no-netlab"]);
    assert.deepStrictEqual(Labs.sourceArgs("netlab"), []);
});


test("big fabric: tiers wrap, map grows, labels become hover-only", () => {
    const nodes = [{name: "ss1", role: "super-spine"}];
    for (let i = 0; i < 4; i++) nodes.push({name: "sp" + i, role: "spine"});
    for (let i = 0; i < 32; i++) nodes.push({name: "l" + i, role: "leaf"});
    for (let i = 0; i < 64; i++) nodes.push({name: "s" + i, role: "server"});
    const m = Labs.mapLayout(nodes, 480);
    assert.strictEqual(Object.keys(m.pos).length, 101);
    assert.ok(m.height > 180 && m.height <= 480, "height " + m.height);
    assert.strictEqual(m.labels, false);
    assert.ok(m.size >= 12 && m.size < 26);
    // no two nodes closer than MIN_SPACING on the same row
    const byRow = {};
    for (const p of Object.values(m.pos)) (byRow[p.y.toFixed(1)] = byRow[p.y.toFixed(1)] || []).push(p.x);
    for (const xs of Object.values(byRow)) {
        xs.sort((a, b) => a - b);
        for (let i = 1; i < xs.length; i++) assert.ok(xs[i] - xs[i - 1] >= 29.9, "spacing " + (xs[i] - xs[i - 1]));
    }
});

test("small lab keeps labels and full-size icons", () => {
    const m = Labs.mapLayout([{name: "a", role: "spine"}, {name: "b", role: "leaf"}, {name: "c", role: "leaf"}], 480);
    assert.strictEqual(m.labels, true);
    assert.strictEqual(m.size, 26);
    assert.strictEqual(m.height, 140);
});

test("mapGraph: ends outside the lab become endpoints, links keep state", () => {
    const lab = {
        nodes: [{name: "srv1", running: true}, {name: "srv2", running: true}],
        links: [
            {a: "srv1", aIf: "eth1", z: "srv2", zIf: "eth1", up: false},
            {a: "srv1", aIf: "eth2", z: "host", zIf: "veth-srv1", up: true},
            {a: "srv2", aIf: "eth2", z: "macvlan", zIf: "enp3s0"},
            {a: "srv2", aIf: "eth3", z: "macvlan", zIf: "enp3s0"}
        ]
    };
    const g = Labs.mapGraph(lab);
    assert.deepStrictEqual(g.nodes.map(n => n.name), ["srv1", "srv2", "host:veth-srv1", "macvlan:enp3s0"]);
    const ext = g.nodes[2];
    assert.strictEqual(ext.external, true);
    assert.strictEqual(ext.label, "veth-srv1");
    assert.strictEqual(ext.kind, "host");
    assert.deepStrictEqual(g.links.map(l => [l.a, l.z, l.up]), [["srv1", "srv2", false], ["srv1", "host:veth-srv1", true], ["srv2", "macvlan:enp3s0", undefined], ["srv2", "macvlan:enp3s0", undefined]]);
    assert.strictEqual(lab.links[1].z, "host"); // snapshot untouched
    assert.strictEqual(Labs.mapGraph({nodes: lab.nodes, links: []}).nodes, lab.nodes);
    // endpoints sit on the bottom tier, below servers
    const m = Labs.mapLayout([{name: "sp", role: "spine"}, {name: "s", role: "server"}, ext], 480);
    assert.ok(m.pos["host:veth-srv1"].y > m.pos.s.y);
});

test("40 same-role nodes become a grid, not a circle", () => {
    const nodes = Array.from({length: 40}, (_, i) => ({name: "r" + i, role: "pe"}));
    const m = Labs.mapLayout(nodes, 480);
    const rows = new Set(Object.values(m.pos).map(p => p.y.toFixed(1)));
    assert.ok(rows.size >= 4, "rows " + rows.size);
});


test("pins: toggle, segments, names for stopped labs, pinned first", () => {
    let pins = Labs.togglePin([], "clab:/l/fab/fabric.clab.yml");
    pins = Labs.togglePin(pins, "netlab:default:/n/ospf");
    assert.deepStrictEqual(pins, ["clab:/l/fab/fabric.clab.yml", "netlab:default:/n/ospf"]);
    assert.deepStrictEqual(Labs.togglePin(pins, "netlab:default:/n/ospf"), ["clab:/l/fab/fabric.clab.yml"]);
    const s = {schemaVersion: 1, labs: [
        {id: "x", name: "x", running: 1, total: 1, nodesKnown: true, lifecycle: "running"},
        {id: "netlab:default:/n/ospf", name: "ospf", running: 2, total: 3, nodesKnown: true, lifecycle: "partial"}
    ]};
    const segs = Labs.pinnedSegments(s, pins);
    assert.strictEqual(Labs.segmentText(segs[0]), "fabric —");  // not running → greyed name from the path
    assert.strictEqual(Labs.segmentText(segs[1]), "ospf 2/3");
    assert.strictEqual(segs[1].lifecycle, "partial");
    assert.deepStrictEqual(Labs.pinnedFirst(s.labs, pins).map(l => l.name), ["ospf", "x"]);
    assert.strictEqual(Labs.nameFromId("remote:srv:clab:/srv/dc/dc.clab.yml"), "dc");
    assert.strictEqual(Labs.nameFromId("netlab:vm:/home/u/netlab/evpn-vms/"), "evpn-vms");
});

const projectSrc = fs.readFileSync(path.join(__dirname, "../package/contents/code/ProjectInfo.js"), "utf8").replace(/^\.pragma library$/m, "");
const Project = new Function(projectSrc + "; return { name, author, currentVersion, count, contributors, parseVersion, releaseStatus, releaseVersion, references };")();

test("ProjectInfo: parse semver and compare release status", () => {
    assert.strictEqual(Project.releaseStatus("0.1.0", "0.1.0"), "Up to date");
    assert.strictEqual(Project.releaseStatus("0.1.0", "0.2.0"), "Update available");
    assert.strictEqual(Project.releaseStatus("0.2.0", "0.1.0"), "Newer than latest release");
    assert.strictEqual(Project.releaseStatus("0.1.0-beta", "0.1.0"), "Update available");
});

test("ProjectInfo: count parser handles shields json", () => {
    assert.strictEqual(Project.count('{"value":"42"}'), "42");
    assert.strictEqual(Project.count('{"value":"1.2k"}'), "1.2k");
    assert.strictEqual(Project.count('{"isError":true}'), "");
});

test("ProjectInfo: references include containerlab and netlab", () => {
    const ids = Project.references.map(r => r.id);
    assert.ok(ids.includes("containerlab"));
    assert.ok(ids.includes("netlab"));
});


// Minimal ListModel stand-in that records every mutation.
function fakeModel(keys) {
    const items = keys.map(k => ({key: k, type: "x"}));
    const ops = [];
    return {
        items, ops,
        get count() { return items.length; },
        get: i => items[i],
        remove(i) { ops.push("remove"); items.splice(i, 1); },
        insert(i, r) { ops.push("insert"); items.splice(i, 0, r); },
        move(f, t) { ops.push("move"); const [x] = items.splice(f, 1); items.splice(t, 0, x); }
    };
}

function lab(id, managedBy, nodes, extra) {
    return Object.assign({id, name: id, managedBy, lifecycle: "running", running: nodes.length, total: nodes.length,
        nodes: nodes.map(n => ({name: n, kind: "srl", ipv4: "10.0.0.1", running: true}))}, extra || {});
}

test("rows: collapsed labs, expand on demand, pinned first, counts", () => {
    const s = {labs: [lab("a", "containerlab", ["n1", "n2"]), lab("b", "netlab", ["r1"])]};
    let r = Labs.rowsFor(s, {pins: ["b"]});
    assert.deepStrictEqual(r.rows.map(x => x.key), ["Lb", "La"]);
    assert.deepStrictEqual(r.counts, {all: 2, containerlab: 1, netlab: 1});
    r = Labs.rowsFor(s, {expanded: {a: true}});
    assert.deepStrictEqual(r.rows.map(x => x.key), ["La", "Na/n1", "Na/n2", "Lb"]);
    assert.strictEqual(r.byKey["Na/n2"].node.name, "n2");
    assert.deepStrictEqual(Labs.rowsFor(s, {filter: "netlab"}).rows.map(x => x.key), ["Lb"]);
});

test("rows: problem labs auto-expand unless huge; user choice wins", () => {
    const small = lab("s", "containerlab", ["x", "y"], {lifecycle: "partial"});
    const big = lab("h", "containerlab", Array.from({length: 40}, (_, i) => "n" + i), {lifecycle: "partial"});
    let r = Labs.rowsFor({labs: [small, big]}, {});
    assert.deepStrictEqual(r.rows.map(x => x.key), ["Ls", "Ns/x", "Ns/y", "Lh"]);
    r = Labs.rowsFor({labs: [small]}, {expanded: {s: false}});
    assert.deepStrictEqual(r.rows.map(x => x.key), ["Ls"]);
});

test("rows: search finds nodes by name/kind/IP and shows only matches", () => {
    const s = {labs: [lab("fab", "containerlab", ["leaf1", "spine1"]), lab("other", "netlab", ["r1"])]};
    const r = Labs.rowsFor(s, {query: "spine"});
    assert.deepStrictEqual(r.rows.map(x => x.key), ["Lfab", "Nfab/spine1"]);
    assert.deepStrictEqual(Labs.rowsFor(s, {query: "other"}).rows.map(x => x.key), ["Lother"]);
    assert.strictEqual(Labs.rowsFor(s, {query: "nomatch"}).rows.length, 0);
});

test("syncModel: unchanged refresh touches nothing; changes are minimal", () => {
    const keys = Array.from({length: 700}, (_, i) => "k" + i);
    let m = fakeModel(keys);
    Labs.syncModel(m, keys.map(k => ({key: k, type: "x"})));
    assert.strictEqual(m.ops.length, 0);
    const next = keys.slice(0, 350).concat(["new"], keys.slice(351));
    Labs.syncModel(m, next.map(k => ({key: k, type: "x"})));
    assert.deepStrictEqual(m.items.map(x => x.key), next);
    assert.ok(m.ops.length <= 2, m.ops.join());
    m = fakeModel(["a", "b", "c"]);
    Labs.syncModel(m, ["c", "a", "b"].map(k => ({key: k, type: "x"})));
    assert.deepStrictEqual(m.items.map(x => x.key), ["c", "a", "b"]);
});


test("search 'down' finds non-running nodes, state/status searchable", () => {
    const s = {labs: [{id: "a", name: "a", managedBy: "containerlab", lifecycle: "partial", running: 1, total: 2,
        nodes: [{name: "n1", kind: "srl", running: true, state: "running"}, {name: "n2", kind: "srl", running: false, state: "exited", status: "Exited (137)"}]}]};
    assert.deepStrictEqual(Labs.rowsFor(s, {query: "down"}).rows.map(r => r.key), ["La", "Na/n2"]);
    assert.deepStrictEqual(Labs.rowsFor(s, {query: "137"}).rows.map(r => r.key), ["La", "Na/n2"]);
});

test("map: mostly placed labs keep their layout, new nodes go below", () => {
    const nodes = [
        {name: "s1", role: "spine", position: {x: 0, y: 0}},
        {name: "s2", role: "spine", position: {x: 200, y: 0}},
        {name: "l1", role: "leaf", position: {x: 0, y: 100}},
        {name: "new", role: "leaf"}
    ];
    const m = Labs.mapLayout(nodes, 480);
    assert.ok(m.pos.s2.x > m.pos.s1.x);
    assert.ok(m.pos.l1.y > m.pos.s1.y);
    assert.ok(m.pos.new.y > m.pos.l1.y, JSON.stringify(m.pos));
    assert.strictEqual(nodes[3].position, undefined); // input untouched
    // Under half placed: tiers, as before.
    const few = [{name: "a", role: "spine", position: {x: 0, y: 0}}, {name: "b", role: "leaf"}, {name: "c", role: "leaf"}];
    const t = Labs.mapLayout(few, 480);
    assert.ok(t.pos.b.y > t.pos.a.y);
});

test("fileUrl: POSIX and Windows paths", () => {
    assert.strictEqual(Labs.fileUrl("/nix/store/x/icons/nodes/pe.svg"), "file:///nix/store/x/icons/nodes/pe.svg");
    assert.strictEqual(Labs.fileUrl("C:\\Users\\me\\AppData\\pe.svg"), "file:///C:/Users/me/AppData/pe.svg");
    assert.strictEqual(Labs.fileUrl("/home/me/my labs/a b.svg"), "file:///home/me/my%20labs/a%20b.svg");
    assert.strictEqual(Labs.fileUrl(""), "");
});

test("open/shell args: local, API remote, ssh host", () => {
    const node = {name: "s1", kind: "nokia_srlinux", container: "clab-fab-s1"};
    const local = {managedBy: "containerlab", topologyFile: "/l/fab.clab.yml", dir: "/l"};
    assert.deepStrictEqual(Labs.openArgs(local), ["open", "containerlab", "/l/fab.clab.yml", "/l"]);
    assert.deepStrictEqual(Labs.shellArgs(local, node, "exec"), ["shell", "exec", "nokia_srlinux", "clab-fab-s1", "s1", "/l"]);
    const api = {managedBy: "netlab", remote: true, uiUrl: "http://srv:8000"};
    assert.deepStrictEqual(Labs.openArgs(api), ["open", "netlab", "", "", "--remote", "--ui", "http://srv:8000"]);
    const ssh = Object.assign({remote: true, via: "ssh", conn: "box"}, local);
    assert.deepStrictEqual(Labs.openArgs(ssh), ["open", "containerlab", "/l/fab.clab.yml", "/l", "--via", "box"]);
    assert.deepStrictEqual(Labs.shellArgs(ssh, node, "ssh").slice(-2), ["--via", "box"]);
    const wsl = Object.assign({}, ssh, {via: "wsl", conn: "wsl"});
    assert.deepStrictEqual(Labs.shellArgs(wsl, node, "exec").slice(-2), ["--via", "wsl"]);
});

test("action args: node ops, lab ops, stop modes, deploy, capture", () => {
    const lab = {id: "clab:/l/fab.clab.yml", fingerprint: "f1", conn: "box"};
    assert.deepStrictEqual(Labs.nodeOpArgs(lab, {name: "leaf2"}, "start"), ["node", "start", lab.id, "leaf2", "f1"]);
    assert.deepStrictEqual(Labs.labOpArgs(lab, "redeploy"), ["lab", "redeploy", lab.id, "f1"]);
    assert.deepStrictEqual(Labs.stopArgs(lab, "stop"), ["stop", lab.id, "f1"]);
    assert.deepStrictEqual(Labs.stopArgs(lab, "clean"), ["stop", lab.id, "f1", "clean"]);
    assert.deepStrictEqual(Labs.deployArgs({topologyFile: "/l/x.clab.yml"}), ["deploy", "/l/x.clab.yml"]);
    const node = {container: "clab-fab-leaf1"};
    assert.deepStrictEqual(Labs.captureArgs(lab, node, "e1-1"), ["capture", "clab-fab-leaf1", "e1-1"]);
    assert.deepStrictEqual(Labs.captureArgs(Object.assign({via: "ssh"}, lab), node, "e1-1").slice(-2), ["--via", "box"]);
    assert.deepStrictEqual(Labs.sourceArgs("both", ["~/labs", " ", "/srv/x"]), ["--scan", "~/labs", "--scan", "/srv/x"]);
    assert.deepStrictEqual(Labs.sourceArgs("containerlab"), ["--no-netlab"]);
});

test("web URLs", () => {
    assert.strictEqual(Labs.webUrl({ipv4: "172.20.20.2"}, 443), "https://172.20.20.2");
    assert.strictEqual(Labs.webUrl({ipv4: "172.20.20.2"}, 8080), "http://172.20.20.2:8080");
    assert.strictEqual(Labs.webUrl({ipv6: "3fff::2"}, 80), "http://[3fff::2]");
});

test("link rates from two snapshots, text", () => {
    const link = (rx, tx) => ({a: "s1", aIf: "e1-1", z: "l1", zIf: "e1-1", up: true, bytes: {end: "s1", rx: rx, tx: tx}});
    const snap = (t, l) => ({observedAt: t, labs: [{id: "L", links: [l]}]});
    const r = Labs.linkRates(snap("2026-09-24T10:00:00Z", link(0, 0)), snap("2026-09-24T10:00:05Z", link(625000, 1250000)));
    const k = Labs.linkKey(link(0, 0));
    assert.deepStrictEqual(r.L[k], {rx: 1000000, tx: 2000000, end: "s1"});
    assert.strictEqual(Labs.bitRate(r.L[k].tx), "2.0 Mb/s");
    assert.strictEqual(Labs.bitRate(950), "950 b/s");
    assert.strictEqual(Labs.linkText(link(0, 0), r.L[k]), "s1:e1-1 ↔ l1:e1-1 · up · ↑ 2.0 Mb/s ↓ 1.0 Mb/s");
    // A node restart resets its counters: no negative rate.
    assert.deepStrictEqual(Labs.linkRates(snap("2026-09-24T10:00:00Z", link(9e9, 9e9)), snap("2026-09-24T10:00:05Z", link(1, 1))), {});
    assert.deepStrictEqual(Labs.linkRates(null, snap("x", link(1, 1))), {});
});

test("rows: only my labs, and the Not deployed group", () => {
    const lab = (id, mine) => ({id: id, name: id, managedBy: "containerlab", lifecycle: "running", running: 1, total: 1, mine: mine, nodes: [{name: "n", kind: "linux", running: true}]});
    const s = {labs: [lab("mine", true), lab("theirs", false)], undeployed: [
        {id: "file:/l/a.clab.yml", name: "bgp", managedBy: "containerlab", topologyFile: "/l/a.clab.yml", dir: "/l"},
        {id: "file:/n/topology.yml", name: "isis", managedBy: "netlab", topologyFile: "/n/topology.yml", dir: "/n"}
    ]};
    let m = Labs.rowsFor(s, {show: "both", onlyMine: true});
    assert.deepStrictEqual(m.rows.map(r => r.key), ["Lmine", "Hundeployed"]); // collapsed while labs run
    assert.strictEqual(m.byKey.Hundeployed.count, 2);
    m = Labs.rowsFor(s, {show: "both", expanded: {undeployed: true}});
    assert.deepStrictEqual(m.rows.map(r => r.type), ["lab", "lab", "header", "undeployed", "undeployed"]);
    assert.strictEqual(m.counts.all, 2); // chips count deployed labs only
    m = Labs.rowsFor(s, {show: "both", query: "isis"});
    assert.deepStrictEqual(m.rows.map(r => r.key), ["Hundeployed", "Ufile:/n/topology.yml"]);
    const shown = Labs.shownSnapshot(s, "both", true);
    assert.deepStrictEqual(shown.labs.map(l => l.id), ["mine"]);
    assert.strictEqual(shown.totals.labs, 1);
});

if (failed) {
    console.log(failed + " failed");
    process.exit(1);
}

