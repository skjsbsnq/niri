pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry
import "Motion.js" as Motion
import "controls" as Controls

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
    // Fixed surface height. Confirm UI overlays inside the glass panel so the
    // layer shell / TahoeGlass region never resizes mid-open (that resize was
    // the whole-card flash when restart/shutdown expanded the menu).
    // confirmReveal is 0..1: opacity + short upward slide of the overlay card.
    property real confirmReveal: 0
    implicitHeight: 300
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

    Behavior on confirmReveal {
        NumberAnimation {
            duration: Motion.elementResize(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
    }

    onConfirmOpenChanged: {
        confirmReveal = confirmOpen ? 1 : 0;
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
            // Ghost (hold, !open) is visual-only. Power confirm no longer arms hold, so
            // the column stays enabled while the card expands. Mid-flash settings
            // rows still block a second arm via holdSeq.
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
                onActivated: root.triggerPower("lock")
                onFlashFinished: {
                    if (!(root.powerService && root.powerService.hasPending))
                        root.closeRequested();
                }
            }

            MenuRow {
                text: "睡眠"
                icon: "\ue51c"
                flashOnActivate: false
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("sleep")
                onFlashFinished: {
                    // Keep-open confirm path: no hold arm, no close.
                    if (!(root.powerService && root.powerService.hasPending))
                        root.closeRequested();
                }
            }

            MenuRow {
                text: "退出登录"
                icon: "\ue9ba"
                flashOnActivate: false
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("logout")
                onFlashFinished: {
                    if (!(root.powerService && root.powerService.hasPending))
                        root.closeRequested();
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "重新启动"
                icon: "\ue5d5"
                destructive: true
                flashOnActivate: false
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("restart")
                onFlashFinished: {
                    if (!(root.powerService && root.powerService.hasPending))
                        root.closeRequested();
                }
            }

            MenuRow {
                text: "关机"
                icon: "\ue8ac"
                destructive: true
                flashOnActivate: false
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: root.triggerPower("shutdown")
                onFlashFinished: {
                    if (!(root.powerService && root.powerService.hasPending))
                        root.closeRequested();
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

        // Dim scrim + confirm card overlay. Pure content transform — no panel
        // height / glass region geometry change.
        Rectangle {
            id: confirmScrim

            anchors.fill: parent
            z: 1
            color: root.darkMode ? "#66000000" : "#33000000"
            opacity: root.confirmReveal * 0.85
            visible: opacity > 0.01


            MouseArea {
                anchors.fill: parent
                enabled: root.confirmOpen
                // Swallow clicks so menu rows under the scrim cannot re-fire.
                onClicked: {
                    if (root.powerService)
                        root.powerService.cancelPending();
                }
            }
        }

        Item {
            id: confirmHost

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            height: root.confirmCardHeight
            z: 2
            opacity: root.confirmReveal
            // Short rise into place (px). Does not affect glass geometry.
            transform: Translate {
                y: (1 - root.confirmReveal) * 14
            }
            visible: root.confirmReveal > 0.01
            enabled: root.confirmOpen


            Rectangle {
                anchors.fill: parent
                radius: 12
                color: root.darkMode ? "#cc2c2c2e" : "#e6ffffff"
                border.color: root.darkMode ? "#40ffffff" : "#50ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 7

                    Text {
                        text: root.powerService ? root.powerService.pendingTitle : ""
                        color: root.darkMode ? "#f5f7fb" : "#1d1d1f"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.powerService ? root.powerService.pendingMessage : ""
                        color: root.darkMode ? "#94a0ad" : "#991d1d1f"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Controls.TextButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            label: "取消"
                            fontPixelSize: 11
                            foregroundColor: root.darkMode ? "#f5f7fb" : "#1d1d1f"
                            baseColor: "#44ffffff"
                            hoverColor: "#70ffffff"
                            cornerRadius: 9
                            settingsService: root.settingsService
                            onActivated: {
                                if (root.powerService)
                                    root.powerService.cancelPending();
                            }
                        }

                        Controls.TextButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            label: root.powerService ? root.powerService.pendingTitle : "确认"
                            fontPixelSize: 11
                            danger: true
                            primary: true
                            cornerRadius: 9
                            prominentBorderColor: "#40ffffff"
                            settingsService: root.settingsService
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
    }


}
