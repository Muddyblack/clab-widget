import QtQuick
import QtQuick.Layouts
import "../../code/Labs.js" as Labs
import "../../code/Theme.js" as Theme

// Settings page shared by all frontends, laid out like the Glassy System
// Monitor studio: icon + uppercase section titles, one rounded card per
// section, label/description left and the control right. `cfg` is whatever
// the host persists: Quickshell's JsonAdapter, Plasmoid.configuration, or
// the tray app's settings.
ColumnLayout {
    id: page

    property var theme
    property var cfg
    // Only Quickshell places its own window; Plasma and the tray app do not.
    property bool showPlacement: true
    property bool showMode: false
    // Card materials from Glassy System Monitor / the audio visualizer.
    readonly property var styles: [
        {
            id: "tint",
            label: "Frosted"
        },
        {
            id: "solid",
            label: "Solid"
        },
        {
            id: "atmosphere",
            label: "Atmosphere"
        },
        {
            id: "glass",
            label: "Glass"
        },
        {
            id: "liquid",
            label: "Liquid"
        }
    ]
    // Hosts with their own header (the shared Popup) hide the title + done.
    property bool showHeader: true
    // Subtabs like the studio: one section at a time instead of a long scroll.
    property string currentTab: "labs"
    readonly property var tabs: [
        {
            id: "labs",
            label: "Labs",
            icon: "network"
        },
        {
            id: "alerts",
            label: "Alerts",
            icon: "bell"
        },
        {
            id: "look",
            label: "Look",
            icon: "palette"
        }
    ].concat(page.showMode || page.showPlacement ? [
        {
            id: "placement",
            label: "Placement",
            icon: "layout-panel-top"
        }
    ] : []).concat([
        {
            id: "info",
            label: "Info",
            icon: "info"
        }
    ])
    signal done

    function set(key, value) {
        if (page.cfg)
            page.cfg[key] = value;
    }
    function get(key, fallback) {
        return page.cfg && page.cfg[key] !== undefined && page.cfg[key] !== null ? page.cfg[key] : fallback;
    }

    spacing: 16

    RowLayout {
        Layout.fillWidth: true
        visible: page.showHeader

        Text {
            text: "Settings"
            color: page.theme.text
            font.pixelSize: page.theme.fontSize + 2
            font.bold: true
        }

        Item {
            Layout.fillWidth: true
        }

        ActionButton {
            theme: page.theme
            text: "done"
            onClicked: page.done()
        }
    }

    SettingsTabs {
        Layout.fillWidth: true
        Layout.topMargin: -8
        theme: page.theme
        tabs: page.tabs
        current: page.currentTab
        onActivated: id => page.currentTab = id
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: -16
        height: 1
        color: page.theme.border
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: page.currentTab !== "info"
        spacing: 16

        SettingsSection {
            Layout.fillWidth: true
            visible: page.currentTab === "labs"
            theme: page.theme
            title: "Labs"
            icon: "network"

            SettingRow {
                theme: page.theme
                first: true
                stacked: true
                label: "Show"
                desc: "With both, filter chips (All / containerlab / netlab) appear above the list."
                Segmented {
                    theme: page.theme
                    options: Labs.SHOW_MODES
                    value: Labs.normShow(page.get("show", "both"))
                    onActivated: v => page.set("show", v)
                }
            }
            SettingRow {
                theme: page.theme
                label: "Refresh while closed"
                desc: "Every 5 s while the popup is open."
                Stepper {
                    theme: page.theme
                    value: page.get("pollSeconds", 30)
                    from: 5
                    to: 600
                    step: 5
                    suffix: " s"
                    onChanged: v => page.set("pollSeconds", v)
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            visible: page.currentTab === "alerts"
            theme: page.theme
            title: "Notifications"
            icon: "scroll-text"

            SettingRow {
                theme: page.theme
                first: true
                label: "Node goes down"
                desc: "A running node that stops or disappears (checked twice first)."
                Toggle {
                    theme: page.theme
                    checked: page.get("notifyNodeDown", true)
                    onToggled: c => page.set("notifyNodeDown", c)
                }
            }
            SettingRow {
                theme: page.theme
                label: "Forgotten labs"
                desc: "Remind once when a lab has been up this long. Never stops anything."
                Stepper {
                    theme: page.theme
                    value: page.get("reminderHours", 0)
                    from: 0
                    to: 168
                    suffix: " h"
                    zeroText: "off"
                    onChanged: v => page.set("reminderHours", v)
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            visible: page.currentTab === "look"
            theme: page.theme
            title: "Appearance"
            icon: "maximize"

            SettingRow {
                theme: page.theme
                first: true
                stacked: true
                label: "Card"
                desc: "The glass materials of Glassy System Monitor and the audio visualizer."

                // Live preview tiles: each a small GlassCard in its material.
                Flow {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: page.styles

                        Item {
                            readonly property bool on: page.get("surfaceStyle", "tint") === modelData.id
                            width: 74
                            height: 64

                            Rectangle {
                                anchors.fill: tile
                                anchors.margins: -3
                                radius: 13
                                color: "transparent"
                                border.width: 2
                                border.color: parent.on ? (page.theme.clab || page.theme.ok) : "transparent"
                            }
                            GlassCard {
                                id: tile
                                width: 74
                                height: 44
                                material: modelData.id
                                fill: Theme.fillFor(modelData.id)
                                frosted: page.get("frosted", true)
                                radiusTL: 10
                                radiusTR: 10
                                radiusBR: 10
                                radiusBL: 10
                                color1: page.theme.clab || "#4aa8ff"
                                color2: page.theme.netlab || "#aa66ff"
                            }
                            Text {
                                anchors.top: tile.bottom
                                anchors.topMargin: 5
                                anchors.horizontalCenter: tile.horizontalCenter
                                text: modelData.label
                                color: parent.on ? page.theme.text : page.theme.sub
                                font.pixelSize: page.theme.smallSize
                                font.weight: parent.on ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.set("surfaceStyle", modelData.id)
                            }
                        }
                    }
                }
            }
            SettingRow {
                theme: page.theme
                stacked: true
                label: "Icon"
                desc: "Panel, pill and tray icon. Auto uses the netlab icon when only netlab is shown."

                Row {
                    spacing: 10

                    Repeater {
                        model: [
                            {
                                id: "clab",
                                label: "containerlab"
                            },
                            {
                                id: "netlab",
                                label: "netlab"
                            },
                            {
                                id: "auto",
                                label: "Auto"
                            }
                        ]

                        Item {
                            readonly property bool on: page.get("appIcon", "clab") === modelData.id
                            width: 74
                            height: 64

                            Rectangle {
                                anchors.fill: iconTile
                                anchors.margins: -3
                                radius: 13
                                color: "transparent"
                                border.width: 2
                                border.color: parent.on ? (page.theme.clab || page.theme.ok) : "transparent"
                            }
                            Rectangle {
                                id: iconTile
                                width: 74
                                height: 44
                                radius: 10
                                color: page.theme.card
                                border.width: 1
                                border.color: page.theme.border

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    // Auto shows both, the one in use first.
                                    Repeater {
                                        model: modelData.id === "auto" ? [Theme.appIconVariant("auto", page.get("show", "both")), Theme.appIconVariant("auto", page.get("show", "both")) === "clab" ? "netlab" : "clab"] : [modelData.id]
                                        Image {
                                            width: modelData === undefined ? 0 : 30
                                            height: 30
                                            opacity: index === 0 ? 1 : 0.45
                                            sourceSize: Qt.size(64, 64)
                                            source: Qt.resolvedUrl("../../" + Theme.appIcon(modelData, "both", 64))
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.top: iconTile.bottom
                                anchors.topMargin: 5
                                anchors.horizontalCenter: iconTile.horizontalCenter
                                text: modelData.label
                                color: parent.on ? page.theme.text : page.theme.sub
                                font.pixelSize: page.theme.smallSize
                                font.weight: parent.on ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.set("appIcon", modelData.id)
                            }
                        }
                    }
                }
            }
            SettingRow {
                theme: page.theme
                visible: page.get("surfaceStyle", "tint") === "tint"
                label: "Frosted blur"
                desc: "Soft blur and sheen on the tinted card."
                Toggle {
                    theme: page.theme
                    checked: page.get("frosted", true)
                    onToggled: c => page.set("frosted", c)
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            visible: page.currentTab === "placement" && (page.showMode || page.showPlacement)
            theme: page.theme
            title: "Placement"
            icon: "pin"

            SettingRow {
                theme: page.theme
                first: true
                visible: page.showMode
                stacked: true
                label: "Mode"
                desc: "A pill with a popup, or the card on the desktop below your windows."
                Segmented {
                    theme: page.theme
                    options: [
                        {
                            id: "pill",
                            label: "Pill + popup"
                        },
                        {
                            id: "desktop",
                            label: "Desktop card"
                        }
                    ]
                    value: page.get("mode", "pill")
                    onActivated: v => page.set("mode", v)
                }
            }
            SettingRow {
                theme: page.theme
                first: !page.showMode
                visible: page.showPlacement
                stacked: true
                label: "Corner"
                Segmented {
                    theme: page.theme
                    options: [
                        {
                            id: "top-left",
                            label: "Top left"
                        },
                        {
                            id: "top-right",
                            label: "Top right"
                        },
                        {
                            id: "bottom-left",
                            label: "Bottom left"
                        },
                        {
                            id: "bottom-right",
                            label: "Bottom right"
                        }
                    ]
                    value: page.get("corner", "top-right")
                    onActivated: v => page.set("corner", v)
                }
            }
        }
    }

    ProjectInfoPane {
        Layout.fillWidth: true
        visible: page.currentTab === "info"
        theme: page.theme
    }
}
