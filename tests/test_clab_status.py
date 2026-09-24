"""Snapshot tests for the backend, fed from saved containerlab/netlab output.

Run: python3 -m unittest discover -s tests   (or `nix flake check`)
"""

import importlib.machinery
import importlib.util
import json
import os
import re
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")
SCRIPT = os.path.join(HERE, "..", "package", "contents", "tools", "clab-status")

_loader = importlib.machinery.SourceFileLoader("clab_status", SCRIPT)
_spec = importlib.util.spec_from_loader("clab_status", _loader)
cs = importlib.util.module_from_spec(_spec)
_loader.exec_module(cs)

BOTH = {"containerlab": True, "netlab": True}


def fixture(name):
    data, err = cs.read_json_file(os.path.join(FIXTURES, name))
    assert err is None, err
    return data


def snapshot(clab="clab_empty.json", netlab="netlab_none.json", clab_error=None, netlab_error=None, enabled=BOTH):
    return cs.build_snapshot(
        None if clab_error else fixture(clab),
        clab_error,
        None if netlab_error else fixture(netlab),
        netlab_error,
        enabled,
    )


def by_name(snap, name):
    return [lab for lab in snap["labs"] if lab["name"] == name]


class EmptyHost(unittest.TestCase):
    def test_no_labs_is_not_an_error(self):
        snap = snapshot()
        self.assertEqual(snap["labs"], [])
        self.assertEqual(snap["totals"], {"labs": 0, "nodes": 0, "running": 0, "attention": 0})
        self.assertEqual(snap["sources"]["containerlab"], {"available": True, "error": ""})
        self.assertEqual(snap["sources"]["netlab"], {"available": True, "error": ""})

    def test_missing_tool_is_unavailable_not_failed(self):
        snap = snapshot(netlab_error="not-installed")
        self.assertEqual(snap["sources"]["netlab"], {"available": False, "error": ""})

    def test_tool_failure_is_reported(self):
        snap = snapshot(clab_error="permission denied")
        self.assertEqual(snap["sources"]["containerlab"], {"available": False, "error": "permission denied"})

    def test_disabled_backend_is_absent(self):
        snap = snapshot(enabled={"containerlab": True, "netlab": False})
        self.assertNotIn("netlab", snap["sources"])


class Mixed(unittest.TestCase):
    def setUp(self):
        self.snap = snapshot("clab_mixed.json", "netlab_mixed.json")

    def test_same_name_different_paths_stay_separate(self):
        lab1 = by_name(self.snap, "lab1")
        self.assertEqual(len(lab1), 2)
        self.assertEqual({lab["lifecycle"] for lab in lab1}, {"running", "stopped"})

    def test_netlab_on_clab_is_one_card(self):
        nl = by_name(self.snap, "nl")
        self.assertEqual(len(nl), 1)
        lab = nl[0]
        self.assertEqual(lab["managedBy"], "netlab")
        self.assertEqual(lab["providers"], ["containerlab"])
        self.assertEqual(lab["status"], "started")
        self.assertEqual((lab["running"], lab["total"]), (1, 2))
        self.assertEqual(lab["lifecycle"], "partial")

    def test_netlab_without_clab_side(self):
        (vm,) = by_name(self.snap, "vmlab")
        self.assertFalse(vm["nodesKnown"])
        self.assertEqual(vm["providers"], ["libvirt"])
        self.assertEqual(vm["lifecycle"], "starting")

    def test_node_fields(self):
        (dc,) = by_name(self.snap, "dc")
        leaf, spine = dc["nodes"]
        self.assertEqual(spine["name"], "spine1")
        self.assertEqual(spine["container"], "clab-dc-spine1")
        self.assertEqual(spine["ipv4"], "172.20.20.2")
        self.assertEqual(spine["ipv6"], "3fff:172:20:20::2")
        self.assertEqual(leaf["ipv6"], "")
        self.assertEqual(dc["dir"], "/home/u/labs/dc")

    def test_totals(self):
        t = self.snap["totals"]
        self.assertEqual(t["labs"], 5)
        self.assertEqual(t["nodes"], 6)
        self.assertEqual(t["running"], 4)
        # nl (partial) + the stopped lab1
        self.assertEqual(t["attention"], 2)


