# Remote hosts

containerlab and netlab run on Linux. The widget can watch as many other
machines as you like, next to (or instead of) this one. On Windows and macOS
this is the normal setup.

Add hosts in the popup: header → **Remote hosts** (server icon). Every
frontend has the page: Plasma, Quickshell and the tray app. Or use the CLI
below. Connections are stored in `~/.config/clab-widget/connections.json`.

| Kind | What you need on the lab machine | What you get |
| --- | --- | --- |
| **ssh** | ssh with key login, `python3`, containerlab and/or netlab | Everything a local widget there would see: both tools, map, memory, node shells, stop, open in VS Code (Remote-SSH) |
| **WSL** (Windows) | containerlab inside a WSL2 distro, `python3` there | Same as ssh, through `wsl.exe`; open in VS Code (WSL) |
| **Kubernetes** (clabernetes) | a cluster (k8s, k3s, kind…) running [clabernetes](https://github.com/srl-labs/clabernetes); `kubectl` here | Each Topology as a lab: nodes, links, map, `kubectl exec` / logs, delete; open in [Kubus](https://github.com/FloSch62/Kubus) |
| **clab-api-server** | `containerlab tools api-server start` | containerlab labs and nodes, destroy; open in the containerlab desktop app |
| **netlab-ui** | a running netlab-ui server | netlab instances; open netlab-ui |

## ssh

```bash
clab-status login lab-box ssh://me@lab-box            # or ssh://me@lab-box:2222
clab-status login lab-box ssh://lab-box --identity ~/.ssh/id_ed25519
```

(`clab-status` is `package/contents/tools/clab-status` in this repo.)

The widget pipes its own status script to `python3 -` on the host, through a
login shell (`sh -lc`, so `~/.profile` PATH additions such as a netlab venv
apply). Nothing gets installed there. Polls use `BatchMode=yes`, so they never
ask for a password: set up key login first (`ssh-copy-id me@lab-box`) or load
the key into your agent. New host keys are accepted on first contact
(`StrictHostKeyChecking=accept-new`), and a changed key is refused.

Node shells, `docker exec`, logs, `netlab connect` and stop open a terminal
running `ssh -t lab-box …`, so sudo can ask for its password there. **Open**
starts `code --remote ssh-remote+me@lab-box <lab folder>`. For a custom port
or key, VS Code reads the host from `~/.ssh/config`, so use an alias there.

The user on the host needs what a local user needs: to be root, in
`clab_admins`, or able to run `containerlab inspect` (and `docker`) otherwise.

Several hosts are polled in parallel. Each one takes about one round trip
plus the tools' own run time.

## WSL (Windows)

containerlab's own Windows setup is WSL2. In the tray app on Windows,
**WSL** is the first choice in the add form. Leave the distro empty for the
default one.

```powershell
clab-status login wsl wsl://            # default distro
clab-status login wsl wsl://Ubuntu
```

## Kubernetes (clabernetes)

```bash
clab-status login k3s k8s://                          # kubectl's current context, all namespaces
clab-status login k3s k8s://k3s-lab/c9s-srl02         # context / namespace
clab-status login k3s k8s:// --kubeconfig /etc/rancher/k3s/k3s.yaml
```

The widget runs `kubectl get topologies.c9s.run,nodes.c9s.run,links.c9s.run -o json`
with your kubeconfig, one call per poll and cluster. Each Topology becomes a lab
(tagged with the connection name). Its Node objects become the nodes: readiness,
kind, image, management address, the first failing condition (for example
`CrashLoopBackOff`) and the `graph-icon` label for the map. Its Link objects
become the links. A Topology that is still deploying, or that has an error (a
name conflict, a compile error), shows that instead of node counts.

- **Node shell**: `kubectl exec -it deploy/<node> -- sr_cli` (the same
  per-kind command as for docker), in a terminal. **Logs**:
  `kubectl logs -f deploy/<node>`, available for nodes that are down too.
- **Delete topology…** (confirmed and re-checked like every stop):
  `kubectl delete topologies.c9s.run <name> -n <namespace>` in a terminal.
  clabernetes then removes the lab's Nodes, Pods and Services.
- **Open in Kubus**: when [Kubus](https://kubus-app.dev) is installed, it opens
  on that Topology (`kubus://r/c9s.run/v1alpha1/topologies?sel=<context>|<namespace>|<name>`).

This is clabernetes 0.7 or newer (API group `c9s.run`, where Node and Link are
the primary objects). Older installs used `clabernetes.containerlab.dev` with
launcher pods and aren't read. A lab isn't one machine here: each node is its
own Deployment / Pod wherever the scheduler put it, so the widget talks to the
cluster's API (the kubectl context), never to a node directly.

The user needs to be allowed to list those resources (and to exec into and
delete them for the actions). Several clusters are polled in parallel with the
ssh hosts.

## clab-api-server

```bash
clab-status login dc-server https://dc-server:8090 alice [--insecure] [--ca FILE]
```

This asks for the password once and stores only the returned token
(`~/.local/state/clab-widget/tokens.json`, mode 600). In Plasma and
Quickshell, "log in (terminal)" opens this prompt in a terminal window.

## netlab-ui

Add the server URL (`http://dc-server:8000`). No login.

## One machine, two servers

Give a clab-api-server and a netlab-ui connection for the same machine the
same **group**. A netlab lab running on containerlab there then shows up as
one card instead of two.
