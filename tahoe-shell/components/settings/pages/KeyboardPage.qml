pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property var input: page.panel && page.panel.inputMethodService ? page.panel.inputMethodService : null
    readonly property bool ready: !!page.svc && page.svc.loaded

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
            title: "键盘"
            subtitle: "按键重复和数字键盘"

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue042"
                label: "重复速率"
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
                iconCode: "\ue045"
                label: "重复延迟"
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
                iconCode: "\ue897"
                checkable: true
                checked: page.svc ? page.svc.keyboardNumlock : false
                enabled: page.ready
                onToggled: function(checked) {
                    if (page.svc)
                        page.svc.setKeyboardNumlock(checked);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "输入法"
            subtitle: "当前输入法状态"

            Controls.TahoeListRow {
                theme: page.theme
                label: "输入法"
                detail: page.panel ? page.panel.inputStatusText() : "输入法服务不可用"
                iconCode: "\ue312"

                RowLayout {
                    spacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "切换"
                        enabled: !!(page.input && page.input.available)
                        onActivated: page.input.toggle()
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "刷新"
                        enabled: !!page.input
                        onActivated: page.input.refresh()
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "快捷键与截图"
            subtitle: "只读快捷键和截图偏好"

            Controls.TahoeListRow {
                theme: page.theme
                label: "键盘快捷键"
                detail: "niri binds 只读查看；改键请编辑 config.kdl。"
                iconCode: "\ue8ef"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("niri-keyboard");
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "截图"
                detail: page.panel ? page.panel.screenshotPathText() : ""
                iconCode: "\ue3b0"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("screenshot");
                    }
                }
            }
        }
    }
}
