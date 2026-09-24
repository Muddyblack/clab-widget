import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "shared"

KCM.SimpleKCM {
    id: page

    ProjectInfoPane {
        anchors.left: parent.left
        anchors.right: parent.right
    }
}
