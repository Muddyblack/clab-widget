# PyInstaller spec for the tray app (Windows .exe folder, macOS .app). From the
# repository root:
#
#   pip install -r desktop/build-requirements.txt
#   pyinstaller --noconfirm desktop/clab-widget.spec
#
# Produces dist/CLAB Widget/CLAB Widget(.exe) and, on macOS, dist/CLAB Widget.app.
# The QML, backend and icons keep the repository's layout inside the bundle,
# so desktop/Main.qml finds ../package exactly as in a checkout.

import os
import sys

ROOT = os.path.abspath(os.path.join(SPECPATH, ".."))  # noqa: F821 — set by PyInstaller
APP = "CLAB Widget"

datas = [
    (os.path.join(ROOT, "desktop", "Main.qml"), "desktop"),
    (os.path.join(ROOT, "desktop", "ConnectionsPage.qml"), "desktop"),
    (os.path.join(ROOT, "package", "contents", "code"), os.path.join("package", "contents", "code")),
    (os.path.join(ROOT, "package", "contents", "ui", "shared"), os.path.join("package", "contents", "ui", "shared")),
    (os.path.join(ROOT, "package", "contents", "icons"), os.path.join("package", "contents", "icons")),
    (os.path.join(ROOT, "package", "contents", "shaders"), os.path.join("package", "contents", "shaders")),
    (os.path.join(ROOT, "package", "contents", "tools", "clab-status"), os.path.join("package", "contents", "tools")),
]

if sys.platform == "win32":
    icon = os.path.join(ROOT, "dist", "clab-widget.ico")  # made by build-installer.ps1 / the workflow
elif sys.platform == "darwin":
    icon = os.path.join(ROOT, "dist", "clab-widget.icns")
else:
    icon = None

a = Analysis(  # noqa: F821
    [os.path.join(ROOT, "desktop", "app.py")],
    datas=datas,
    excludes=["tkinter"],
)
pyz = PYZ(a.pure)  # noqa: F821
exe = EXE(  # noqa: F821
    pyz,
    a.scripts,
    # UTF-8 mode: Windows' default text encoding is otherwise the ANSI code page.
    [("X utf8", None, "OPTION")],
    exclude_binaries=True,
    name=APP,
    console=False,
    icon=icon if icon and os.path.exists(icon) else None,
)
coll = COLLECT(exe, a.binaries, a.datas, name=APP)  # noqa: F821

if sys.platform == "darwin":
    app = BUNDLE(  # noqa: F821
        coll,
        name=APP + ".app",
        icon=icon if icon and os.path.exists(icon) else None,
        bundle_identifier="org.muddyblack.clabWidget",
        info_plist={
            # A menu-bar app: no Dock icon.
            "LSUIElement": True,
            "NSHighResolutionCapable": True,
        },
    )
