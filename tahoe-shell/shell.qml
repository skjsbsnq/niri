//@ pragma ShellId tahoe
//@ pragma AppId org.quickshell.tahoe
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
    property bool notificationOpen: false

    Apps {
        id: apps
    }

    Niri {
        id: niri
    }

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: shell.notificationOpen = true
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
                appMenuOpen: shell.appMenuOpen
                controlCenterOpen: shell.controlCenterOpen
                launchpadOpen: shell.launchpadOpen
                onToggleAppMenu: {
                    shell.appMenuOpen = !shell.appMenuOpen;
                    shell.controlCenterOpen = false;
                    shell.launchpadOpen = false;
                }
                onToggleControlCenter: {
                    shell.controlCenterOpen = !shell.controlCenterOpen;
                    shell.appMenuOpen = false;
                    shell.launchpadOpen = false;
                }
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                }
            }

            MenuPopup {
                screen: modelData
                open: shell.appMenuOpen
                activeApp: apps.toplevelLabel(niri.activeToplevel)
                onCloseRequested: shell.appMenuOpen = false
            }

            Dock {
                screen: modelData
                appsService: apps
                niriService: niri
                launchpadOpen: shell.launchpadOpen
                onToggleLaunchpad: {
                    shell.launchpadOpen = !shell.launchpadOpen;
                    shell.appMenuOpen = false;
                    shell.controlCenterOpen = false;
                }
            }

            ControlCenter {
                screen: modelData
                niriService: niri
                open: shell.controlCenterOpen
                onCloseRequested: shell.controlCenterOpen = false
            }

            Launchpad {
                screen: modelData
                appsService: apps
                open: shell.launchpadOpen
                onCloseRequested: shell.launchpadOpen = false
            }

            NotificationToast {
                screen: modelData
                open: shell.notificationOpen
                onDismissRequested: shell.notificationOpen = false
            }
        }
    }
}
