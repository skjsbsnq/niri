pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme

    readonly property var niri: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property var appearance: page.panel && page.panel.appearanceService ? page.panel.appearanceService : null
    readonly property bool niriReady: !!page.niri && page.niri.loaded

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

        Text {
            Layout.fillWidth: true
            visible: !page.niriReady || (page.niri && page.niri.lastError.length > 0)
            text: !page.niri ? "niri 设置服务不可用"
                : !page.niri.loaded ? "正在读取 niri 配置..."
                : page.niri.lastError
            color: page.niri && page.niri.lastError.length > 0
                ? (page.theme ? page.theme.danger : "#ff453a")
                : (page.theme ? page.theme.textSecondary : "#721d1d1f")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "显示输出"
            subtitle: "输出、缩放和刷新率"

            Controls.TahoeListRow {
                theme: page.theme
                label: page.niri && page.niri.outputPresent ? page.niri.outputName : "未检测到输出"
                detail: page.niri && page.niri.outputPresent ? "缩放 " + page.niri.outputScale : "由 niri config.kdl 管理"
                iconCode: "\ue333"
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue8b8"
                label: "缩放"
                valueText: page.niri && page.niri.outputPresent ? page.niri.outputScale.toFixed(2) + "x" : "-"
                value: page.niri && page.niri.outputPresent ? Math.max(0, Math.min(1, (page.niri.outputScale - 0.5) / 3.5)) : 0
                enabled: page.niriReady && page.niri && page.niri.outputPresent && !page.niri.updating
                onUserCommit: function(value) {
                    if (page.niri)
                        page.niri.setOutputScale(0.5 + value * 3.5);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "VRR"
                detail: "Tahoe niri 配置默认启用；实际支持状态以 niri msg outputs 为准。"
                iconCode: "\ue8b8"
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "夜览"
            subtitle: "降低夜间色温"

            Controls.TahoeListRow {
                theme: page.theme
                label: "夜览"
                detail: page.appearance && page.appearance.nightMode
                    ? "色温 " + page.appearance.colorTemperature + "K"
                    : "关闭"
                iconCode: "\ue3a9"
                checkable: true
                checked: page.appearance && page.appearance.nightMode
                enabled: !!page.appearance
                onToggled: function(checked) {
                    if (page.appearance)
                        page.appearance.setNightMode(checked);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ueb37"
                label: "色温"
                valueText: page.appearance ? page.appearance.colorTemperature + "K" : "-"
                value: page.appearance
                    ? Math.max(0, Math.min(1, (page.appearance.colorTemperature - 2500) / 4000))
                    : 0
                enabled: !!page.appearance
                onUserCommit: function(v) {
                    if (page.appearance)
                        page.appearance.setColorTemperature(2500 + Math.round(v * 4000));
                }
            }
        }
    }
}
