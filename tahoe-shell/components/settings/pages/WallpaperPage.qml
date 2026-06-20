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
            title: "壁纸"
            subtitle: "静态图片和 linux-wallpaper-engine 动态壁纸"

            Controls.TahoeListRow {
                theme: page.theme
                label: "壁纸模式"
                detail: page.panel && page.panel.settingsService
                    ? page.panel.settingsService.wallpaperModeLabel(page.panel.settingsService.wallpaperMode)
                    : "设置服务不可用"
                iconCode: "\ue40b"

                RowLayout {
                    spacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "静态"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "static"
                        minimumWidth: 72
                        onActivated: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setWallpaperMode("static");
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "动态"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "dynamic"
                        minimumWidth: 72
                        onActivated: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setWallpaperMode("dynamic");
                        }
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "静态图片"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.effectiveStaticWallpaper.length > 0
                    ? page.panel.settingsService.effectiveStaticWallpaper
                    : "使用内置默认壁纸"
                iconCode: "\ue3f4"

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 440

                    Controls.TahoeTextField {
                        id: staticWallpaperInput
                        theme: page.theme
                        Layout.preferredWidth: 300
                        text: page.panel && page.panel.settingsService ? page.panel.settingsService.staticWallpaperPath : ""
                        onEditingFinished: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setStaticWallpaperPath(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setStaticWallpaperPath(staticWallpaperInput.text)
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "默认"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.resetStaticWallpaperPath()
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "动态壁纸"
            subtitle: "命令退出时回落到静态壁纸"

            Controls.TahoeListRow {
                theme: page.theme
                label: "启动命令"
                detail: "支持 {output} 输出名占位符，示例里的 WALLPAPER_ID 需替换"
                iconCode: "\ue8b8"

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 520

                    Controls.TahoeTextField {
                        id: dynamicCommandInput
                        theme: page.theme
                        Layout.preferredWidth: 370
                        text: page.panel && page.panel.settingsService ? page.panel.settingsService.dynamicWallpaperCommand : ""
                        onEditingFinished: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setDynamicWallpaperCommand(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setDynamicWallpaperCommand(dynamicCommandInput.text)
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "示例"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.useDynamicWallpaperExampleCommand()
                    }
                }
            }
        }
    }
}
