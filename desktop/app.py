"""CLAB Widget desktop app — a tray icon with the same popup as the widgets.

For Windows, macOS and any Linux desktop without Plasma/Quickshell. The popup
is desktop/Main.qml (shared LabList + settings); data comes from the same
backend script, run with this interpreter. On Windows/macOS containerlab and
netlab usually live on another machine: add it under "remote hosts".

  python desktop/app.py                     start (a second start toggles the popup)
  python desktop/app.py --render OUT.png [--page labs|settings|connections]
                                            render the popup off-screen and exit
  python desktop/app.py --selftest          load the QML off-screen, open every page,
                                            exit 1 on any QML warning (CI, and the
                                            built .exe / .app checks itself with it)
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import sys
import threading
import time

# Frozen (PyInstaller), the bundle keeps the repository's layout under
# sys._MEIPASS, so desktop/Main.qml still finds ../package.
FROZEN = getattr(sys, "frozen", False)
HERE = os.path.join(sys._MEIPASS, "desktop") if FROZEN else os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.path.join(ROOT, "package", "contents", "tools", "clab-status")
ICON_DIR = os.path.join(ROOT, "package", "contents", "icons", "app")
ICON = os.path.join(ICON_DIR, "org.muddyblack.clabWidget-128.png")
ICON_PREFIX = {"clab": "org.muddyblack.clabWidget", "netlab": "netlab"}
_icon_variant = "clab"  # settings "Icon", set from the QML via Backend.setAppIcon
ICON_SIZES = (16, 22, 32, 48, 64, 128, 256)

_loader = importlib.machinery.SourceFileLoader("clab_status", TOOL)
_spec = importlib.util.spec_from_loader("clab_status", _loader)
cs = importlib.util.module_from_spec(_spec)
_loader.exec_module(cs)

from PySide6.QtCore import Property, QObject, QPoint, QRect, QSize, Qt, QTimer, Signal, Slot  # noqa: E402
from PySide6.QtGui import QColor, QCursor, QGuiApplication, QIcon, QPainter  # noqa: E402
from PySide6.QtNetwork import QLocalServer, QLocalSocket  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon  # noqa: E402

INSTANCE_KEY = "clab-widget-desktop"
POPUP_MARGIN = 10


def settings_path():
    return os.path.join(cs.config_dir(), "desktop.json")


class ToolResult:
    def __init__(self, stdout, returncode):
        self.stdout = stdout
        self.returncode = returncode


def run_tool(args):
    """The backend: a child Python normally; in a frozen build sys.executable is
    this app itself, so the backend runs in-process (it only uses subprocess and
    the standard library, and prints its JSON to stdout)."""
    if FROZEN:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            try:
                rc = cs.main(list(args))
            except SystemExit as ex:
                rc = ex.code if isinstance(ex.code, int) else 1
        return ToolResult(buf.getvalue(), rc or 0)
    no_window = {"creationflags": 0x08000000} if os.name == "nt" else {}  # CREATE_NO_WINDOW
    proc = subprocess.run(
        [sys.executable, TOOL, *args],
        capture_output=True,
        text=True,
        timeout=60,
        stdin=subprocess.DEVNULL,
        **no_window,
    )
    return ToolResult(proc.stdout, proc.returncode)


class Backend(QObject):
    snapshotReady = Signal(str)
    refreshFailed = Signal()
    loginFinished = Signal(bool, str)
    popupVisibleChanged = Signal()
    notifyRequested = Signal(str, str)
    trayStateChanged = Signal(str, str)
    appIconChanged = Signal()

    _snapshotDone = Signal(str, bool)
    _loginDone = Signal(bool, str)

    def __init__(self):
        super().__init__()
        self._busy = False
        self._popup_visible = False
        self._snapshotDone.connect(self._finish_snapshot)
        self._loginDone.connect(self.loginFinished)

    def _get_popup_visible(self):
        return self._popup_visible

    def set_popup_visible(self, visible):
        if visible != self._popup_visible:
            self._popup_visible = visible
            self.popupVisibleChanged.emit()

    popupVisible = Property(bool, _get_popup_visible, notify=popupVisibleChanged)

    @Slot(str)
    def refresh(self, args_json):
        if self._busy:
            return
        self._busy = True
        args = json.loads(args_json)

        def work():
            try:
                proc = run_tool(args)
                self._snapshotDone.emit(proc.stdout, proc.returncode == 0)
            except (OSError, subprocess.TimeoutExpired):
                self._snapshotDone.emit("", False)

        threading.Thread(target=work, daemon=True).start()

    def _finish_snapshot(self, text, ok):
        self._busy = False
        if ok:
            self.snapshotReady.emit(text)
        else:
            self.refreshFailed.emit()

    @Slot(str)
    def action(self, args_json):
        args = json.loads(args_json)
        if args and args[0] == "notify":
            self.notify(args[1], args[2])
            return
        if FROZEN:
            # open / shell / stop only spawn their own processes and return.
            threading.Thread(target=run_tool, args=(args,), daemon=True).start()
            return
        no_window = {"creationflags": 0x08000000} if os.name == "nt" else {}
        subprocess.Popen([sys.executable, TOOL, *args], stdin=subprocess.DEVNULL, **no_window)

    @Slot(str, str)
    def notify(self, title, body):
        # The tray balloon: native on Windows/macOS, a notification on Linux.
        self.notifyRequested.emit(title, body)

    @Slot(str)
    def setAppIcon(self, variant):
        global _icon_variant
        if variant in ICON_PREFIX and variant != _icon_variant:
            _icon_variant = variant
            self.appIconChanged.emit()

    @Slot(str, str)
    def setTrayState(self, totals_json, summary):
        self.trayStateChanged.emit(totals_json, summary)

    @Slot(result=str)
    def loadSettings(self):
        data, _err = cs.read_json_file(settings_path())
        return json.dumps(data if isinstance(data, dict) else {})

    @Slot(str)
    def saveSettings(self, text):
        os.makedirs(os.path.dirname(settings_path()), exist_ok=True)
        with open(settings_path(), "w", encoding="utf-8") as f:
            f.write(text)

    @Slot(result=str)
    def connectionsJson(self):
        return json.dumps(cs.load_connections())

    @Slot(str, str)
    def addConnection(self, conn_json, password):
        conn = json.loads(conn_json)

        def work():
            try:
                ok, err = cs.login(conn, password)
            except Exception as ex:  # shown in the page; nothing else would
                ok, err = False, str(ex)
            self._loginDone.emit(ok, f"added {conn['name']}" if ok else f"login failed: {err}")

        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def removeConnection(self, name):
        cs.cmd_logout([name, "--forget"])


def app_icon():
    """All shipped sizes, so each platform picks a sharp one (the small ones
    are the symbol without the "clab widget" text)."""
    prefix = ICON_PREFIX.get(_icon_variant, ICON_PREFIX["clab"])
    icon = QIcon()
    for n in ICON_SIZES:
        icon.addFile(os.path.join(ICON_DIR, f"{prefix}-{n}.png"), QSize(n, n))
    return icon


def tray_icon(attention, active):
    """App icon with a status dot: red = needs attention, green = labs up."""
    pix = app_icon().pixmap(64, 64)
    if active or attention:
        p = QPainter(pix)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor("#0d1526"))
        p.drawEllipse(QRect(38, 38, 26, 26))
        p.setBrush(QColor("#f87171" if attention else "#4ade80"))
        p.drawEllipse(QRect(42, 42, 18, 18))
        p.end()
    return QIcon(pix)


class App:
    def __init__(self, qt_app, render_to=None, page="labs", headless=False):
        self.qt_app = qt_app
        self.backend = Backend()
        self.view = QQuickView()
        self.view.setColor(Qt.transparent)
        self.view.rootContext().setContextProperty("backend", self.backend)
        self.view.rootContext().setContextProperty("initialPage", page)
        self.view.setResizeMode(QQuickView.SizeViewToRootObject)
        self.view.setSource(os.path.join(HERE, "Main.qml"))
        if self.view.status() == QQuickView.Error:
            for e in self.view.errors():
                print(e.toString(), file=sys.stderr)
            sys.exit(1)

        if render_to:
            self._render(render_to)
            return
        if headless:
            self.view.show()
            return

        self.view.setFlags(Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.view.activeChanged.connect(self._on_active_changed)
        self.view.heightChanged.connect(self._reposition)

        self.tray = QSystemTrayIcon(tray_icon(False, False))
        self.tray.setToolTip("CLAB Widget")
        menu = QMenu()
        menu.addAction("Show labs", self.show_popup)
        menu.addAction("Refresh", lambda: self.view.rootObject().refresh())
        menu.addSeparator()
        menu.addAction("Quit", qt_app.quit)
        self.tray.setContextMenu(menu)
        self.tray.activated.connect(self._on_tray)
        self.tray.show()
        self.menu = menu

        self.backend.notifyRequested.connect(lambda t, b: self.tray.showMessage(t, b, app_icon(), 8000))
        self.backend.trayStateChanged.connect(self._on_tray_state)
        self.backend.appIconChanged.connect(self._on_app_icon)
        self._last_totals = {}
        self._hidden_at = 0

    def _render(self, path):
        self.view.show()

        def grab():
            self.view.grabWindow().save(path)
            self.qt_app.quit()

        QTimer.singleShot(2500, grab)

    def _on_app_icon(self):
        self.qt_app.setWindowIcon(app_icon())
        t = self._last_totals
        self.tray.setIcon(tray_icon(t.get("attention", 0) > 0, t.get("labs", 0) > 0))

    def _on_tray_state(self, totals_json, summary):
        t = json.loads(totals_json)
        self._last_totals = t
        self.tray.setIcon(tray_icon(t.get("attention", 0) > 0, t.get("labs", 0) > 0))
        self.tray.setToolTip(f"CLAB Widget — {summary}")

    def _on_tray(self, reason):
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self.toggle_popup()

    def _on_active_changed(self):
        # Clicking anywhere else closes the popup, like a panel popup.
        if not self.view.isActive() and self.view.isVisible():
            self.hide_popup()

    def toggle_popup(self):
        if self.view.isVisible():
            self.hide_popup()
        # Clicking the tray icon first deactivates (and so hides) an open
        # popup; that same click must not reopen it.
        elif time.monotonic() - self._hidden_at > 0.3:
            self.show_popup()

    def show_popup(self):
        self._reposition()
        self.view.show()
        self.view.raise_()
        self.view.requestActivate()
        self.backend.set_popup_visible(True)

    def hide_popup(self):
        self.view.hide()
        self._hidden_at = time.monotonic()
        self.backend.set_popup_visible(False)

    def _reposition(self):
        """Next to the tray icon, inside the screen's work area."""
        anchor = self.tray.geometry() if self.tray.geometry().isValid() else QRect(QCursor.pos(), QCursor.pos())
        screen = QGuiApplication.screenAt(anchor.center()) or QGuiApplication.primaryScreen()
        area = screen.availableGeometry()
        w, h = self.view.width(), self.view.height()
        x = min(max(anchor.center().x() - w // 2, area.left() + POPUP_MARGIN), area.right() - w - POPUP_MARGIN)
        # Taskbar at the bottom (Windows) → above the icon; menu bar on top (macOS) → below.
        if anchor.center().y() > area.center().y():
            y = area.bottom() - h - POPUP_MARGIN
        else:
            y = area.top() + POPUP_MARGIN
        self.view.setPosition(QPoint(x, y))


def setup_log():
    """A windowed .exe/.app has no console: warnings and errors go to
    <state dir>/tray.log (one older copy kept as tray.log.1)."""
    path = os.path.join(cs.state_dir(), "tray.log")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path) and os.path.getsize(path) > 512 * 1024:
            os.replace(path, path + ".1")
        log = open(path, "a", encoding="utf-8", buffering=1)  # noqa: SIM115 — lives as long as the app
    except OSError:
        return
    if sys.stdout is None:
        sys.stdout = log
    if sys.stderr is None:
        sys.stderr = log


def selftest():
    """Load Main.qml off-screen, walk every page, fail on any QML warning."""
    from PySide6.QtCore import QtMsgType, qInstallMessageHandler

    problems = []

    def handler(kind, _ctx, msg):
        print(msg, file=sys.stderr)
        # JS errors in bindings can arrive at any level; count them all.
        bad_kind = kind in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg)
        if bad_kind or any(e in msg for e in ("TypeError", "ReferenceError", "Error:")):
            problems.append(msg)

    qInstallMessageHandler(handler)
    qt_app = QApplication(sys.argv)
    app = App(qt_app, headless=True)
    popup = app.view.rootObject().findChild(QObject, "popup")
    if popup is None:
        print("selftest: popup not found", file=sys.stderr)
        return 1
    pages = ["settings", "extra", "map", "list"]

    def step():
        if pages:
            popup.setProperty("page", pages.pop(0))
            QTimer.singleShot(300, step)
        else:
            qt_app.quit()

    QTimer.singleShot(500, step)
    qt_app.exec()
    # Tear the QML down while the handler still listens: shutdown-time
    # binding errors count too.
    app.view.setSource("")
    del app
    qt_app.processEvents()
    if problems:
        print(f"selftest: {len(problems)} QML problem(s)", file=sys.stderr)
        return 1
    print("selftest: ok")
    return 0


