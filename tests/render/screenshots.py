#!/usr/bin/env python3
"""Render the README screenshots (docs/readme/*.png) from the demo labs.

    python3 tests/render/screenshots.py [OUT_DIR]     (make screenshots)

Needs PySide6 (the `nix develop .#desktop` shell, or pip). No Docker, no labs:
tests/demo.py writes saved tool output, the backend turns it into a snapshot,
and tests/render/Render.qml draws the shared popup off-screen for each page.
One lab is shown as if it came from an ssh host, to show the host tag, and
the clabernetes fixture (tests/fixtures/c9s.json) adds a lab on Kubernetes.
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(ROOT, "package", "contents", "tools", "clab-status")

# (file, page, lab to expand / map / open the menu of, search query or None)
SHOTS = [
    ("labs", "list", "fabric", None),
    ("map", "map", "fabric", None),
    ("map-large", "map", "dc-large", None),
    ("menu", "menu", "fabric", None),
    ("search-down", "list", "-", "down"),
    ("settings", "settings-look", "-", None),
    ("hosts", "hosts", "-", None),
]


def snapshot(tmp):
    demo = subprocess.run(
        [sys.executable, os.path.join(ROOT, "tests", "demo.py"), os.path.join(tmp, "demo"), "--large"],
        capture_output=True,
        text=True,
        check=True,
    )
    env = dict(os.environ)
    for part in demo.stdout.strip().splitlines()[-1].removeprefix("export ").split():
        key, _, value = part.partition("=")
        env[key] = value
    env["XDG_CONFIG_HOME"] = os.path.join(tmp, "config")  # no real remote hosts
    out = subprocess.run(
        [sys.executable, TOOL, "snapshot", "--details"], capture_output=True, text=True, check=True, env=env
    )
    snap = json.loads(out.stdout)
    # A clabernetes lab on a k3s cluster, from the saved kubectl output.
    loader = importlib.machinery.SourceFileLoader("clab_status", TOOL)
    cs = importlib.util.module_from_spec(importlib.util.spec_from_loader("clab_status", loader))
    loader.exec_module(cs)
    with open(os.path.join(ROOT, "tests", "fixtures", "c9s.json")) as f:
        items = [i for i in json.load(f)["items"] if (i.get("metadata") or {}).get("namespace") == "c9s-srl02"]
    k8s = cs.k8s_labs({"name": "k3s", "type": "k8s", "context": "k3s"}, items)
    both = {"containerlab": True, "netlab": True}
    k8s_snap = cs.build_snapshot({}, None, {}, None, both, remotes=[("k3s", k8s, None)])
    snap["labs"] = sorted(snap["labs"] + k8s_snap["labs"], key=lambda lab: lab["name"])
    for key, value in k8s_snap["totals"].items():
        snap["totals"][key] += value
    for lab in snap["labs"]:
        if lab["name"] == "ospf":
            lab.update(remote=True, via="ssh", host="lab-box", conn="lab-box", sshHost="me@lab-box")
            lab["id"] = "remote:lab-box:" + lab["id"]
    path = os.path.join(tmp, "snap.json")
    with open(path, "w") as f:
        json.dump(snap, f)
    return path


def main(args):
    out_dir = os.path.abspath(args[0] if args else os.path.join(ROOT, "docs", "readme"))
    os.makedirs(out_dir, exist_ok=True)
    env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1", QML_XHR_ALLOW_FILE_WRITE="1")
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    with tempfile.TemporaryDirectory() as tmp:
        snap = snapshot(tmp)
        for name, page, lab, query in SHOTS:
            png = os.path.join(out_dir, name + ".png")
            argv = [sys.executable, os.path.join(HERE, "run.py"), os.path.join(HERE, "Render.qml")]
            argv += [page, lab, snap, png] + ([query] if query else [])
            subprocess.run(argv, env=env, timeout=120, check=True, stderr=subprocess.DEVNULL)
            try:
                os.remove(png + ".timing.txt")
            except OSError:
                pass
            print(os.path.relpath(png, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
