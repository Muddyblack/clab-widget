# Contributing

## Dependencies

`nix develop` (or `direnv allow`) has everything: containerlab, netlab (with
Ansible), Quickshell, the Plasma SDK, Python with jsonschema, Node, ruff and
the Qt tools. `nix develop .#desktop` adds PySide6 for the tray app. Without
Nix you need:

| Tool | Needed for |
|---|---|
| Plasma SDK (`kpackagetool6`, `plasmoidviewer`) | `./test_install.sh`, `make view` |
| Python 3.8+ | the backend (`package/contents/tools/clab-status`) and its tests |
| `jsonschema` (Python) | the snapshot schema tests (skipped without it) |
| Node.js | `tests/labs.test.js` (skipped without it) |
| Qt 6 `qmlformat` | QML formatting (`make lint`, `make format`) |
| `ruff` | Python lint / format |
| `zip` | `make pack` |
| Quickshell | `make view-hyprland` |
| PySide6 | the tray app (`desktop/requirements.txt`) |

## Layout

| Path | What |
|---|---|
| `package/contents/tools/clab-status` | the backend: one JSON snapshot of every lab (containerlab, netlab, remote hosts), plus open / shell / stop / notify / login |
| `docs/snapshot.schema.json` | the snapshot contract every frontend reads |
| `package/contents/code/` | shared JS: `Labs.js` (row model, notifications, map layout, pins), `Theme.js`, `Icons.js` (generated) |
| `package/contents/ui/shared/` | shared QML: `Popup.qml` is the whole popup; `GlassCard` + `card/` come from Glassy System Monitor |
| `package/contents/ui/main.qml` | Plasma host (desktop card, panel, system tray) |
| `hyprland/`, `shell.qml` | Quickshell host (pill or desktop card) |
| `desktop/` | tray app for Windows / macOS / other desktops (PySide6) |
| `nix/` | netlab + containerlab packages, NixOS module |
| `tests/` | backend, schema and JS tests; `demo.py` demo labs; `render/` off-screen renders; `integration.sh` real labs |

## Development

```bash
make run             # Plasma preview with the demo labs (FORM=horizontal: panel)
make view            # Plasma, desktop form     make view-h   # in a panel
make view-hyprland   # Quickshell               make run-desktop  # tray app
eval "$(make -s demo)"   # demo labs for any of the above (python3 tests/demo.py DIR --huge for 700 nodes)
make install         # a separate "CLAB Widget (Test)" in your Plasma session
make test            # backend + schema + shared JS
make lint            # ruff + qmlformat check   (make format fixes)
```

Look at a change without a running shell:

```bash
QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1 QT_QPA_PLATFORM=offscreen \
  qml tests/render/Render.qml -- list fabric snap.json out.png   # list | map | settings | menu | nodemenu | hosts
# no qml tool? the same with PySide6:  python3 tests/render/run.py tests/render/Render.qml list fabric snap.json out.png
python3 desktop/app.py --render out.png --page settings
python3 desktop/app.py --selftest
make screenshots     # re-render the README images (docs/readme/*.png) from the demo labs
```

Remote hosts without a lab server: `tests/test_clab_status.py` (`SshHost`) runs the
whole ssh path against a fake `ssh` that executes the remote command locally.

New UI icons: drop the Lucide SVG into `package/contents/icons/ui/` and run `make icons`.

App icons (the "Icon" setting): `assets/icon.png` is the containerlab one,
`assets/icon-netlab.png` the netlab one: rounded glass tiles with the emblem
filling them and no text, so they read at 16 px too. Replace a PNG with new
artwork and run `make app-icons`, which scales the whole tile to every size.

## Upstream data (clab-ui, vscode-containerlab)

The widget doesn't embed clab-ui (React / Electron) or the VS Code extension;
it reuses their *data* so the map and node actions look and behave the same:

| What | From | In this repo |
| --- | --- | --- |
| Node icons | `packages/clab-ui/src/icons/SvgGenerator.ts` (run as is with Node) | `package/contents/icons/nodes/*.svg` |
| Role label → icon, default icon colour | `packages/clab-ui/src/core/types/graph.ts` (`ROLE_SVG_MAP`, `DEFAULT_ICON_COLOR`) | `package/contents/upstream/clab-ui-roles.json` |
| `docker exec` command / SSH user per kind | `apps/vscode-containerlab/resources/exec_cmd.json`, `ssh_users.json` | `package/contents/upstream/*.json` |

All three live in [srl-labs/containerlab-app](https://github.com/srl-labs/containerlab-app);
clab-ui and the VS Code extension moved into that monorepo, and their old repos
only point there now. `make sync-upstream` (tools/sync-upstream.py) takes a
sparse clone of it, regenerates those files and records the commit in
`upstream/SOURCES.json`;
`tools/sync-upstream.py --check` exits 1 when upstream has moved on. Don't edit
the files by hand. If clab-ui adds a role, the tests say what else it needs:
a tier in `ROLE_TIER` (Labs.js, map rows) and the schema's role list.

The formats the widget *reads* at run time are upstream's too and are handled
in `clab-status`: `topology-data.json` + the `graph-*` labels (containerlab),
`<topology>.annotations.json` (clab-ui: icon, colour, position),
`netlab status --format json`, clabernetes' `c9s.run` objects and Kubus'
`kubus://` links. A format change there means a code change, with a fixture
in `tests/fixtures/` to show it.

## Releases

`make tag` (./tag.sh) bumps the version in `package/metadata.json`, commits,
tags and pushes. `.github/workflows/release.yml` then builds the `.plasmoid`
and publishes the release; `desktop.yml` builds the Windows installer / zip and
the macOS dmg / zip, checks each with its own `--selftest`, and attaches them.
`make tag` with `--beta` (`./tag.sh --beta`) makes a pre-release.
