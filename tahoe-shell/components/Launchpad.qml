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

    // DIAG (VMware 图标消失对照): blurRegion 临时禁用（见 Dock.qml 同款注释）。
    // BackgroundEffect.blurRegion: Region {
    //     item: backdrop
    //     radius: 0
    // }

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
        // Open: scale 1.1 -> 1, "flying in from afar" (the web Launchpad
        // keyframe is 1.2->1; we use 1.1 for a touch less travel). The
        // previous 0.96->1 went the WRONG direction — it grew, which reads
        // as a zoom, not the Tahoe "settle from the distance" feel.
        scale: root.open ? 1 : 1.1

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // Spring on scale so the grid settles with a slight ease-out from
        // its 1.1 starting point, not a linear tween.
        Behavior on scale {
            SpringAnimation {
                spring: 200
                damping: 1.0
                epsilon: 0.01
            }
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
