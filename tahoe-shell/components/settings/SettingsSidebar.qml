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

    Layout.preferredWidth: 188
    Layout.fillHeight: true
    radius: 18
    color: "#20ffffff"
    border.color: "#34ffffff"
    border.width: 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 10
                color: "#4cffffff"
                border.color: "#42ffffff"

                Text {
                    anchors.centerIn: parent
                    text: "\ue8b8"
                    color: sidebar.textPrimary
                    font.family: sidebar.iconFont
                    font.pixelSize: 19
                }
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
            active: sidebar.panel && sidebar.panel.selectedPage === "settings"
            onActivated: sidebar.panel.selectedPage = "settings"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "外观"
            iconCode: "\ue51c"
            active: sidebar.panel && sidebar.panel.selectedPage === "appearance"
            onActivated: sidebar.panel.selectedPage = "appearance"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "通知与输入"
            iconCode: "\ue7f4"
            active: sidebar.panel && sidebar.panel.selectedPage === "notifications"
            badgeText: sidebar.panel && sidebar.panel.notificationsService && sidebar.panel.notificationsService.historyCount > 0
                ? String(Math.min(99, sidebar.panel.notificationsService.historyCount))
                : ""
            onActivated: sidebar.panel.selectedPage = "notifications"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "截图"
            iconCode: "\ue3b0"
            active: sidebar.panel && sidebar.panel.selectedPage === "screenshot"
            onActivated: sidebar.panel.selectedPage = "screenshot"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "Dock"
            iconCode: "\ue8d0"
            active: sidebar.panel && sidebar.panel.selectedPage === "dock"
            onActivated: sidebar.panel.selectedPage = "dock"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "启动项"
            iconCode: "\ue89e"
            active: sidebar.panel && sidebar.panel.selectedPage === "startup"
            onActivated: sidebar.panel.selectedPage = "startup"
        }

        Controls.TahoeSidebarButton {
            theme: sidebar.theme
            label: "系统健康"
            iconCode: "\ue868"
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