class Topology(unittest.TestCase):
    """Icons, colours, positions and links from the lab dir + annotations."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        os.environ["XDG_CACHE_HOME"] = os.path.join(self.tmp.name, "cache")
        self.addCleanup(os.environ.pop, "XDG_CACHE_HOME", None)
        root = self.tmp.name
        topo = os.path.join(root, "fab.clab.yml")
        open(topo, "w").close()
        os.makedirs(os.path.join(root, "clab-fab"))
        with open(os.path.join(root, "clab-fab", "topology-data.json"), "w") as f:
            json.dump(
                {
                    "nodes": {
                        "s1": {"labels": {"graph-icon": "spine", "graph-posX": "120", "graph-posY": "40.5"}},
                        "l1": {"labels": {"graph-posX": "1", "graph-posY": "2"}},
                        "br": {"labels": {"graph-posX": "nan", "graph-posY": "x"}},
                    },
                    "links": [
                        {
                            "endpoints": {
                                "a": {"node": "s1", "interface": "e1-1"},
                                "z": {"node": "l1", "interface": "e1-49"},
                            }
                        }
                    ],
                },
                f,
            )
        with open(topo + ".annotations.json", "w") as f:
            json.dump(
                {
                    "nodeAnnotations": [
                        {"id": "l1", "icon": "leaf", "iconColor": "#80b9d8", "position": {"x": 40, "y": 230}}
                    ]
                },
                f,
            )
        c = {"lab_name": "fab", "absLabPath": topo, "kind": "nokia_srlinux", "state": "running"}
        data = {
            "fab": [
                dict(c, name="clab-fab-s1"),
                dict(c, name="clab-fab-l1"),
                dict(c, name="clab-fab-br", kind="bridge"),
            ]
        }
        snap = cs.build_snapshot(data, None, {}, None, BOTH)
        self.lab = snap["labs"][0]
        self.nodes = {n["name"]: n for n in self.lab["nodes"]}

    def test_roles(self):
        self.assertEqual(self.nodes["s1"]["role"], "spine")  # graph-icon label
        self.assertEqual(self.nodes["l1"]["role"], "leaf")  # annotation wins
        self.assertEqual(self.nodes["br"]["role"], "bridge")  # kind fallback

    def test_default_colour_uses_shipped_icon(self):
        self.assertTrue(self.nodes["s1"]["icon"].endswith(os.path.join("icons", "nodes", "spine.svg")))
        self.assertTrue(os.path.isfile(self.nodes["s1"]["icon"]))

    def test_custom_colour_is_recoloured_copy(self):
        icon = self.nodes["l1"]["icon"]
        self.assertTrue(icon.startswith(os.environ["XDG_CACHE_HOME"]))
        with open(icon) as f:
            svg = f.read()
        self.assertIn("#80b9d8", svg)
        self.assertNotIn("#005aff", svg)

    def test_legacy_position_labels(self):
        self.assertEqual(self.nodes["s1"]["position"], {"x": 120.0, "y": 40.5})
        self.assertEqual(self.nodes["l1"]["position"], {"x": 40, "y": 230})  # annotation wins
        self.assertNotIn("position", self.nodes["br"])

    def test_position_and_links(self):
        self.assertEqual(self.nodes["l1"]["position"], {"x": 40, "y": 230})
        self.assertEqual(self.lab["links"], [{"a": "s1", "aIf": "e1-1", "z": "l1", "zIf": "e1-49"}])

    def test_missing_lab_dir_still_has_icons(self):
        snap = snapshot("clab_mixed.json")
        for lab in snap["labs"]:
            for n in lab["nodes"]:
                self.assertEqual(n["role"], "pe")
            self.assertEqual(lab["links"], [])


class Formats(unittest.TestCase):
    def test_legacy_containers_list(self):
        snap = snapshot("clab_legacy.json")
        (lab,) = snap["labs"]
        self.assertEqual(lab["name"], "old")
        self.assertEqual(lab["nodes"][0]["name"], "n1")

    def test_garbage_is_ignored(self):
        self.assertEqual(cs.normalize_clab(["not", "a", "dict"]), [])
        self.assertEqual(cs.netlab_instances({"warning": "x", "1": "bad"}), [])


if __name__ == "__main__":
    unittest.main()


class Details(unittest.TestCase):
    """--details: memory from docker stats, nodes from `netlab status -i`."""

    def setUp(self):
        detail = fixture("netlab_detail_vmlab.json")
        stats = cs.parse_docker_stats(
            '{"Name":"clab-dc-spine1","MemUsage":"1.5GiB / 31.2GiB"}\n'
            '{"Name":"clab-dc-leaf1","MemUsage":"512MiB / 31.2GiB"}\n'
            "not json\n"
        )
        self.asked = []

        def fetch_netlab(instance):
            self.asked.append(instance)
            return detail if instance == "vm1" else None

        self.snap = cs.build_snapshot(
            fixture("clab_mixed.json"),
            None,
            fixture("netlab_mixed.json"),
            None,
            BOTH,
            details=lambda labs: cs.add_details(labs, lambda: stats, fetch_netlab),
        )

    def test_parse_size(self):
        self.assertEqual(cs.parse_size("1.5GiB"), 1610612736)
        self.assertEqual(cs.parse_size("2kB"), 2000)
        self.assertEqual(cs.parse_size("512.0MiB"), 536870912)
        self.assertIsNone(cs.parse_size(""))
        self.assertIsNone(cs.parse_size("lots"))

    def test_only_unresolved_netlab_labs_are_queried(self):
        self.assertEqual(self.asked, ["vm1"])

    def test_netlab_nodes_from_detail(self):
        (vm,) = by_name(self.snap, "vmlab")
        self.assertTrue(vm["nodesKnown"])
        self.assertEqual([n["name"] for n in vm["nodes"]], ["r1", "r2"])  # unmanaged dropped
        self.assertEqual(vm["lifecycle"], "partial")
        r1 = vm["nodes"][0]
        self.assertEqual((r1["container"], r1["ipv4"], r1["provider"]), ("vmlab_r1", "192.168.121.101", "libvirt"))

    def test_memory(self):
        (dc,) = by_name(self.snap, "dc")
        self.assertEqual(dc["memoryBytes"], 1610612736 + 536870912)
        self.assertEqual(dc["memoryCoverage"], "full")
        (vm,) = by_name(self.snap, "vmlab")
        self.assertEqual(vm["memoryCoverage"], "partial")  # r2 is shut off
        (nl,) = by_name(self.snap, "nl")
        self.assertIsNone(nl["memoryBytes"])  # nothing measured is not zero
        self.assertEqual(nl["memoryCoverage"], "none")
        self.assertTrue(self.snap["details"])

    def test_without_details_no_memory_keys(self):
        snap = snapshot("clab_mixed.json", "netlab_mixed.json")
        self.assertFalse(snap["details"])
        self.assertNotIn("memoryBytes", snap["labs"][0])


class LinkState(unittest.TestCase):
    """--details: link up/down from each node's interface operstate."""

    def lab(self, links, stopped=()):
        nodes = [{"name": n, "container": f"clab-x-{n}", "running": n not in stopped} for n in ("a", "b", "c", "d")]
        return {"managedBy": "containerlab", "providers": ["containerlab"], "nodes": nodes, "links": links}

    def test_parse_operstates(self):
        self.assertEqual(cs.parse_operstates("lo unknown\neth1 up\nbroken\n"), {"lo": "unknown", "eth1": "up"})

    def test_up_down_and_unknown(self):
        states = {
            "clab-x-a": {"eth1": "up", "eth2": "up", "eth3": "up"},
            "clab-x-b": {"eth1": "up", "eth2": "lowerlayerdown"},
            "clab-x-c": None,  # no sh in the image
        }
        links = [
            {"a": "a", "aIf": "eth1", "z": "b", "zIf": "eth1"},  # both up
            {"a": "a", "aIf": "eth2", "z": "b", "zIf": "eth2"},  # peer shut
            {"a": "a", "aIf": "eth3", "z": "c", "zIf": "eth1"},  # c unreadable
            {"a": "b", "aIf": "eth1", "z": "d", "zIf": "eth1"},  # d stopped
            {"a": "a", "aIf": "eth3", "z": "host", "zIf": "veth-a"},  # outside end ignored
            {"a": "a", "aIf": "eth9", "z": "macvlan", "zIf": "enp3s0"},  # iface not found
        ]
        lab = self.lab(links, stopped=("d",))
        asked = []
        cs.add_link_state([lab], lambda c: asked.append(c) or states.get(c))
        self.assertEqual([link.get("up") for link in links], [True, False, None, False, True, None])
        self.assertNotIn("clab-x-d", asked)  # stopped nodes aren't exec'd into

    def test_netlab_on_vm_and_linkless_labs_skipped(self):
        r1 = {"name": "r1", "container": "r1", "running": True}
        vm = {"managedBy": "netlab", "providers": ["libvirt"], "nodes": [r1]}
        vm["links"] = [{"a": "r1", "aIf": "eth1", "z": "r2", "zIf": "eth1"}]
        bare = self.lab([])
        cs.add_link_state([vm, bare], lambda c: self.fail("asked " + c))

    def test_demo_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            import subprocess
            import sys

            subprocess.run([sys.executable, os.path.join(HERE, "demo.py"), d], check=True, capture_output=True)
            env = dict(
                os.environ,
                CLAB_WIDGET_CLAB_JSON=os.path.join(d, "clab.json"),
                CLAB_WIDGET_NETLAB_JSON=os.path.join(d, "netlab.json"),
                CLAB_WIDGET_IFACES_JSON=os.path.join(d, "ifaces.json"),
            )
            out = subprocess.run(
                [sys.executable, SCRIPT, "snapshot", "--details", "--no-remote"],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
        (fab,) = [lab for lab in json.loads(out.stdout)["labs"] if lab["name"] == "fabric"]
        up = {(link["a"], link["z"]): link.get("up") for link in fab["links"]}
        self.assertIs(up[("spine1", "leaf1")], True)
        self.assertIs(up[("spine2", "leaf3")], False)  # shut
        self.assertIs(up[("spine1", "leaf2")], False)  # leaf2 exited
        self.assertIs(up[("srv2", "macvlan")], True)


class Uptime(unittest.TestCase):
    def test_docker_status(self):
        cases = {
            "Up 3 hours": 10800,
            "Up 3 hours (healthy)": 10800,
            "Up About an hour": 3600,
            "Up Less than a second": 0,
            "Up 45 seconds": 45,
            "Up 2 days": 172800,
            "Up a minute": 60,
            "Exited (0) 2 hours ago": None,
            "": None,
            "Up forever": None,
        }
        for status, want in cases.items():
            self.assertEqual(cs.docker_uptime(status), want, status)

    def test_lab_uptime_is_oldest_node(self):
        (dc,) = by_name(snapshot("clab_mixed.json"), "dc")
        self.assertEqual(dc["uptimeSeconds"], 7200)

    def test_netlab_timestamp(self):
        from datetime import datetime, timedelta, timezone

        now = datetime.now(timezone.utc)
        started = (now - timedelta(hours=5)).astimezone().replace(tzinfo=None).isoformat(" ")
        self.assertAlmostEqual(cs.netlab_uptime(started, now), 18000, delta=2)
        self.assertIsNone(cs.netlab_uptime("garbage", now))


class OpenPlan(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.topo = os.path.join(self.tmp.name, "a.clab.yml")
        open(self.topo, "w").close()

    def plan(self, managed_by, have=(), ui=None):
        def which(b):
            return "/bin/" + b if b in have else None

        return cs.open_plan(managed_by, self.topo, self.tmp.name, which, lambda: ui)

    def test_containerlab_prefers_desktop_app(self):
        plan = self.plan("containerlab", have=("containerlab-desktop", "code"))
        self.assertEqual(plan, ["/bin/containerlab-desktop"])

    def test_containerlab_falls_back_to_editor_with_topology(self):
        self.assertEqual(self.plan("containerlab", have=("codium",)), ["/bin/codium", self.tmp.name, self.topo])

    def test_netlab_ui_when_server_responds(self):
        plan = self.plan("netlab", have=("netlab-ui-desktop", "code"), ui="http://x:8000")
        self.assertEqual(plan, ["/bin/netlab-ui-desktop"])
        self.assertEqual(self.plan("netlab", have=("code",), ui="http://x:8000"), ["xdg-open", "http://x:8000"])

    def test_netlab_without_server_uses_editor(self):
        self.assertEqual(self.plan("netlab", have=("code",)), ["/bin/code", self.tmp.name, self.topo])

    def test_nothing_installed_opens_folder(self):
        self.assertEqual(self.plan("containerlab"), ["xdg-open", self.tmp.name])


class Remote(unittest.TestCase):
    """clab-api-server client against a fake server on localhost."""

    @classmethod
    def setUpClass(cls):
        import http.server
        import threading

        labs = {
            "fab": [
                {
                    "name": "clab-fab-s1",
                    "nodeName": "s1",
                    "lab_name": "fab",
                    "absLabPath": "/srv/labs/fab.clab.yml",
                    "kind": "nokia_srlinux",
                    "state": "running",
                    "status": "Up 3 hours",
                    "ipv4_address": "172.20.20.2/24",
                    "owner": "alice",
                }
            ]
        }

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def reply(self, code, body):
                raw = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if self.path == "/login" and body == {"username": "alice", "password": "pw", "sessionDuration": "720h"}:
                    return self.reply(200, {"token": "good"})
                return self.reply(401, {"error": "Invalid credentials"})

            def do_GET(self):
                if self.path != "/api/v1/labs":
                    return self.reply(404, {"error": "no"})
                if self.headers.get("Authorization") != "Bearer good":
                    return self.reply(401, {"error": "Unauthorized"})
                return self.reply(200, labs)

        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        for var in ("XDG_CONFIG_HOME", "XDG_STATE_HOME"):
            old = os.environ.get(var)
            os.environ[var] = os.path.join(self.tmp.name, var)
            self.addCleanup(lambda v=var, o=old: os.environ.pop(v) if o is None else os.environ.__setitem__(v, o))
        self.conn = {"name": "srv", "url": self.url, "username": "alice"}

    def test_labs_with_token(self):
        labs, err = cs.fetch_remote(self.conn, {"srv": "good"})
        self.assertIsNone(err)
        (lab,) = labs
        self.assertEqual((lab["host"], lab["name"], lab["nodes"][0]["name"]), ("srv", "fab", "s1"))
        self.assertTrue(lab["remote"])
        self.assertTrue(lab["id"].startswith("remote:srv:"))

    def test_expired_token(self):
        _labs, err = cs.fetch_remote(self.conn, {"srv": "stale"})
        self.assertIn("login expired", err)

    def test_not_logged_in(self):
        _labs, err = cs.fetch_remote(self.conn, {})
        self.assertIn("not logged in", err)

    def test_unreachable(self):
        _labs, err = cs.fetch_remote({"name": "x", "url": "http://127.0.0.1:1"}, {"x": "t"})
        self.assertIn("unreachable", err)

    def test_login_stores_token_not_password(self):
        from unittest import mock

        with mock.patch("getpass.getpass", return_value="pw"), mock.patch("sys.stdout"):
            self.assertEqual(cs.cmd_login(["srv", self.url, "alice"]), 0)
        tokens_path = os.path.join(os.environ["XDG_STATE_HOME"], "clab-widget", "tokens.json")
        if os.name == "posix":  # Windows has no mode bits; the file sits in the user's profile
            self.assertEqual(os.stat(tokens_path).st_mode & 0o777, 0o600)
        with open(tokens_path) as f:
            self.assertEqual(json.load(f), {"srv": "good"})
        self.assertEqual(cs.load_connections()[0]["url"], self.url)
        with open(os.path.join(os.environ["XDG_CONFIG_HOME"], "clab-widget", "connections.json")) as f:
            self.assertNotIn("pw", f.read())

    def test_bad_password(self):
        from unittest import mock

        with mock.patch("getpass.getpass", return_value="nope"), mock.patch("sys.stderr"):
            self.assertEqual(cs.cmd_login(["srv", self.url, "alice"]), 1)
        self.assertEqual(cs.load_tokens(), {})

    def test_remote_labs_in_snapshot_skip_details(self):
        rlabs, _ = cs.fetch_remote(self.conn, {"srv": "good"})
        seen = []
        snap = cs.build_snapshot(
            {}, None, {}, None, BOTH, details=lambda labs: seen.extend(labs), remotes=[("srv", rlabs, None)]
        )
        self.assertEqual(snap["sources"]["remote:srv"], {"available": True, "error": ""})
        self.assertEqual(snap["totals"]["labs"], 1)
        self.assertEqual(seen, [])  # no docker stats for someone else's host


class RemoteGroups(unittest.TestCase):
    def test_netlab_ui_merges_into_same_host_clab_labs(self):
        clab = {"fab": [{"name": "clab-nl-r1", "lab_name": "nl", "absLabPath": "/srv/nl/clab.yml", "state": "running"}]}

        def fetch_clab(conn, _t):
            labs = cs.normalize_clab(clab)
            for lab in labs:
                lab.update(host=conn["name"], remote=True, id="remote:" + conn["name"] + ":" + lab["id"])
            return labs, None

        def fetch_nl(_conn, _t):
            return [
                {"instance": "default", "name": "nl", "dir": "/srv/nl/", "status": "started", "providers": ["clab"]},
                {"instance": "vm", "name": "vms", "dir": "/srv/vms", "status": "started", "providers": ["libvirt"]},
            ], None

        conns = [
            {"name": "srv", "url": "http://x", "group": "box"},
            {"name": "srv-nl", "type": "netlab-ui", "url": "http://x:8000", "group": "box"},
            {"name": "other", "type": "netlab-ui", "url": "http://y:8000"},
        ]
        res = cs.collect_remotes(conns, {}, fetch_clab, fetch_nl)
        by = {name: (labs, err) for name, labs, err in res}
        (merged,) = by["srv"][0]
        self.assertEqual((merged["managedBy"], merged["name"]), ("netlab", "nl"))
        (vms,) = by["srv-nl"][0]  # only the unmatched instance is new
        self.assertEqual((vms["host"], vms["remote"]), ("box", True))
        self.assertTrue(vms["id"].startswith("remote:srv-nl:"))
        self.assertEqual(len(by["other"][0]), 2)  # different group: no merge


FAKE_SSH = """#!/bin/sh
# Fake ssh for the tests: drop the options, run the remote command here,
# after a chatty login profile (the snapshot must still parse).
while [ "$1" != "--" ]; do shift; done
shift 2
echo "Welcome to box"
exec sh -c "$*"
"""


@unittest.skipIf(os.name == "nt", "fake ssh is a shell script")
class SshHost(unittest.TestCase):
    """ssh hosts: this script runs on the host through `ssh … python3 -`."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        fake = os.path.join(self.tmp.name, "ssh")
        with open(fake, "w") as f:
            f.write(FAKE_SSH)
        os.chmod(fake, 0o755)
        old_bin = cs.SSH_BIN
        cs.SSH_BIN = fake
        self.addCleanup(setattr, cs, "SSH_BIN", old_bin)
        env = {
            "XDG_CONFIG_HOME": os.path.join(self.tmp.name, "cfg"),
            "XDG_STATE_HOME": os.path.join(self.tmp.name, "state"),
            "CLAB_WIDGET_CLAB_JSON": os.path.join(FIXTURES, "clab_mixed.json"),
            "CLAB_WIDGET_NETLAB_JSON": os.path.join(FIXTURES, "netlab_mixed.json"),
        }
        for var, value in env.items():
            old = os.environ.get(var)
            os.environ[var] = value
            self.addCleanup(lambda v=var, o=old: os.environ.pop(v) if o is None else os.environ.__setitem__(v, o))
        self.conn = {"name": "box", "type": "ssh", "host": "me@box"}

    def test_snapshot_over_ssh(self):
        snap, err = cs.fetch_ssh(self.conn)
        self.assertIsNone(err)
        local = snapshot("clab_mixed.json", "netlab_mixed.json")
        self.assertEqual(len(snap["labs"]), len(local["labs"]))
        results = cs.collect_remotes([self.conn], {})
        self.assertEqual(results[0][0], "box")
        self.assertIsNone(results[0][2])
        labs = results[0][1]
        self.assertTrue(all(lab["id"].startswith("remote:box:") and lab["via"] == "ssh" for lab in labs))
        full = cs.build_snapshot({}, None, {}, None, BOTH, remotes=results)
        self.assertEqual(full["totals"]["nodes"], local["totals"]["nodes"])
        lab = next(lab for lab in full["labs"] if lab["managedBy"] == "containerlab" and lab["running"])
        self.assertIn("shell", lab["actions"])
        self.assertIn("stop", lab["actions"])
        self.assertTrue(any(n["access"] for n in lab["nodes"]))
        for n in lab["nodes"]:
            self.assertTrue(os.path.isfile(n["icon"]), n["icon"])

    def test_unreachable(self):
        cs.SSH_BIN = os.path.join(self.tmp.name, "nope")
        snap, err = cs.fetch_ssh(self.conn)
        self.assertIsNone(snap)
        self.assertIn("ssh", err)

    def test_ssh_failure_message(self):
        with open(cs.SSH_BIN, "w") as f:
            f.write("#!/bin/sh\necho 'ssh: connect to host box port 22: Connection refused' >&2\nexit 255\n")
        snap, err = cs.fetch_ssh(self.conn)
        self.assertIsNone(snap)
        self.assertEqual(err, "ssh: ssh: connect to host box port 22: Connection refused")
        ok, err = cs.login(dict(self.conn), "")
        self.assertFalse(ok)
        self.assertIn("key login", err)
        self.assertEqual(cs.load_connections(), [])

    def test_login_saves_ssh_host_without_secrets(self):
        ok, err = cs.login(dict(self.conn), "ignored")
        self.assertTrue(ok, err)
        self.assertEqual(cs.load_connections(), [self.conn])
        self.assertEqual(cs.load_tokens(), {})

    def test_add_command(self):
        import contextlib
        import io

        def add(conn):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = cs.main(["add", json.dumps(conn)])
            return rc, json.loads(buf.getvalue())

        rc, out = add(dict(self.conn, junk="x", port=""))
        self.assertEqual((rc, out), (0, {"ok": True, "message": "added box"}))
        self.assertEqual(cs.load_connections(), [self.conn])
        rc, out = add({"name": "api", "type": "clab-api", "url": "https://x"})
        self.assertEqual(rc, 1)
        self.assertIn("password", out["message"])
        rc, out = add({"name": "ui", "type": "netlab-ui", "url": "http://x:8000"})
        self.assertTrue(out["ok"])
        self.assertEqual([c["name"] for c in cs.load_connections()], ["box", "ui"])

    def test_tool_errors_on_host(self):
        snap = {"sources": {"containerlab": {"available": False, "error": "permission denied"}}}
        self.assertEqual(cs.ssh_source_error(snap), "containerlab: permission denied")
        snap["sources"]["netlab"] = {"available": True, "error": ""}
        self.assertIsNone(cs.ssh_source_error(snap))
        self.assertIn("neither", cs.ssh_source_error({"sources": {}}))


class Upstream(unittest.TestCase):
    """Data from clab-ui / vscode-containerlab (package/contents/upstream, tools/sync-upstream.py)."""

    def test_loaded(self):
        self.assertEqual(cs.ROLE_SVG_MAP["router"], "pe")
        self.assertEqual(cs.EXEC_CMD["nokia_srlinux"], "sr_cli")
        self.assertEqual(cs.SSH_USERS["arista_ceos"], "admin")
        self.assertRegex(cs.DEFAULT_ICON_COLOR, r"^#[0-9a-f]{6}$")

    def test_every_role_has_an_icon_a_tier_and_a_schema_entry(self):
        with open(os.path.join(HERE, "..", "docs", "snapshot.schema.json")) as f:
            enum = set(json.load(f)["$defs"]["node"]["properties"]["role"]["enum"])
        with open(os.path.join(HERE, "..", "package", "contents", "code", "Labs.js")) as f:
            labs_js = f.read()
        for role in cs.ROLE_ICONS:
            self.assertTrue(os.path.isfile(os.path.join(cs.ICON_DIR, role + ".svg")), role)
            self.assertIn(role, enum)
            self.assertRegex(labs_js, rf'"{re.escape(role)}": \d')

    def test_icons_use_the_default_colour(self):
        with open(os.path.join(cs.ICON_DIR, "leaf.svg")) as f:
            self.assertIn(cs.DEFAULT_ICON_COLOR, f.read().lower())

    def test_script_sent_to_hosts_carries_the_data(self):
        src = cs.own_source().decode()
        ns = {"__name__": "remote", "__file__": "<stdin>"}
        exec(compile(src, "<stdin>", "exec"), ns)
        self.assertEqual(ns["ROLE_SVG_MAP"], cs.ROLE_SVG_MAP)
        self.assertEqual(ns["EXEC_CMD"], cs.EXEC_CMD)


class SshPlans(unittest.TestCase):
    conn = {"name": "box", "type": "ssh", "host": "me@box", "port": 2222}

    def test_parse_ssh_url(self):
        self.assertEqual(cs.parse_ssh_url("b", "ssh://me@box:2222"), dict(self.conn, name="b"))
        self.assertEqual(cs.parse_ssh_url("b", "ssh://box"), {"name": "b", "type": "ssh", "host": "box"})
        self.assertEqual(cs.parse_ssh_url("b", "ssh://me@box:22")["host"], "me@box")
        self.assertIsNone(cs.parse_ssh_url("b", "ssh://-oProxyCommand=x"))
        self.assertIsNone(cs.parse_ssh_url("b", "http://box"))

    def test_invalid_connections_are_dropped(self):
        self.assertFalse(cs.valid_connection({"name": "x", "type": "ssh", "host": "-oProxyCommand=evil"}))
        self.assertFalse(cs.valid_connection({"name": "x", "type": "ssh"}))
        self.assertTrue(cs.valid_connection(self.conn))
        self.assertFalse(cs.valid_connection(dict(self.conn, port="22; rm")))
        self.assertFalse(cs.valid_connection(dict(self.conn, port=70000)))

    def test_argv(self):
        argv = cs.ssh_argv(self.conn)
        self.assertIn("BatchMode=yes", argv)
        self.assertEqual(argv[-2:], ["--", "me@box"])
        self.assertEqual(argv[argv.index("-p") + 1], "2222")
        self.assertIn("-t", cs.ssh_argv(self.conn, interactive=True))
        self.assertNotIn("BatchMode=yes", cs.ssh_argv(self.conn, interactive=True))

    def test_shell_runs_on_host(self):
        argv = cs.ssh_shell_plan(self.conn, "exec", "nokia_srlinux", "clab-fab-s1", env={})
        self.assertEqual(argv[-1], "sh -lc 'docker exec -it clab-fab-s1 sr_cli'")
        argv = cs.ssh_shell_plan(self.conn, "connect", "frr", "", "r1", "/srv/my lab", env={})
        self.assertIn("netlab", argv[-1])
        self.assertIn("my lab", argv[-1])

    def test_stop_and_open(self):
        clab = {"managedBy": "containerlab", "topologyFile": "/srv/fab.clab.yml", "dir": "/srv"}
        argv = cs.ssh_stop_plan(self.conn, clab)
        self.assertIn("destroy -t /srv/fab.clab.yml", argv[-1])
        self.assertIn("-t", argv)
        argv = cs.ssh_stop_plan(self.conn, {"managedBy": "netlab", "dir": "/srv/x"})
        self.assertIn("netlab down", argv[-1])
        argv = cs.ssh_open_plan(self.conn, "/srv", lambda b: "/bin/" + b if b == "code" else None)
        self.assertEqual(argv, ["/bin/code", "--remote", "ssh-remote+me@box", "/srv"])

    def test_wsl(self):
        conn = {"name": "wsl", "type": "wsl", "distro": "Ubuntu"}
        self.assertTrue(cs.valid_connection(conn))
        self.assertTrue(cs.valid_connection({"name": "wsl", "type": "wsl"}))
        self.assertFalse(cs.valid_connection({"name": "w", "type": "wsl", "distro": "-x"}))
        argv = cs.host_argv(conn, "echo hi")
        self.assertTrue(argv[0].endswith("wsl.exe"))
        self.assertEqual(argv[1:], ["-d", "Ubuntu", "-e", "sh", "-lc", "echo hi"])
        argv = cs.ssh_shell_plan(conn, "logs", "linux", "clab-x-a", env={})
        self.assertEqual(argv[-1], "docker logs -f --tail 200 clab-x-a")
        argv = cs.ssh_open_plan(conn, "/home/me/lab", lambda b: b)
        self.assertEqual(argv, ["code", "--remote", "wsl+Ubuntu", "/home/me/lab"])
        labs = cs.ssh_labs(conn, snapshot("clab_mixed.json"))
        self.assertTrue(all(lab["via"] == "wsl" and lab["wslDistro"] == "Ubuntu" for lab in labs))
        snap = cs.build_snapshot({}, None, {}, None, BOTH, remotes=[("wsl", labs, None)])
        self.assertIn("shell", snap["labs"][0]["actions"])

    def test_terminal_plans(self):
        self.assertEqual(cs.terminal_plan(["ssh", "x"], "win32"), (["ssh", "x"], 0x10))
        argv, _ = cs.terminal_plan(["ssh", "-t", "a b"], "darwin")
        self.assertEqual(argv[0], "osascript")
        self.assertIn("do script \"ssh -t 'a b'\"", argv[2])
        self.assertEqual(cs.terminal_plan(["x"], "linux", lambda: ["konsole", "-e"]), (["konsole", "-e", "x"], 0))
        self.assertIsNone(cs.terminal_plan(["x"], "linux", lambda: None))


FAKE_KUBECTL = """#!/bin/sh
# Fake kubectl: prints the saved clabernetes objects for `get`, records argv.
echo "$*" >> "$(dirname "$0")/argv.log"
case "$*" in
  *" get topologies.c9s.run,nodes.c9s.run,links.c9s.run "*) cat "$C9S_FIXTURE" ;;
  *) echo "error: unknown" >&2; exit 1 ;;
