#!/usr/bin/env python3
"""Write a realistic demo (lab dirs + saved tool output) for screenshots/dev.

    python3 tests/demo.py DIR [--large | --huge]   then run the frontend with the printed env

--large adds a 102-node fabric, --huge a ~700-node one (performance checks).

Builds a leaf-spine fabric with clab-ui role labels, links and one stopped
node, a netlab lab on containerlab, and a netlab libvirt lab — no Docker needed.
"""

import json
import os
import sys


def big_fabric(root, spines=4, leaves=32, servers_per_leaf=2, name="dc-large"):
    """A data-centre-sized lab (--large) to see how the map copes."""
    d = os.path.join(root, "labs", name)
    os.makedirs(os.path.join(d, f"clab-{name}"), exist_ok=True)
    topo = os.path.join(d, "dc.clab.yml")
    open(topo, "a").close()
    roles = {"ss1": "super-spine", "ss2": "super-spine"}
    roles.update({f"spine{i}": "spine" for i in range(1, spines + 1)})
    roles.update({f"leaf{i}": "leaf" for i in range(1, leaves + 1)})
    links = [(ss, f"spine{i}") for ss in ("ss1", "ss2") for i in range(1, spines + 1)]
    links += [(f"spine{i}", f"leaf{j}") for i in range(1, spines + 1) for j in range(1, leaves + 1)]
    for j in range(1, leaves + 1):
        for k in range(1, servers_per_leaf + 1):
            roles[f"srv{j}-{k}"] = "server"
            links.append((f"leaf{j}", f"srv{j}-{k}"))
    with open(os.path.join(d, f"clab-{name}", "topology-data.json"), "w") as f:
        json.dump(
            {
                "nodes": {n: {"labels": {"graph-icon": r}} for n, r in roles.items()},
                "links": [{"endpoints": {"a": {"node": a}, "z": {"node": z}}} for a, z in links],
            },
            f,
        )
    return [
        {
            "lab_name": name,
            "absLabPath": topo,
            "name": f"clab-{name}-{n}",
            "kind": "linux" if n.startswith("srv") else "nokia_srlinux",
            "state": "exited" if n in ("leaf7", "srv40-2") else "running",
            "status": "Up 2 hours",
            "ipv4_address": f"172.30.{i // 250}.{i % 250 + 2}/16",
        }
        for i, n in enumerate(roles)
    ]


