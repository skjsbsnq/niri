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

    // Spring animations look great on real GPUs but corrupt Image textures
    // on software/virtual GPUs (VMware, Hyper-V): a SpringAnimation driving
    // an Image's geometry (x/y/scale) makes the icon turn transparent while
    // the spring runs. NumberAnimation is safe everywhere. This is the global
    // switch — keep false on VMs / software rendering; flip to true on a real
    // GPU to restore the bouncy macOS feel. Components read this to gate
    // their spring Behaviors (see Dock.qml, WindowButton.qml, Launchpad.qml,
    // NotificationToast.qml).
    property bool useSpring: false

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
                appMenuOpen: shell.appMenuOpen
                spotlightOpen: shell.spotlightOpen
                controlCenterOpen: shell.controlCenterOpen
                launchpadOpen: shell.launchpadOpen
                notificationCenterOpen: shell.notificationCenterOpen
                batteryPopupOpen: shell.batteryPopupOpen
                onToggleAppMenu: {
                    shell.appMenuOpen = !shell.appMenuOpen;
                    shell.controlCenterOpen = false;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                    shell.notificationCenterOpen = false;
                    shell.batteryPopupOpen = false;
                }
                onToggleControlCenter: {
                    shell.controlCenterOpen = !shell.controlCenterOpen;
                    shell.appMenuOpen = false;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                    shell.notificationCenterOpen = false;
                    shell.batteryPopupOpen = false;
                }
                onToggleSpotlight: {
                    shell.spotlightOpen = !shell.spotlightOpen;
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                    shell.launchpadOpen = false;
                    shell.notificationCenterOpen = false;
                    shell.batteryPopupOpen = false;
                }
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                    shell.spotlightOpen = false;
                    shell.notificationCenterOpen = false;
                    shell.batteryPopupOpen = false;
                }
                onToggleNotifications: {
                    shell.notificationCenterOpen = !shell.notificationCenterOpen;
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                    shell.batteryPopupOpen = false;
                }
                onToggleBattery: {
                    shell.batteryPopupOpen = !shell.batteryPopupOpen;
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                    shell.launchpadOpen = false;
                    shell.spotlightOpen = false;
                    shell.notificationCenterOpen = false;
                }
            }

            MenuPopup {
                screen: modelData
                open: shell.appMenuOpen
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
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                    shell.spotlightOpen = false;
                    shell.notificationCenterOpen = false;
                    shell.batteryPopupOpen = false;
                }
            }

            ControlCenter {
                screen: modelData
                niriService: niri
                controlsService: controls
                open: shell.controlCenterOpen
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
                open: shell.notificationCenterOpen
                onCloseRequested: shell.notificationCenterOpen = false
            }

            BatteryPopup {
                screen: modelData
                batteryService: battery
                open: shell.batteryPopupOpen
                onCloseRequested: shell.batteryPopupOpen = false
            }

            NotificationToast {
                screen: modelData
                notificationsService: notifications
                useSpring: shell.useSpring
            }
        }
    }
}
