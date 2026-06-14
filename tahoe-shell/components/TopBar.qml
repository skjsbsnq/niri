pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

PanelWindow {
    id: root

    property var appsService
    property var niriService
    property var notificationsService
    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property bool appMenuOpen: false
    property date now: new Date()
    readonly property string activeApp: appsService && niriService ? appsService.toplevelLabel(niriService.activeToplevel) : "Desktop"
    // Number of undismissed notifications. Drives the bell badge to the
    // left of the clock. Guards against a missing service (e.g. before
    // the property is wired from the shell root).
    readonly property int notificationCount: notificationsService ? notificationsService.activeCount : 0
    readonly property color glassFill: "#20ffffff"
    readonly property color glassStroke: "#42ffffff"
    readonly property color glassHairline: "#4cffffff"
    readonly property color glassShadowLine: "#12000000"

    signal toggleAppMenu()
    signal toggleControlCenter()
    signal toggleLaunchpad()

    anchors {
        left: true
        right: true
        top: true
    }

    exclusiveZone: 34
    implicitHeight: 34
    color: "transparent"

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    BackgroundEffect.blurRegion: Region {
        item: barSurface
        radius: 0
    }

    Rectangle {
        id: barSurface
        anchors.fill: parent
        color: root.glassFill
        border.color: root.glassStroke
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.glassHairline
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.glassShadowLine
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 14

            Item {
                Layout.preferredWidth: tahoeLabel.implicitWidth + 18
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.appMenuOpen ? "#32ffffff" : "transparent"
                    border.color: root.appMenuOpen ? "#42ffffff" : "transparent"
                }

                Text {
                    id: tahoeLabel
                    anchors.centerIn: parent
                    text: "Tahoe"
                    color: "#202124"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleAppMenu()
                }
            }

            Text {
                text: root.activeApp
                color: "#2c2d30"
                font.pixelSize: 13
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 220
            }

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Repeater {
                    model: ScriptModel {
                        values: root.niriService ? root.niriService.visibleWindowsets : []
                    }

                    delegate: Item {
                        required property var modelData
                        required property int index

                        width: 28
                        height: 20

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: modelData.active ? "#32ffffff" : "#18ffffff"
                            border.color: modelData.urgent ? "#ccff453a" : "#36ffffff"
                            border.width: 1
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.niriService ? root.niriService.workspaceLabel(modelData, index) : String(index + 1)
                            color: "#202124"
                            font.pixelSize: 11
                            font.weight: modelData.active ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: modelData.canActivate ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.niriService)
                                    root.niriService.activateWorkspace(modelData);
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Tray {
                panelWindow: root
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter
            }

            // Notification bell badge. Hidden when there is nothing
            // pending so the bar stays clean. Clicking it dismisses the
            // current toast (same as clicking the toast itself); for a
            // count > 9 it just shows "9+".
            Item {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                visible: root.notificationCount > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: badgeMouse.containsMouse ? "#38ffffff" : "#22ffffff"
                    border.color: "#40ffffff"
                }

                Text {
                    anchors.centerIn: parent
                    // Material Icons "notifications" glyph.
                    text: "\ue7f4"
                    color: "#202124"
                    font.family: "Material Icons"
                    font.pixelSize: 16
                }

                Rectangle {
                    // Count pip, top-right of the bell.
                    x: parent.width - width - 3
                    y: 1
                    width: countLabel.implicitWidth + 8
                    height: 14
                    radius: 7
                    color: "#ccff453a"
                    border.color: "#ffffff"
                    border.width: 1

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: root.notificationCount > 9 ? "9+" : root.notificationCount
                        color: "#ffffff"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: badgeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.notificationsService)
                            root.notificationsService.dismissCurrent();
                    }
                }
            }

            Text {
                text: Qt.formatDateTime(root.now, "ddd HH:mm")
                color: "#2c2d30"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                id: statusButton
                Layout.preferredWidth: 44
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.controlCenterOpen ? "#38ffffff" : "#22ffffff"
                    border.color: "#40ffffff"
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        text: root.niriService ? root.niriService.activeWorkspaceName : "1"
                        color: "#202124"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleControlCenter()
                }
            }
        }
    }
}
