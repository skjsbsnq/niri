pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "settings" as Settings
import "settings/SettingsTheme.js" as SettingsTheme
import "settings/controls" as Controls
import "settings/pages" as Pages

PanelWindow {
    id: root

    property bool open: false
    property string page: "settings"
    property string selectedPage: page.length > 0 ? page : "settings"
    property var settingsService
    property var systemStatusService
    property var appearanceService
    property var notificationsService
    property var inputMethodService

    readonly property bool darkMode: appearanceService && appearanceService.darkMode
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    readonly property int panelWidth: Math.max(320, Math.min(screenWidth - 32, 1080))
    readonly property int panelHeight: Math.max(420, Math.min(screenHeight - 64, 720))
    readonly property int panelLeft: Math.round(Math.max(8, (screenWidth - panelWidth) / 2))
    readonly property int panelTop: Math.round(Math.max(42, (screenHeight - panelHeight) / 2))
    readonly property string iconFont: "Material Icons"
    readonly property color textPrimary: SettingsTheme.textPrimary(darkMode)
    readonly property color textSecondary: SettingsTheme.textSecondary(darkMode)
    readonly property color textMuted: SettingsTheme.textMuted(darkMode)
    readonly property color accentBlue: SettingsTheme.accentBlue(darkMode)
    readonly property color sectionFill: SettingsTheme.sectionFill(darkMode)
    readonly property color sectionStroke: SettingsTheme.sectionStroke(darkMode)
    readonly property color rowFill: SettingsTheme.rowFill(darkMode)
    readonly property color rowFillHover: SettingsTheme.rowFillHover(darkMode)
    readonly property color rowStroke: SettingsTheme.rowStroke(darkMode)

    signal closeRequested()

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: open
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-settings"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    onPageChanged: {
        if (page.length > 0)
            selectedPage = page;
    }

    onOpenChanged: {
        if (open) {
            if (systemStatusService)
                systemStatusService.refresh();
            Qt.callLater(function() {
                if (root.open)
                    focusCatcher.forceActiveFocus();
            });
        }
    }

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function pageTitle() {
        if (selectedPage === "appearance")
            return "外观";
        if (selectedPage === "notifications")
            return "通知与输入";
        if (selectedPage === "screenshot")
            return "截图";
        if (selectedPage === "dock")
            return "Dock";
        if (selectedPage === "startup")
            return "启动项";
        if (selectedPage === "health")
            return "系统健康";
        if (selectedPage === "about")
            return "关于 niri";
        return "概览";
    }

    function pageSubtitle() {
        if (selectedPage === "appearance")
            return "深浅色、夜览和色温";
        if (selectedPage === "notifications")
            return "勿扰、通知历史和输入法状态";
        if (selectedPage === "screenshot")
            return "保存目录、复制和通知动作";
        if (selectedPage === "dock")
            return "窗口按钮显示偏好";
        if (selectedPage === "startup")
            return "XDG autostart 和会话备注";
        if (selectedPage === "health")
            return systemStatusService ? "最后检测 " + systemStatusService.lastUpdatedText : "系统状态检测";
        if (selectedPage === "about")
            return "Tahoe Shell、niri、Quickshell 和当前会话";
        return "常用状态、偏好入口和系统摘要";
    }

    function pageIndex(name) {
        if (name === "appearance")
            return 1;
        if (name === "notifications")
            return 2;
        if (name === "screenshot")
            return 3;
        if (name === "dock")
            return 4;
        if (name === "startup")
            return 5;
        if (name === "health")
            return 6;
        if (name === "about")
            return 7;
        return 0;
    }

    function stateLabel(state) {
        return SettingsTheme.stateLabel(state);
    }

    function stateColor(state) {
        return SettingsTheme.stateColor(state);
    }

    function inputStatusText() {
        if (!inputMethodService)
            return "输入法服务不可用";
        if (!inputMethodService.available)
            return "不可用";
        return inputMethodService.tooltipText;
    }

    function screenshotPathText() {
        return settingsService ? settingsService.effectiveScreenshotDirectory : "";
    }

    function dockTitleMode() {
        return settingsService ? settingsService.dockWindowTitleMode : "auto";
    }

    function setDockTitleMode(mode) {
        if (settingsService)
            settingsService.setDockWindowTitleMode(mode);
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: panel.x + panelSurface.x
            y: panel.y + panelSurface.y
            width: panelSurface.width
            height: panelSurface.height
            material: panelSurface.tahoeGlassMaterial
            radius: panelSurface.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: panel.opacity
            materialAlpha: panel.opacity
            enabled: root.open || panel.opacity > 0.01
        }
    ]

    Rectangle {
        anchors.fill: parent
        color: "#1a101418"
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    FocusScope {
        id: focusCatcher

        anchors.fill: parent
        focus: root.open
        Keys.onEscapePressed: root.closeRequested()
    }

    Item {
        id: panel

        x: root.panelLeft
        y: root.panelTop
        width: root.panelWidth
        height: root.panelHeight
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.985

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        Rectangle {
            id: panelSurface
            readonly property string tahoeGlassMaterial: GlassStyle.MaterialPanel
            readonly property real tahoeGlassRadius: GlassStyle.RadiusPanel

            anchors.fill: parent
            radius: tahoeGlassRadius
            color: GlassStyle.FillPanelBright
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: panelSurface.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Settings.SettingsSidebar {
                panel: root
                theme: root
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: root.pageTitle()
                            color: root.textPrimary
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.pageSubtitle()
                            color: root.textSecondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Controls.TahoeButton {
                        theme: root
                        visible: root.selectedPage === "health" || root.selectedPage === "about"
                        iconCode: "\ue5d5"
                        label: "刷新"
                        enabled: !!root.systemStatusService && !root.systemStatusService.refreshing
                        onActivated: {
                            if (root.systemStatusService)
                                root.systemStatusService.refresh();
                        }
                    }

                    Controls.TahoeButton {
                        theme: root
                        iconOnly: true
                        iconCode: "\ue5cd"
                        onActivated: root.closeRequested()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.pageIndex(root.selectedPage)

                        Pages.OverviewPage {
                            panel: root
                            theme: root
                        }

                        Pages.AppearancePage {
                            panel: root
                            theme: root
                        }

                        Pages.NotificationsPage {
                            panel: root
                            theme: root
                        }

                        Pages.ScreenshotPage {
                            panel: root
                            theme: root
                        }

                        Pages.DockPage {
                            panel: root
                            theme: root
                        }

                        Pages.StartupPage {
                            panel: root
                            theme: root
                        }

                        Pages.HealthPage {
                            panel: root
                            theme: root
                        }

                        Pages.AboutPage {
                            panel: root
                            theme: root
                        }
                    }
                }
            }
        }
    }
}
