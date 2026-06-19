pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// S5.2: input domain. Keyboard repeat-rate/repeat-delay/numlock and touchpad
// tap/natural-scroll/dwt/accel-speed write through NiriSettings.setX. Output
// scale is read-only (display only) — the GUI never writes output and never
// touches variable-refresh-rate (guardrails hard constraint). accel-speed is
// clamped to [-1,1] per the niri schema.
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

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded

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
                : !page.svc.loaded ? "正在读取 niri 配置…"
                : page.svc.lastError
            color: page.svc && page.svc.lastError.length > 0
                ? (page.theme ? page.theme.danger : "#ff453a")
                : (page.theme ? page.theme.textSecondary : "#721d1d1f")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "键盘"
            subtitle: "按键重复速率与延迟"

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e042"
                label: "重复速率（repeat-rate）"
                valueText: (page.svc ? page.svc.keyboardRepeatRate : 25) + " /秒"
                value: page.svc ? Math.max(0, Math.min(1, page.svc.keyboardRepeatRate / 100)) : 0.25
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setKeyboardRepeatRate(Math.round(v * 100));
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e045"
                label: "重复延迟（repeat-delay）"
                valueText: (page.svc ? page.svc.keyboardRepeatDelay : 600) + " ms"
                value: page.svc ? Math.max(0, Math.min(1, page.svc.keyboardRepeatDelay / 1000)) : 0.6
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setKeyboardRepeatDelay(Math.round(v * 1000));
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "Numlock"
                detail: page.svc && page.svc.keyboardNumlock ? "开机自动开启" : "关闭"
                iconCode: "\e897"
                checkable: true
                checked: page.svc ? page.svc.keyboardNumlock : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setKeyboardNumlock(c);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "触摸板"
            subtitle: "点按、自然滚动与手感"

            Controls.TahoeListRow {
                theme: page.theme
                label: "点按以点按（tap）"
                detail: page.svc && page.svc.touchpadTap ? "轻点即可点击" : "关闭"
                iconCode: "\e04d"
                checkable: true
                checked: page.svc ? page.svc.touchpadTap : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setTouchpadTap(c);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "自然滚动"
                detail: page.svc && page.svc.touchpadNaturalScroll ? "内容跟随手指方向" : "关闭"
                iconCode: "\e9ba"
                checkable: true
                checked: page.svc ? page.svc.touchpadNaturalScroll : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setTouchpadNaturalScroll(c);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "打字时禁用（dwt）"
                detail: page.svc && page.svc.touchpadDwt ? "打字时屏蔽触摸板" : "关闭"
                iconCode: "\e313"
                checkable: true
                checked: page.svc ? page.svc.touchpadDwt : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setTouchpadDwt(c);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\e9e9"
                label: "指针速度（accel-speed）"
                valueText: page.svc ? page.signed(page.svc.touchpadAccelSpeed) : "0"
                value: page.svc ? Math.max(0, Math.min(1, (page.svc.touchpadAccelSpeed + 1) / 2)) : 0.5
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setTouchpadAccelSpeed(Math.round((v * 2 - 1) * 100) / 100);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "输出"
            subtitle: "显示器与缩放（只读）"

            Controls.TahoeListRow {
                theme: page.theme
                label: page.svc && page.svc.outputPresent ? page.svc.outputName : "未检测到输出"
                detail: page.svc && page.svc.outputPresent ? "缩放 " + page.svc.outputScale : "由 config.kdl 管理"
                iconCode: "\e307"
                checkable: false
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                text: "输出分辨率、缩放与可变刷新率（VRR）由 niri config.kdl 直接管理。VRR 保持关闭（护栏），如需更改请编辑配置文件。"
                color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }

        Text {
            Layout.fillWidth: true
            text: "这些选项写入 niri 的 config.kdl 并在写入后立即热重载，重启 niri 后仍然生效。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
