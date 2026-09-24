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
  qml tests/render/Render.qml -- list fabric snap.json out.png   # list | map | settings | menu | nodemenu
python3 desktop/app.py --render out.png --page settings
python3 desktop/app.py --selftest
```

New UI icons: drop the Lucide SVG into `package/contents/icons/ui/` and run `make icons`.

App icons (the "Icon" setting): `assets/icon.png` is the containerlab one,
`assets/icon-netlab.png` the netlab one (currently a purple placeholder made
by `tools/netlab-placeholder.py`). Replace a PNG with new artwork in the same
style (rounded tile, emblem in the middle, name at the bottom) and run
`make app-icons`: 16–128 px get the emblem only, 256 px the full tile.

## Releases

`make tag` (./tag.sh) bumps the version in `package/metadata.json`, commits,
tags and pushes. `.github/workflows/release.yml` then builds the `.plasmoid`
and publishes the release; `desktop.yml` builds the Windows installer / zip and
the macOS dmg / zip, checks each with its own `--selftest`, and attaches them.
`make tag` with `--beta` (`./tag.sh --beta`) makes a pre-release.
