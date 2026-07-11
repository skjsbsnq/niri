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
            title: "强调色"
            subtitle: page.panel && page.panel.settingsService
                ? ("当前 " + page.panel.settingsService.accentColorLabel(page.panel.settingsService.accentColor) + " · 菜单高亮与系统强调色")
                : "菜单高亮、开关与系统强调色（macOS 八色）"

            Flow {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { "id": "blue" },
                        { "id": "purple" },
                        { "id": "pink" },
                        { "id": "red" },
                        { "id": "orange" },
                        { "id": "yellow" },
                        { "id": "green" },
                        { "id": "graphite" }
                    ]

                    delegate: Item {
                        id: swatch

                        required property var modelData

                        width: 36
                        height: 36

                        readonly property bool selected: page.panel && page.panel.settingsService
                            && page.panel.settingsService.accentColor === swatch.modelData.id
                        readonly property color swatchColor: {
                            var id = swatch.modelData.id;
                            var dark = page.theme && page.theme.darkMode;
                            // Match SettingsTheme.systemAccent palette.
                            if (id === "purple") return dark ? "#bf5af2" : "#af52de";
                            if (id === "pink") return dark ? "#ff375f" : "#ff2d55";
                            if (id === "red") return dark ? "#ff453a" : "#ff3b30";
                            if (id === "orange") return dark ? "#ff9f0a" : "#ff9500";
                            if (id === "yellow") return dark ? "#ffd60a" : "#ffcc00";
                            if (id === "green") return dark ? "#30d158" : "#34c759";
                            if (id === "graphite") return dark ? "#98989d" : "#8e8e93";
                            return dark ? "#0a84ff" : "#007ff7";
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: 14
                            color: swatch.swatchColor
                            border.color: swatch.selected ? (page.theme ? page.theme.textPrimary : "#1d1d1f") : "#55ffffff"
                            border.width: swatch.selected ? 2 : 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !!(page.panel && page.panel.settingsService)
                            onClicked: page.panel.settingsService.setAccentColor(swatch.modelData.id)
                        }
                    }
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
