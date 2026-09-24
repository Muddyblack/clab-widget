import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "../code/Labs.js" as Labs

KCM.SimpleKCM {
    property alias cfg_pollSeconds: poll.value
    property string cfg_show
    property alias cfg_notifyNodeDown: notifyDown.checked
    property alias cfg_reminderHours: reminder.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: poll
            Kirigami.FormData.label: i18n("Refresh every (s):")
            from: 5
            to: 3600
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Show:")
            textRole: "label"
            valueRole: "id"
            model: Labs.SHOW_MODES
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_show))
            onActivated: cfg_show = currentValue
        }
        QQC2.CheckBox {
            id: notifyDown
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("When a running node goes down")
        }
        QQC2.SpinBox {
            id: reminder
            Kirigami.FormData.label: i18n("Remind after (h, 0 = off):")
            from: 0
            to: 168
        }
    }
}
