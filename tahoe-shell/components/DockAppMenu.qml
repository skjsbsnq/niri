pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property bool open: false
    property var appsService
    property var app: null
    property string appId: ""
    property var anchorRect: null
    property var settingsService
    property bool darkMode: false
    readonly property int edgePadding: 8
    readonly property int popupGap: 8
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: 224
    readonly property int panelHeight: Math.max(1, panel.implicitHeight)
    readonly property string resolvedAppId: resolvedPinnedId()
    readonly property var resolvedApp: appsService ? appsService.resolveApplication(resolvedAppId, app) : app
    readonly property bool hasApp: !!resolvedApp || resolvedAppId.length > 0
    readonly property bool canUnpin: hasApp && resolvedAppId !== "launchpad" && !!appsService
    readonly property string appTitle: appsService && hasApp ? appsService.appLabel(resolvedApp || resolvedAppId) : "应用"
    readonly property string appIcon: appsService && hasApp ? appsService.iconForApp(resolvedApp || resolvedAppId) : ""
    readonly property int popupLeft: popupLeftFor()
    readonly property int popupTop: popupTopFor()
    readonly property real popupOriginX: Math.max(0, Math.min(panel.width, anchorCenterX() - root.popupLeft))
    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-dock-app-menu"

    anchors {
        left: true
        top: true
    }

    margins {
        left: root.popupLeft
        top: root.popupTop
    }

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function anchorCenterX() {
        if (!anchorRect)
            return root.width / 2;

        var width = numberOr(anchorRect.width, numberOr(anchorRect.w, 1));
        return numberOr(anchorRect.x, 0) + width / 2;
    }

    function popupLeftFor() {
        var maxLeft = Math.max(edgePadding, root.screenWidth - panelWidth - edgePadding);
        return Math.round(Math.max(edgePadding, Math.min(maxLeft, anchorCenterX() - panelWidth / 2)));
    }

    function popupTopFor() {
        var maxTop = Math.max(edgePadding, root.screenHeight - panelHeight - edgePadding);
        if (!anchorRect)
            return maxTop;

        var y = numberOr(anchorRect.y, root.height - 96);
        return Math.round(Math.max(edgePadding, Math.min(maxTop, y - panelHeight - popupGap)));
    }

    function resolvedPinnedId() {
        var stable = String(appId || "").trim();
        if (stable.length > 0)
            return stable;
        if (appsService && app)
            return appsService.appStableId(app);
        return "";
    }

    TahoeGlass.regions: [panel.region]

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    GlassPanel {
        id: panel

        z: 1
        x: 0
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 16
        height: implicitHeight
        material: GlassStyle.MaterialMenu
        radius: GlassStyle.RadiusMenu
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    radius: 8
                    color: "#48ffffff"
                    border.color: "#40ffffff"

                    Image {
                        id: headerIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: root.appIcon
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: root.appIcon.length > 0 && status !== Image.Error
                    }

                    TahoeSymbol {
                        anchors.centerIn: parent
                        name: "\ue8b8"
                        color: root.darkMode ? "#94a0ad" : "#661d1d1f"
                        size: 16
                        visible: !headerIcon.visible
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.appTitle
                    color: root.darkMode ? "#f5f7fb" : "#1d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "打开"
                icon: "\ue89e"
                enabledRow: root.hasApp && !!root.appsService
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.appsService && root.hasApp)
                        root.appsService.launchPinnedApp(root.resolvedApp, root.resolvedAppId);
                    root.closeRequested();
                }
            }

            MenuRow {
                text: "从 Dock 移除"
                icon: "\ue872"
                destructive: true
                enabledRow: root.canUnpin
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.canUnpin)
                        root.appsService.unpinAppId(root.resolvedAppId);
                    root.closeRequested();
                }
            }
        }
    }
}
