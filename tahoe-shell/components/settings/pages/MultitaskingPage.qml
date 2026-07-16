pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme

    readonly property var niri: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property var settings: page.panel && page.panel.settingsService ? page.panel.settingsService : null

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function open(id) {
        if (page.panel)
            page.panel.openPage(id);
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口与工作区"
            subtitle: "布局、工作区和窗口动画"

            Controls.TahoeListRow {
                theme: page.theme
                label: "布局与窗口"
                detail: page.niri
                    ? "间距 " + page.niri.gaps + " px · 焦点环/边框/阴影/Snap"
                    : "niri 布局设置"
                iconCode: "\ue871"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("niri-layout")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "动画"
                detail: page.niri && page.niri.layerAnimationsEnabled
                    ? "面板交给 compositor layer animation；窗口动画由 niri 管理"
                    : "面板外层显隐即时完成；窗口动画由 niri 管理"
                iconCode: "\ue8c1"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("niri-animations")
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "Shell 多任务"
            subtitle: "Dock 和顶栏交互"

            Controls.TahoeListRow {
                theme: page.theme
                label: "Dock"
                detail: page.settings
                    ? (page.settings.dockAutoHide ? "自动隐藏" : "始终显示")
                        + " · " + page.settings.modeLabel(page.panel.dockTitleMode())
                        + (page.settings.dockMinimizedShelfEnabled ? " · 缩略栏" : " · 旧式最小化")
                    : "窗口按钮显示偏好"
                iconCode: "\ue8d0"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("dock")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "灵动岛"
                detail: page.settings && page.settings.dynamicIslandEnabled
                    ? "顶栏中心胶囊已启用"
                    : "使用顶栏时间 fallback"
                iconCode: "\ueb81"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("dynamic-island")
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "高级窗口管理"
            subtitle: "niri 和 Tahoe 专用配置"

            Controls.TahoeListRow {
                theme: page.theme
                label: "Niri / Window Manager"
                detail: "玻璃材质、输入兼容页和其他无法归入 GNOME 标准域的设置。"
                iconCode: "\ue871"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("niri")
                }
            }
        }
    }
}
