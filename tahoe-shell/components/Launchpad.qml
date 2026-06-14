pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool open: false
    property var appsService

    signal closeRequested()

    visible: open || backdrop.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    color: "transparent"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    BackgroundEffect.blurRegion: Region {
        item: backdrop
        radius: 0
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#66eef2f7"
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
    }

    Image {
        anchors.fill: parent
        source: root.appsService ? root.appsService.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        opacity: root.open ? 0.22 : 0
        smooth: true

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Item {
        id: launcher
        anchors.centerIn: parent
        width: Math.min(parent.width - 72, 820)
        height: Math.min(parent.height - 96, 590)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true;
            }
        }

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: grid.implicitHeight
            clip: true

            Grid {
                id: grid
                width: parent.width
                columns: Math.max(4, Math.floor(width / 104))
                rowSpacing: 22
                columnSpacing: 12

                Repeater {
                    model: ScriptModel {
                        values: root.appsService ? root.appsService.launchpadApps : []
                    }

                    delegate: Item {
                        id: appButton

                        required property var modelData

                        width: grid.width / grid.columns - grid.columnSpacing
                        height: 96

                        Image {
                            id: appIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: 64
                            height: 64
                            source: root.appsService ? root.appsService.iconForApp(appButton.modelData) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: appIcon.bottom
                            anchors.topMargin: 7
                            text: root.appsService ? root.appsService.appLabel(appButton.modelData) : ""
                            color: "#202124"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.appsService)
                                    root.appsService.launchApp(appButton.modelData);
                                root.closeRequested();
                            }
                        }
                    }
                }
            }
        }
    }
}
