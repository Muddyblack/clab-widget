#!/usr/bin/env python3
"""Run a QML file with PySide6 (a stand-in for Qt's `qml` tool), e.g.

    QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1 QT_QPA_PLATFORM=offscreen \\
      python3 tests/render/run.py tests/render/Render.qml map fabric snap.json out.png

The arguments after the file reach QML as Qt.application.arguments.
"""

import sys

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView


def main():
    app = QGuiApplication(sys.argv)
    view = QQuickView()
    view.engine().quit.connect(app.quit)
    view.setSource(QUrl.fromLocalFile(sys.argv[1]))
    if view.status() == QQuickView.Error:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        return 1
    view.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
