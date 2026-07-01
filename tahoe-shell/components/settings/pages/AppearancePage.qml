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
            title: "外观"
            subtitle: "深浅色和系统主题"

            Controls.TahoeListRow {
                theme: page.theme
                label: "深色模式"
                detail: page.panel && page.panel.appearanceService && page.panel.appearanceService.darkMode ? "当前偏好深色" : "当前偏好浅色"
                iconCode: "\ue51c"
                checkable: true
                checked: page.panel && page.panel.appearanceService && page.panel.appearanceService.darkMode
                enabled: !!(page.panel && page.panel.appearanceService)
                onToggled: function(checked) {
                    if (page.panel.appearanceService)
                        page.panel.appearanceService.setDarkMode(checked);
                }
            }

        }

        Controls.TahoeSection {
            theme: page.theme
            title: "壁纸"
            subtitle: "背景图片和动态壁纸"

            Controls.TahoeListRow {
                theme: page.theme
                label: "壁纸"
                detail: page.panel && page.panel.settingsService
                    ? page.panel.settingsService.wallpaperModeLabel(page.panel.settingsService.wallpaperMode)
                    : "设置服务不可用"
                iconCode: "\ue40b"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("wallpaper");
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "图标主题"
            subtitle: page.panel && page.panel.settingsService ? page.panel.settingsService.iconThemeStatusText() : "选择应用和托盘图标来源"

            Controls.TahoeListRow {
                theme: page.theme
                label: "预设主题"
                detail: "第三方主题需安装到 ~/.local/share/icons 或 /usr/share/icons"
                iconCode: "\ue3b7"

                GridLayout {
                    columns: 2
                    columnSpacing: 7
                    rowSpacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "系统默认"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.iconThemeMode === "system"
                        minimumWidth: 92
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setIconThemeMode("system")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "内置默认"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.iconThemeMode === "builtin"
                        minimumWidth: 92
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setIconThemeMode("builtin")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "Papirus"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.iconThemeMode === "papirus"
                        minimumWidth: 92
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setIconThemeMode("papirus")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "Papirus Dark"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.iconThemeMode === "papirus-dark"
                        minimumWidth: 112
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setIconThemeMode("papirus-dark")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "Papirus Light"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.iconThemeMode === "papirus-light"
                        minimumWidth: 112
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setIconThemeMode("papirus-light")
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "自定义主题名"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.customIconTheme.length > 0
                    ? page.panel.settingsService.customIconTheme
                    : "例如 Tela、Fluent、WhiteSur"
                iconCode: "\ue8b8"

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 420

                    Controls.TahoeTextField {
                        id: customIconThemeInput
                        theme: page.theme
                        text: page.panel && page.panel.settingsService ? page.panel.settingsService.customIconTheme : ""
                        onEditingFinished: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setCustomIconTheme(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "使用"
                        enabled: !!(page.panel && page.panel.settingsService)
                        primary: page.panel && page.panel.settingsService && page.panel.settingsService.iconThemeMode === "custom"
                        onActivated: page.panel.settingsService.setCustomIconTheme(customIconThemeInput.text)
                    }
                }
            }
        }
    }
}
