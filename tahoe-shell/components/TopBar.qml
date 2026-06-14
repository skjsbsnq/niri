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
    property bool controlCenterOpen: false
    property bool launchpadOpen: false
    property date now: new Date()
    readonly property string activeApp: appsService && niriService ? appsService.toplevelLabel(niriService.activeToplevel) : "Finder"

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
        color: "#58f7f8fb"
        border.color: "#36ffffff"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 14

            Text {
                text: "Tahoe"
                color: "#202124"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
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
                            color: modelData.active ? "#70ffffff" : "#30ffffff"
                            border.color: modelData.urgent ? "#ccff453a" : "#38ffffff"
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

            Text {
                text: Qt.formatDateTime(root.now, "ddd HH:mm")
                color: "#2c2d30"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                id: statusButton
                Layout.preferredWidth: 118
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.controlCenterOpen ? "#96ffffff" : "#4dffffff"
                    border.color: "#4dffffff"
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "Wi-Fi"
                        color: "#202124"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "100%"
                        color: "#202124"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 1
                        height: 12
                        color: "#42000000"
                        anchors.verticalCenter: parent.verticalCenter
                    }

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
