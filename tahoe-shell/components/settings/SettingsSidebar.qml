pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "controls" as Controls

Rectangle {
    id: sidebar

    property var panel
    property var theme

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color sidebarFill: theme ? theme.sidebarFill : "#20ffffff"
    readonly property color sidebarStroke: theme ? theme.sidebarStroke : "#34ffffff"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

    function categoryColor(key) {
        return theme && theme.categoryColor ? theme.categoryColor(key) : accentBlue
    }

    Layout.preferredWidth: 188
    Layout.fillHeight: true
    radius: 18
    color: sidebar.sidebarFill
    border.color: sidebar.sidebarStroke
    border.width: 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: 9

            Controls.TahoeCategoryIcon {
                theme: sidebar.theme
                iconCode: "\ue8b8"
                accentColor: sidebar.accentBlue
                square: 30
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Tahoe"
                    color: sidebar.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: "Desktop"
                    color: sidebar.textSecondary
                    font.pixelSize: 11
                }
            }
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "概览"
            iconCode: "\ue8b8"
            accentColor: sidebar.categoryColor("overview")
            active: sidebar.panel && sidebar.panel.selectedPage === "settings"
            onActivated: sidebar.panel.selectedPage = "settings"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "外观"
            iconCode: "\ue51c"
            accentColor: sidebar.categoryColor("appearance")
            active: sidebar.panel && sidebar.panel.selectedPage === "appearance"
            onActivated: sidebar.panel.selectedPage = "appearance"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "壁纸"
            iconCode: "\ue40b"
            accentColor: sidebar.categoryColor("wallpaper")
            active: sidebar.panel && sidebar.panel.selectedPage === "wallpaper"
            onActivated: sidebar.panel.selectedPage = "wallpaper"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "布局与窗口"
            iconCode: "\ue871"
            accentColor: sidebar.categoryColor("niri")
            // Stays active on the niri hub and every niri-* sub-page so the
            // sidebar highlights the group the user is inside.
            active: sidebar.panel && (sidebar.panel.selectedPage === "niri"
                || String(sidebar.panel.selectedPage).indexOf("niri-") === 0)
            onActivated: sidebar.panel.selectedPage = "niri"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "通知与输入"
            iconCode: "\ue7f4"
            accentColor: sidebar.categoryColor("notifications")
            active: sidebar.panel && sidebar.panel.selectedPage === "notifications"
            badgeText: sidebar.panel && sidebar.panel.notificationsService && sidebar.panel.notificationsService.historyCount > 0
                ? String(Math.min(99, sidebar.panel.notificationsService.historyCount))
                : ""
            onActivated: sidebar.panel.selectedPage = "notifications"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "灵动岛"
            iconCode: "\ueb81"
            accentColor: sidebar.categoryColor("dynamic-island")
            active: sidebar.panel && sidebar.panel.selectedPage === "dynamic-island"
            onActivated: sidebar.panel.selectedPage = "dynamic-island"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "截图"
            iconCode: "\ue3b0"
            accentColor: sidebar.categoryColor("screenshot")
            active: sidebar.panel && sidebar.panel.selectedPage === "screenshot"
            onActivated: sidebar.panel.selectedPage = "screenshot"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "Dock"
            iconCode: "\ue8d0"
            accentColor: sidebar.categoryColor("dock")
            active: sidebar.panel && sidebar.panel.selectedPage === "dock"
            onActivated: sidebar.panel.selectedPage = "dock"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "天气"
            iconCode: "\ue2bd"
            accentColor: sidebar.categoryColor("weather")
            active: sidebar.panel && sidebar.panel.selectedPage === "weather"
            onActivated: sidebar.panel.selectedPage = "weather"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "启动项"
            iconCode: "\ue89e"
            accentColor: sidebar.categoryColor("startup")
            active: sidebar.panel && sidebar.panel.selectedPage === "startup"
            onActivated: sidebar.panel.selectedPage = "startup"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "系统健康"
            iconCode: "\ue868"
            accentColor: sidebar.categoryColor("health")
            active: sidebar.panel && sidebar.panel.selectedPage === "health"
            badgeText: sidebar.panel && sidebar.panel.systemStatusService && sidebar.panel.systemStatusService.missingCount > 0
                ? String(sidebar.panel.systemStatusService.missingCount)
                : ""
            onActivated: {
                sidebar.panel.selectedPage = "health";
                if (sidebar.panel.systemStatusService)
                    sidebar.panel.systemStatusService.refresh();
            }
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "关于"
            iconCode: "\ue88e"
            accentColor: sidebar.categoryColor("about")
            active: sidebar.panel && sidebar.panel.selectedPage === "about"
            onActivated: sidebar.panel.selectedPage = "about"
        }

        Item { Layout.fillHeight: true }

        Text {
            Layout.fillWidth: true
            text: sidebar.panel && sidebar.panel.settingsService ? sidebar.panel.settingsService.settingsPath : ""
            color: sidebar.textSecondary
            font.pixelSize: 10
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
        }
    }
}
