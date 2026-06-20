//@ pragma ShellId tahoe
//@ pragma AppId org.quickshell.tahoe
//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
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
    // Global default font. Noto Sans CJK SC covers Chinese and Latin; the
    // fontconfig fallback installed by arch-zh-setup handles emoji/edge cases.
    property string baseFontFamily: "Noto Sans CJK SC"
    property string monoFontFamily: "Noto Sans Mono CJK SC"
    property bool darkMode: appearance.darkMode

    // Real hardware default: spring gives the dock and panel animations their
    // bouncy settle. If Image textures vanish on a VM/software renderer, flip
    // this back to false; components gate their spring Behaviors through it.
    // Blur/glass region geometry stays on bounded NumberAnimation paths.
    property bool useSpring: true

    signal taskSwitcherCycleRequested(int direction)
    signal taskSwitcherConfirmRequested()

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
            return 560;
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

    function prepareDockAppMenu(screen, app, anchorRect) {
        dockAppMenuScreenName = screenName(screen);
        dockAppMenuApp = app || null;
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

    function closeTaskSwitcher() {
        taskSwitcherOpen = false;
    }

    function closeWindowOverview() {
        windowOverviewOpen = false;
    }

    function closeSettingsPanel() {
        settingsPanelOpen = false;
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
        launchpadOpen = false;
        spotlightOpen = false;
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
        launchpadOpen = false;
        spotlightOpen = false;
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
        launchpadOpen = false;
        spotlightOpen = false;
        settingsPanelOpen = true;
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
        if (except !== "settings")
            closeSettingsPanel();
        closeWindowNavigation(except);
    }

    onWifiPopupOpenChanged: if (wifiPopupOpen) {
        appMenuOpen = false;
        applicationMenuOpen = false;
        controlCenterOpen = false;
        launchpadOpen = false;
        spotlightOpen = false;
        notificationCenterOpen = false;
        batteryPopupOpen = false;
        fanPopupOpen = false;
        clipboardPopupOpen = false;
        trayMenuOpen = false;
        closeDockMenus();
        closeWindowNavigation("");
        closeSettingsPanel();
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
    }

    Windows {
        id: niri
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
        function closeSettings(): void { shell.closeSettingsPanel(); }
    }

    AppMenu {
        id: appMenu
        windowsService: niri
        appsService: apps
    }

    Controls {
        id: controls
    }

    DesktopSettings {
        id: desktopSettings
    }

    SystemStatus {
        id: systemStatus
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
    }

    Battery {
        id: battery
    }

    PowerProfiles {
        id: powerProfiles
    }

    FanControl {
        id: fanControl
    }

    InputMethod {
        id: inputMethod
    }

    Sound {
        id: sound
    }

    ClipboardHistory {
        id: clipboardHistory
    }

    Screenshot {
        id: screenshotService
        settingsService: desktopSettings
    }

    Search {
        id: search
        appsService: apps
        screenshotService: screenshotService
        onOpenSettingsRequested: function(page) {
            shell.openSettingsPanel(page);
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

    LockScreen {
        id: lockScreen
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
                darkMode: shell.darkMode
                onToggleAppMenu: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.appMenuOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("appMenu");
                    shell.appMenuOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleApplicationMenu: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.applicationMenuOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("applicationMenu");
                    shell.applicationMenuOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleControlCenter: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.controlCenterOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("controlCenter");
                    shell.controlCenterOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
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
                onToggleNotifications: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.notificationCenterOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("notificationCenter");
                    shell.notificationCenterOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleBattery: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.batteryPopupOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("battery");
                    shell.batteryPopupOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleWifi: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.wifiPopupOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("wifi");
                    shell.wifiPopupOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleFan: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.fanPopupOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("fan");
                    shell.fanPopupOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleClipboard: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.clipboardPopupOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("clipboard");
                    shell.clipboardPopupOpen = !wasOpenHere;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onTriggerScreenshot: {
                    screenshotService.captureSelection();
                    shell.closeTopBarPopups("");
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
                onToggleInputMethod: inputMethod.toggle()
                onOpenTrayMenu: function(item, anchorRect) {
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("trayMenu");
                    shell.trayMenuItem = item;
                    shell.trayMenuOpen = true;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
            }

            MenuPopup {
                screen: modelData
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.appMenuOpen, modelData)
                activeApp: apps.toplevelLabel(niri.focusedWindow || niri.activeToplevel)
                powerService: power
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
                onCloseRequested: shell.applicationMenuOpen = false
            }

            Dock {
                screen: modelData
                appsService: apps
                niriService: niri
                settingsService: desktopSettings
                useSpring: shell.useSpring
                darkMode: shell.darkMode
                launchpadOpen: shell.launchpadOpen
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.closeTopBarPopups("");
                    shell.spotlightOpen = false;
                }
                onOpenPinnedAppMenu: function(app, anchorRect) {
                    var wasOpenHere = shell.dockAppMenuOpenFor(modelData);
                    var wasSameApp = wasOpenHere && shell.dockAppMenuApp === app;
                    shell.prepareDockAppMenu(modelData, app, anchorRect);
                    shell.closeTopBarPopups("dockAppMenu");
                    shell.dockAppMenuOpen = !wasSameApp;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
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
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                }
            }

            DockAppMenu {
                screen: modelData
                appsService: apps
                app: shell.dockAppMenuApp
                anchorRect: shell.dockAppMenuAnchorRect
                open: shell.dockAppMenuOpenFor(modelData)
                onCloseRequested: shell.closeDockAppMenu()
            }

            DockWindowMenu {
                screen: modelData
                windowsService: niri
                appsService: apps
                window: shell.dockWindowMenuWindow
                anchorRect: shell.dockWindowMenuAnchorRect
                open: shell.dockWindowMenuOpenFor(modelData)
                onCloseRequested: shell.closeDockWindowMenu()
            }

            ControlCenter {
                screen: modelData
                niriService: niri
                controlsService: controls
                appearanceService: appearance
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.controlCenterOpen, modelData)
                onCloseRequested: shell.controlCenterOpen = false
            }

            Launchpad {
                screen: modelData
                appsService: apps
                useSpring: shell.useSpring
                open: shell.launchpadOpen
                onCloseRequested: shell.launchpadOpen = false
            }

            Spotlight {
                screen: modelData
                appsService: apps
                searchService: search
                open: shell.spotlightOpen
                onCloseRequested: shell.spotlightOpen = false
            }

            TaskSwitcher {
                id: taskSwitcher

                screen: modelData
                windowsService: niri
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
                open: shell.navigationOpenFor(shell.settingsPanelOpen, shell.settingsPanelScreenName, modelData)
                onCloseRequested: shell.closeSettingsPanel()
            }

            NotificationCenter {
                screen: modelData
                notificationsService: notifications
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.notificationCenterOpen, modelData)
                onCloseRequested: shell.notificationCenterOpen = false
            }

            BatteryPopup {
                screen: modelData
                batteryService: battery
                powerProfileService: powerProfiles
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.batteryPopupOpen, modelData)
                onCloseRequested: shell.batteryPopupOpen = false
            }

            WifiPopup {
                screen: modelData
                controlsService: controls
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.wifiPopupOpen, modelData)
                onCloseRequested: shell.wifiPopupOpen = false
            }

            FanPopup {
                screen: modelData
                fanService: fanControl
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.fanPopupOpen, modelData)
                onCloseRequested: shell.fanPopupOpen = false
            }

            ClipboardPopup {
                screen: modelData
                clipboardService: clipboardHistory
                anchorRect: shell.topBarPopupAnchorRect
                open: shell.topBarPopupOpenFor(shell.clipboardPopupOpen, modelData)
                onCloseRequested: shell.clipboardPopupOpen = false
            }

            TrayMenu {
                screen: modelData
                trayItem: shell.trayMenuItem
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
                useSpring: shell.useSpring
            }
        }
    }
}
