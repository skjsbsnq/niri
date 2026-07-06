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

    ShellPopupState {
        id: shellPopupState
    }

    property alias controlCenterOpen: shellPopupState.controlCenterOpen
    property alias appMenuOpen: shellPopupState.appMenuOpen
    property alias applicationMenuOpen: shellPopupState.applicationMenuOpen
    property alias notificationCenterOpen: shellPopupState.notificationCenterOpen
    property alias batteryPopupOpen: shellPopupState.batteryPopupOpen
    property alias wifiPopupOpen: shellPopupState.wifiPopupOpen
    property alias fanPopupOpen: shellPopupState.fanPopupOpen
    property alias clipboardPopupOpen: shellPopupState.clipboardPopupOpen
    property alias trayMenuOpen: shellPopupState.trayMenuOpen
    property alias trayMenuItem: shellPopupState.trayMenuItem
    property alias topBarPopupAnchorRect: shellPopupState.topBarPopupAnchorRect
    property alias topBarPopupScreenName: shellPopupState.topBarPopupScreenName
    property bool launchpadOpen: false
    property bool spotlightOpen: false
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
        return shellNavigation.screenName(screen);
    }

    function navigationScreenName() {
        return shellNavigation.navigationScreenName();
    }

    function navigationOpenFor(open, targetScreenName, screen) {
        return shellNavigation.navigationOpenFor(open, targetScreenName, screen);
    }

    function prepareTopBarPopup(screen, anchorRect) {
        shellPopupState.prepareTopBarPopup(screenName(screen), anchorRect);
    }

    function closeLaunchpadAndSpotlight() {
        launchpadOpen = false;
        spotlightOpen = false;
    }

    function topBarPopupOpenValue(popupName) {
        return shellPopupState.topBarPopupOpenValue(popupName);
    }

    function setTopBarPopupOpen(popupName, open) {
        shellPopupState.setTopBarPopupOpen(popupName, open);
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
        return shellNavigation.screenByName(name);
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

    function ipcScreen() {
        return screenByName(navigationScreenName());
    }

    function topBarIpcAnchorRect(screen, slot) {
        var width = Math.max(1, Number(screen && screen.width) || 1);
        var button = 38;
        var gap = 8;
        var rightMargin = 12;
        var index = Math.max(0, Math.round(Number(slot) || 0));
        return {
            "x": Math.round(Math.max(0, width - rightMargin - button - index * (button + gap))),
            "y": 0,
            "width": button,
            "height": 38
        };
    }

    function openTopBarPopupForIpc(popupName, slot) {
        var screen = ipcScreen();
        if (!screen)
            return;

        prepareTopBarPopup(screen, topBarIpcAnchorRect(screen, slot));
        closeTopBarPopups(popupName);
        setTopBarPopupOpen(popupName, true);
        closeLaunchpadAndSpotlight();
    }

    function toggleTopBarPopupForIpc(popupName, slot) {
        var screen = ipcScreen();
        if (!screen)
            return;

        toggleTopBarPopup(popupName, screen, topBarIpcAnchorRect(screen, slot));
    }

    function closeMotionSamplingSurfaces() {
        closeTopBarPopups("");
        closeLaunchpadAndSpotlight();
        closeTaskSwitcher();
        closeWindowOverview();
        closeLeftSidebar();
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
        return shellPopupState.topBarPopupOpenFor(open, screenName(screen));
    }

    function topBarDismissOpenFor(screen) {
        return shellPopupState.topBarDismissOpenFor(screenName(screen));
    }

    function topBarDismissPopupWidth() {
        return shellPopupState.topBarDismissPopupWidth();
    }

    function topBarDismissPopupHeight() {
        return shellPopupState.topBarDismissPopupHeight();
    }

    function topBarDismissFallbackRight() {
        return shellPopupState.topBarDismissFallbackRight();
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
        shellPopupState.closeTopBarPopups(except);
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
        trayMenuItem = null;
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

    ShellNavigation {
        id: shellNavigation
        windowsService: niri
    }

    ThumbnailProvider {
        id: thumbnailProvider
        windowsService: niri
    }

    CommandRunner {
        id: commandRunner
    }

    AppsSettings {
        id: appsSettings
        appsService: apps
        commandRunner: commandRunner
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
        function openControlCenter(): void { shell.openTopBarPopupForIpc("controlCenter", 4); }
        function toggleControlCenter(): void { shell.toggleTopBarPopupForIpc("controlCenter", 4); }
        function closeControlCenter(): void { shell.controlCenterOpen = false; }
        function openNotificationCenter(): void { shell.openTopBarPopupForIpc("notificationCenter", 5); }
        function toggleNotificationCenter(): void { shell.toggleTopBarPopupForIpc("notificationCenter", 5); }
        function closeNotificationCenter(): void { shell.notificationCenterOpen = false; }
        function openBatteryPopup(): void { shell.openTopBarPopupForIpc("battery", 3); }
        function toggleBatteryPopup(): void { shell.toggleTopBarPopupForIpc("battery", 3); }
        function closeBatteryPopup(): void { shell.batteryPopupOpen = false; }
        function openWifiPopup(): void { shell.openTopBarPopupForIpc("wifi", 2); }
        function toggleWifiPopup(): void { shell.toggleTopBarPopupForIpc("wifi", 2); }
        function closeWifiPopup(): void { shell.wifiPopupOpen = false; }
        function openFanPopup(): void { shell.openTopBarPopupForIpc("fan", 1); }
        function toggleFanPopup(): void { shell.toggleTopBarPopupForIpc("fan", 1); }
        function closeFanPopup(): void { shell.fanPopupOpen = false; }
        function openClipboardPopup(): void { shell.openTopBarPopupForIpc("clipboard", 0); }
        function toggleClipboardPopup(): void { shell.toggleTopBarPopupForIpc("clipboard", 0); }
        function closeClipboardPopup(): void { shell.clipboardPopupOpen = false; }
        function openSpotlight(): void {
            shell.closeTopBarPopups("spotlight");
            shell.launchpadOpen = false;
            shell.spotlightOpen = true;
        }
        function toggleSpotlight(): void {
            shell.closeTopBarPopups("spotlight");
            shell.launchpadOpen = false;
            shell.spotlightOpen = !shell.spotlightOpen;
        }
        function closeSpotlight(): void { shell.spotlightOpen = false; }
        function closeMotionSamplingSurfaces(): void { shell.closeMotionSamplingSurfaces(); }
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

    NetworkSettings {
        id: networkSettings
        commandRunner: commandRunner
    }

    SystemFeatures {
        id: systemFeatures
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

    Connections {
        target: niriSettings

        function onMotionProfileChanged() {
            if (desktopSettings.validMotionProfile(niriSettings.motionProfile)
                    && desktopSettings.motionProfile !== niriSettings.motionProfile)
                desktopSettings.setMotionProfile(niriSettings.motionProfile);
        }
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
        commandRunner: commandRunner
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
                settingsService: desktopSettings
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
                settingsService: desktopSettings
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
                controlsService: controls
                soundService: sound
                batteryService: battery
                powerProfileService: powerProfiles
                powerService: power
                idleLockEnabled: shell.idleLockEnabled
                idleLockTimeoutSeconds: shell.idleLockTimeoutSeconds
                networkSettingsService: networkSettings
                appsSettingsService: appsSettings
                appsService: apps
                systemFeaturesService: systemFeatures
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