def main(root, large=False, huge=False):
    root = os.path.abspath(root)
    fab = os.path.join(root, "labs", "fabric")
    nl = os.path.join(root, "netlab", "ospf")
    for d in (os.path.join(fab, "clab-fabric"), os.path.join(nl, "clab-ospf")):
        os.makedirs(d, exist_ok=True)
    fab_topo = os.path.join(fab, "fabric.clab.yml")
    nl_topo = os.path.join(nl, "clab.yml")
    for f in (fab_topo, nl_topo):
        open(f, "a").close()

    roles = {"spine1": "spine", "spine2": "spine", "leaf1": "leaf", "leaf2": "leaf", "leaf3": "leaf"}
    roles.update({"srv1": "server", "srv2": "server"})
    links = [(s, lf) for s in ("spine1", "spine2") for lf in ("leaf1", "leaf2", "leaf3")]
    links += [("leaf1", "srv1"), ("leaf3", "srv2")]
    # Ends outside the lab: a host veth and a macvlan on the host's NIC.
    links += [("srv1", "host:srv1-eth2"), ("srv2", "macvlan:enp3s0")]

    def topo_data(nodes, pairs):
        """Each end gets the node's next e1-N (or the given host-side name)."""
        used, out = {}, []
        for a, z in pairs:
            eps = {}
            for side, end in (("a", a), ("z", z)):
                node, _, iface = end.partition(":")
                if not iface:
                    used[node] = used.get(node, 0) + 1
                    iface = f"e1-{used[node]}"
                eps[side] = {"node": node, "interface": iface}
            out.append({"endpoints": eps})
        return {"nodes": {n: {"labels": {"graph-icon": r} if r else {}} for n, r in nodes.items()}, "links": out}

    def ifaces(lab, data, down=()):
        """Saved operstates per container (what `docker exec` would read):
        every link end up except those in `down` (node, iface)."""
        out = {}
        for link in data["links"]:
            for ep in link["endpoints"].values():
                if ep["node"] in ("host", "macvlan"):
                    continue
                state = "down" if (ep["node"], ep["interface"]) in down else "up"
                out.setdefault(f"clab-{lab}-{ep['node']}", {})[ep["interface"]] = state
        return out

    fab_data = topo_data(roles, links)
    ospf_data = topo_data({"r1": "", "r2": "", "r3": ""}, [("r1", "r2"), ("r2", "r3"), ("r3", "r1")])
    with open(os.path.join(fab, "clab-fabric", "topology-data.json"), "w") as f:
        json.dump(fab_data, f)
    with open(os.path.join(nl, "clab-ospf", "topology-data.json"), "w") as f:
        json.dump(ospf_data, f)
    # spine2 ↔ leaf3 is down (interface shut on spine2), the rest up.
    down_end = next(
        (ep["node"], ep["interface"])
        for link in fab_data["links"]
        for ep in link["endpoints"].values()
        if {e["node"] for e in link["endpoints"].values()} == {"spine2", "leaf3"} and ep["node"] == "spine2"
    )
    with open(os.path.join(root, "ifaces.json"), "w") as f:
        json.dump({**ifaces("fabric", fab_data, [down_end]), **ifaces("ospf", ospf_data)}, f)

    def c(lab, path, node, kind, ip, state="running", status="Up 3 hours"):
        return {
            "lab_name": lab,
            "absLabPath": path,
            "name": f"clab-{lab}-{node}",
            "kind": kind,
            "image": "ghcr.io/nokia/srlinux:25.3" if kind == "nokia_srlinux" else "quay.io/frrouting/frr:10.7.1",
            "state": state,
            "status": status,
            "ipv4_address": f"{ip}/24" if state == "running" else "N/A",
            "owner": "demo",
        }

    fabric = [
        c("fabric", fab_topo, n, "linux" if n.startswith("srv") else "nokia_srlinux", f"172.20.20.{i + 2}")
        for i, n in enumerate(roles)
    ]
    fabric[3] = c("fabric", fab_topo, "leaf2", "nokia_srlinux", "", "exited", "Exited (137) 4 minutes ago")
    ospf = [c("ospf", nl_topo, f"r{i}", "linux", f"192.168.121.10{i}", status="Up 9 hours") for i in (1, 2, 3)]
    labs = {"fabric": fabric, "ospf": ospf}
    if large:
        labs["dc-large"] = big_fabric(root)
    if huge:
        labs["dc-huge"] = big_fabric(root, spines=16, leaves=160, servers_per_leaf=3, name="dc-huge")
    with open(os.path.join(root, "clab.json"), "w") as f:
        json.dump(labs, f)

    netlab = {
        "default": {"dir": nl, "name": "ospf", "status": "started", "providers": ["clab"]},
        "vm": {
            "dir": os.path.join(root, "netlab", "evpn-vms"),
            "name": "evpn-vms",
            "status": "starting provider libvirt",
            "providers": ["libvirt"],
        },
    }
    with open(os.path.join(root, "netlab.json"), "w") as f:
        json.dump(netlab, f)

    print(
        f"export CLAB_WIDGET_CLAB_JSON={root}/clab.json CLAB_WIDGET_NETLAB_JSON={root}/netlab.json"
        f" CLAB_WIDGET_IFACES_JSON={root}/ifaces.json"
    )


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(args[0] if args else "demo", large="--large" in sys.argv, huge="--huge" in sys.argv)
