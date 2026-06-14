//@ pragma ShellId tahoe-phase0
//@ pragma AppId org.quickshell.tahoe.phase0
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "components"

ShellRoot {
    id: shell

    property bool controlCenterOpen: false

    Variants {
        model: Quickshell.screens

        Scope {
            required property var modelData

            TopBar {
                screen: modelData
                controlCenterOpen: shell.controlCenterOpen
                onToggleControlCenter: shell.controlCenterOpen = !shell.controlCenterOpen
            }

            Dock {
                screen: modelData
            }

            ControlCenter {
                screen: modelData
                open: shell.controlCenterOpen
            }
        }
    }
}
