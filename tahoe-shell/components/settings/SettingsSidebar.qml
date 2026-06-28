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
    clip: true

    function activeButton() {
        if (!sidebar.panel)
            return null;

        var selected = String(sidebar.panel.selectedPage);
        if (selected === "settings")
            return overviewButton;
        if (selected === "appearance")
            return appearanceButton;
        if (selected === "wallpaper")
            return wallpaperButton;
        if (selected === "niri" || selected.indexOf("niri-") === 0)
            return niriButton;
        if (selected === "notifications")
            return notificationsButton;
        if (selected === "dynamic-island")
            return dynamicIslandButton;
        if (selected === "screenshot")
            return screenshotButton;
        if (selected === "dock")
            return dockButton;
        if (selected === "weather")
            return weatherButton;
        if (selected === "startup")
            return startupButton;
        if (selected === "health")
            return healthButton;
        if (selected === "about")
            return aboutButton;
        return overviewButton;
    }

    function ensureActiveVisible() {
        var item = activeButton();
        if (!item || navFlick.height <= 0)
            return;
        if (navFlick.contentHeight <= navFlick.height) {
            navFlick.contentY = 0;
            return;
        }

        var margin = 6;
        var top = item.y;
        var bottom = item.y + item.height;
        var maxY = Math.max(0, navFlick.contentHeight - navFlick.height);

        if (top < navFlick.contentY + margin)
            navFlick.contentY = Math.max(0, top - margin);
        else if (bottom > navFlick.contentY + navFlick.height - margin)
            navFlick.contentY = Math.min(maxY, bottom - navFlick.height + margin);
    }

    Component.onCompleted: Qt.callLater(function() { sidebar.ensureActiveVisible(); })
    onHeightChanged: Qt.callLater(function() { sidebar.ensureActiveVisible(); })

    Connections {
        target: sidebar.panel

        function onSelectedPageChanged() {
            Qt.callLater(function() { sidebar.ensureActiveVisible(); });
        }
    }

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

        Flickable {
            id: navFlick

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: navColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            onHeightChanged: Qt.callLater(function() { sidebar.ensureActiveVisible(); })
            onContentHeightChanged: Qt.callLater(function() { sidebar.ensureActiveVisible(); })

            ColumnLayout {
                id: navColumn

                width: navFlick.width
                spacing: 8

                Controls.TahoeSidebarButton {
                    id: overviewButton

                    theme: sidebar.theme
                    label: "概览"
                    iconCode: "\ue8b8"
                    accentColor: sidebar.categoryColor("overview")
                    active: sidebar.panel && sidebar.panel.selectedPage === "settings"
                    onActivated: sidebar.panel.selectedPage = "settings"
                }

                Controls.TahoeSidebarButton {
                    id: appearanceButton

                    theme: sidebar.theme
                    label: "外观"
                    iconCode: "\ue51c"
                    accentColor: sidebar.categoryColor("appearance")
                    active: sidebar.panel && sidebar.panel.selectedPage === "appearance"
                    onActivated: sidebar.panel.selectedPage = "appearance"
                }

                Controls.TahoeSidebarButton {
                    id: wallpaperButton

                    theme: sidebar.theme
                    label: "壁纸"
                    iconCode: "\ue40b"
                    accentColor: sidebar.categoryColor("wallpaper")
                    active: sidebar.panel && sidebar.panel.selectedPage === "wallpaper"
                    onActivated: sidebar.panel.selectedPage = "wallpaper"
                }

                Controls.TahoeSidebarButton {
                    id: niriButton

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
                    id: notificationsButton

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
                    id: dynamicIslandButton

                    theme: sidebar.theme
                    label: "灵动岛"
                    iconCode: "\ueb81"
                    accentColor: sidebar.categoryColor("dynamic-island")
                    active: sidebar.panel && sidebar.panel.selectedPage === "dynamic-island"
                    onActivated: sidebar.panel.selectedPage = "dynamic-island"
                }

                Controls.TahoeSidebarButton {
                    id: screenshotButton

                    theme: sidebar.theme
                    label: "截图"
                    iconCode: "\ue3b0"
                    accentColor: sidebar.categoryColor("screenshot")
                    active: sidebar.panel && sidebar.panel.selectedPage === "screenshot"
                    onActivated: sidebar.panel.selectedPage = "screenshot"
                }

                Controls.TahoeSidebarButton {
                    id: dockButton

                    theme: sidebar.theme
                    label: "Dock"
                    iconCode: "\ue8d0"
                    accentColor: sidebar.categoryColor("dock")
                    active: sidebar.panel && sidebar.panel.selectedPage === "dock"
                    onActivated: sidebar.panel.selectedPage = "dock"
                }

                Controls.TahoeSidebarButton {
                    id: weatherButton

                    theme: sidebar.theme
                    label: "天气"
                    iconCode: "\ue2bd"
                    accentColor: sidebar.categoryColor("weather")
                    active: sidebar.panel && sidebar.panel.selectedPage === "weather"
                    onActivated: sidebar.panel.selectedPage = "weather"
                }

                Controls.TahoeSidebarButton {
                    id: startupButton

                    theme: sidebar.theme
                    label: "启动项"
                    iconCode: "\ue89e"
                    accentColor: sidebar.categoryColor("startup")
                    active: sidebar.panel && sidebar.panel.selectedPage === "startup"
                    onActivated: sidebar.panel.selectedPage = "startup"
                }

                Controls.TahoeSidebarButton {
                    id: healthButton

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
                    id: aboutButton

                    theme: sidebar.theme
                    label: "关于"
                    iconCode: "\ue88e"
                    accentColor: sidebar.categoryColor("about")
                    active: sidebar.panel && sidebar.panel.selectedPage === "about"
                    onActivated: sidebar.panel.selectedPage = "about"
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 14
            text: sidebar.panel && sidebar.panel.settingsService ? sidebar.panel.settingsService.settingsPath : ""
            color: sidebar.textSecondary
            font.pixelSize: 10
            elide: Text.ElideMiddle
            maximumLineCount: 1
        }
    }
}
