#!/usr/bin/env python3
"""Refresh what CLAB Widget takes from upstream projects, so it can be pulled
again when they change:

    python3 tools/sync-upstream.py            # fetch upstream, rewrite the files below
    python3 tools/sync-upstream.py --check    # exit 1 if upstream has changed (CI)
    python3 tools/sync-upstream.py --clab-ui DIR --vscode DIR   # local checkouts instead

From srl-labs/clab-ui (the containerlab-app / VS Code TopoViewer graph):
  src/core/types/graph.ts   ROLE_SVG_MAP, DEFAULT_ICON_COLOR -> upstream/clab-ui-roles.json
  src/icons/SvgGenerator.ts the node icons, run with Node   -> icons/nodes/<role>.svg
From srl-labs/vscode-containerlab (the containerlab VS Code extension):
  resources/exec_cmd.json, resources/ssh_users.json (verbatim) -> upstream/

upstream/SOURCES.json records the commits. The widget reads these files at run
time; nothing of theirs is edited by hand here. Needs git and Node >= 22.6
(TypeScript is run with --experimental-strip-types; no npm install).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENTS = os.path.join(ROOT, "package", "contents")
UPSTREAM = os.path.join(CONTENTS, "upstream")
ICONS = os.path.join(CONTENTS, "icons", "nodes")
REPOS = {
    "clab-ui": "https://github.com/srl-labs/clab-ui",
    "vscode-containerlab": "https://github.com/srl-labs/vscode-containerlab",
}

# Runs SvgGenerator.ts as is (its logger import swapped for a stub) and prints
# {nodeType: svg} for every type in its NodeType union.
RUNNER = r"""
import { readFileSync } from "node:fs";
const { generateEncodedSVG } = await import(process.argv[2]);
const src = readFileSync(process.argv[2].replace("file://", ""), "utf8");
const union = src.match(/export type NodeType =([^;]*);/)[1];
const types = [...union.matchAll(/"([\w-]+)"/g)].map((m) => m[1]);
const out = {};
for (const t of types) {
  const uri = generateEncodedSVG(t, process.argv[3]);
  out[t] = decodeURIComponent(uri.slice(uri.indexOf(",") + 1));
}
console.log(JSON.stringify(out));
"""


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def checkout(name, path, tmp):
    if path:
        return os.path.abspath(path)
    dest = os.path.join(tmp, name)
    git("clone", "--quiet", "--depth", "1", REPOS[name], dest)
    return dest


def role_map(clab_ui):
    """ROLE_SVG_MAP and DEFAULT_ICON_COLOR from graph.ts (plain literals)."""
    with open(os.path.join(clab_ui, "src", "core", "types", "graph.ts"), encoding="utf-8") as f:
        src = f.read()
    color = re.search(r'DEFAULT_ICON_COLOR\s*=\s*[^"]*"(#[0-9a-fA-F]{6})"', src).group(1).lower()
    body = re.search(r"ROLE_SVG_MAP[^=]*=\s*\{(.*?)\}", src, re.S).group(1)
    roles = dict(re.findall(r'"?([\w-]+)"?\s*:\s*"([\w-]+)"', body))
    if not roles:
        sys.exit("ROLE_SVG_MAP not found in graph.ts: its format changed, update tools/sync-upstream.py")
    return {"defaultIconColor": color, "roleSvgMap": roles}


def node_icons(clab_ui, color, tmp):
    node = shutil.which("node")
    if not node:
        sys.exit("node (>= 22.6) is needed to run clab-ui's SvgGenerator.ts")
    with open(os.path.join(clab_ui, "src", "icons", "SvgGenerator.ts"), encoding="utf-8") as f:
        src = f.read()
    stub = "const log = { info() {}, warn() {}, error() {}, debug() {} };"
    src, n = re.subn(r'^import \{ log \} from "[^"]+";', stub, src, flags=re.M)
    if n != 1:
        sys.exit("SvgGenerator.ts imports changed: update the stub in tools/sync-upstream.py")
    gen = os.path.join(tmp, "SvgGenerator.ts")
    with open(gen, "w", encoding="utf-8") as f:
        f.write(src)
    runner = os.path.join(tmp, "run.mjs")
    with open(runner, "w", encoding="utf-8") as f:
        f.write(RUNNER)
    out = subprocess.run(
        [node, "--experimental-strip-types", "--no-warnings", runner, "file://" + gen, color],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return {t: svg.strip() + "\n" for t, svg in json.loads(out).items()}


def vscode_tables(vscode):
    tables = {}
    for name in ("exec_cmd.json", "ssh_users.json"):
        with open(os.path.join(vscode, "resources", name), encoding="utf-8") as f:
            tables[name] = json.load(f)
    return tables


def wanted_files(clab_ui, vscode, tmp):
    roles = role_map(clab_ui)
    files = {os.path.join(UPSTREAM, "clab-ui-roles.json"): roles}
    for name, table in vscode_tables(vscode).items():
        files[os.path.join(UPSTREAM, name)] = table
    for role, svg in node_icons(clab_ui, roles["defaultIconColor"], tmp).items():
        files[os.path.join(ICONS, role + ".svg")] = svg
    missing = set(roles["roleSvgMap"].values()) - {os.path.basename(p)[:-4] for p in files if p.endswith(".svg")}
    if missing:
        sys.exit(f"ROLE_SVG_MAP names icons SvgGenerator doesn't draw: {sorted(missing)}")
    return files


def render(content):
    return content if isinstance(content, str) else json.dumps(content, indent=2, sort_keys=True) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="only report differences; exit 1 if any")
    ap.add_argument("--clab-ui", help="a local clab-ui checkout instead of cloning")
    ap.add_argument("--vscode", help="a local vscode-containerlab checkout instead of cloning")
    args = ap.parse_args(argv)

    with tempfile.TemporaryDirectory() as tmp:
        clab_ui = checkout("clab-ui", args.clab_ui, tmp)
        vscode = checkout("vscode-containerlab", args.vscode, tmp)
        files = wanted_files(clab_ui, vscode, tmp)
        paths = {"clab-ui": clab_ui, "vscode-containerlab": vscode}
        sources = {name: git("rev-parse", "HEAD", cwd=path) for name, path in paths.items()}

    changed = []
    for path, content in sorted(files.items()):
        text = render(content)
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if old != text:
            changed.append(os.path.relpath(path, ROOT))
            if not args.check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
    stale = sorted(
        os.path.relpath(os.path.join(ICONS, n), ROOT)
        for n in os.listdir(ICONS)
        if n.endswith(".svg") and os.path.join(ICONS, n) not in files
    )

    if args.check:
        for p in changed + [s + " (no longer upstream)" for s in stale]:
            print("differs:", p)
        return 1 if changed or stale else 0
    for p in stale:
        os.remove(os.path.join(ROOT, p))
    with open(os.path.join(UPSTREAM, "SOURCES.json"), "w", encoding="utf-8") as f:
        json.dump({"repos": REPOS, "commits": sources}, f, indent=2)
        f.write("\n")
    for p in changed:
        print("updated:", p)
    for p in stale:
        print("removed:", p)
    if not changed and not stale:
        print("already in sync with", ", ".join(f"{k}@{v[:8]}" for k, v in sources.items()))
    new_roles = set(files[os.path.join(UPSTREAM, "clab-ui-roles.json")]["roleSvgMap"].values())
    print("roles:", " ".join(sorted(new_roles)), "(new ones also need a tier in Labs.js ROLE_TIER)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
