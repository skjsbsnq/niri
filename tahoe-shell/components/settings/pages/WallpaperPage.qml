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
                        label: "命令"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "dynamic"
                        minimumWidth: 72
                        onActivated: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setWallpaperMode("dynamic");
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "UX 管理"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "external"
                        minimumWidth: 82
                        onActivated: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setWallpaperMode("external");
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

            Controls.TahoeListRow {
                theme: page.theme
                label: "锁屏跟随壁纸"
                detail: "静态壁纸直接沿用；动态壁纸使用引擎渲染的高清静态帧"
                iconCode: "\ue897"
                checkable: true
                enabled: !!(page.panel && page.panel.settingsService)
                checked: !!(page.panel && page.panel.settingsService
                    && page.panel.settingsService.lockScreenFollowWallpaper)
                onToggled: function(next) {
                    if (page.panel && page.panel.settingsService)
                        page.panel.settingsService.setLockScreenFollowWallpaper(next);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "动态壁纸"
            subtitle: "用命令托管，或交给 Linux Wallpaper Engine UX 切换。全屏策略交给引擎原生处理，Shell 不销毁壁纸进程。"

            Controls.TahoeListRow {
                theme: page.theme
                label: "Linux Wallpaper Engine"
                detail: "UX 管理模式会在 Tahoe 启动时恢复上次应用的动态壁纸"
                iconCode: "\ue8b8"

                RowLayout {
                    spacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "打开管理器"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.openWallpaperEngineUx()
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "活动帧率"
                detail: "播放时上限（1–20）。高帧率会抬高 CPU 并拖累毛玻璃采样。"
                iconCode: "\ue425"
                enabled: !!(page.panel && page.panel.settingsService
                    && page.panel.settingsService.wallpaperMode !== "static")

                RowLayout {
                    spacing: 7
                    Controls.TahoeButton {
                        theme: page.theme
                        label: "12"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperEngineFps === 12
                        minimumWidth: 48
                        onActivated: page.panel.settingsService.setWallpaperEngineFps(12)
                    }
                    Controls.TahoeButton {
                        theme: page.theme
                        label: "15"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperEngineFps === 15
                        minimumWidth: 48
                        onActivated: page.panel.settingsService.setWallpaperEngineFps(15)
                    }
                    Controls.TahoeButton {
                        theme: page.theme
                        label: "20"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperEngineFps === 20
                        minimumWidth: 48
                        onActivated: page.panel.settingsService.setWallpaperEngineFps(20)
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "空闲帧率"
                detail: {
                    if (!page.panel || !page.panel.settingsService)
                        return "空闲后的下次安全启动使用较低帧率";
                    var sec = page.panel.settingsService.wallpaperEngineIdleSeconds;
                    var fps = page.panel.settingsService.wallpaperEngineIdleFps;
                    return "无输入 " + sec + "s 后，下次启动使用 " + fps + " fps；不会为调速打断当前画面";
                }
                iconCode: "\ue192"
                enabled: !!(page.panel && page.panel.settingsService
                    && page.panel.settingsService.wallpaperMode !== "static")

                RowLayout {
                    spacing: 7
                    Controls.TahoeButton {
                        theme: page.theme
                        label: "5"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperEngineIdleFps === 5
                        minimumWidth: 48
                        onActivated: page.panel.settingsService.setWallpaperEngineIdleFps(5)
                    }
                    Controls.TahoeButton {
                        theme: page.theme
                        label: "8"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperEngineIdleFps === 8
                        minimumWidth: 48
                        onActivated: page.panel.settingsService.setWallpaperEngineIdleFps(8)
                    }
                    Controls.TahoeButton {
                        theme: page.theme
                        label: "12"
                        active: page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperEngineIdleFps === 12
                        minimumWidth: 48
                        onActivated: page.panel.settingsService.setWallpaperEngineIdleFps(12)
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "空闲暂停"
                detail: "空闲时停止动态引擎并显示静态壁纸（最省电）"
                iconCode: "\ue034"
                checkable: true
                enabled: !!(page.panel && page.panel.settingsService
                    && page.panel.settingsService.wallpaperMode !== "static")
                checked: !!(page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperPauseWhenIdle)
                onToggled: function(next) {
                    if (page.panel && page.panel.settingsService)
                        page.panel.settingsService.setWallpaperPauseWhenIdle(next);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "全屏时暂停动态壁纸"
                detail: "开启时使用 Wallpaper Engine 默认暂停；关闭时保持播放。非 Wallpaper Engine 自定义命令需自行处理。"
                iconCode: "\ue037"
                checkable: true
                enabled: !!(page.panel && page.panel.settingsService
                    && page.panel.settingsService.wallpaperMode !== "static")
                checked: !!(page.panel && page.panel.settingsService
                    && page.panel.settingsService.wallpaperPauseWhenFullscreen)
                onToggled: function(next) {
                    if (page.panel && page.panel.settingsService)
                        page.panel.settingsService.setWallpaperPauseWhenFullscreen(next);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "启动命令"
                detail: "支持 {output} 输出名占位符，示例里的 WALLPAPER_ID 需替换"
                iconCode: "\ue8b8"
                enabled: !!(page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "dynamic")

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 520

                    Controls.TahoeTextField {
                        id: dynamicCommandInput
                        theme: page.theme
                        Layout.preferredWidth: 370
                        enabled: !!(page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "dynamic")
                        text: page.panel && page.panel.settingsService ? page.panel.settingsService.dynamicWallpaperCommand : ""
                        onEditingFinished: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setDynamicWallpaperCommand(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: !!(page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "dynamic")
                        onActivated: page.panel.settingsService.setDynamicWallpaperCommand(dynamicCommandInput.text)
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "示例"
                        enabled: !!(page.panel && page.panel.settingsService && page.panel.settingsService.wallpaperMode === "dynamic")
                        onActivated: page.panel.settingsService.useDynamicWallpaperExampleCommand()
                    }
                }
            }
        }
    }
}
