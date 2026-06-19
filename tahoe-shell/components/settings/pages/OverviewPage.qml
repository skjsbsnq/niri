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

        GridLayout {
            Layout.fillWidth: true
            columns: settingsColumn.width >= 620 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: page.panel && page.panel.appearanceService && page.panel.appearanceService.darkMode ? "\ue51c" : "\ue518"
                title: page.panel && page.panel.appearanceService && page.panel.appearanceService.darkMode ? "深色模式" : "浅色模式"
                detail: page.panel && page.panel.appearanceService && page.panel.appearanceService.nightMode
                    ? "夜览 " + page.panel.appearanceService.colorTemperature + "K"
                    : "夜览关闭"
                accentColor: page.panel ? page.panel.categoryColor("appearance") : "#5856d6"
                onActivated: page.panel.selectedPage = "appearance"
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled ? "\ue7f6" : "\ue7f4"
                title: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled ? "勿扰已开启" : "通知正常"
                detail: page.panel && page.panel.notificationsService
                    ? page.panel.notificationsService.historyCount + " 条历史通知"
                    : "通知服务不可用"
                accentColor: page.panel ? page.panel.categoryColor("notifications") : "#ff3b30"
                onActivated: page.panel.selectedPage = "notifications"
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue3b0"
                title: "截图"
                detail: page.panel ? page.panel.screenshotPathText() : ""
                accentColor: page.panel ? page.panel.categoryColor("screenshot") : "#ff7a59"
                onActivated: page.panel.selectedPage = "screenshot"
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue8d0"
                title: "Dock"
                detail: page.panel && page.panel.settingsService ? "窗口标题：" + page.panel.settingsService.modeLabel(page.panel.dockTitleMode()) : "设置服务不可用"
                accentColor: page.panel ? page.panel.categoryColor("dock") : "#0a84ff"
                onActivated: page.panel.selectedPage = "dock"
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue871"
                title: "布局与窗口"
                detail: page.panel && page.panel.niriSettingsService
                    ? "间距 " + page.panel.niriSettingsService.gaps + " px"
                    : "niri 布局设置"
                accentColor: page.panel ? page.panel.categoryColor("niri") : "#30b0c8"
                onActivated: page.panel.selectedPage = "niri"
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: page.panel && page.panel.systemStatusService && page.panel.systemStatusService.missingCount > 0 ? "\ue002" : "\ue86c"
                title: page.panel && page.panel.systemStatusService && page.panel.systemStatusService.missingCount > 0 ? "有缺失项" : "系统健康"
                detail: page.panel && page.panel.systemStatusService
                    ? page.panel.systemStatusService.okCount + " 正常 · " + page.panel.systemStatusService.warnCount + " 注意 · " + page.panel.systemStatusService.missingCount + " 缺失"
                    : "等待检测"
                accentColor: page.panel ? page.panel.categoryColor("health") : "#34c759"
                onActivated: {
                    page.panel.selectedPage = "health";
                    if (page.panel.systemStatusService)
                        page.panel.systemStatusService.refresh();
                }
            }

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue89e"
                title: "启动项"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.startupNote.length > 0
                    ? page.panel.settingsService.startupNote
                    : "管理 autostart 目录"
                accentColor: page.panel ? page.panel.categoryColor("startup") : "#ff9f0a"
                onActivated: page.panel.selectedPage = "startup"
            }
        }
    }
}
