//@ pragma ShellId tahoe
//@ pragma AppId org.quickshell.tahoe
//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "components"
import "services"

ShellRoot {
    id: shell

    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property bool appMenuOpen: false
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

    // Spring animations look great on real GPUs but corrupt Image textures
    // on software/virtual GPUs (VMware, Hyper-V): a SpringAnimation driving
    // an Image's geometry (x/y/scale) makes the icon turn transparent while
    // the spring runs. NumberAnimation is safe everywhere. This is the global
    // switch — keep false on VMs / software rendering; flip to true on a real
    // GPU to restore the bouncy macOS feel. Components read this to gate
    // their spring Behaviors (see Dock.qml, WindowButton.qml, Launchpad.qml).
    // Blur/glass region geometry does not use spring; Phase 3 keeps those
    // x/y/width/height transitions bounded for compositor-owned glass.
    property bool useSpring: false

    function screenName(screen) {
        return screen ? String(screen.name || "") : "";
    }

    function prepareTopBarPopup(screen, anchorRect) {
        topBarPopupScreenName = screenName(screen);
        topBarPopupAnchorRect = anchorRect || null;
    }

    function topBarPopupOpenFor(open, screen) {
        return open && topBarPopupScreenName === screenName(screen);
    }

    function closeTopBarPopups(except) {
        if (except !== "appMenu")
            appMenuOpen = false;
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
    }

    onWifiPopupOpenChanged: if (wifiPopupOpen) {
        appMenuOpen = false;
        controlCenterOpen = false;
        launchpadOpen = false;
        spotlightOpen = false;
        notificationCenterOpen = false;
        batteryPopupOpen = false;
        fanPopupOpen = false;
        clipboardPopupOpen = false;
        trayMenuOpen = false;
    }

    // Register the Material Icons font once for the whole shell. Used by the
    // Control Center (Text { font.family: "Material Icons" }). The font ships
    // under assets/fonts/ and is resolved through Quickshell.shellPath.
    FontLoader {
        source: Quickshell.shellPath("assets/fonts/MaterialIconsRound.ttf")
    }

    Apps {
        id: apps
    }

    Niri {
        id: niri
    }

    Controls {
        id: controls
    }

    Power {
        id: power
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

    ClipboardHistory {
        id: clipboardHistory
    }

    // Owns the org.freedesktop.Notifications daemon for the session. Any
    // app using libnotify / notify-send (or the spec directly) is routed
    // here. Declared once at the shell root so there is exactly one
    // server instance across all screens.
    Notifications {
        id: notifications
    }

    Variants {
        model: Quickshell.screens

        Scope {
            required property var modelData

            Wallpaper {
                screen: modelData
                appsService: apps
            }

            TopBar {
                screen: modelData
                appsService: apps
                niriService: niri
                notificationsService: notifications
                batteryService: battery
                controlsService: controls
                fanService: fanControl
                clipboardService: clipboardHistory
                appMenuOpen: shell.topBarPopupOpenFor(shell.appMenuOpen, modelData)
                spotlightOpen: shell.spotlightOpen
                controlCenterOpen: shell.topBarPopupOpenFor(shell.controlCenterOpen, modelData)
                launchpadOpen: shell.launchpadOpen
                notificationCenterOpen: shell.topBarPopupOpenFor(shell.notificationCenterOpen, modelData)
                batteryPopupOpen: shell.topBarPopupOpenFor(shell.batteryPopupOpen, modelData)
                wifiPopupOpen: shell.topBarPopupOpenFor(shell.wifiPopupOpen, modelData)
                fanPopupOpen: shell.topBarPopupOpenFor(shell.fanPopupOpen, modelData)
                clipboardPopupOpen: shell.topBarPopupOpenFor(shell.clipboardPopupOpen, modelData)
                onToggleAppMenu: function(anchorRect) {
                    var wasOpenHere = shell.topBarPopupOpenFor(shell.appMenuOpen, modelData);
                    shell.prepareTopBarPopup(modelData, anchorRect);
                    shell.closeTopBarPopups("appMenu");
                    shell.appMenuOpen = !wasOpenHere;
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
            }

            Dock {
                screen: modelData
                appsService: apps
                niriService: niri
                useSpring: shell.useSpring
                launchpadOpen: shell.launchpadOpen
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.closeTopBarPopups("");
                    shell.spotlightOpen = false;
                }
            }

            ControlCenter {
                screen: modelData
                niriService: niri
                controlsService: controls
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
                open: shell.spotlightOpen
                onCloseRequested: shell.spotlightOpen = false
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
