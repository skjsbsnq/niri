pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// Desktop & multitasking hub: primary Dock / island toggles live here;
// advanced niri domains open as sub-pages (no second sidebar entry for niri).
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
            title: "Dock 与顶栏"
            subtitle: "常用桌面行为可在此直接调整"

            Controls.TahoeListRow {
                theme: page.theme
                label: "自动隐藏 Dock"
                detail: page.settings && page.settings.dockAutoHide
                    ? "移到底部热区时显示"
                    : "始终显示"
                iconCode: "\ue5d2"
                checkable: true
                checked: page.settings && page.settings.dockAutoHide
                enabled: !!page.settings
                onToggled: function(checked) {
                    if (page.settings)
                        page.settings.setDockAutoHide(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "启用灵动岛"
                detail: page.settings && page.settings.dynamicIslandEnabled
                    ? "顶栏中心由灵动岛接管"
                    : "使用顶栏时间"
                iconCode: "\ueb81"
                checkable: true
                checked: page.settings && page.settings.dynamicIslandEnabled
                enabled: !!page.settings
                onToggled: function(checked) {
                    if (page.settings)
                        page.settings.setDynamicIslandEnabled(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "Dock 详细设置"
                detail: page.settings
                    ? page.settings.modeLabel(page.panel.dockTitleMode())
                        + (page.settings.dockMinimizedShelfEnabled ? " · 缩略栏" : "")
                    : "标题模式、热区和最小化"
                iconCode: "\ue8d0"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("dock")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "灵动岛详细设置"
                detail: "点击行为、媒体展开与工作区反馈"
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
            title: "窗口管理"
            subtitle: "布局、动画、玻璃与快捷键"

            Controls.TahoeListRow {
                theme: page.theme
                label: "窗口管理器"
                detail: page.niri
                    ? "间距 " + page.niri.gaps + " px · 布局/玻璃/动画"
                    : "布局、玻璃、动画与快捷键"
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
