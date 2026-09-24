<p align="center"><img src="assets/icon.png" width="160" alt="CLAB Widget icon"></p>

# CLAB Widget

Containerlab & netlab lab status on your desktop: which labs are running, which
nodes are down, how much memory they use, and one click back into the
containerlab app, netlab-ui, VS Code or a node shell. It complements
containerlab-app and netlab-ui rather than replacing them.

Frontends: KDE Plasma 6 widget, Hyprland/Quickshell pill, and a tray app for
Windows, macOS and other Linux desktops. All three share one backend and the
same QML components.

> Community project. Not affiliated with srl-labs/Nokia (containerlab) or ipSpace (netlab).
> Lab badges use the containerlab logo from [srl-labs/containerlab-app](https://github.com/srl-labs/containerlab-app) (MIT)
> and the netlab-ui logo from [Muddyblack/netlab-ui](https://github.com/Muddyblack/netlab-ui) (Apache-2.0).
> Node icons are generated from clab-ui's `SvgGenerator.ts` (containerlab-app, MIT).

## What it shows

- Every lab on this host, from `containerlab inspect` and `netlab status`. A
  netlab lab running on containerlab appears once, as a "netlab · via clab" card.
- Per node: clab-ui role icon, state, management IP, memory (while open).
- A read-only topology map (links from `topology-data.json`, positions from
  clab-ui's `.annotations.json` when present).
- Remote labs through clab-api-server and netlab-ui.
- **Show**: both together, both as containerlab | netlab tabs, or only one.

Actions: copy IP, node shell (ssh / `docker exec`), open in the owning app,
and **stop**. Stop asks you to confirm, re-checks that the lab is unchanged,
and runs through its owner (`netlab down` or `containerlab destroy`) in a
terminal.

Notifications (debounced over two polls): a node goes down or disappears, a
tool or host becomes unreachable, and an optional reminder for labs left
running. The reminder never tears anything down.

## Where it lives

- **KDE Plasma:** on the desktop it is the glass card itself (resize it like any widget); in a panel it's an icon with a popup; it can also sit in the **system tray** (System Tray Settings → Entries → CLAB Widget) and asks for attention when a lab breaks.
- **Hyprland / Quickshell:** `mode` in settings: a pill in a corner with a popup, or a **desktop card** below your windows. For blur behind the glass: `layerrule = blur, clab-widget-glass`.
- **Windows / macOS / other desktops:** the tray app (`nix run .#desktop`).

The card uses the same glass materials as Glassy System Monitor and the audio visualizer (Settings → Appearance: frosted, solid, atmosphere, glass, liquid glass).

## Using it

- Header: search (names, kinds, IPs, state; `down` = every node that isn't running), refresh, settings.
- Click a lab to show its nodes; hover a row for quick actions; **right-click** (or ⋮) for everything: map, open, pin, copy, stop.
- Nodes: hover for ssh / shell / logs, click the IP to copy it.
- Map: drag to pan, wheel or pinch to zoom, hover a node to highlight its links, click it for its menu.
  Labs with 150+ nodes are drawn as tiles (shaded by tier) so a 700-node fabric stays smooth.

The snapshot format the UI consumes is documented as a JSON Schema: [`docs/snapshot.schema.json`](docs/snapshot.schema.json).

## Run

```bash
direnv allow            # or: nix develop — ships containerlab + netlab
nix run .#view          # Plasma widget preview
nix run .#view-hyprland # Quickshell pill + popup
nix run .#desktop       # tray app (the Windows/macOS frontend)
```

Demo without any labs:

```bash
eval "$(python3 tests/demo.py /tmp/clab-demo)"   # writes lab dirs + saved tool output
CLAB_WIDGET_OPEN=1 nix run .#view-hyprland
```

## Quickshell IPC (keybinds)

With the Quickshell version running (`qs -p .` or `nix run .#view-hyprland`):

```bash
qs ipc -p /path/to/CLAB-Widget call panel toggle     # open | close | refresh | settings | quit
qs ipc -p /path/to/CLAB-Widget call panel setShow tabs   # both | tabs | containerlab | netlab
```

Hyprland: `bind = SUPER, L, exec, qs ipc -p /path/to/CLAB-Widget call panel toggle`

## Remote hosts

```bash
package/contents/tools/clab-status login lab-server https://lab-server:8090 alice [--insecure]
```

This prompts for the password once and stores only the returned token
(`~/.local/state/clab-widget/tokens.json`, mode 600). Connections live in
`~/.config/clab-widget/connections.json`. The tray app has a form for this. A
netlab-ui server is added as `{"type": "netlab-ui", "url": …}`. Give both
connections to one machine the same `group` and their labs merge into one card
each.

## Test

```bash
nix flake check                 # backend (python) + shared QML logic (node) tests
tests/integration.sh [netlab]   # real mini lab, needs Docker + sudo
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
  qml tests/render/Render.qml -- snap.json out.png   # render map/tabs/settings
```

See [TODO.md](TODO.md) for what's next.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE). Bundled third-party artwork keeps its
own license: Lucide icons (ISC, `package/contents/icons/ui/LICENSE-lucide.txt`),
clab-ui node icons and the containerlab logo (MIT, srl-labs/containerlab-app),
the netlab-ui logo (Apache-2.0).

## Development & releases

`make help` lists everything (`view`, `view-h`, `view-hyprland`, `run-desktop`,
`demo`, `install`, `test`, `lint`, `format`, `pack`, `tag`). `make tag` bumps the
version, tags and pushes; GitHub Actions then publishes the `.plasmoid` and
attaches the Windows installer / zip and the macOS dmg / zip. Details in
[CONTRIBUTING.md](CONTRIBUTING.md).
