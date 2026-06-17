pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property string activeApp: "Desktop"
    property var powerService
    property var anchorRect: null
    readonly property int edgePadding: 8
    readonly property int fallbackTop: 29
    readonly property int popupGap: 0
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: anchorRect
        ? PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, 12)
        : 12
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: anchorRect
        ? PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, 12)
        : 0

    signal closeRequested()

    visible: open || menuSurface.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 218
    implicitHeight: powerService && powerService.hasPending ? 404 : 338
    color: "transparent"
    WlrLayershell.namespace: "tahoe-menu-popup"

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.popupTopMargin
        left: root.popupLeftMargin
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            x: menuSurface.x
            y: menuSurface.y
            width: menuSurface.width
            height: menuSurface.height
            material: menuSurface.tahoeGlassMaterial
            radius: menuSurface.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: menuSurface.opacity
            materialAlpha: menuSurface.opacity
            enabled: root.open || menuSurface.opacity > 0.01
        }
    ]

    onOpenChanged: {
        if (!open && powerService)
            powerService.cancelPending();
    }

    function triggerPower(action) {
        if (!powerService) {
            root.closeRequested();
            return;
        }

        var pending = powerService.requestAction(action);
        if (!pending)
            root.closeRequested();
    }

    Rectangle {
        id: menuSurface
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialMenu
        readonly property real tahoeGlassRadius: GlassStyle.RadiusMenu
        property real contentScale: root.open ? 1 : 0.98

        x: 0
        // menuSurface is the compositor-owned glass region item. Open/close
        // keeps its region bounds fixed; opacity/scale and compositor material
        // alpha carry the animation without moving blur geometry.
        y: 0
        width: parent.width
        height: parent.height
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.open ? 1 : 0

        transform: Scale {
            origin.x: root.popupOriginX
            origin.y: 0
            xScale: menuSurface.contentScale
            yScale: menuSurface.contentScale
        }

        // NOTE: no `border.width` on the surface itself — a centered 1px
        // border antialiased against the outside pixels produces faint
        // near-square corners at the arc tangents. Draw the glass edges
        // with inset Rectangles instead, whose borders sit fully inside.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: GlassStyle.StrokePanelBright
            border.width: 1
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on contentScale {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3

            MenuRow {
                text: "About Tahoe"
                icon: "\ue88e"
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
                icon: "\ue8b8"
                onActivated: root.closeRequested()
            }

            MenuRow {
                text: "Window"
                icon: "\ue8a7"
                onActivated: root.closeRequested()
            }

            MenuRow {
                text: "Settings"
                icon: "\ue8b8"
                onActivated: root.closeRequested()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#24000000"
            }

            MenuRow {
                text: "Lock Screen"
                icon: "\ue897"
                onActivated: root.triggerPower("lock")
            }

            MenuRow {
                text: "Sleep"
                icon: "\ue51c"
                onActivated: root.triggerPower("sleep")
            }

            MenuRow {
                text: "Log Out"
                icon: "\ue9ba"
                onActivated: root.triggerPower("logout")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#24000000"
            }

            MenuRow {
                text: "Restart"
                icon: "\ue5d5"
                destructive: true
                onActivated: root.triggerPower("restart")
            }

            MenuRow {
                text: "Shut Down"
                icon: "\ue8ac"
                destructive: true
                onActivated: root.triggerPower("shutdown")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                radius: 12
                color: "#5cffffff"
                border.color: "#50ffffff"
                visible: root.powerService && root.powerService.hasPending

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 7

                    Text {
                        text: root.powerService ? root.powerService.pendingTitle : ""
                        color: "#1d1d1f"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.powerService ? root.powerService.pendingMessage : ""
                        color: "#991d1d1f"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ConfirmButton {
                            text: "Cancel"
                            onActivated: {
                                if (root.powerService)
                                    root.powerService.cancelPending();
                            }
                        }

                        ConfirmButton {
                            text: root.powerService ? root.powerService.pendingTitle : "Confirm"
                            primary: true
                            onActivated: {
                                if (root.powerService)
                                    root.powerService.confirmPending();
                                root.closeRequested();
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

    }

    component MenuRow: Item {
        id: row

        property alias text: label.text
        property string icon: ""
        property bool bold: false
        property bool destructive: false

        signal activated()

        Layout.fillWidth: true
        Layout.preferredHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: rowMouse.containsMouse ? "#70ffffff" : "transparent"
        }

        Text {
            id: iconLabel

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            color: row.destructive ? "#ccff3b30" : "#202124"
            font.family: "Material Icons"
            font.pixelSize: 16
            visible: row.icon.length > 0
        }

        Text {
            id: label

            anchors.left: parent.left
            anchors.leftMargin: row.icon.length > 0 ? 34 : 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: row.destructive ? "#ccff3b30" : "#202124"
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

    component ConfirmButton: Item {
        id: button

        property alias text: label.text
        property bool primary: false

        signal activated()

        Layout.fillWidth: true
        Layout.preferredHeight: 26

        Rectangle {
            anchors.fill: parent
            radius: 9
            color: button.primary
                ? (buttonMouse.containsMouse ? "#e0ff453a" : "#d8ff453a")
                : (buttonMouse.containsMouse ? "#70ffffff" : "#44ffffff")
            border.color: button.primary ? "#40ffffff" : "#50ffffff"
        }

        Text {
            id: label

            anchors.centerIn: parent
            color: button.primary ? "#ffffff" : "#1d1d1f"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width - 10
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }
}
