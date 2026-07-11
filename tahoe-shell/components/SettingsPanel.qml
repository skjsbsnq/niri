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
    readonly property color buttonFillSolid: SettingsTheme.buttonFillSolid(darkMode)
    readonly property color buttonFillSolidHover: SettingsTheme.buttonFillSolidHover(darkMode)
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
        // pageHost may not exist during early property init.
        if (pageHost)
            pageHost.navigateTo(resolved);
    }

    onOpenChanged: {
        if (open) {
            if (systemStatusService)
                systemStatusService.refresh();
            // Snap to current page with no transition when opening the panel.
            if (pageHost)
                pageHost.snapTo(SettingsModel.resolveId(selectedPage));
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

    // T15: sub-pages (parent in SettingsModel) show a back chevron to parentId.
    function parentPageId(name) {
        var id = SettingsModel.resolveId(name || selectedPage);
        var parent = SettingsModel.parentId(id);
        return parent !== id ? parent : "";
    }

    function canGoBack(name) {
        return parentPageId(name).length > 0;
    }

    function goBack() {
        var parent = parentPageId();
        if (parent.length > 0)
            openPage(parent);
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
                    spacing: 8

                    // T15: sub-page back chevron (SettingsModel.parentId).
                    Controls.TahoeButton {
                        theme: root
                        iconOnly: true
                        iconCode: "\ue5c4"
                        visible: root.canGoBack()
                        onActivated: root.goBack()
                    }

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

                // T15: dual-page host — enter +24px fade, leave -12px parallax;
                // 280ms emphasized. Glass region geometry is not animated.
                Item {
                    id: pageHost

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    property string fromId: ""
                    property string toId: SettingsModel.resolveId(root.selectedPage)
                    property real progress: 1

                    function snapTo(id) {
                        var key = SettingsModel.resolveId(id);
                        progressAnim.stop();
                        fromId = "";
                        toId = key;
                        progress = 1;
                    }

                    // Rapid re-entry: abandon in-flight anim and retarget.
                    function navigateTo(id) {
                        var key = SettingsModel.resolveId(id);
                        if (key === toId && progress >= 0.999) {
                            fromId = "";
                            progress = 1;
                            return;
                        }

                        var leaveId = toId;
                        if (leaveId === key) {
                            snapTo(key);
                            return;
                        }

                        fromId = leaveId;
                        toId = key;
                        progress = 0;
                        progressAnim.stop();
                        progressAnim.duration = Motion.settingsPageTransition(root.settingsService);
                        if (progressAnim.duration <= 0) {
                            progress = 1;
                            fromId = "";
                            return;
                        }
                        progressAnim.start();
                    }

                    function layerOpacity(pageId) {
                        if (pageId === toId)
                            return progress;
                        if (pageId === fromId)
                            return 1 - progress;
                        return 0;
                    }

                    function layerX(pageId) {
                        if (pageId === toId)
                            return Motion.settingsPageEnterOffsetPx * (1 - progress);
                        if (pageId === fromId)
                            return -Motion.settingsPageExitOffsetPx * progress;
                        return 0;
                    }

                    function layerVisible(pageId) {
                        return layerOpacity(pageId) > 0.01;
                    }

                    NumberAnimation {
                        id: progressAnim
                        target: pageHost
                        property: "progress"
                        from: 0
                        to: 1
                        duration: Motion.settingsPageTransitionMs
                        easing.type: Motion.emphasizedDecel
                        onFinished: {
                            pageHost.fromId = "";
                            pageHost.progress = 1;
                        }
                    }

                    Component.onCompleted: snapTo(root.selectedPage)

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("wifi")
                        visible: pageHost.layerVisible("wifi")
                        transform: Translate { x: pageHost.layerX("wifi") }
                        Pages.WifiPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            controlsService: root.controlsService
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("network")
                        visible: pageHost.layerVisible("network")
                        transform: Translate { x: pageHost.layerX("network") }
                        Pages.NetworkPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            networkSettingsService: root.networkSettingsService
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("bluetooth")
                        visible: pageHost.layerVisible("bluetooth")
                        transform: Translate { x: pageHost.layerX("bluetooth") }
                        Pages.BluetoothPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            controlsService: root.controlsService
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("displays")
                        visible: pageHost.layerVisible("displays")
                        transform: Translate { x: pageHost.layerX("displays") }
                        Pages.DisplaysPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("sound")
                        visible: pageHost.layerVisible("sound")
                        transform: Translate { x: pageHost.layerX("sound") }
                        Pages.SoundPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("power")
                        visible: pageHost.layerVisible("power")
                        transform: Translate { x: pageHost.layerX("power") }
                        Pages.PowerPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("multitasking")
                        visible: pageHost.layerVisible("multitasking")
                        transform: Translate { x: pageHost.layerX("multitasking") }
                        Pages.MultitaskingPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("appearance")
                        visible: pageHost.layerVisible("appearance")
                        transform: Translate { x: pageHost.layerX("appearance") }
                        Pages.AppearancePage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("apps")
                        visible: pageHost.layerVisible("apps")
                        transform: Translate { x: pageHost.layerX("apps") }
                        Pages.AppsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            appsSettingsService: root.appsSettingsService
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("notifications")
                        visible: pageHost.layerVisible("notifications")
                        transform: Translate { x: pageHost.layerX("notifications") }
                        Pages.NotificationsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("search")
                        visible: pageHost.layerVisible("search")
                        transform: Translate { x: pageHost.layerX("search") }
                        Pages.FeatureProbePage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "search"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("online-accounts")
                        visible: pageHost.layerVisible("online-accounts")
                        transform: Translate { x: pageHost.layerX("online-accounts") }
                        Pages.ExternalSettingsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "online-accounts"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("sharing")
                        visible: pageHost.layerVisible("sharing")
                        transform: Translate { x: pageHost.layerX("sharing") }
                        Pages.FeatureProbePage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "sharing"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("wellbeing")
                        visible: pageHost.layerVisible("wellbeing")
                        transform: Translate { x: pageHost.layerX("wellbeing") }
                        Pages.ReadOnlyCapabilityPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "wellbeing"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("mouse-touchpad")
                        visible: pageHost.layerVisible("mouse-touchpad")
                        transform: Translate { x: pageHost.layerX("mouse-touchpad") }
                        Pages.MouseTouchpadPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("keyboard")
                        visible: pageHost.layerVisible("keyboard")
                        transform: Translate { x: pageHost.layerX("keyboard") }
                        Pages.KeyboardPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("color")
                        visible: pageHost.layerVisible("color")
                        transform: Translate { x: pageHost.layerX("color") }
                        Pages.ExternalSettingsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "color"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("printers")
                        visible: pageHost.layerVisible("printers")
                        transform: Translate { x: pageHost.layerX("printers") }
                        Pages.ExternalSettingsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "printers"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("accessibility")
                        visible: pageHost.layerVisible("accessibility")
                        transform: Translate { x: pageHost.layerX("accessibility") }
                        Pages.ExternalSettingsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "accessibility"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("privacy")
                        visible: pageHost.layerVisible("privacy")
                        transform: Translate { x: pageHost.layerX("privacy") }
                        Pages.ReadOnlyCapabilityPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            panelId: "privacy"
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("system")
                        visible: pageHost.layerVisible("system")
                        transform: Translate { x: pageHost.layerX("system") }
                        Pages.SystemPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("niri")
                        visible: pageHost.layerVisible("niri")
                        transform: Translate { x: pageHost.layerX("niri") }
                        Pages.NiriPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("wallpaper")
                        visible: pageHost.layerVisible("wallpaper")
                        transform: Translate { x: pageHost.layerX("wallpaper") }
                        Pages.WallpaperPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("dynamic-island")
                        visible: pageHost.layerVisible("dynamic-island")
                        transform: Translate { x: pageHost.layerX("dynamic-island") }
                        Pages.DynamicIslandPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("screenshot")
                        visible: pageHost.layerVisible("screenshot")
                        transform: Translate { x: pageHost.layerX("screenshot") }
                        Pages.ScreenshotPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("dock")
                        visible: pageHost.layerVisible("dock")
                        transform: Translate { x: pageHost.layerX("dock") }
                        Pages.DockPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("weather")
                        visible: pageHost.layerVisible("weather")
                        transform: Translate { x: pageHost.layerX("weather") }
                        Pages.WeatherPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("startup")
                        visible: pageHost.layerVisible("startup")
                        transform: Translate { x: pageHost.layerX("startup") }
                        Pages.StartupPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                            appsService: root.appsService
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("health")
                        visible: pageHost.layerVisible("health")
                        transform: Translate { x: pageHost.layerX("health") }
                        Pages.HealthPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("about")
                        visible: pageHost.layerVisible("about")
                        transform: Translate { x: pageHost.layerX("about") }
                        Pages.AboutPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("niri-layout")
                        visible: pageHost.layerVisible("niri-layout")
                        transform: Translate { x: pageHost.layerX("niri-layout") }
                        Pages.NiriLayoutPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("niri-glass")
                        visible: pageHost.layerVisible("niri-glass")
                        transform: Translate { x: pageHost.layerX("niri-glass") }
                        Pages.NiriGlassPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("niri-input")
                        visible: pageHost.layerVisible("niri-input")
                        transform: Translate { x: pageHost.layerX("niri-input") }
                        Pages.NiriInputPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("niri-animations")
                        visible: pageHost.layerVisible("niri-animations")
                        transform: Translate { x: pageHost.layerX("niri-animations") }
                        Pages.NiriAnimationsPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("niri-keyboard")
                        visible: pageHost.layerVisible("niri-keyboard")
                        transform: Translate { x: pageHost.layerX("niri-keyboard") }
                        Pages.NiriKeyboardPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: pageHost.layerOpacity("overview")
                        visible: pageHost.layerVisible("overview")
                        transform: Translate { x: pageHost.layerX("overview") }
                        Pages.OverviewPage {
                            anchors.fill: parent
                            panel: root
                            theme: root
                        }
                    }
                }
            }
        }
    }
}
