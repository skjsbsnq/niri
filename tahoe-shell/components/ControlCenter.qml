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

    visible: open || panel.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 330
    implicitHeight: 392
    color: "transparent"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 34
        right: 14
    }

    BackgroundEffect.blurRegion: Region {
        item: panel
        radius: 24
    }

    Rectangle {
        id: panel
        x: 0
        y: root.open ? 0 : -8
        width: parent.width
        height: parent.height
        radius: 24
        color: "#8cf5f6f8"
        border.color: "#70ffffff"
        border.width: 1
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.98
        transformOrigin: Item.TopRight

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

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
                Layout.preferredHeight: 72
            }

            ControlTile {
                title: "Sound"
                value: "42%"
                accent: "#30d158"
                Layout.fillWidth: true
                Layout.preferredHeight: 72
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: 18
                color: "#52ffffff"
                border.color: "#52ffffff"

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

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

        Layout.preferredHeight: 82
        radius: 18
        color: "#5cffffff"
        border.color: "#61ffffff"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 14
                color: accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: title
                    color: "#202124"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: value
                    color: "#5f6368"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }
}