esac
"""


class Clabernetes(unittest.TestCase):
    """clabernetes on Kubernetes: kubectl → one lab per Topology."""

    conn = {"name": "k3s", "type": "k8s", "context": "k3s-lab"}

    def labs(self):
        items = fixture("c9s.json")["items"]
        snap = cs.build_snapshot({}, None, {}, None, BOTH, remotes=[("k3s", cs.k8s_labs(self.conn, items), None)])
        return snap, {lab["name"]: lab for lab in snap["labs"]}

    def test_topology_to_lab(self):
        _snap, labs = self.labs()
        lab = labs["srl02"]
        self.assertEqual(lab["id"], "remote:k3s:k8s:c9s-srl02/srl02")
        self.assertEqual((lab["managedBy"], lab["providers"], lab["via"]), ("containerlab", ["clabernetes"], "k8s"))
        self.assertEqual((lab["running"], lab["total"], lab["lifecycle"]), (2, 3, "partial"))
        self.assertEqual(lab["namespace"], "c9s-srl02")
        nodes = {n["name"]: n for n in lab["nodes"]}
        self.assertEqual(nodes["srl1"]["role"], "spine")
        self.assertEqual(nodes["srl1"]["ipv4"], "10.123.0.11")
        self.assertEqual(nodes["srl1"]["container"], "c9s-srl02/srl1")
        self.assertEqual(nodes["client1"]["state"], "notready")
        self.assertEqual(nodes["client1"]["status"], "CrashLoopBackOff")
        self.assertEqual(len(lab["links"]), 2)
        self.assertEqual(nodes["srl1"]["access"], ["exec", "logs"])
        self.assertEqual(nodes["client1"]["access"], ["logs"])  # down: logs still help
        self.assertIn("shell", lab["actions"])
        self.assertIn("stop", lab["actions"])

    def test_deploying_and_errors(self):
        _snap, labs = self.labs()
        self.assertEqual(labs["evpn"]["lifecycle"], "starting")
        self.assertFalse(labs["evpn"]["nodesKnown"])
        self.assertIn("conflicts", labs["broken"]["status"])
        self.assertEqual(labs["broken"]["lifecycle"], "unknown")

    def test_plans(self):
        argv = cs.k8s_shell_plan(self.conn, "exec", "nokia_srlinux", "c9s-srl02/srl1", env={})
        self.assertEqual(
            argv[1:], ["--context", "k3s-lab", "-n", "c9s-srl02", "exec", "-it", "deploy/srl1", "--", "sr_cli"]
        )
        argv = cs.k8s_shell_plan(self.conn, "logs", "linux", "c9s-srl02/client1", env={})
        self.assertEqual(argv[-5:], ["logs", "-f", "--tail", "200", "deploy/client1"])
        self.assertIsNone(cs.k8s_shell_plan(self.conn, "exec", "linux", "no-namespace", env={}))
        argv = cs.k8s_stop_plan(self.conn, {"namespace": "c9s-srl02", "name": "srl02"})
        self.assertEqual(argv[-4:], ["c9s-srl02", "delete", "topologies.c9s.run", "srl02"])
        self.assertEqual(
            cs.hold_open(["C:\\k\\kubectl.exe", "delete", "x"], "win32"), ["cmd", "/k", "kubectl", "delete", "x"]
        )
        self.assertEqual(cs.hold_open(["kubectl", "x"], "linux")[:2], ["sh", "-c"])

    def test_kubus(self):
        self.assertEqual(
            cs.kubus_url("k3s-lab", "c9s-srl02", "srl02"),
            "kubus://r/c9s.run/v1alpha1/topologies?sel=k3s-lab%7Cc9s-srl02%7Csrl02",
        )
        self.assertEqual(
            cs.kubus_app(lambda b: "/usr/bin/kubus" if b == "kubus" else None, "linux"), ["/usr/bin/kubus"]
        )
        self.assertIsNone(cs.kubus_app(lambda b: None, "linux"))
        self.assertEqual(
            cs.kubus_app(lambda b: None, "darwin", isdir=lambda p: p == "/Applications/Kubus.app"), ["open"]
        )
        self.assertIsNone(cs.kubus_app(lambda b: None, "win32", env={}))
        from unittest import mock

        lab = self.labs()[1]["srl02"]
        with mock.patch.object(cs, "kubus_app", lambda _which: ["/x/kubus"]):
            self.assertIn("open", cs.lab_actions(lab))
        with mock.patch.object(cs, "kubus_app", lambda _which: None):
            self.assertNotIn("open", cs.lab_actions(lab))

    def test_connections(self):
        self.assertTrue(cs.valid_connection(self.conn))
        self.assertTrue(cs.valid_connection({"name": "k", "type": "k8s"}))
        self.assertFalse(cs.valid_connection({"name": "k", "type": "k8s", "context": "--kubeconfig=/x"}))
        argv = cs.kubectl_argv({"name": "k", "type": "k8s", "kubeconfig": "~/k3s.yaml"})
        self.assertEqual(argv[1], "--kubeconfig")
        self.assertTrue(argv[2].endswith("k3s.yaml") and "~" not in argv[2])

    def test_schema(self):
        Schema.setUpClass()
        Schema().check(self.labs()[0])

    @unittest.skipIf(os.name == "nt", "fake kubectl is a shell script")
    def test_end_to_end_with_fake_kubectl(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        fake = os.path.join(tmp.name, "kubectl")
        with open(fake, "w") as f:
            f.write(FAKE_KUBECTL)
        os.chmod(fake, 0o755)
        old = cs.KUBECTL_BIN
        cs.KUBECTL_BIN = fake
        self.addCleanup(setattr, cs, "KUBECTL_BIN", old)
        os.environ["C9S_FIXTURE"] = os.path.join(FIXTURES, "c9s.json")
        self.addCleanup(os.environ.pop, "C9S_FIXTURE", None)
        results = cs.collect_remotes([self.conn], {})
        self.assertEqual([lab["name"] for lab in results[0][1]], ["srl02", "evpn", "broken"])
        self.assertIsNone(results[0][2])
        with open(os.path.join(tmp.name, "argv.log")) as f:
            self.assertIn("--context k3s-lab get topologies.c9s.run,nodes.c9s.run,links.c9s.run -A -o json", f.read())
        with open(fake, "w") as f:
            f.write('#!/bin/sh\necho "error: the server doesn\'t have a resource type \\"topologies\\"" >&2\nexit 1\n')
        _items, err = cs.fetch_k8s(self.conn)
        self.assertIn("is not installed in this cluster", err)
        ok, err = cs.login(dict(self.conn), "")
        self.assertFalse(ok)


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.snap = snapshot("clab_mixed.json", "netlab_mixed.json")

    def test_actions_by_owner(self):
        (dc,) = by_name(self.snap, "dc")
        self.assertEqual(dc["actions"], ["copy", "open", "shell", "stop"])
        (vm,) = by_name(self.snap, "vmlab")
        self.assertEqual(vm["actions"], ["copy", "open", "stop"])  # netlab down; no node shells yet

    def test_remote_actions(self):
        lab = {"managedBy": "containerlab", "remote": True, "apiUrl": "http://x", "nodes": [], "nodesKnown": True}
        self.assertEqual(cs.lab_actions(lab, which=lambda _b: None), ["copy", "stop"])
        self.assertEqual(cs.lab_actions(lab, which=lambda b: "/bin/" + b), ["copy", "open", "stop"])
        nl = {"managedBy": "netlab", "remote": True, "uiUrl": "http://x:8000", "nodes": [], "nodesKnown": False}
        self.assertEqual(cs.lab_actions(nl, which=lambda _b: None), ["copy", "open"])

    def test_stop_rechecks_fingerprint(self):
        (dc,) = by_name(self.snap, "dc")
        lab, reason = cs.check_stop(self.snap, dc["id"], dc["fingerprint"])
        self.assertIs(lab, dc)
        self.assertIsNone(reason)
        lab, reason = cs.check_stop(self.snap, dc["id"], "stale")
        self.assertIsNone(lab)
        self.assertIn("changed", reason)
        lab, reason = cs.check_stop(self.snap, "clab:/gone.clab.yml", "x")
        self.assertIn("no longer running", reason)

    def test_fingerprint_changes_with_containers(self):
        (dc,) = by_name(self.snap, "dc")
        before = dc["fingerprint"]
        dc["nodes"].append({"name": "new", "container": "clab-dc-new"})
        self.assertNotEqual(cs.fingerprint(dc), before)

    def test_stop_plans(self):
        which = {"containerlab": "/nix/bin/containerlab", "netlab": "/nix/bin/netlab"}.get
        (dc,) = by_name(self.snap, "dc")
        argv, cwd = cs.stop_plan(dc, which=which, in_admin_group=False)
        self.assertEqual(argv, ["sudo", "/nix/bin/containerlab", "destroy", "-t", "/home/u/labs/dc/dc.clab.yml"])
        self.assertEqual(cwd, "/home/u/labs/dc")
        argv, _ = cs.stop_plan(dc, which=which, in_admin_group=True)
        self.assertEqual(argv[0], "/nix/bin/containerlab")
        (nl,) = by_name(self.snap, "nl")
        argv, cwd = cs.stop_plan(nl, which=which)
        self.assertEqual(argv[-2:], ["/home/u/netlab/nl", "/nix/bin/netlab"])  # netlab down in its dir
        self.assertIn("down", argv[2])


class RemoteDestroy(Remote):
    """DELETE against the same fake server (extended with a DELETE handler)."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        handler = cls.server.RequestHandlerClass

        def do_DELETE(self):
            if self.headers.get("Authorization") != "Bearer good":
                return self.reply(401, {"error": "Unauthorized"})
            if self.path == "/api/v1/labs/fab":
                return self.reply(200, {"message": "Lab 'fab' destroyed"})
            return self.reply(404, {"error": "Lab not found"})

        handler.do_DELETE = do_DELETE

    def test_destroy(self):
        self.assertEqual(cs.remote_destroy(self.conn, "good", "fab"), (True, ""))
        self.assertEqual(cs.remote_destroy(self.conn, "good", "nope"), (False, "Lab not found"))
        self.assertEqual(cs.remote_destroy(self.conn, "bad", "fab"), (False, "Unauthorized"))
        dead = {"name": "x", "url": "http://127.0.0.1:1"}
        self.assertEqual(cs.remote_destroy(dead, "t", "fab"), (False, "unreachable"))


