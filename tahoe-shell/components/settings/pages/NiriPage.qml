pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// Window-manager hub under 桌面与多任务. Domain pages parent to "niri" so
// back navigation returns here; sidebar highlight walks to multitasking.
Flickable {
    id: page

    property var panel
    property var theme

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        // Status line: surfaces service-absent, still-loading and write-error
        // states. Hidden once loaded and error-free so it does not clutter
        // the hub in the common case.
        Text {
            Layout.fillWidth: true
            visible: !page.ready || (page.svc && page.svc.lastError.length > 0)
            text: !page.svc ? "niri 设置服务不可用"
                : !page.svc.loaded ? "正在读取 niri 配置…"
                : page.svc.lastError
            color: page.svc && page.svc.lastError.length > 0
                ? (page.theme ? page.theme.danger : "#ff453a")
                : (page.theme ? page.theme.textSecondary : "#721d1d1f")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: "高级窗口管理选项。更改会立即生效，并在重启后保留。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: settingsColumn.width >= 560 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue871"
                title: "布局与窗口"
                detail: page.svc ? "间距 " + page.svc.gaps + " px · 焦点环/边框/阴影/Snap" : "布局设置"
                accentColor: page.panel ? page.panel.categoryColor("niri") : "#30b0c8"
                onActivated: {
                    if (page.panel)
                        page.panel.openPage("niri-layout");
                }
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue3a3"
                title: "玻璃材质"
                detail: page.svc ? "全局模糊与折射材质" : "玻璃材质"
                accentColor: page.panel ? page.panel.categoryColor("niri-glass") : "#5e5ce6"
                onActivated: {
                    if (page.panel)
                        page.panel.openPage("niri-glass");
                }
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue312"
                title: "输入与显示"
                detail: page.svc ? "键盘/触摸板手感，输出只读" : "输入设置"
                accentColor: page.panel ? page.panel.categoryColor("niri-input") : "#0a84ff"
                onActivated: {
                    if (page.panel)
                        page.panel.openPage("niri-input");
                }
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue8c1"
                title: "动画"
                detail: page.svc ? "工作区/窗口/概览的弹簧手感" : "动画设置"
                accentColor: page.panel ? page.panel.categoryColor("niri-animations") : "#ff9f0a"
                onActivated: {
                    if (page.panel)
                        page.panel.openPage("niri-animations");
                }
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue8ef"
                title: "快捷键"
                detail: page.svc ? "当前快捷键只读查看" : "快捷键"
                accentColor: page.panel ? page.panel.categoryColor("niri-keyboard") : "#8e8e93"
                onActivated: {
                    if (page.panel)
                        page.panel.openPage("niri-keyboard");
                }
            }
        }
    }
}
