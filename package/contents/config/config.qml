import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: i18n("Info")
        icon: "help-about"
        source: "configInfo.qml"
    }
}
