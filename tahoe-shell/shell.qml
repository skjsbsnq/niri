//@ pragma ShellId tahoe
//@ pragma AppId org.quickshell.tahoe
//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "services"

ShellRoot {
    id: shell

    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property bool appMenuOpen: false
    property bool applicationMenuOpen: false
    property bool spotlightOpen: false
    property bool notificationCenterOpen: false
    property bool batteryPopupOpen: false
    property bool wifiPopupOpen: false
    property bool fanPopupOpen: false
    property bool clipboardPopupOpen: false
    property bool trayMenuOpen: false
    property var trayMenuItem: null
    property var topBarPopupAnchorRect: null
    property string topBarPopupScreenName: ""
    property bool dockAppMenuOpen: false
    property var dockAppMenuApp: null
    property string dockAppMenuAppId: ""
    property var dockAppMenuAnchorRect: null
    property string dockAppMenuScreenName: ""
    property bool dockWindowMenuOpen: false
    property var dockWindowMenuWindow: null
    property var dockWindowMenuAnchorRect: null
    property string dockWindowMenuScreenName: ""
    property bool taskSwitcherOpen: false
    property string taskSwitcherScreenName: ""
    property bool windowOverviewOpen: false
    property string windowOverviewScreenName: ""
    property bool settingsPanelOpen: false
    property string settingsPanelScreenName: ""
    property string settingsPanelPage: "settings"
    property bool leftSidebarOpen: false
    property string leftSidebarScreenName: ""
    // LS07 ProcessMenu state（照 dockWindowMenu 模式：open/screen/anchorRect/data 四件套）。
    property bool processMenuOpen: false
    property string processMenuScreenName: ""
    property var processMenuAnchorRect: null
    property var processMenuProc: null
    // Global default font. Noto Sans CJK SC covers Chinese and Latin; the
    // fontconfig fallback installed by arch-zh-setup handles emoji/edge cases.
    property string baseFontFamily: "Noto Sans CJK SC"
    property string monoFontFamily: "Noto Sans Mono CJK SC"
    property bool darkMode: appearance.darkMode
    readonly property real idleLockTimeoutSeconds: Math.max(0, envNumber("TAHOE_IDLE_LOCK_SECONDS", 600))
    readonly property bool idleLockEnabled: idleLockTimeoutSeconds > 0
    property string lastLockSource: ""

    // Real hardware default: spring gives the dock and panel animations their
    // bouncy settle. If Image textures vanish on a VM/software renderer, flip
    // this back to false; components gate their spring Behaviors through it.
    // Blur/glass region geometry stays on bounded NumberAnimation paths.
    property bool useSpring: true

    signal taskSwitcherCycleRequested(int direction)
    signal taskSwitcherConfirmRequested()

    function envNumber(name, fallback) {
        var raw = Quickshell.env(name);
        var parsed = parseFloat(String(raw || ""));
        return isNaN(parsed) ? fallback : parsed;
    }

    function screenName(screen) {
        return screen ? String(screen.name || "") : "";
    }

    function navigationScreenName() {
        var focused = niri ? niri.focusedWindow : null;
        var output = focused ? String(focused.output || "").trim() : "";
        if (output.length > 0)
            return output;

        var screens = [...Quickshell.screens];
        return screens.length > 0 ? screenName(screens[0]) : "";
    }

    function navigationOpenFor(open, targetScreenName, screen) {
        var target = String(targetScreenName || "");
        return open && (target.length === 0 || target === screenName(screen));
    }

    function prepareTopBarPopup(screen, anchorRect) {
        topBarPopupScreenName = screenName(screen);
        topBarPopupAnchorRect = anchorRect || null;
    }

    function closeLaunchpadAndSpotlight() {
        launchpadOpen = false;
        spotlightOpen = false;
    }

    function topBarPopupOpenValue(popupName) {
        switch (popupName) {
        case "appMenu":
            return appMenuOpen;
        case "applicationMenu":
            return applicationMenuOpen;
        case "controlCenter":
            return controlCenterOpen;
        case "notificationCenter":
            return notificationCenterOpen;
        case "battery":
            return batteryPopupOpen;
        case "wifi":
            return wifiPopupOpen;
        case "fan":
            return fanPopupOpen;
        case "clipboard":
            return clipboardPopupOpen;
        case "trayMenu":
            return trayMenuOpen;
        default:
            return false;
        }
    }

    function setTopBarPopupOpen(popupName, open) {
        switch (popupName) {
        case "appMenu":
            appMenuOpen = open;
            break;
        case "applicationMenu":
            applicationMenuOpen = open;
            break;
        case "controlCenter":
            controlCenterOpen = open;
            break;
        case "notificationCenter":
            notificationCenterOpen = open;
            break;
        case "battery":
            batteryPopupOpen = open;
            break;
        case "wifi":
            wifiPopupOpen = open;
            break;
        case "fan":
            fanPopupOpen = open;
            break;
        case "clipboard":
            clipboardPopupOpen = open;
            break;
        case "trayMenu":
            trayMenuOpen = open;
            if (!open)
                trayMenuItem = null;
            break;
        }
    }

    function topBarPopupOpenForName(popupName, screen) {
        return topBarPopupOpenFor(topBarPopupOpenValue(popupName), screen);
    }

    function toggleTopBarPopup(popupName, screen, anchorRect) {
        var wasOpenHere = topBarPopupOpenForName(popupName, screen);
        prepareTopBarPopup(screen, anchorRect);
        closeTopBarPopups(popupName);
        setTopBarPopupOpen(popupName, !wasOpenHere);
        closeLaunchpadAndSpotlight();
    }

    function openTopBarTrayMenu(item, screen, anchorRect) {
        prepareTopBarPopup(screen, anchorRect);
        closeTopBarPopups("trayMenu");
        trayMenuItem = item;
        trayMenuOpen = true;
        closeLaunchpadAndSpotlight();
    }

    function screenByName(name) {
        var target = String(name || "");
        var screens = [...Quickshell.screens];
        for (var i = 0; i < screens.length; i++) {
            if (screenName(screens[i]) === target)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function dynamicIslandAnchorRect(screen) {
        var width = Math.max(1, Number(screen && screen.width) || 1);
        var islandWidth = dynamicIsland && dynamicIsland.state === "expanded_summary" ? 360
            : dynamicIsland && dynamicIsland.state === "expanded_media" ? 400
            : 140;
        return {
            "x": Math.round(Math.max(0, (width - islandWidth) / 2)),
            "y": 0,
            "width": Math.round(islandWidth),
            "height": 38
        };
    }

    function openDynamicIslandControlCenter() {
        var screen = screenByName(dynamicIsland ? dynamicIsland.targetScreenName : navigationScreenName());
        if (!screen)
            return;
        toggleTopBarPopup("controlCenter", screen, dynamicIslandAnchorRect(screen));
    }

    function openDynamicIslandNotificationCenter() {
        var screen = screenByName(dynamicIsland ? dynamicIsland.targetScreenName : navigationScreenName());
        if (!screen)
            return;
        toggleTopBarPopup("notificationCenter", screen, dynamicIslandAnchorRect(screen));
    }

    function requestLock(source) {
        lastLockSource = String(source || "unknown");
        if (power && power.requestAction) {
            power.requestAction("lock");
        } else if (lockScreen && lockScreen.lock) {
            lockScreen.lock();
        }
        return lockStatus();
    }

    function lockStatus() {
        return [
            "locked=" + (lockScreen ? lockScreen.locked : false),
            "secure=" + (lockScreen ? lockScreen.secure : false),
            "source=" + lastLockSource,
            "idleEnabled=" + idleLockEnabled,
            "idleTimeoutSeconds=" + idleLockTimeoutSeconds
        ].join("; ");
    }

    function topBarPopupOpenFor(open, screen) {
        return open && topBarPopupScreenName === screenName(screen);
    }

    function topBarDismissOpenFor(screen) {
        return topBarPopupOpenFor(appMenuOpen, screen)
            || topBarPopupOpenFor(applicationMenuOpen, screen)
            || topBarPopupOpenFor(controlCenterOpen, screen)
            || topBarPopupOpenFor(notificationCenterOpen, screen)
            || topBarPopupOpenFor(batteryPopupOpen, screen)
            || topBarPopupOpenFor(wifiPopupOpen, screen)
            || topBarPopupOpenFor(fanPopupOpen, screen)
            || topBarPopupOpenFor(clipboardPopupOpen, screen)
            || topBarPopupOpenFor(trayMenuOpen, screen);
    }

    function topBarDismissPopupWidth() {
        if (applicationMenuOpen)
            return 286;
        if (controlCenterOpen)
            return 360;
        if (notificationCenterOpen)
            return 360;
        if (batteryPopupOpen)
            return 292;
        if (wifiPopupOpen)
            return 328;
        if (fanPopupOpen)
            return 328;
        if (clipboardPopupOpen)
            return 360;
        if (trayMenuOpen)
            return 238;
        return 218;
    }

    function topBarDismissPopupHeight() {
        if (applicationMenuOpen)
            return 700;
        if (controlCenterOpen)
            return 380;
        if (notificationCenterOpen)
            return 560;
        if (batteryPopupOpen)
            return 340;
        if (wifiPopupOpen)
            return 520;
        if (fanPopupOpen)
            return 440;
        if (clipboardPopupOpen)
            return 620;
        if (trayMenuOpen)
            return 560;
        return 420;
    }

    function topBarDismissFallbackRight() {
        if (applicationMenuOpen)
            return 96;
        if (notificationCenterOpen)
            return 56;
        if (batteryPopupOpen)
            return 92;
        if (wifiPopupOpen)
            return 132;
        if (fanPopupOpen)
            return 164;
        if (clipboardPopupOpen)
            return 202;
        if (trayMenuOpen)
            return 40;
        return 12;
    }

    function prepareDockAppMenu(screen, app, appId, anchorRect) {
        dockAppMenuScreenName = screenName(screen);
        dockAppMenuApp = app || null;
        dockAppMenuAppId = String(appId || "");
        dockAppMenuAnchorRect = anchorRect || null;
    }

    function dockAppMenuOpenFor(screen) {
        return dockAppMenuOpen && dockAppMenuScreenName === screenName(screen);
    }

    function closeDockAppMenu() {
        dockAppMenuOpen = false;
    }

    function prepareDockWindowMenu(screen, window, anchorRect) {
        dockWindowMenuScreenName = screenName(screen);
        dockWindowMenuWindow = window || null;
        dockWindowMenuAnchorRect = anchorRect || null;
    }

    function dockWindowMenuOpenFor(screen) {
        return dockWindowMenuOpen && dockWindowMenuScreenName === screenName(screen);
    }

    function closeDockWindowMenu() {
        dockWindowMenuOpen = false;
    }

    function closeDockMenus() {
        closeDockAppMenu();
        closeDockWindowMenu();
    }

    // LS07 ProcessMenu：进程行右键菜单的状态协调，照 dockWindowMenu 模式。
    function prepareProcessMenu(screen, proc, anchorRect) {
        processMenuScreenName = screenName(screen);
        processMenuProc = proc || null;
        processMenuAnchorRect = anchorRect || null;
    }

    function processMenuOpenFor(screen) {
        return processMenuOpen && processMenuScreenName === screenName(screen);
    }

    function closeProcessMenu() {
        processMenuOpen = false;
    }

    function closeTaskSwitcher() {
        taskSwitcherOpen = false;
    }

    function closeWindowOverview() {
        windowOverviewOpen = false;
    }

    function closeSettingsPanel() {
        settingsPanelOpen = false;
    }

    function closeLeftSidebar() {
        leftSidebarOpen = false;
        // 关侧边栏时一并收起进程右键菜单（否则菜单会悬空）。
        closeProcessMenu();
    }

    function closeWindowNavigation(except) {
        if (except !== "taskSwitcher")
            closeTaskSwitcher();
        if (except !== "windowOverview")
            closeWindowOverview();
    }

    function prepareWindowNavigation() {
        var target = navigationScreenName();
        taskSwitcherScreenName = target;
        windowOverviewScreenName = target;
    }

    function cycleTaskSwitcher(direction) {
        if (!niri || !niri.recentWindowList || niri.recentWindowList.length === 0)
            return;

        prepareWindowNavigation();
        closeTopBarPopups("taskSwitcher");
        closeWindowNavigation("taskSwitcher");
        closeLaunchpadAndSpotlight();
        taskSwitcherOpen = true;
        taskSwitcherCycleRequested(direction);
    }

    function showTaskSwitcher() {
        cycleTaskSwitcher(0);
    }

    function confirmTaskSwitcher() {
        if (taskSwitcherOpen)
            taskSwitcherConfirmRequested();
    }

    function openWindowOverview() {
        prepareWindowNavigation();
        closeTopBarPopups("windowOverview");
        closeWindowNavigation("windowOverview");
        closeLaunchpadAndSpotlight();
        windowOverviewOpen = true;
    }

    function toggleWindowOverview() {
        if (windowOverviewOpen) {
            closeWindowOverview();
        } else {
            openWindowOverview();
        }
    }

    function openSettingsPanel(page) {
        var targetPage = String(page || "settings");
        if (targetPage.length === 0)
            targetPage = "settings";

        settingsPanelPage = targetPage;
        settingsPanelScreenName = navigationScreenName();
        closeTopBarPopups("settings");
        closeWindowNavigation("");
        closeLaunchpadAndSpotlight();
        settingsPanelOpen = true;
    }

    function openClipboardPopupFromSearch() {
        var screen = screenByName(navigationScreenName());
        if (!screen)
            return;

        prepareTopBarPopup(screen, dynamicIslandAnchorRect(screen));
        closeTopBarPopups("clipboard");
        clipboardPopupOpen = true;
        closeLaunchpadAndSpotlight();
    }

    function requestPowerActionFromSearch(action) {
        var text = String(action || "");
        if (text.length === 0 || !power || !power.requestAction)
            return;

        var pending = power.requestAction(text);
        if (!pending)
            return;

        var screen = screenByName(navigationScreenName());
        if (!screen)
            return;

        prepareTopBarPopup(screen, dynamicIslandAnchorRect(screen));
        closeTopBarPopups("appMenu");
        appMenuOpen = true;
        closeLaunchpadAndSpotlight();
    }

    function runSearchSystemAction(action) {
        var text = String(action || "");
        if (text === "lock") {
            requestLock("spotlight");
        } else if (text === "overview") {
            openWindowOverview();
        } else if (text === "task-switcher") {
            showTaskSwitcher();
        } else if (text === "launchpad") {
            closeTopBarPopups("launchpad");
            spotlightOpen = false;
            launchpadOpen = true;
        } else if (text === "control-center") {
            openDynamicIslandControlCenter();
        } else if (text === "notification-center") {
            openDynamicIslandNotificationCenter();
        } else if (text === "clipboard") {
            openClipboardPopupFromSearch();
        } else if (text === "sleep" || text === "logout" || text === "restart" || text === "shutdown") {
            requestPowerActionFromSearch(text);
        }
    }

    function toggleLeftSidebar(screen) {
        var target = screenName(screen);
        var wasOpenHere = leftSidebarOpen
            && (leftSidebarScreenName.length === 0 || leftSidebarScreenName === target);
        leftSidebarScreenName = target;
        closeTopBarPopups("leftSidebar");
        leftSidebarOpen = !wasOpenHere;
        closeLaunchpadAndSpotlight();
    }

    function closeTopBarPopups(except) {
        if (except !== "appMenu")
            appMenuOpen = false;
        if (except !== "applicationMenu")
            applicationMenuOpen = false;
        if (except !== "controlCenter")
            controlCenterOpen = false;
        if (except !== "notificationCenter")
            notificationCenterOpen = false;
        if (except !== "battery")
            batteryPopupOpen = false;
        if (except !== "wifi")
            wifiPopupOpen = false;
        if (except !== "fan")
            fanPopupOpen = false;
        if (except !== "clipboard")
            clipboardPopupOpen = false;
        if (except !== "trayMenu") {
            trayMenuOpen = false;
            trayMenuItem = null;
        }
        if (except !== "dockAppMenu")
            closeDockAppMenu();
        if (except !== "dockWindowMenu")
            closeDockWindowMenu();
        if (except !== "processMenu")
            closeProcessMenu();
        if (except !== "settings")
            closeSettingsPanel();
        if (except !== "leftSidebar" && except !== "processMenu")
            closeLeftSidebar();
        closeWindowNavigation(except);
    }

    onWifiPopupOpenChanged: if (wifiPopupOpen) {
        appMenuOpen = false;
        applicationMenuOpen = false;
        controlCenterOpen = false;
        closeLaunchpadAndSpotlight();
        notificationCenterOpen = false;
        batteryPopupOpen = false;
        fanPopupOpen = false;
        clipboardPopupOpen = false;
        trayMenuOpen = false;
        closeDockMenus();
        closeWindowNavigation("");
        closeSettingsPanel();
        closeLeftSidebar();
    }

    // Register the Material Icons font once for the whole shell. Used by the
    // Control Center (Text { font.family: "Material Icons" }). The font ships
    // under assets/fonts/ and is resolved through Quickshell.shellPath.
    FontLoader {
        source: Quickshell.shellPath("assets/fonts/MaterialIconsRound.ttf")
    }

    Component.onCompleted: {
        Qt.application.font = Qt.font({
            family: shell.baseFontFamily,
            pixelSize: 13
        });
    }

    Apps {
        id: apps
        settingsService: desktopSettings
    }

    Windows {
        id: niri
    }

    ThumbnailProvider {
        id: thumbnailProvider
        windowsService: niri
    }

    CommandRunner {
        id: commandRunner
    }

    IpcHandler {
        target: "tahoe"

        function openTaskSwitcher(): void { shell.cycleTaskSwitcher(1); }
        function showTaskSwitcher(): void { shell.showTaskSwitcher(); }
        function cycleTaskSwitcher(direction: int): void { shell.cycleTaskSwitcher(direction); }
        function confirmTaskSwitcher(): void { shell.confirmTaskSwitcher(); }
        function closeTaskSwitcher(): void { shell.closeTaskSwitcher(); }
        function openWindowOverview(): void { shell.openWindowOverview(); }
        function toggleWindowOverview(): void { shell.toggleWindowOverview(); }
        function closeWindowOverview(): void { shell.closeWindowOverview(); }
        function openSettings(): void { shell.openSettingsPanel("settings"); }
        function openAbout(): void { shell.openSettingsPanel("about"); }
        function openSystemHealth(): void { shell.openSettingsPanel("health"); }
        function openDynamicIslandSettings(): void { shell.openSettingsPanel("dynamic-island"); }
        function openWeatherSettings(): void { shell.openSettingsPanel("weather"); }
        function closeSettings(): void { shell.closeSettingsPanel(); }
        function lock(): string { return shell.requestLock("ipc"); }
        function lockFrom(source: string): string { return shell.requestLock(source); }
        function lockStatus(): string { return shell.lockStatus(); }
        function toggleLeftSidebar(): void { shell.toggleLeftSidebar(shell.screenByName(shell.navigationScreenName())); }
        function openLeftSidebar(): void {
            shell.leftSidebarScreenName = shell.navigationScreenName();
            shell.closeTopBarPopups("leftSidebar");
            shell.leftSidebarOpen = true;
            shell.closeLaunchpadAndSpotlight();
        }
        function closeLeftSidebar(): void { shell.closeLeftSidebar(); }
        function dynamicIslandGetState(): string { return dynamicIsland.state; }
        function dynamicIslandGetDebugSummary(): string { return dynamicIsland.debugSummary(); }
        function dynamicIslandGetSettingsSummary(): string {
            return [
                "enabled=" + desktopSettings.dynamicIslandEnabled,
                "hideTopbarTime=" + desktopSettings.dynamicIslandHideTopbarTime,
                "leftClickAction=" + desktopSettings.dynamicIslandLeftClickAction,
                "rightClickAction=" + desktopSettings.dynamicIslandRightClickAction,
                "autoExpandMedia=" + desktopSettings.dynamicIslandAutoExpandMedia,
                "hoverExpand=" + desktopSettings.dynamicIslandHoverExpand
            ].join("; ");
        }
        function dynamicIslandSetEnabled(enabled: bool): string { desktopSettings.setDynamicIslandEnabled(enabled); return dynamicIslandGetSettingsSummary(); }
        function dynamicIslandSetHideTopbarTime(enabled: bool): string { desktopSettings.setDynamicIslandHideTopbarTime(enabled); return dynamicIslandGetSettingsSummary(); }
        function dynamicIslandSetLeftClickAction(action: string): string { desktopSettings.setDynamicIslandLeftClickAction(action); return dynamicIslandGetSettingsSummary(); }
        function dynamicIslandSetRightClickAction(action: string): string { desktopSettings.setDynamicIslandRightClickAction(action); return dynamicIslandGetSettingsSummary(); }
        function dynamicIslandSetAutoExpandMedia(enabled: bool): string { desktopSettings.setDynamicIslandAutoExpandMedia(enabled); return dynamicIslandGetSettingsSummary(); }
        function dynamicIslandSetHoverExpand(enabled: bool): string { desktopSettings.setDynamicIslandHoverExpand(enabled); return dynamicIslandGetSettingsSummary(); }
        function dynamicIslandReset(): string { dynamicIsland.reset(); return dynamicIsland.state; }
        function dynamicIslandShowTime(): string { dynamicIsland.showTime(); return dynamicIsland.state; }
        function dynamicIslandShowMedia(): string { dynamicIsland.showMedia(); return dynamicIsland.state; }
        function dynamicIslandShowExpandedMedia(): string { dynamicIsland.showExpandedMedia(); return dynamicIsland.state; }
        function dynamicIslandShowExpandedSummary(): string { dynamicIsland.showExpandedSummary(); return dynamicIsland.state; }
        function dynamicIslandShowOsd(text: string, progress: real): string { dynamicIsland.showTransientOsd(text, progress); return dynamicIsland.state; }
        function dynamicIslandShowNotification(summary: string, body: string): string { dynamicIsland.showTransientNotification(summary, body); return dynamicIsland.state; }
        function dynamicIslandShowWorkspace(label: string): string { dynamicIsland.showTransientWorkspace(label); return dynamicIsland.state; }
        function dynamicIslandMediaNext(): string { dynamicIsland.mediaNext(); return dynamicIsland.state; }
        function dynamicIslandMediaPrevious(): string { dynamicIsland.mediaPrevious(); return dynamicIsland.state; }
        function dynamicIslandMediaToggle(): string { dynamicIsland.mediaTogglePlayPause(); return dynamicIsland.state; }
        function dynamicIslandSwipeBegin(): string { dynamicIsland.beginSwipe(); return dynamicIsland.debugSummary(); }
        function dynamicIslandSwipeAdvance(deltaX: real, deltaY: real): string { dynamicIsland.advanceSwipe(deltaX, deltaY); return dynamicIsland.debugSummary(); }
        function dynamicIslandSwipeResolve(): string { dynamicIsland.resolveSwipe(); return dynamicIsland.debugSummary(); }
        function dynamicIslandSwipeCancel(): string { dynamicIsland.cancelSwipe(); return dynamicIsland.debugSummary(); }
    }

    AppMenu {
        id: appMenu
        windowsService: niri
        appsService: apps
        commandRunner: commandRunner
    }

    Controls {
        id: controls
        commandRunner: commandRunner
    }

    DesktopSettings {
        id: desktopSettings
    }

    SystemStatus {
        id: systemStatus
        commandRunner: commandRunner
    }

    SystemStats {
        id: systemStats
    }

    Weather {
        id: weather
        settingsService: desktopSettings
    }

    Appearance {
        id: appearance
    }

    NiriSettings {
        id: niriSettings
    }

    Power {
        id: power
        lockService: lockScreen
        commandRunner: commandRunner
    }

    Battery {
        id: battery
    }

    PowerProfiles {
        id: powerProfiles
        commandRunner: commandRunner
    }

    FanControl {
        id: fanControl
    }

    InputMethod {
        id: inputMethod
        commandRunner: commandRunner
    }

    Sound {
        id: sound
    }

    ClipboardHistory {
        id: clipboardHistory
        commandRunner: commandRunner
    }

    Screenshot {
        id: screenshotService
        settingsService: desktopSettings
        commandRunner: commandRunner
    }

    Search {
        id: search
        appsService: apps
        screenshotService: screenshotService
        windowsService: niri
        clipboardService: clipboardHistory
        commandRunner: commandRunner
        onOpenSettingsRequested: function(page) {
            shell.openSettingsPanel(page);
        }
        onSystemActionRequested: function(action) {
            shell.runSearchSystemAction(action);
        }
    }

    // Owns the org.freedesktop.Notifications daemon for the session. Any
    // app using libnotify / notify-send (or the spec directly) is routed
    // here. Declared once at the shell root so there is exactly one
    // server instance across all screens.
    Notifications {
        id: notifications
        soundService: sound
    }

    DynamicIsland {
        id: dynamicIsland
        controlsService: controls
        notificationsService: notifications
        windowsService: niri
        batteryService: battery
        settingsService: desktopSettings
        onOpenControlCenterRequested: shell.openDynamicIslandControlCenter()
        onOpenNotificationCenterRequested: shell.openDynamicIslandNotificationCenter()
    }

    LockScreen {
        id: lockScreen
    }

    IdleMonitor {
        id: idleLockMonitor
        enabled: shell.idleLockEnabled
        timeout: shell.idleLockTimeoutSeconds
        respectInhibitors: true

        onIsIdleChanged: {
            if (isIdle && !lockScreen.locked)
                shell.requestLock("idle");
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            required property var modelData

            Wallpaper {
                screen: modelData
                appsService: apps
                settingsService: desktopSettings
            }

            PopupDismissLayer {
                screen: modelData
                open: shell.topBarDismissOpenFor(modelData)
                anchorRect: shell.topBarPopupAnchorRect
                popupWidth: shell.topBarDismissPopupWidth()
                popupHeight: shell.topBarDismissPopupHeight()
                fallbackRight: shell.topBarDismissFallbackRight()
                onCloseRequested: shell.closeTopBarPopups("")
            }

            TopBar {
                screen: modelData
                appsService: apps
                appMenuService: appMenu
                niriService: niri
                notificationsService: notifications
                batteryService: battery
                controlsService: controls
                fanService: fanControl
                clipboardService: clipboardHistory
                screenshotService: screenshotService
                inputMethodService: inputMethod
                dynamicIslandService: dynamicIsland
                settingsService: desktopSettings
                appMenuOpen: shell.topBarPopupOpenFor(shell.appMenuOpen, modelData)
                applicationMenuOpen: shell.topBarPopupOpenFor(shell.applicationMenuOpen, modelData)
                spotlightOpen: shell.spotlightOpen
                controlCenterOpen: shell.topBarPopupOpenFor(shell.controlCenterOpen, modelData)
                launchpadOpen: shell.launchpadOpen
                notificationCenterOpen: shell.topBarPopupOpenFor(shell.notificationCenterOpen, modelData)
                batteryPopupOpen: shell.topBarPopupOpenFor(shell.batteryPopupOpen, modelData)
                wifiPopupOpen: shell.topBarPopupOpenFor(shell.wifiPopupOpen, modelData)
                fanPopupOpen: shell.topBarPopupOpenFor(shell.fanPopupOpen, modelData)
                clipboardPopupOpen: shell.topBarPopupOpenFor(shell.clipboardPopupOpen, modelData)
                leftSidebarOpen: shell.navigationOpenFor(shell.leftSidebarOpen, shell.leftSidebarScreenName, modelData)
                darkMode: shell.darkMode
                onToggleAppMenu: function(anchorRect) {
                    shell.toggleTopBarPopup("appMenu", modelData, anchorRect);
                }
                onToggleApplicationMenu: function(anchorRect) {
                    shell.toggleTopBarPopup("applicationMenu", modelData, anchorRect);
                }
                onToggleControlCenter: function(anchorRect) {
                    shell.toggleTopBarPopup("controlCenter", modelData, anchorRect);
                }
                onToggleSpotlight: {
                    shell.spotlightOpen = !shell.spotlightOpen;
                    shell.closeTopBarPopups("");
                    shell.launchpadOpen = false;
                }
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.closeTopBarPopups("");
                    shell.spotlightOpen = false;
                }
                onToggleLeftSidebar: shell.toggleLeftSidebar(modelData)
                onToggleNotifications: function(anchorRect) {
                    shell.toggleTopBarPopup("notificationCenter", modelData, anchorRect);
                }
                onToggleBattery: function(anchorRect) {
                    shell.toggleTopBarPopup("battery", modelData, anchorRect);
                }
                onToggleWifi: function(anchorRect) {
                    shell.toggleTopBarPopup("wifi", modelData, anchorRect);
                }
                onToggleFan: function(anchorRect) {
                    shell.toggleTopBarPopup("fan", modelData, anchorRect);
                }
                onToggleClipboard: function(anchorRect) {
                    shell.toggleTopBarPopup("clipboard", modelData, anchorRect);
                }
                onTriggerScreenshot: {
                    screenshotService.captureSelection();
                    shell.closeTopBarPopups("");
                    shell.closeLaunchpadAndSpotlight();
                }
                onToggleInputMethod: inputMethod.toggle()
                onOpenTrayMenu: function(item, anchorRect) {
                    shell.openTopBarTrayMenu(item, modelData, anchorRect);
                }
            }

            DynamicIslandOverlay {
                screen: modelData
                dynamicIslandService: dynamicIsland
                darkMode: shell.darkMode
            }

            LeftSidebar {
                id: leftSidebar

                screen: modelData
                open: shell.navigationOpenFor(shell.leftSidebarOpen, shell.leftSidebarScreenName, modelData)
                systemStatsService: systemStats
                weatherService: weather
                settingsService: desktopSettings
                batteryService: battery
                darkMode: shell.darkMode
                monoFontFamily: shell.monoFontFamily
                processMenuOpen: shell.processMenuOpenFor(modelData)
                onCloseRequested: shell.closeLeftSidebar()
                onOpenProcessMenuRequested: function(proc, anchorRect) {
                    // 系统页右键进程行 → 实例化 ProcessMenu。先登记屏幕/proc/锚点，
                    // 再关其它弹层、开菜单（开菜单会回灌 processMenuOpen 暂停刷新）。
                    shell.prepareProcessMenu(modelData, proc, anchorRect);
                    shell.closeTopBarPopups("processMenu");
                    shell.processMenuOpen = true;
                }
                onOpenWeatherSettingsRequested: shell.openSettingsPanel("weather")
            }

            // LS07 进程右键菜单（照 dockWindowMenu 模式：PanelWindow + margins 定位）。
            ProcessMenu {
                id: processMenu

                screen: modelData
                proc: shell.processMenuProc
                anchorRect: shell.processMenuAnchorRect
                darkMode: shell.darkMode
                monoFontFamily: shell.monoFontFamily
                open: shell.processMenuOpenFor(modelData)
                onCloseRequested: shell.closeProcessMenu()
            }

            // 点外部关闭层（照 dockWindowMenu 配对：全屏点击遮罩，挖空菜单区）。
            PopupDismissLayer {
                screen: modelData
                open: shell.processMenuOpenFor(modelData)
                usePopupCutout: true
                useTopBarCutout: false
                useCustomPopupGeometry: true
                customPopupLeft: processMenu.popupLeft
                customPopupTop: processMenu.popupTop
                popupWidth: processMenu.panelWidth
                popupHeight: processMenu.panelHeight
                onCloseRequested: shell.closeProcessMenu()
            }

            MenuPopup {
                screen: modelData
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.appMenuOpen, modelData)
                activeApp: apps.windowAppLabel(niri.focusedWindow || niri.activeToplevel)
                powerService: power
                settingsService: desktopSettings
                onCloseRequested: shell.appMenuOpen = false
                onOpenSettingsRequested: function(page) {
                    shell.openSettingsPanel(page);
                }
            }

            AppMenuPopup {
                screen: modelData
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.applicationMenuOpen, modelData)
                appMenuService: appMenu
                settingsService: desktopSettings
                onCloseRequested: shell.applicationMenuOpen = false
            }

            Dock {
                screen: modelData
                appsService: apps
                niriService: niri
                thumbnailProvider: thumbnailProvider
                settingsService: desktopSettings
                useSpring: shell.useSpring
                darkMode: shell.darkMode
                launchpadOpen: shell.launchpadOpen
                menuOpen: shell.dockAppMenuOpenFor(modelData) || shell.dockWindowMenuOpenFor(modelData)
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.closeTopBarPopups("");
                    shell.spotlightOpen = false;
                }
                onOpenPinnedAppMenu: function(app, appId, anchorRect) {
                    var wasOpenHere = shell.dockAppMenuOpenFor(modelData);
                    var wasSameApp = wasOpenHere && shell.dockAppMenuAppId === String(appId || "");
                    shell.prepareDockAppMenu(modelData, app, appId, anchorRect);
                    shell.closeTopBarPopups("dockAppMenu");
                    shell.dockAppMenuOpen = !wasSameApp;
                    shell.closeLaunchpadAndSpotlight();
                }
                onOpenWindowMenu: function(window, anchorRect) {
                    var wasOpenHere = shell.dockWindowMenuOpenFor(modelData);
                    var currentId = window && window.id !== undefined && window.id !== null ? String(window.id) : "";
                    var previous = shell.dockWindowMenuWindow;
                    var previousId = previous && previous.id !== undefined && previous.id !== null ? String(previous.id) : "";
                    var wasSameWindow = wasOpenHere
                        && ((currentId.length > 0 && currentId === previousId)
                            || (currentId.length === 0 && previous === window));
                    shell.prepareDockWindowMenu(modelData, window, anchorRect);
                    shell.closeTopBarPopups("dockWindowMenu");
                    shell.dockWindowMenuOpen = !wasSameWindow;
                    shell.closeLaunchpadAndSpotlight();
                }
            }

            DockAppMenu {
                id: dockAppMenu

                screen: modelData
                appsService: apps
                app: shell.dockAppMenuApp
                appId: shell.dockAppMenuAppId
                anchorRect: shell.dockAppMenuAnchorRect
                open: shell.dockAppMenuOpenFor(modelData)
                settingsService: desktopSettings
                onCloseRequested: shell.closeDockAppMenu()
            }

            DockWindowMenu {
                id: dockWindowMenu

                screen: modelData
                windowsService: niri
                appsService: apps
                window: shell.dockWindowMenuWindow
                anchorRect: shell.dockWindowMenuAnchorRect
                open: shell.dockWindowMenuOpenFor(modelData)
                settingsService: desktopSettings
                onCloseRequested: shell.closeDockWindowMenu()
            }

            PopupDismissLayer {
                screen: modelData
                open: shell.dockAppMenuOpenFor(modelData) || shell.dockWindowMenuOpenFor(modelData)
                usePopupCutout: true
                useTopBarCutout: false
                useCustomPopupGeometry: true
                customPopupLeft: shell.dockAppMenuOpenFor(modelData) ? dockAppMenu.popupLeft : dockWindowMenu.popupLeft
                customPopupTop: shell.dockAppMenuOpenFor(modelData) ? dockAppMenu.popupTop : dockWindowMenu.popupTop
                popupWidth: shell.dockAppMenuOpenFor(modelData) ? dockAppMenu.panelWidth : dockWindowMenu.panelWidth
                popupHeight: shell.dockAppMenuOpenFor(modelData) ? dockAppMenu.panelHeight : dockWindowMenu.panelHeight
                onCloseRequested: shell.closeDockMenus()
            }

            ControlCenter {
                screen: modelData
                niriService: niri
                controlsService: controls
                appearanceService: appearance
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.controlCenterOpen, modelData)
                onCloseRequested: shell.controlCenterOpen = false
            }

            Launchpad {
                screen: modelData
                appsService: apps
                settingsService: desktopSettings
                useSpring: shell.useSpring
                open: shell.launchpadOpen
                onCloseRequested: shell.launchpadOpen = false
            }

            Spotlight {
                screen: modelData
                appsService: apps
                searchService: search
                settingsService: desktopSettings
                open: shell.spotlightOpen
                onCloseRequested: shell.spotlightOpen = false
            }

            TaskSwitcher {
                id: taskSwitcher

                screen: modelData
                windowsService: niri
                thumbnailProvider: thumbnailProvider
                appsService: apps
                open: shell.navigationOpenFor(shell.taskSwitcherOpen, shell.taskSwitcherScreenName, modelData)
                onCloseRequested: shell.closeTaskSwitcher()
            }

            Connections {
                target: shell

                function onTaskSwitcherCycleRequested(direction) {
                    if (shell.navigationOpenFor(shell.taskSwitcherOpen, shell.taskSwitcherScreenName, modelData))
                        taskSwitcher.cycleFromKeyboard(direction);
                }

                function onTaskSwitcherConfirmRequested() {
                    if (shell.navigationOpenFor(shell.taskSwitcherOpen, shell.taskSwitcherScreenName, modelData))
                        taskSwitcher.confirm();
                }
            }

            WindowOverview {
                screen: modelData
                windowsService: niri
                thumbnailProvider: thumbnailProvider
                appsService: apps
                open: shell.navigationOpenFor(shell.windowOverviewOpen, shell.windowOverviewScreenName, modelData)
                onCloseRequested: shell.closeWindowOverview()
            }

            SettingsPanel {
                screen: modelData
                page: shell.settingsPanelPage
                settingsService: desktopSettings
                systemStatusService: systemStatus
                appearanceService: appearance
                notificationsService: notifications
                inputMethodService: inputMethod
                niriSettingsService: niriSettings
                weatherService: weather
                open: shell.navigationOpenFor(shell.settingsPanelOpen, shell.settingsPanelScreenName, modelData)
                onCloseRequested: shell.closeSettingsPanel()
            }

            NotificationCenter {
                screen: modelData
                notificationsService: notifications
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.notificationCenterOpen, modelData)
                onCloseRequested: shell.notificationCenterOpen = false
            }

            BatteryPopup {
                screen: modelData
                batteryService: battery
                powerProfileService: powerProfiles
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.batteryPopupOpen, modelData)
                onCloseRequested: shell.batteryPopupOpen = false
            }

            WifiPopup {
                screen: modelData
                controlsService: controls
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.wifiPopupOpen, modelData)
                onCloseRequested: shell.wifiPopupOpen = false
            }

            FanPopup {
                screen: modelData
                fanService: fanControl
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.fanPopupOpen, modelData)
                onCloseRequested: shell.fanPopupOpen = false
            }

            ClipboardPopup {
                screen: modelData
                clipboardService: clipboardHistory
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.clipboardPopupOpen, modelData)
                onCloseRequested: shell.clipboardPopupOpen = false
            }

            TrayMenu {
                screen: modelData
                trayItem: shell.trayMenuItem
                settingsService: desktopSettings
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.trayMenuOpen, modelData)
                onCloseRequested: {
                    shell.trayMenuOpen = false;
                    shell.trayMenuItem = null;
                }
            }

            NotificationToast {
                screen: modelData
                notificationsService: notifications
                settingsService: desktopSettings
                dynamicIslandService: dynamicIsland
                useSpring: shell.useSpring
            }
        }
    }
}
