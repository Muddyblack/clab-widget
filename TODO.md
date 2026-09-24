# CLAB Widget — TODO

> Desktop companion for **Containerlab & netlab**: see what's running, what broke,
> and jump back into the right tool. Not an editor. It hands off to containerlab-app,
> netlab-ui or VS Code.

## Decisions (locked 2026-09-23)

- **Name:** CLAB Widget (`clab-widget`). Store/README title: *"CLAB Widget — Containerlab & netlab lab status"*, so netlab still gets search reach. The README says it's a community project, not affiliated with srl-labs/Nokia or ipSpace.
- **Path:** pure QML companion. No WebView, no embedded React. clab-ui *logic* and *artwork* are ported instead: role → icon map, `SvgGenerator` icons, annotations.
- **Frontends:** Plasma 6 plasmoid, Quickshell pill, PySide6 tray app (Windows/macOS/other Linux). All three use the same `clab-status` backend and the same shared QML (`package/contents/ui/shared`, `code/Labs.js`).

## Done

- [x] Backend `package/contents/tools/clab-status`: one JSON snapshot. containerlab regrouped by topology path; netlab on clab merged by directory; lifecycle states; uptime; fingerprints; per-lab `actions`
- [x] clab-ui node icons (14 roles, `icons/nodes/`, generated from `SvgGenerator.ts`, `#005aff`). Role from `graph-icon` label / `.annotations.json`, custom colours recoloured into `~/.cache`
- [x] containerlab + netlab logos (badges, tabs). App icon: `assets/icon.png` (neon flask); 16–128 px use a text-free symbol crop, 256 px the full icon; installed to hicolor at 7 sizes
- [x] `--details` while open: memory (`docker stats`, netlab `--memory`), node state for netlab on libvirt etc. (`netlab status -i`)
- [x] Topology map: links + role icons, saved clab-ui positions, else tiers by role (wrapped into even rows for big fabrics, icons shrink, hover labels, down nodes always labelled), else a circle/grid. `tests/demo.py --large` = 102-node fabric
- [x] Node access like the containerlab VS Code extension: ssh (per-kind user) / `netlab connect`, docker shell (per-kind exec cmd, `sr_cli`…), logs
- [x] Same in-popup settings page in all three frontends (Plasma writes `Plasmoid.configuration`)
- [x] UI redesign (shared `Popup.qml` in all three frontends): fixed header (summary · search · refresh · settings; back arrow on subpages), All/containerlab/netlab chips, one-line lab rows with hover icon actions, right-click / ⋮ menus for labs and nodes, stop confirm bar, Lucide icons drawn as Shapes (no shader; `tools/lucide-to-js.py`)
- [x] Glass look from Glassy System Monitor / the audio visualizer: shared `GlassCard` + `card/` materials (frosted tint, solid, atmosphere, glass, liquid), section-style header, owner accent bars (containerlab blue, netlab purple), palette in `code/Theme.js`; Appearance settings
- [x] Plasma: desktop = the glass card itself; panel = icon + popup; system tray entry (NotificationArea) with needs-attention / passive status
- [x] Quickshell `mode`: pill + popup, or desktop card on the Bottom layer (namespace `clab-widget-glass` for Hyprland blur); IPC `setMode`
- [x] Repo like the other widgets: `tag.sh`, Makefile (`make help`), `test_install.sh`, pre-commit, LICENSE, CONTRIBUTING, KDE Store description; workflows `lint.yml` (qmlformat, Icons.js sync, ruff, tests, flake check), `desktop.yml` (tray app tests on Linux/Windows/macOS, `.exe` zip + Inno Setup installer, `.app` zip + dmg, each `--selftest`ed), `release.yml` (`.plasmoid` + attached desktop builds)
- [x] Tray app ready to freeze: in-process backend when frozen, `tray.log`, `--selftest`; PyInstaller spec checked with a local Linux build + frozen selftest
- [x] Settings in the studio's style: icon + uppercase sections, rounded cards, label/description rows, segmented controls, live material preview tiles (`Segmented`, `SettingsSection`, `SettingRow`)
- [x] Icon setting: containerlab / netlab / auto; `tools/make-app-icons.py` builds the sizes from `assets/icon*.png`
- [x] Scale: virtualized ListView synced in place (`Labs.rowsFor` + `syncModel`): 658-node lab refresh 11 ms expanded, 7 ms collapsed (400 KB snapshot, parse 8 ms). Map page: pan/zoom/pinch, fit, canvas-drawn nodes above 150, viewport-shaped layout; search `down` finds broken nodes; natural node order
- [x] Snapshot JSON Schema (`docs/snapshot.schema.json`), validated in the tests for local / details / topology / remote snapshots
- [x] Pin labs: pinned labs sort first and the pill / panel item / tray tooltip show only them ("● fabric 6/7 · ● ospf 3/3", "fabric —" when not running)
- [x] **Show** setting: both / both as tabs / only containerlab / only netlab (all frontends)
- [x] Notifications, debounced over 2 polls: node down, node disappeared, tool/host unreachable. Forgotten-lab reminder (opt-in, never destroys)
- [x] Open: containerlab desktop app → VS Code (folder + topology) → file manager. netlab-ui (if `/api/health` answers) → VS Code. Remote: containerlab desktop / netlab-ui URL
- [x] Remote hosts: clab-api-server (`login` stores the token only, mode 600) + netlab-ui (`/api/lab/instances`), `group` merges both for one machine
- [x] Stop: confirm click, fresh-snapshot fingerprint check, runs via the owner (`netlab down` / `sudo containerlab destroy` in a terminal; remote `DELETE /api/v1/labs/<name>`)
- [x] Quickshell settings page (`~/.config/clab-widget/quickshell.json`), corner placement
- [x] Quickshell IPC `panel`: toggle / open / close / refresh / settings / setShow <mode> / quit (same target as ai-usage-widget)
- [x] Tray app `desktop/` (`nix run .#desktop`): tray dot, popup at the tray, native notifications, remote-host form, single instance
- [x] Tests: 54 Python (fixtures, fake clab-api-server over HTTP, stop checks, node shells) + 30 JS (notification rules, map layout, show modes, pins, row model/sync, search) in `nix flake check`; `tests/demo.py` + `tests/render/Render.qml` for visual checks
- [x] Nix: devShell with containerlab + netlab (`nix/netlab.nix`), plasmoid package, `view` / `view-hyprland` / `desktop` apps
- [x] `packages.containerlab` 0.79.0 (upstream release binary; nixpkgs has 0.71, netlab 26.9 needs >= 0.75) + `nixosModules.default` (`programs.clab-widget`: setuid containerlab for `clab_admins`, users, widget + netlab installed)

