pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function signed(n) {
        var value = Math.round(Number(n) * 100) / 100;
        return value > 0 ? "+" + value : "" + value;
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Text {
            Layout.fillWidth: true
            visible: !page.ready || (page.svc && page.svc.lastError.length > 0)
            text: !page.svc ? "niri 设置服务不可用"
                : !page.svc.loaded ? "正在读取 niri 配置..."
                : page.svc.lastError
            color: page.svc && page.svc.lastError.length > 0
                ? (page.theme ? page.theme.danger : "#ff453a")
                : (page.theme ? page.theme.textSecondary : "#721d1d1f")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "触摸板"
            subtitle: "点按、滚动和指针速度"

            Controls.TahoeListRow {
                theme: page.theme
                label: "点按以点按"
                detail: page.svc && page.svc.touchpadTap ? "轻点即可点击" : "关闭"
                iconCode: "\ue04d"
                checkable: true
                checked: page.svc ? page.svc.touchpadTap : false
                enabled: page.ready
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setTouchpadTap(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "自然滚动"
                detail: page.svc && page.svc.touchpadNaturalScroll ? "内容跟随手指方向" : "关闭"
                iconCode: "\ue9ba"
                checkable: true
                checked: page.svc ? page.svc.touchpadNaturalScroll : false
                enabled: page.ready
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setTouchpadNaturalScroll(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "打字时禁用"
                detail: page.svc && page.svc.touchpadDwt ? "打字时屏蔽触摸板" : "关闭"
                iconCode: "\ue313"
                checkable: true
                checked: page.svc ? page.svc.touchpadDwt : false
                enabled: page.ready
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setTouchpadDwt(checked);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue9e9"
                label: "指针速度"
                valueText: page.svc ? page.signed(page.svc.touchpadAccelSpeed) : "0"
                value: page.svc ? Math.max(0, Math.min(1, (page.svc.touchpadAccelSpeed + 1) / 2)) : 0.5
                enabled: page.ready
                onUserCommit: function(v) {
                    if (page.svc)
                        page.svc.setTouchpadAccelSpeed(Math.round((v * 2 - 1) * 100) / 100);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "鼠标"
            subtitle: "当前没有独立鼠标后端"

            Controls.TahoeListRow {
                theme: page.theme
                label: "鼠标设置"
                detail: "触摸板设置已内置；鼠标速度、主键和滚轮后续接入后端。"
                iconCode: "\ue323"
            }
        }
    }
}
