pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion
import "TahoeGlass.js" as GlassStyle
import "settings" as Settings
import "settings/SettingsModel.js" as SettingsModel
import "settings/SettingsTheme.js" as SettingsTheme
import "settings/controls" as Controls
import "settings/pages" as Pages

PanelWindow {
    id: root

    property bool open: false
    property string page: "settings"
    property string selectedPage: SettingsModel.resolveId(page)
    property var settingsService
    property var systemStatusService
    property var appearanceService
    property var notificationsService
    property var inputMethodService
    property var controlsService
    property var soundService
    property var batteryService
    property var powerProfileService
    property var powerService
    property bool idleLockEnabled: false
    property real idleLockTimeoutSeconds: 0
    property var networkSettingsService
    property var appsSettingsService
    property var appsService
    property var systemFeaturesService
    property var niriSettingsService
    property var weatherService

    readonly property bool darkMode: appearanceService && appearanceService.darkMode
    readonly property int screenWidth: Math.max(1, numberOr(root.screen && root.screen.width, root.width))
    readonly property int screenHeight: Math.max(1, numberOr(root.screen && root.screen.height, root.height))
    // macOS System Settings converges toward ~900x540; clamp the overlay there
    // on typical screens while keeping a usable floor on small displays. The
    // glass region follows panelSurface geometry, so shrinking the panel keeps
    // the region inside the safe area (no spring on geometry, guardrail 0704ea4).
    readonly property int panelWidth: Math.max(320, Math.min(screenWidth - 32, 900))
    readonly property int panelHeight: Math.max(420, Math.min(screenHeight - 64, 540))
    readonly property int panelLeft: Math.round(Math.max(8, (screenWidth - panelWidth) / 2))
    readonly property int panelTop: Math.round(Math.max(42, (screenHeight - panelHeight) / 2))
    readonly property color textPrimary: SettingsTheme.textPrimary(darkMode)
    readonly property color textSecondary: SettingsTheme.textSecondary(darkMode)
    readonly property color textMuted: SettingsTheme.textMuted(darkMode)
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color accentBlue: SettingsTheme.accent(darkMode, accentId)
    readonly property color panelFill: SettingsTheme.panelFill(darkMode)
    readonly property color panelStroke: SettingsTheme.panelStroke(darkMode)
    readonly property color sectionFill: SettingsTheme.sectionFill(darkMode)
    readonly property color sectionStroke: SettingsTheme.sectionStroke(darkMode)
    readonly property color rowFill: SettingsTheme.rowFill(darkMode)
    readonly property color rowFillHover: SettingsTheme.rowFillHover(darkMode)
    readonly property color rowStroke: SettingsTheme.rowStroke(darkMode)
    readonly property color sidebarFill: SettingsTheme.sidebarFill(darkMode)
    readonly property color sidebarStroke: SettingsTheme.sidebarStroke(darkMode)
    readonly property color sidebarActiveFill: SettingsTheme.sidebarActiveFill(darkMode)
    readonly property color sidebarActiveStroke: SettingsTheme.sidebarActiveStroke(darkMode)
    readonly property color sidebarHoverFill: SettingsTheme.sidebarHoverFill(darkMode)
    readonly property color buttonFill: SettingsTheme.buttonFill(darkMode)
    readonly property color buttonStroke: SettingsTheme.buttonStroke(darkMode)
    readonly property color accentFillStrong: SettingsTheme.accentFillStrong(darkMode, accentId)
    readonly property color accentStrokeStrong: SettingsTheme.accentStrokeStrong(darkMode)
    readonly property color fieldFill: SettingsTheme.fieldFill(darkMode)
    readonly property color fieldStroke: SettingsTheme.fieldStroke(darkMode)
    readonly property color fieldStrokeFocus: SettingsTheme.fieldStrokeFocus(darkMode, accentId)
    readonly property color sliderTrack: SettingsTheme.sliderTrack(darkMode)
    readonly property color switchOff: SettingsTheme.switchOff(darkMode)
    readonly property color tileFill: SettingsTheme.tileFill(darkMode)
    readonly property color tileFillHover: SettingsTheme.tileFillHover(darkMode)
    readonly property color tileStroke: SettingsTheme.tileStroke(darkMode)
    readonly property color tileStrokeHover: SettingsTheme.tileStrokeHover(darkMode)
    readonly property color scrim: SettingsTheme.scrim(darkMode)
    readonly property color danger: SettingsTheme.danger(darkMode)
    readonly property string currentPageId: SettingsModel.resolveId(selectedPage)

    function categoryColor(key) {
        return SettingsTheme.categoryColor(key, darkMode, accentId);
    }

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
        selectedPage = SettingsModel.resolveId(page);
    }

    onSelectedPageChanged: {
        var resolved = SettingsModel.resolveId(selectedPage);
        if (selectedPage !== resolved) {
            selectedPage = resolved;
            return;
        }
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

    function pageInfo(name) {
        return SettingsModel.resolvedPanel(name || selectedPage);
    }

    function pageTitle(name) {
        return SettingsModel.title(name || selectedPage);
    }

    function pageSubtitle(name) {
        var id = SettingsModel.resolveId(name || selectedPage);
        if (id === "health")
            return systemStatusService ? "最后检测 " + systemStatusService.lastUpdatedText : "系统状态检测";
        return SettingsModel.subtitle(id);
    }

    function pageIndex(name) {
        return SettingsModel.pageIndex(name || selectedPage);
    }

    function isSelectedPage(name) {
        return SettingsModel.resolveId(selectedPage) === SettingsModel.resolveId(name);
    }

    function openPage(name) {
        selectedPage = SettingsModel.resolveId(name);
        if (selectedPage === "health" && systemStatusService)
            systemStatusService.refresh();
    }

    function stateLabel(state) {
        return SettingsTheme.stateLabel(state);
    }

    function stateColor(state) {
        return SettingsTheme.stateColor(state, darkMode);
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

    TahoeGlass.regions: [panelSurface.region]

    Rectangle {
        anchors.fill: parent
        color: root.scrim
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Motion.fadeFast(root.settingsService); easing.type: Motion.emphasizedDecel }
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
            NumberAnimation { duration: Motion.panelExit(root.settingsService); easing.type: Motion.emphasizedDecel }
        }

        // Local exception: settings panel scale keeps the existing 160ms settle;
        // opacity is tokenized, but the scale timing is deliberately unchanged.
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Motion.emphasizedDecel }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        GlassPanel {
            id: panelSurface

            anchors.fill: parent
            material: GlassStyle.MaterialPanel
            radius: GlassStyle.RadiusPanel
            fillColor: root.panelFill
            strokeColor: root.panelStroke
            useItemRegion: false
            regionX: Math.round(panel.x + panelSurface.x)
            regionY: Math.round(panel.y + panelSurface.y)
            regionWidth: Math.round(panelSurface.width)
            regionHeight: Math.round(panelSurface.height)
            interaction: 0.0
            materialAlpha: panel.opacity
            regionEnabled: root.open || panel.opacity > 0.01
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
                        visible: root.currentPageId === "health" || root.currentPageId === "about" || root.currentPageId === "system"
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

                        Pages.WifiPage {
                            panel: root
                            theme: root
                            controlsService: root.controlsService
                        }

                        Pages.NetworkPage {
                            panel: root
                            theme: root
                            networkSettingsService: root.networkSettingsService
                        }

                        Pages.BluetoothPage {
                            panel: root
                            theme: root
                            controlsService: root.controlsService
                        }

                        Pages.DisplaysPage {
                            panel: root
                            theme: root
                        }

                        Pages.SoundPage {
                            panel: root
                            theme: root
                        }

                        Pages.PowerPage {
                            panel: root
                            theme: root
                        }

                        Pages.MultitaskingPage {
                            panel: root
                            theme: root
                        }

                        Pages.AppearancePage {
                            panel: root
                            theme: root
                        }

                        Pages.AppsPage {
                            panel: root
                            theme: root
                            appsSettingsService: root.appsSettingsService
                        }

                        Pages.NotificationsPage {
                            panel: root
                            theme: root
                        }

                        Pages.FeatureProbePage {
                            panel: root
                            theme: root
                            panelId: "search"
                        }

                        Pages.ExternalSettingsPage {
                            panel: root
                            theme: root
                            panelId: "online-accounts"
                        }

                        Pages.FeatureProbePage {
                            panel: root
                            theme: root
                            panelId: "sharing"
                        }

                        Pages.ReadOnlyCapabilityPage {
                            panel: root
                            theme: root
                            panelId: "wellbeing"
                        }

                        Pages.MouseTouchpadPage {
                            panel: root
                            theme: root
                        }

                        Pages.KeyboardPage {
                            panel: root
                            theme: root
                        }

                        Pages.ExternalSettingsPage {
                            panel: root
                            theme: root
                            panelId: "color"
                        }

                        Pages.ExternalSettingsPage {
                            panel: root
                            theme: root
                            panelId: "printers"
                        }

                        Pages.ExternalSettingsPage {
                            panel: root
                            theme: root
                            panelId: "accessibility"
                        }

                        Pages.ReadOnlyCapabilityPage {
                            panel: root
                            theme: root
                            panelId: "privacy"
                        }

                        Pages.SystemPage {
                            panel: root
                            theme: root
                        }

                        Pages.NiriPage {
                            panel: root
                            theme: root
                        }

                        Pages.WallpaperPage {
                            panel: root
                            theme: root
                        }

                        Pages.DynamicIslandPage {
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

                        Pages.WeatherPage {
                            panel: root
                            theme: root
                        }

                        Pages.StartupPage {
                            panel: root
                            theme: root
                            appsService: root.appsService
                        }

                        Pages.HealthPage {
                            panel: root
                            theme: root
                        }

                        Pages.AboutPage {
                            panel: root
                            theme: root
                        }

                        Pages.NiriLayoutPage {
                            panel: root
                            theme: root
                        }

                        Pages.NiriGlassPage {
                            panel: root
                            theme: root
                        }

                        Pages.NiriInputPage {
                            panel: root
                            theme: root
                        }

                        Pages.NiriAnimationsPage {
                            panel: root
                            theme: root
                        }

                        Pages.NiriKeyboardPage {
                            panel: root
                            theme: root
                        }

                        Pages.OverviewPage {
                            panel: root
                            theme: root
                        }
                    }
                }
            }
        }
    }
}
