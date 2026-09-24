import QtQuick
import QtQuick.Shapes
import "../../code/Icons.js" as Icons

// A Lucide icon drawn as a vector Shape (paths from code/Icons.js, generated
// by tools/lucide-to-js.py): tinted by `color`, crisp at any size, and no
// shader, so it renders the same in Plasma, Quickshell, the tray app and
// off-screen renders.
Item {
    id: icon

    property string name
    property color color: "white"
    property int size: 16

    implicitWidth: size
    implicitHeight: size

    Shape {
        // Lucide's 24×24 box scaled to `size`.
        width: 24
        height: 24
        scale: icon.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        visible: icon.name !== "" && Icons.PATHS[icon.name] !== undefined

        ShapePath {
            strokeColor: icon.color
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: Icons.PATHS[icon.name] || ""
            }
        }
    }
}
