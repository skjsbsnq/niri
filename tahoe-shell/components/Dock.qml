pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property bool launchpadOpen: false
    readonly property bool hasWindows: niriService && niriService.toplevelList && niriService.toplevelList.length > 0

    signal toggleLaunchpad()

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
                model: root.appsService ? root.appsService.pinnedApps : []

                delegate: Item {
                    id: pinnedButton

                    required property var modelData

                    width: 54
                    height: 58

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 16
                        color: root.launchpadOpen && modelData.id === "launchpad" ? "#70ffffff" : "transparent"
                    }

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 48
                        height: 48
                        source: root.appsService ? root.appsService.iconForApp(modelData) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: modelData.id === "finder" ? 5 : 0
                        height: 5
                        radius: 3
                        color: "#99000000"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.id === "launchpad") {
                                root.toggleLaunchpad();
                            } else if (root.appsService) {
                                root.appsService.launchApp(modelData);
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                height: 46
                radius: 1
                color: "#3d000000"
                visible: root.hasWindows
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                model: root.niriService ? root.niriService.toplevels : null

                delegate: WindowButton {
                    required property var modelData

                    toplevel: modelData
                    appsService: root.appsService
                    showTitle: true
                }
            }
        }
    }
}
