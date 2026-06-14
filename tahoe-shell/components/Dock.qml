pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property bool launchpadOpen: false
    property real dockMouseX: -10000
    property bool dockHovered: false
    readonly property bool hasWindows: niriService && niriService.toplevelList && niriService.toplevelList.length > 0
    readonly property color glassFill: "#22ffffff"
    readonly property color glassStroke: "#50ffffff"
    readonly property color glassInnerStroke: "#18ffffff"
    readonly property color glassShadowLine: "#16000000"

    signal toggleLaunchpad()

    function proximityScale(item) {
        if (!dockHovered || !item || !dockSurface)
            return 1.0;

        var point = item.mapToItem(dockSurface, item.width / 2, item.height / 2);
        var distance = Math.abs(dockMouseX - point.x);
        var influence = Math.max(0, 1 - distance / 118);
        return 1.0 + influence * 0.38;
    }

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 98
    implicitHeight: 132
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
        width: Math.min(parent.width - 28, dockRow.implicitWidth + 34)
        height: 78
        radius: 24
        color: root.glassFill
        border.color: root.glassStroke
        border.width: 1

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                root.dockMouseX = mouse.x;
            }
            onEntered: root.dockHovered = true
            onExited: {
                root.dockHovered = false;
                root.dockMouseX = -10000;
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 23
            color: "#08ffffff"
            border.color: root.glassInnerStroke
            border.width: 1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 1
            height: 1
            radius: 1
            color: "#4cffffff"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 1
            radius: 1
            color: root.glassShadowLine
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: ScriptModel {
                    values: root.appsService ? root.appsService.pinnedApps : []
                }

                delegate: Item {
                    id: pinnedButton

                    required property var modelData
                    property real magnification: root.proximityScale(pinnedButton)
                    property real bounceOffset: 0
                    readonly property bool hovered: iconMouse.containsMouse
                    readonly property real lift: (magnification - 1.0) * 18 + (hovered ? 3 : 0)

                    width: 62
                    height: 70

                    Rectangle {
                        x: 4
                        y: 8
                        width: 54
                        height: 54
                        radius: 16
                        color: root.launchpadOpen && modelData.id === "launchpad" ? "#70ffffff" : "transparent"
                    }

                    Image {
                        id: appIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8 - pinnedButton.lift - pinnedButton.bounceOffset
                        width: 48
                        height: 48
                        scale: pinnedButton.magnification
                        source: root.appsService ? root.appsService.iconForApp(modelData) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        transformOrigin: Item.Center

                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }

                        Behavior on y {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: modelData.shellAction === "launchpad" ? 0 : 5
                        height: 5
                        radius: 3
                        color: "#99000000"
                    }

                    Rectangle {
                        id: hoverLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 10
                        y: pinnedButton.hovered ? -34 : -24
                        width: Math.max(labelText.implicitWidth + 18, 42)
                        height: 24
                        radius: 7
                        color: "#d9f7f8fb"
                        border.color: "#70ffffff"
                        opacity: pinnedButton.hovered ? 1 : 0
                        visible: opacity > 0.01

                        Text {
                            id: labelText
                            anchors.centerIn: parent
                            text: root.appsService ? root.appsService.appLabel(modelData) : ""
                            color: "#202124"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }

                        Behavior on y {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        id: iconMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            var point = pinnedButton.mapToItem(dockSurface, mouse.x, mouse.y);
                            root.dockMouseX = point.x;
                            root.dockHovered = true;
                        }
                        onEntered: root.dockHovered = true
                        onClicked: {
                            bounceAnimation.restart();
                            if (modelData.shellAction === "launchpad") {
                                root.toggleLaunchpad();
                            } else if (root.appsService) {
                                root.appsService.launchApp(modelData);
                            }
                        }
                    }

                    SequentialAnimation {
                        id: bounceAnimation

                        NumberAnimation {
                            target: pinnedButton
                            property: "bounceOffset"
                            to: 5
                            duration: 70
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            target: pinnedButton
                            property: "bounceOffset"
                            to: 0
                            duration: 110
                            easing.type: Easing.OutCubic
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
                    id: windowButton

                    required property var modelData

                    toplevel: modelData
                    appsService: root.appsService
                    showTitle: true
                    magnification: root.proximityScale(windowButton)
                    dockWindow: root
                    dockSurfaceItem: dockSurface
                    onDockPointerMoved: function(x) {
                        root.dockMouseX = x;
                        root.dockHovered = true;
                    }
                    onDockPointerEntered: root.dockHovered = true
                }
            }
        }
    }
}