def main():
    if FROZEN:
        setup_log()
    if "--selftest" in sys.argv:
        return selftest()
    render_to = None
    if "--render" in sys.argv:
        render_to = sys.argv[sys.argv.index("--render") + 1]

    qt_app = QApplication(sys.argv)
    qt_app.setApplicationName("CLAB Widget")
    qt_app.setWindowIcon(app_icon())
    qt_app.setQuitOnLastWindowClosed(False)

    if not render_to:
        # Single instance: a second start asks the first to toggle its popup.
        sock = QLocalSocket()
        sock.connectToServer(INSTANCE_KEY)
        if sock.waitForConnected(300):
            sock.write(b"toggle")
            sock.waitForBytesWritten(300)
            return 0
        if not QSystemTrayIcon.isSystemTrayAvailable():
            print("no system tray available", file=sys.stderr)

    page = sys.argv[sys.argv.index("--page") + 1] if "--page" in sys.argv else "labs"
    app = App(qt_app, render_to, page)

    if not render_to:
        QLocalServer.removeServer(INSTANCE_KEY)
        server = QLocalServer()
        server.listen(INSTANCE_KEY)
        server.newConnection.connect(lambda: (server.nextPendingConnection(), app.toggle_popup()))
        app.server = server

    return qt_app.exec()


if __name__ == "__main__":
    sys.exit(main())
