pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    readonly property string iconRoot: Quickshell.shellDir + "/assets/icons/dock/"
    property var dockApps: [
        { "name": "Finder", "icon": "finder.png" },
        { "name": "Launchpad", "icon": "launchpad.png" },
        { "name": "Safari", "icon": "safari.png" },
        { "name": "Terminal", "icon": "terminal.png" },
        { "name": "Settings", "icon": "preferences.png" },
        { "name": "Trash", "icon": "bin.png" }
    ]

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 86
    implicitHeight: 86
    color: "transparent"

    BackgroundEffect.blurRegion: Region {
        item: dockSurface
        radius: 24
    }

    Rectangle {
        id: dockSurface
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: Math.min(parent.width - 28, dockRow.implicitWidth + 22)
        height: 70
        radius: 24
        color: "#33ffffff"
        border.color: "#59ffffff"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 23
            color: "#14ffffff"
            border.color: "#1f000000"
            border.width: 1
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: root.dockApps

                delegate: Item {
                    required property var modelData

                    width: 54
                    height: 58

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 48
                        height: 48
                        source: root.iconRoot + modelData.icon
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: modelData.name === "Finder" ? 5 : 0
                        height: 5
                        radius: 3
                        color: "#99000000"
                    }
                }
            }
        }
    }
}