## Not verified yet

- [ ] Import `nixosModules.default` in nixos-config (`programs.clab-widget = { enable = true; users = [ username ]; }`), rebuild, re-login. Until then `netlab up` fails: "not a member of the clab_admins group"
- [ ] `tests/integration.sh [netlab]` against a real deploy, after the step above (first run hit a 172.20.20.0/24 clash with the `kind` network; test labs now use 10.123.x)
- [ ] Pins on screen in the Plasma panel item and the tray app (only Quickshell checked visually)
- [ ] Quickshell desktop card seen on screen (loads fine; was hidden under windows when screenshotted)
- [ ] System tray entry: enable under System Tray Settings → Entries and check attention/passive
- [ ] New popup live on screen: Quickshell loads it without errors, but hover actions, right-click menus, map pan/zoom and search typing were only checked via off-screen renders
- [ ] `docker stats` time with 700 real containers (the 0.26 s backend figure is with saved output)
- [ ] Remote code only ran against a fake server: try a real `containerlab tools api-server start` and a running netlab-ui
- [ ] Plasma config dialog (Show combo, reminder spin box) not opened yet
- [ ] Tray app on real Windows and macOS (only run on Linux, offscreen + tray logic)
- [ ] Confirm the `inspect --format json` shape on containerlab 0.79 with a real lab (parser written against 0.71 source)
- [ ] qmllint in the dev shell (import paths not picked up yet)

- [ ] CI never ran: no GitHub repo / remote yet (`tag.sh` pushes to `origin`). First push: check lint.yml, desktop.yml (Windows + macOS builds) and a `--beta` tag through release.yml
- [ ] Windows installer / macOS dmg not tried on real machines

- [ ] Real netlab icon: replace the purple placeholder `assets/icon-netlab.png`, then `make app-icons`

## Next

- [ ] Packaging: `.plasmoid` pack app, KDE Store; PyInstaller + installer for Windows (see ai-usage-widget/windows), signed `.app` for macOS
- [ ] Quickshell Nix package + home-manager module (`nixos-config/modules/home-manager`)
- [ ] Remote-host UI in Plasma/Quickshell settings (CLI `clab-status login` only for now)
- [ ] Node shell for remote labs (ssh via the API server's SSH proxy: `/api/v1/labs/{lab}/nodes/{node}/ssh`)
- [ ] Deploy (start a lab from a topology), again via its owner, with confirm
- [ ] Clicking a notification opens the popup on that lab

## Upstream ideas (would make "open" exact)

- [ ] netlab-ui (own repo): a route or `?instance=<id>` / `?dir=<path>` that opens one lab, plus a desktop argv/URL handler
- [ ] containerlab-app: propose an argv/`containerlab://` handler in the desktop app, or a URI handler in the VS Code extension

## Community

- [ ] Post in the containerlab Discord, ask to be listed on containerlab.dev community tools
- [ ] KDE Store listing, GitHub topics: `containerlab`, `netlab`, `network-automation`, `kde-plasma`, `quickshell`