class NodeShells(unittest.TestCase):
    def test_access_per_owner_and_kind(self):
        snap = snapshot("clab_mixed.json", "netlab_mixed.json")
        (dc,) = by_name(snap, "dc")
        self.assertEqual(dc["nodes"][0]["access"], ["ssh", "exec", "logs"])  # SR Linux
        (nl,) = by_name(snap, "nl")
        r1 = next(n for n in nl["nodes"] if n["name"] == "r1")
        self.assertEqual(r1["access"], ["connect", "exec", "logs"])  # netlab on clab
        r2 = next(n for n in nl["nodes"] if n["name"] == "r2")
        self.assertEqual(r2["access"], [])  # not running
        lab1 = next(lab for lab in by_name(snap, "lab1") if lab["lifecycle"] == "running")
        self.assertEqual(lab1["nodes"][0]["access"], ["exec", "logs"])  # linux: no sshd

    def test_libvirt_node_only_connect(self):
        lab = {"managedBy": "netlab", "dir": "/l"}
        node = {"running": True, "kind": "frr", "container": "vm_r1", "provider": "libvirt"}
        self.assertEqual(cs.node_access(lab, node), ["connect"])

    def test_plans_follow_the_vscode_extension(self):
        env = {}
        self.assertEqual(cs.shell_plan("ssh", "nokia_srlinux", "clab-dc-s1", env=env), ["ssh", "admin@clab-dc-s1"])
        self.assertEqual(cs.shell_plan("ssh", "frr", "clab-x-r1", env=env), ["ssh", "clab-x-r1"])
        srl = cs.shell_plan("exec", "nokia_srlinux", "clab-dc-s1", env=env)
        self.assertEqual(srl, ["docker", "exec", "-it", "clab-dc-s1", "sr_cli"])
        self.assertEqual(cs.shell_plan("exec", "linux", "c", env=env)[:5], ["docker", "exec", "-it", "c", "sh"])
        self.assertEqual(cs.shell_plan("logs", "linux", "c", env=env), ["docker", "logs", "-f", "--tail", "200", "c"])
        connect = cs.shell_plan("connect", "frr", "c", node="r1", lab_dir="/l", env=env, which=lambda _b: "/bin/netlab")
        self.assertEqual(connect[-3:], ["/l", "/bin/netlab", "r1"])
        self.assertIsNone(cs.shell_plan("nope", "x", "c", env=env))

    def test_env_overrides(self):
        env = {"CLAB_WIDGET_EXEC_ARISTA_CEOS": "Cli", "CLAB_WIDGET_SSH_USER_FRR": "vagrant"}
        self.assertEqual(cs.shell_plan("exec", "arista_ceos", "c", env=env)[-1], "Cli")
        self.assertEqual(cs.shell_plan("ssh", "frr", "c", env=env), ["ssh", "vagrant@c"])


