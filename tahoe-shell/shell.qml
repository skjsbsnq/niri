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

    Apps {
        id: apps
    }

    Niri {
        id: niri
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
                controlCenterOpen: shell.controlCenterOpen
                launchpadOpen: shell.launchpadOpen
                onToggleControlCenter: shell.controlCenterOpen = !shell.controlCenterOpen
                onToggleLaunchpad: shell.launchpadOpen = !shell.launchpadOpen
            }

            Dock {
                screen: modelData
                appsService: apps
                niriService: niri
                launchpadOpen: shell.launchpadOpen
                onToggleLaunchpad: shell.launchpadOpen = !shell.launchpadOpen
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
        }
    }
}
