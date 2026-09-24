# Installation

Pick the frontend for your desktop. They all use the same backend
(`package/contents/tools/clab-status`, Python 3 standard library) and the same
popup.

| Desktop | Frontend |
| --- | --- |
| KDE Plasma 6 | the widget (desktop card, panel popup or system tray) |
| Hyprland, niri, Sway… with Quickshell | the pill + popup, or a desktop card |
| GNOME, Cinnamon, XFCE, any other Linux desktop | the tray app |
| Windows 10/11 | the tray app (installer or zip) |
| macOS | the tray app (`.dmg` or zip) |

On the machine that runs your labs you need **containerlab ≥ 0.75** (node
start/stop/restart) and, for netlab labs, **netlab ≥ 26.2** (`netlab status
--format json`). *Settings → Info* shows which versions it found and turns red
when one is too old.

## KDE Plasma 6

From the [KDE Store](https://www.opendesktop.org/p/2373754/): *Add Widgets… → Get New Widgets → CLAB Widget*. Or
download the `.plasmoid` from the
[releases](https://github.com/Muddyblack/clab-widget/releases) and run
`kpackagetool6 -t Plasma/Applet -i clab-widget-*.plasmoid`. From a checkout,
`make install` does the same.

- Desktop: the glass card itself. Resize it like any widget.
- Panel: an icon, or your pinned labs, with the popup.
- System tray: *System Tray Settings → Entries → CLAB Widget*. It asks for
  attention when a lab breaks.

## Quickshell (Hyprland and other wlroots compositors)

```bash
qs -p /path/to/clab-widget          # or: nix run .#view-hyprland
```

In settings, set `mode` to pill or desktop card. For blur behind the glass on
Hyprland: `layerrule = blur, clab-widget-glass`. For keybinds, see
[the README](../README.md#quickshell-ipc).

## GNOME and other Linux desktops

```bash
make install-desktop       # = desktop/install-linux.sh --autostart
```

This adds a menu entry, the icons and autostart for the tray app, which runs
from the checkout. It needs PySide6 from your distro (`python3-pyside6`,
`pyside6`) or `pip install --user PySide6-Essentials`.

GNOME shows tray icons only with the
[AppIndicator and KStatusNotifierItem Support](https://extensions.gnome.org/extension/615/appindicator-support/)
extension (Ubuntu ships it). Without a tray, the app opens as a normal window
and notifications still arrive. `python3 desktop/app.py --window` forces
window mode.

## Windows

Download `CLAB-Widget-Setup-*.exe` (or the zip) from the
[releases](https://github.com/Muddyblack/clab-widget/releases). containerlab
doesn't run on Windows itself. Add your lab machine under **Remote hosts**:
WSL2 if containerlab lives in WSL on this PC, or ssh / clab-api-server /
netlab-ui for another machine. See [remote hosts](remote-hosts.md). The
OpenSSH client and `wsl.exe` come with Windows 10 and 11.

## macOS

Download the `.dmg` from the releases. It is ad-hoc signed and not notarized,
so on first start right-click → Open. As on Windows, add the Linux machine
that runs your labs under **Remote hosts** (ssh is built in). Node shells
open in Terminal.app.

## Nix / NixOS

```bash
nix run github:Muddyblack/clab-widget#desktop     # tray app
nix build github:Muddyblack/clab-widget           # the plasmoid package
```

`nixosModules.default` (`programs.clab-widget`) installs the widget and uses the
containerlab and netlab you already have. The backend looks on your `PATH` and in
`/run/wrappers/bin`, your Nix profiles, `~/.local/bin` and `/usr/local/bin`.
`users` adds people to `clab_admins`, the group a setuid containerlab lets run
labs without sudo. It installs the tools only when you ask:

```nix
programs.clab-widget = {
  enable = true;
  users = [ "me" ];
  containerlab.enable = true;  # setuid for clab_admins, like containerlab's installer
  netlab.enable = true;
};
```

For development, `nix develop` (direnv) still brings both tools. The ones you
have installed come first on `PATH` there too, so a setuid containerlab still
wins.