class NaturalOrder(unittest.TestCase):
    def test_nodes_sort_naturally(self):
        names = ["leaf10", "leaf2", "leaf1", "Spine1", "leaf100"]
        self.assertEqual(sorted(names, key=cs.natural_key), ["leaf1", "leaf2", "leaf10", "leaf100", "Spine1"])


class Schema(unittest.TestCase):
    """Every kind of snapshot the backend makes validates against docs/snapshot.schema.json."""

    @classmethod
    def setUpClass(cls):
        try:
            import jsonschema
        except ImportError:
            raise unittest.SkipTest("jsonschema not installed") from None
        with open(os.path.join(HERE, "..", "docs", "snapshot.schema.json")) as f:
            cls.validator = jsonschema.Draft202012Validator(json.load(f))

    def check(self, snap):
        errors = sorted(self.validator.iter_errors(json.loads(json.dumps(snap))), key=str)
        self.assertEqual(errors, [], "\n".join(f"{list(e.path)}: {e.message}" for e in errors[:5]))

    def test_empty(self):
        self.check(snapshot())

    def test_mixed_local(self):
        self.check(snapshot("clab_mixed.json", "netlab_mixed.json"))

    def test_with_details(self):
        detail = fixture("netlab_detail_vmlab.json")
        self.check(
            cs.build_snapshot(
                fixture("clab_mixed.json"),
                None,
                fixture("netlab_mixed.json"),
                None,
                BOTH,
                details=lambda labs: cs.add_details(labs, lambda: {"clab-dc-spine1": 10}, lambda _i: detail),
            )
        )

    def test_topology_and_remote(self):
        t = Topology()
        t.setUp()
        self.addCleanup(t.doCleanups)
        remote = cs.normalize_clab(fixture("clab_mixed.json"))
        for lab in remote:
            lab.update(remote=True, host="srv", hostUrl="http://x", apiUrl="http://x", conn="srv")
        snap = cs.build_snapshot({}, None, {}, None, BOTH, remotes=[("srv", remote, None)])
        self.check(snap)

    def test_ssh_host(self):
        remote = snapshot("clab_mixed.json", "netlab_mixed.json")
        labs = cs.ssh_labs({"name": "box", "type": "ssh", "host": "box"}, json.loads(json.dumps(remote)))
        self.check(cs.build_snapshot({}, None, {}, None, BOTH, remotes=[("box", labs, None)]))


class Source(unittest.TestCase):
    def test_backend_compiles_without_warnings(self):
        """Invalid escapes etc. are SyntaxWarnings today and errors tomorrow."""
        import warnings

        with open(SCRIPT, encoding="utf-8") as f:
            src = f.read()
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            compile(src, SCRIPT, "exec")
