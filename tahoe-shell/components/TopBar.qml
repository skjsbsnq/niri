pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool controlCenterOpen: false
    property date now: new Date()
    signal toggleControlCenter()

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
        color: "#72f7f8fb"
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
                text: "Finder"
                color: "#2c2d30"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
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
                Layout.preferredWidth: 72
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
                    spacing: 7

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
