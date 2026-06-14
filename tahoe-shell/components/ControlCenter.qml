pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool open: false
    property var niriService

    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 330
    implicitHeight: 372
    color: "transparent"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 42
        right: 14
    }

    BackgroundEffect.blurRegion: Region {
        item: panel
        radius: 24
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 24
        color: "#b8f5f6f8"
        border.color: "#70ffffff"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Control Center"
                    color: "#202124"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "#52ffffff"

                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        color: "#202124"
                        font.pixelSize: 13
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ControlTile {
                    title: "Wi-Fi"
                    value: "Home"
                    accent: "#0a84ff"
                    Layout.fillWidth: true
                }

                ControlTile {
                    title: "Bluetooth"
                    value: "On"
                    accent: "#5e5ce6"
                    Layout.fillWidth: true
                }
            }

            ControlTile {
                title: "Workspace"
                value: root.niriService ? root.niriService.activeWorkspaceName : "1"
                accent: "#ff9f0a"
                Layout.fillWidth: true
                Layout.preferredHeight: 78
            }

            ControlTile {
                title: "Sound"
                value: "42%"
                accent: "#30d158"
                Layout.fillWidth: true
                Layout.preferredHeight: 78
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 18
                color: "#52ffffff"
                border.color: "#52ffffff"

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    Text {
                        text: "Now Playing"
                        color: "#202124"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Tahoe Preview"
                        color: "#5f6368"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    component ControlTile: Rectangle {
        required property string title
        required property string value
        required property color accent

        Layout.preferredHeight: 92
        radius: 18
        color: "#5cffffff"
        border.color: "#61ffffff"

        Rectangle {
            x: 14
            y: 14
            width: 28
            height: 28
            radius: 14
            color: accent
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.bottom: valueText.top
            anchors.bottomMargin: 3
            text: title
            color: "#202124"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            id: valueText
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: value
            color: "#5f6368"
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }
}
