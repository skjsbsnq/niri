pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

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

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "Dock"
            subtitle: "自动隐藏、触发热区和窗口按钮"

            Controls.TahoeListRow {
                theme: page.theme
                label: "自动隐藏"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.dockAutoHide
                    ? "鼠标移到底部热区时显示"
                    : "始终显示并为窗口预留底部空间"
                iconCode: "\ue5d2"
                checkable: true
                checked: page.panel && page.panel.settingsService && page.panel.settingsService.dockAutoHide
                enabled: !!(page.panel && page.panel.settingsService)
                onToggled: function(checked) {
                    if (page.panel.settingsService)
                        page.panel.settingsService.setDockAutoHide(checked);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue425"
                label: "隐藏延迟"
                valueText: page.panel && page.panel.settingsService ? page.panel.settingsService.dockAutoHideDelayMs + " ms" : "—"
                value: page.panel && page.panel.settingsService
                    ? Math.max(0, Math.min(1, page.panel.settingsService.dockAutoHideDelayMs / 1500))
                    : 0
                enabled: !!(page.panel && page.panel.settingsService && page.panel.settingsService.dockAutoHide)
                onUserSet: function(v) {
                    if (page.panel.settingsService)
                        page.panel.settingsService.setDockAutoHideDelayMs(Math.round(v * 1500));
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue5d5"
                label: "底部触发热区"
                valueText: page.panel && page.panel.settingsService ? page.panel.settingsService.dockRevealZoneHeight + " px" : "—"
                value: page.panel && page.panel.settingsService
                    ? Math.max(0, Math.min(1, (page.panel.settingsService.dockRevealZoneHeight - 2) / 22))
                    : 0
                enabled: !!(page.panel && page.panel.settingsService && page.panel.settingsService.dockAutoHide)
                onUserSet: function(v) {
                    if (page.panel.settingsService)
                        page.panel.settingsService.setDockRevealZoneHeight(2 + Math.round(v * 22));
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "窗口标题"
                detail: "空间不足时始终保留阶段 2 的不出屏约束"
                iconCode: "\ue8d0"

                RowLayout {
                    spacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "自动"
                        active: page.panel && page.panel.dockTitleMode() === "auto"
                        minimumWidth: Math.max(72, label.length * 8 + 20)
                        onActivated: page.panel.setDockTitleMode("auto")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "仅图标"
                        active: page.panel && page.panel.dockTitleMode() === "icons"
                        minimumWidth: Math.max(72, label.length * 8 + 20)
                        onActivated: page.panel.setDockTitleMode("icons")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "标题优先"
                        active: page.panel && page.panel.dockTitleMode() === "titles"
                        minimumWidth: Math.max(72, label.length * 8 + 20)
                        onActivated: page.panel.setDockTitleMode("titles")
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "最小化缩略栏"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.dockMinimizedShelfEnabled
                    ? "最小化窗口显示为右侧缩略图"
                    : "关闭，最小化窗口保留旧图标样式"
                iconCode: "\ue8ff"
                checkable: true
                checked: page.panel && page.panel.settingsService && page.panel.settingsService.dockMinimizedShelfEnabled
                enabled: !!(page.panel && page.panel.settingsService)
                onToggled: function(checked) {
                    if (page.panel.settingsService)
                        page.panel.settingsService.setDockMinimizedShelfEnabled(checked);
                }
            }
        }
    }
}
