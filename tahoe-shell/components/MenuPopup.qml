pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry
import "Motion.js" as Motion

PanelWindow {
    id: root

    property bool open: false
    property string activeApp: "桌面"
    property var powerService
    property var appMenuService
    property var shellBridge
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
    readonly property bool confirmOpen: powerService && powerService.hasPending
    readonly property int confirmCardHeight: 90
    // Keep the layer mapped while a row is flashing even if activated() already
    // closed appMenuOpen (settings/overview). Otherwise the flash is clipped.
    // holdSeq is the in-flight flash token; 0 means no hold. Reopen clears it so a
    // stale flashFinished cannot close the newly opened menu.
    property int flashSeq: 0
    property int holdSeq: 0
    readonly property bool flashHold: holdSeq !== 0

    signal closeRequested()
    signal openSettingsRequested(string page)

    visible: open || flashHold
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 218
    // Base menu content is fixed; confirm card expands in-place so panel height
    // can animate via Behavior (eased only — feeds glass region geometry).
    implicitHeight: 300 + (confirmOpen ? (confirmCardHeight + 2) : 0)
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

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    onOpenChanged: {
        if (open) {
            // Invalidate any in-flight flash from a previous open epoch.
            holdSeq = 0;
            flashSeq += 1;
            return;
        }
        if (powerService)
            powerService.cancelPending();
    }

    function armFlashHold() {
        flashSeq += 1;
        holdSeq = flashSeq;
    }

    function finishRowFlash(closeMenu) {
        // Stale finish after reopen (hold cleared) must not close the new menu.
        if (holdSeq === 0)
            return;
        holdSeq = 0;
        if (closeMenu && root.open)
            root.closeRequested();
    }

    function triggerPower(action) {
        // Action only. Closing is owned by MenuRow.flashFinished so the flash
        // stays visible; confirm-card actions leave the menu open via hasPending.
        if (!powerService)
            return;
        powerService.requestAction(action);
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
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            // Ghost (hold, !open) is visual-only. While a flash is in flight, block
            // further row clicks so a second arm cannot orphan the first finish.
            enabled: root.open && root.holdSeq === 0

            MenuRow {
                text: "关于 niri"
                icon: "\ue88e"
                bold: true
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    root.openSettingsRequested("about");
                }
                onFlashFinished: root.finishRowFlash(true)
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: root.activeApp
                icon: "\ue8b8"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    if (root.appMenuService)
                        root.appMenuService.activateFocusedWindow();
                }
                onFlashFinished: root.finishRowFlash(true)
            }

            MenuRow {
                text: "窗口"
                icon: "\ue8a7"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    if (root.shellBridge && root.shellBridge.toggleWindowOverview)
                        root.shellBridge.toggleWindowOverview();
                }
                onFlashFinished: root.finishRowFlash(true)
            }

            MenuRow {
                text: "设置"
                icon: "\ue8b8"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    root.openSettingsRequested("settings");
                }
                onFlashFinished: root.finishRowFlash(true)
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "锁定屏幕"
                icon: "\ue897"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    root.triggerPower("lock");
                }
                onFlashFinished: {
                    root.finishRowFlash(!(root.powerService && root.powerService.hasPending));
                }
            }

            MenuRow {
                text: "睡眠"
                icon: "\ue51c"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    root.triggerPower("sleep");
                }
                onFlashFinished: {
                    root.finishRowFlash(!(root.powerService && root.powerService.hasPending));
                }
            }

            MenuRow {
                text: "退出登录"
                icon: "\ue9ba"
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    root.triggerPower("logout");
                }
                onFlashFinished: {
                    root.finishRowFlash(!(root.powerService && root.powerService.hasPending));
                }
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
                onActivated: {
                    root.armFlashHold();
                    root.triggerPower("restart");
                }
                onFlashFinished: {
                    root.finishRowFlash(!(root.powerService && root.powerService.hasPending));
                }
            }

            MenuRow {
                text: "关机"
                icon: "\ue8ac"
                destructive: true
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    root.armFlashHold();
                    root.triggerPower("shutdown");
                }
                onFlashFinished: {
                    root.finishRowFlash(!(root.powerService && root.powerService.hasPending));
                }
            }

            Item {
                id: confirmHost

                Layout.fillWidth: true
                Layout.preferredHeight: root.confirmOpen ? root.confirmCardHeight : 0
                clip: true
                opacity: root.confirmOpen ? 1 : 0
                visible: Layout.preferredHeight > 0.5 || opacity > 0.01

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: Motion.elementResize(root.settingsService)
                        easing.type: Motion.emphasizedDecel
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.confirmOpen
                            ? Motion.elementResize(root.settingsService)
                            : Motion.panelExit(root.settingsService)
                        easing.type: root.confirmOpen
                            ? Motion.emphasizedDecel
                            : Motion.emphasizedAccel
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.confirmCardHeight
                    radius: 12
                    color: "#5cffffff"
                    border.color: "#50ffffff"

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
