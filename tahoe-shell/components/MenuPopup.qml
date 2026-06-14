pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool open: false
    property string activeApp: "Desktop"

    signal closeRequested()

    visible: open || menuSurface.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 218
    implicitHeight: 174
    color: "transparent"

    anchors {
        top: true
        left: true
    }

    margins {
        top: 38
        left: 12
    }

    BackgroundEffect.blurRegion: Region {
        item: menuSurface
        radius: 18
    }

    Rectangle {
        id: menuSurface

        x: 0
        y: 0
        width: parent.width
        height: parent.height
        radius: 18
        color: "#e6f7f8fb"
        // Open: scale down from the top-left corner (under the Apple/Tahoe
        // menu-bar entry) + fade. macOS menus expand from the menu-bar
        // item that spawned them, not slide.
        transformOrigin: Item.TopLeft
        scale: root.open ? 1 : 0.9
        opacity: root.open ? 1 : 0

        // NOTE: no `border.width` on the surface itself — a centered 1px
        // border antialiased against the outside pixels produces faint
        // near-square corners at the arc tangents. Draw the glass edges
        // with inset Rectangles instead, whose borders sit fully inside.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: "#70ffffff"
            border.width: 1
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: "#14000000"
            border.width: 1
            z: -1
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // Spring on scale — menu expands from its top-left anchor with a
        // hint of overshoot (the Tahoe pop) instead of a slide.
        Behavior on scale {
            SpringAnimation {
                spring: 420
                damping: 0.8
                epsilon: 0.01
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3

            MenuRow {
                text: "About Tahoe"
                bold: true
                onActivated: root.closeRequested()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#24000000"
            }

            MenuRow {
                text: root.activeApp
                onActivated: root.closeRequested()
            }

            MenuRow {
                text: "Window"
                onActivated: root.closeRequested()
            }

            MenuRow {
                text: "Settings"
                onActivated: root.closeRequested()
            }

            Item {
                Layout.fillHeight: true
            }
        }

    }

    component MenuRow: Item {
        id: row

        property alias text: label.text
        property bool bold: false

        signal activated()

        Layout.fillWidth: true
        Layout.preferredHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: rowMouse.containsMouse ? "#70ffffff" : "transparent"
        }

        Text {
            id: label

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: "#202124"
            font.pixelSize: 12
            font.weight: row.bold ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        MouseArea {
            id: rowMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.activated()
        }
    }
}
