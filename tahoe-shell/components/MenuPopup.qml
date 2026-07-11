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
    property string activeApp: "桌面"
    property var powerService
    property var anchorRect: null
    property var settingsService
    property bool darkMode: false
    readonly property int edgePadding: 8
    readonly property int fallbackTop: 28
    readonly property int popupGap: 8
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int popupLeftMargin: anchorRect
        ? PopupGeometry.popupLeft(anchorRect, root.implicitWidth, screenWidth, edgePadding, 12)
        : 12
    readonly property int popupTopMargin: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property real popupOriginX: anchorRect
        ? PopupGeometry.originX(anchorRect, popupLeftMargin, root.implicitWidth, screenWidth, 12)
        : 0
    signal closeRequested()
    signal openSettingsRequested(string page)

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 218
    implicitHeight: powerService && powerService.hasPending ? 380 : 300
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

    TahoeGlass.regions: [menuSurface.region]

    GlassPanel {
        id: menuSurface

        x: 0
        // menuSurface is the compositor-owned glass region item. niri owns the
        // outer layer motion without QML opacity/scale changes.
        y: 0
        width: parent.width
        height: parent.height
        material: GlassStyle.MaterialMenu
        radius: GlassStyle.RadiusMenu
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            MenuRow {
                text: "关于 niri"
                icon: "\ue88e"
                bold: true
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.openSettingsRequested("about");
                    root.closeRequested();
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: root.activeApp
                icon: "\ue8b8"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.closeRequested()
            }

            MenuRow {
                text: "窗口"
                icon: "\ue8a7"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.closeRequested()
            }

            MenuRow {
                text: "设置"
                icon: "\ue8b8"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.openSettingsRequested("settings");
                    root.closeRequested();
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "锁定屏幕"
                icon: "\ue897"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("lock")
            }

            MenuRow {
                text: "睡眠"
                icon: "\ue51c"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("sleep")
            }

            MenuRow {
                text: "退出登录"
                icon: "\ue9ba"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("logout")
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "重新启动"
                icon: "\ue5d5"
                destructive: true
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("restart")
            }

            MenuRow {
                text: "关机"
                icon: "\ue8ac"
                destructive: true
                settingsService: root.settingsService
                darkMode: root.darkMode
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
                            text: "取消"
                            onActivated: {
                                if (root.powerService)
                                    root.powerService.cancelPending();
                            }
                        }

                        ConfirmButton {
                            text: root.powerService ? root.powerService.pendingTitle : "确认"
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
