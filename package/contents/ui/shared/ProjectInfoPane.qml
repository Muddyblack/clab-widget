import QtQuick
import QtQuick.Layouts
import "../../code/ProjectInfo.js" as Project

ColumnLayout {
    id: info

    property var theme: null
    readonly property var activeTheme: theme ? theme : ({
        text: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Kirigami.Theme.textColor : "#e2e8f0",
        sub: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6) : "#94a3b8",
        card: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05) : Qt.rgba(1, 1, 1, 0.04),
        cardSolid: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Kirigami.Theme.backgroundColor : "#111318",
        badge: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : Qt.rgba(1, 1, 1, 0.07),
        hover: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25) : Qt.rgba(1, 1, 1, 0.10),
        border: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12) : Qt.rgba(1, 1, 1, 0.12),
        ok: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Kirigami.Theme.positiveTextColor : "#4ade80",
        warn: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Kirigami.Theme.neutralTextColor : "#fbbf24",
        bad: (typeof Kirigami !== "undefined" && Kirigami.Theme) ? Kirigami.Theme.negativeTextColor : "#f87171",
        fontSize: (typeof Kirigami !== "undefined" && Kirigami.Theme && Kirigami.Theme.defaultFont.pixelSize > 0) ? Kirigami.Theme.defaultFont.pixelSize : 13,
        smallSize: (typeof Kirigami !== "undefined" && Kirigami.Theme && Kirigami.Theme.smallFont.pixelSize > 0) ? Kirigami.Theme.smallFont.pixelSize : 11
    })

    readonly property string iconDir: Qt.resolvedUrl("../../icons/")
    property var counts: ({})
    property var contributorList: []
    property var requests: []
    property bool requested: false
    readonly property string currentVersion: Project.currentVersion
    property string latestVersion: ""
    property string releaseCheckState: "Not checked"
    readonly property string versionStatus: latestVersion ? Project.releaseStatus(currentVersion, latestVersion) : releaseCheckState
    readonly property bool onlineEnabled: true

    spacing: 12

    function checkRelease() {
        if (!onlineEnabled || releaseCheckState === "Checking…")
            return;
        latestVersion = "";
        releaseCheckState = "Checking…";
        const request = new XMLHttpRequest();
        requests.push(request);
        request.open("GET", Project.latestReleaseUrl);
        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            info.latestVersion = request.status === 200 ? Project.releaseVersion(request.responseText) : "";
            info.releaseCheckState = info.latestVersion ? "Checked" : "Could not check for updates";
        };
        request.send();
        timeout.restart();
    }

    function loadCounts() {
        if (!onlineEnabled || requested)
            return;
        requested = true;
        checkRelease();
        Project.statistics.forEach(function (stat) {
            const request = new XMLHttpRequest();
            info.requests.push(request);
            request.open("GET", stat.url);
            request.onreadystatechange = function () {
                if (request.readyState !== XMLHttpRequest.DONE || request.status !== 200)
                    return;
                const value = Project.count(request.responseText);
                if (value) {
                    const next = Object.assign({}, info.counts);
                    next[stat.id] = value;
                    info.counts = next;
                }
            };
            request.send();
        });
        const contributorsRequest = new XMLHttpRequest();
        requests.push(contributorsRequest);
        contributorsRequest.open("GET", Project.contributorsUrl);
        contributorsRequest.onreadystatechange = function () {
            if (contributorsRequest.readyState === XMLHttpRequest.DONE && contributorsRequest.status === 200)
                info.contributorList = Project.contributors(contributorsRequest.responseText);
        };
        contributorsRequest.send();
        timeout.restart();
    }

    function cancelRequests() {
        requests.forEach(function (request) {
            request.onreadystatechange = null;
            request.abort();
        });
        requests = [];
        if (releaseCheckState === "Checking…")
            releaseCheckState = "Could not check for updates";
    }

    onVisibleChanged: {
        if (visible && !requested)
            loadCounts();
    }
    Component.onCompleted: loadCounts()
    Component.onDestruction: cancelRequests()

    Timer {
        id: timeout
        interval: 8000
        onTriggered: info.cancelRequests()
    }

    // ── Header (Icon, Title, Author) ─────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        Image {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            source: Qt.resolvedUrl("../../icons/app/org.muddyblack.clabWidget-64.png")
            sourceSize.width: 104
            sourceSize.height: 104
            fillMode: Image.PreserveAspectFit
            Accessible.name: "CLAB Widget icon"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: Project.name
                wrapMode: Text.WordWrap
                color: info.activeTheme.text
                font.pixelSize: info.activeTheme.fontSize + 3
                font.bold: true
            }

            RowLayout {
                spacing: 8

                RoundAvatar {
                    theme: info.activeTheme
                    login: Project.author
                    source: info.onlineEnabled ? Project.avatar : ""
                    implicitWidth: 24
                    implicitHeight: 24
                }

                ActionButton {
                    theme: info.activeTheme
                    text: "By " + Project.author + " ↗"
                    onClicked: Qt.openUrlExternally(Project.profile)
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "Containerlab & netlab lab status on your desktop: which labs are running, which nodes are down, how much memory they use, and one click back into VS Code or a node shell."
        wrapMode: Text.WordWrap
        color: info.activeTheme.sub
        font.pixelSize: info.activeTheme.smallSize
        lineHeight: 1.25
    }

    // ── Version Card ─────────────────────────────────────────────────────────
    Rectangle {
        objectName: "projectVersion"
        Layout.fillWidth: true
        implicitHeight: versionContent.implicitHeight + 20
        radius: 8
        color: info.activeTheme.card
        border.color: info.activeTheme.border
        border.width: 1

        ColumnLayout {
            id: versionContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Text {
                text: "Installed version · " + info.currentVersion
                color: info.activeTheme.text
                font.pixelSize: info.activeTheme.smallSize
                font.bold: true
            }

            Text {
                objectName: "latestVersionLabel"
                text: "Latest stable release · " + (info.latestVersion || "—")
                color: info.activeTheme.sub
                font.pixelSize: info.activeTheme.smallSize - 1
            }

            Text {
                objectName: "versionStatusLabel"
                Layout.fillWidth: true
                text: info.versionStatus
                wrapMode: Text.WordWrap
                color: {
                    if (text === "Update available") return info.activeTheme.warn;
                    if (text === "Up to date") return info.activeTheme.ok;
                    return info.activeTheme.sub;
                }
                font.pixelSize: info.activeTheme.smallSize - 1
            }

            RowLayout {
                spacing: 8

                ActionButton {
                    theme: info.activeTheme
                    text: info.versionStatus === "Update available" ? "Get update ↗" : "View latest release ↗"
                    onClicked: Qt.openUrlExternally(Project.releasesPage)
                }

                ActionButton {
                    theme: info.activeTheme
                    text: "Check again"
                    enabled: info.onlineEnabled && info.releaseCheckState !== "Checking…"
                    onClicked: info.checkRelease()
                }
            }
        }
    }

    // ── Statistics Cards ─────────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: Project.statistics

            Rectangle {
                id: statBox
                required property var modelData
                objectName: "stat_" + modelData.id
                width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                height: 64
                radius: 8
                color: statArea.containsMouse ? info.activeTheme.hover : info.activeTheme.card
                border.width: 1
                border.color: statArea.containsMouse ? info.activeTheme.sub : info.activeTheme.border

                Image {
                    objectName: "statIcon_" + statBox.modelData.id
                    x: 10
                    y: 10
                    width: 20
                    height: 20
                    source: info.iconDir + statBox.modelData.icon
                    sourceSize: Qt.size(40, 40)
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    x: 38
                    y: 8
                    text: info.counts[statBox.modelData.id] || "—"
                    color: info.activeTheme.text
                    font.pixelSize: info.activeTheme.fontSize + 3
                    font.bold: true
                }

                Text {
                    x: 10
                    y: 36
                    width: parent.width - 20
                    text: statBox.modelData.label + " ↗"
                    color: info.activeTheme.sub
                    font.pixelSize: info.activeTheme.smallSize - 1
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: statArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    Accessible.name: statBox.modelData.label + ", open " + statBox.modelData.href
                    onClicked: Qt.openUrlExternally(statBox.modelData.href)
                }
            }
        }
    }

    // ── Referenced Tools & Ecosystem (Containerlab & netlab from ipSpace) ────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            text: "Referenced Tools"
            color: info.activeTheme.text
            font.pixelSize: info.activeTheme.fontSize
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: "CLAB Widget monitors and links into labs created with these network orchestration tools:"
            color: info.activeTheme.sub
            font.pixelSize: info.activeTheme.smallSize - 1
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: Project.references

                Rectangle {
                    id: refCard
                    required property var modelData
                    objectName: "ref_" + modelData.id
                    width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                    height: 72
                    radius: 8
                    color: refArea.containsMouse ? info.activeTheme.hover : info.activeTheme.card
                    border.width: 1
                    border.color: refArea.containsMouse ? info.activeTheme.sub : info.activeTheme.border

                    Image {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        source: info.iconDir + refCard.modelData.icon
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(56, 56)
                    }

                    ColumnLayout {
                        x: 46
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 54
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: refCard.modelData.name + " ↗"
                            color: info.activeTheme.text
                            font.pixelSize: info.activeTheme.smallSize
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: refCard.modelData.by
                            color: info.activeTheme.sub
                            font.pixelSize: info.activeTheme.smallSize - 2
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: refCard.modelData.desc
                            color: info.activeTheme.sub
                            font.pixelSize: info.activeTheme.smallSize - 2
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: refArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: refCard.modelData.name + " (" + refCard.modelData.by + ")"
                        onClicked: Qt.openUrlExternally(refCard.modelData.url)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Community project. Not affiliated with srl-labs/Nokia (containerlab) or ipSpace (netlab)."
            color: info.activeTheme.sub
            font.pixelSize: info.activeTheme.smallSize - 2
            wrapMode: Text.WordWrap
            opacity: 0.8
        }
    }

    // ── License Card ─────────────────────────────────────────────────────────
    Rectangle {
        objectName: "projectLicense"
        Layout.fillWidth: true
        height: 52
        radius: 8
        color: info.activeTheme.card
        border.color: info.activeTheme.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Text {
                text: "License · " + Project.license
                color: info.activeTheme.text
                font.pixelSize: info.activeTheme.smallSize
                font.bold: true
            }

            Text {
                text: Project.licenseId + " · From the bundled LICENSE file"
                color: info.activeTheme.sub
                font.pixelSize: info.activeTheme.smallSize - 2
            }
        }
    }

    // ── Contributors Section ─────────────────────────────────────────────────
    ColumnLayout {
        objectName: "contributorsSection"
        Layout.fillWidth: true
        visible: info.contributorList.length > 0
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Contributors"
                color: info.activeTheme.text
                font.pixelSize: info.activeTheme.fontSize
                font.bold: true
            }

            Item {
                Layout.fillWidth: true
            }

            ActionButton {
                theme: info.activeTheme
                text: "See all on GitHub ↗"
                onClicked: Qt.openUrlExternally(Project.contributorsPage)
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: info.contributorList

                Rectangle {
                    id: contributorCard
                    required property var modelData
                    objectName: "contributor_" + modelData.login
                    width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                    height: 50
                    radius: 8
                    color: contributorArea.containsMouse ? info.activeTheme.hover : info.activeTheme.card
                    border.color: contributorArea.containsMouse ? info.activeTheme.sub : info.activeTheme.border
                    border.width: 1

                    RoundAvatar {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        theme: info.activeTheme
                        login: contributorCard.modelData.login
                        source: info.onlineEnabled ? contributorCard.modelData.avatar : ""
                        implicitWidth: 30
                        implicitHeight: 30
                    }

                    ColumnLayout {
                        x: 46
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 54
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: contributorCard.modelData.login
                            elide: Text.ElideRight
                            color: info.activeTheme.text
                            font.pixelSize: info.activeTheme.smallSize
                            font.bold: true
                        }

                        Text {
                            text: contributorCard.modelData.commits + (contributorCard.modelData.commits === 1 ? " commit" : " commits")
                            color: info.activeTheme.sub
                            font.pixelSize: info.activeTheme.smallSize - 2
                        }
                    }

                    MouseArea {
                        id: contributorArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: "Open " + contributorCard.modelData.login + " on GitHub"
                        onClicked: Qt.openUrlExternally(contributorCard.modelData.profile)
                    }
                }
            }
        }
    }

    // ── Footer Actions ───────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ActionButton {
            theme: info.activeTheme
            text: "View source on GitHub ↗"
            onClicked: Qt.openUrlExternally(Project.repository)
        }

        ActionButton {
            theme: info.activeTheme
            text: "Report an issue ↗"
            onClicked: Qt.openUrlExternally(Project.repository + "/issues")
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
