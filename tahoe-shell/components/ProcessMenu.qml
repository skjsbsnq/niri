pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "PopupGeometry.js" as PopupGeometry

// LS07: 进程列表右键菜单。
//
// 视图职责：玻璃 PanelWindow + 共享 MenuRow 列，提供「复制 PID / 复制名称 / 复制完整命令 /
// 结束进程 / 强制结束(SIGKILL)」五项。位置由进程行屏幕坐标（LeftSidebarSystem 经
// itemRect 算出的 anchorRect）经 PopupGeometry 定位；Shell 用 PopupDismissLayer 处理
// 点外部关闭，本面板再加 Esc 关闭以满足 DoD。
//
// 数据/动作职责：只读传入的 `proc`（{pid,name,uid,cmdline,...}）。复制走
// Quickshell.execDetached + wl-copy（照 Search.qml 模式）；结束走 execDetached(["kill",...])。
// 强制结束守 uid>=1000，对系统进程禁用（DoD）。
//
// 视觉：T06 共享 MenuRow（accent 蓝高亮 + 选中闪烁）；深浅色由 darkMode 驱动。
PanelWindow {
    id: root

    property bool open: false
    property var proc: null
    property var anchorRect: null
    property var settingsService
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"

    readonly property int edgePadding: 8
    readonly property int popupGap: 8
    readonly property int panelWidth: 224
    readonly property int panelHeight: Math.max(1, panel.implicitHeight)
    readonly property int screenWidth: PopupGeometry.screenWidth(root.screen, root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)
    // 菜单左缘对齐进程行左缘，右缘不越过屏幕。
    readonly property int popupLeft: anchorRect
        ? Math.round(Math.max(edgePadding,
            Math.min(screenWidth - panelWidth - edgePadding,
                PopupGeometry.numberOr(anchorRect.x, 0) - 4)))
        : edgePadding
    // 菜单出现在进程行下方（右键光标附近），贴底不越界。
    readonly property int popupTop: anchorRect
        ? Math.round(Math.max(edgePadding,
            Math.min(screenHeight - panelHeight - edgePadding,
                PopupGeometry.numberOr(anchorRect.y, 0)
                + PopupGeometry.numberOr(anchorRect.height, 0)
                + popupGap)))
        : edgePadding

    readonly property color textPrimary: darkMode ? "#f5f7fb" : "#1d1d1f"
    readonly property color textTertiary: darkMode ? "#9da7b1" : "#731d1d1f"

    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    focusable: open
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tahoe-process-menu"

    anchors {
        left: true
        top: true
    }

    margins {
        left: root.popupLeft
        top: root.popupTop
    }

    onOpenChanged: {
        if (open)
            Qt.callLater(function() { if (root.open) focusCatcher.forceActiveFocus(); });
    }

    TahoeGlass.regions: [panel.region]

    // 背景 MouseArea：点菜单面板空白处也关闭（与 PopupDismissLayer 的点外部关闭叠加）。
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }

    GlassPanel {
        id: panel

        z: 1
        x: 0
        y: 0
        width: parent.width
        implicitHeight: content.implicitHeight + 16
        height: implicitHeight
        material: GlassStyle.MaterialMenu
        radius: GlassStyle.RadiusMenu
        fillColor: GlassStyle.FillPanelBright
        strokeColor: GlassStyle.StrokePanelBright
        opacity: 1

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

            // 头部：进程名 + PID。
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                spacing: 8

                Text {
                    text: "\ueb8e" // terminal
                    color: root.textTertiary
                    font.family: "Material Icons"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.proc && root.proc.name ? root.proc.name : "进程"
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    text: root.proc && root.proc.pid ? ("PID " + root.proc.pid) : ""
                    color: root.textTertiary
                    font.pixelSize: 11
                    font.family: root.monoFontFamily
                    Layout.alignment: Qt.AlignVCenter
                    visible: text.length > 0
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "复制进程 ID"
                icon: "\ue9ef" // tag
                enabledRow: root.proc && root.proc.pid > 0
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.proc && root.proc.pid)
                        copyToClipboard(String(root.proc.pid));
                    root.closeRequested();
                }
            }
            MenuRow {
                text: "复制名称"
                icon: "\ue14d" // content_copy
                enabledRow: root.proc && root.proc.name && root.proc.name.length > 0
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.proc && root.proc.name)
                        copyToClipboard(root.proc.name);
                    root.closeRequested();
                }
            }
            MenuRow {
                text: "复制完整命令"
                icon: "\ue86f" // code
                enabledRow: root.proc && root.proc.cmdline && root.proc.cmdline.length > 0
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.proc && root.proc.cmdline)
                        copyToClipboard(root.proc.cmdline);
                    root.closeRequested();
                }
            }

            MenuSeparator {
                darkMode: root.darkMode
            }

            MenuRow {
                text: "结束进程"
                icon: "\ue5cd" // close
                enabledRow: root.proc && root.proc.pid > 0
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.proc && root.proc.pid)
                        Quickshell.execDetached(["kill", String(root.proc.pid)]);
                    root.closeRequested();
                }
            }
            MenuRow {
                text: "强制结束 (SIGKILL)"
                icon: "\ue5c9" // cancel
                destructive: true
                // 强制结束守 uid>=1000：对系统进程（uid<1000）禁用，防误杀关键进程（DoD）。
                enabledRow: root.proc && root.proc.pid > 0
                    && root.proc.uid !== undefined && root.proc.uid !== null
                    && root.proc.uid >= 1000
                settingsService: root.settingsService
                darkMode: root.darkMode
                onActivated: {
                    if (root.proc && root.proc.pid)
                        Quickshell.execDetached(["kill", "-9", String(root.proc.pid)]);
                    root.closeRequested();
                }
            }
        }

        // 焦点捕获 + Esc 关闭（DoD：Esc 关闭）。PanelWindow focusable:open 已可获焦，
        // 这里给一个 Item 承载按键。
        Item {
            id: focusCatcher
            anchors.fill: parent
            focus: root.open
            Keys.onEscapePressed: root.closeRequested()
        }
    }

    // 复制到剪贴板：显式使用文本 MIME，避免文本目标误判格式。
    function copyToClipboard(text) {
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy --type 'text/plain;charset=utf-8'", "sh", String(text)]);
    }
}
