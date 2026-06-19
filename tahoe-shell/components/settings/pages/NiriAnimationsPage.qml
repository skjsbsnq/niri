pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// S5.3: animations domain. Spring params (damping-ratio/stiffness/epsilon) for
// the four spring-based actions present in the config write through
// NiriSettings.setAnimParam (optimistic object update + queued KDL write +
// hot-reload). window-open/close carry custom GLSL shaders and are never
// written here. Ranges follow the niri schema parse-time bounds:
// damping-ratio [0.1,10], stiffness >=1, epsilon [0.00001,0.1].
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

    function animValue(action, param) {
        if (!page.svc || !page.svc.animSprings)
            return 0;
        var entry = page.svc.animSprings[action];
        var value = entry ? entry[param] : 0;
        return isFinite(value) ? value : 0;
    }

    function roundTo(value, decimals) {
        var factor = Math.pow(10, decimals);
        return Math.round(Number(value) * factor) / factor;
    }

    // damping-ratio [0.1, 10] <-> [0,1]
    function dampingFromValue(v) {
        return Math.max(0, Math.min(1, (Number(v) - 0.1) / 9.9));
    }
    function dampingToValue(r) {
        return page.roundTo(0.1 + r * 9.9, 2);
    }
    // stiffness [1, 1000] <-> [0,1]
    function stiffnessFromValue(v) {
        return Math.max(0, Math.min(1, (Number(v) - 1) / 999));
    }
    function stiffnessToValue(r) {
        return Math.round(1 + r * 999);
    }
    // epsilon [0.00001, 0.1] <-> [0,1]
    function epsilonFromValue(v) {
        return Math.max(0, Math.min(1, (Number(v) - 0.00001) / 0.09999));
    }
    function epsilonToValue(r) {
        return page.roundTo(0.00001 + r * 0.09999, 5);
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
            title: "工作区切换（workspace-switch）"
            subtitle: "切换虚拟工作区时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("workspace_switch", "damping_ratio")
                value: page.dampingFromValue(page.animValue("workspace_switch", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("workspace_switch", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("workspace_switch", "stiffness")
                value: page.stiffnessFromValue(page.animValue("workspace_switch", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("workspace_switch", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("workspace_switch", "epsilon")
                value: page.epsilonFromValue(page.animValue("workspace_switch", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("workspace_switch", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口移动（window-movement）"
            subtitle: "拖动窗口跟随指针时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("window_movement", "damping_ratio")
                value: page.dampingFromValue(page.animValue("window_movement", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_movement", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("window_movement", "stiffness")
                value: page.stiffnessFromValue(page.animValue("window_movement", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_movement", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("window_movement", "epsilon")
                value: page.epsilonFromValue(page.animValue("window_movement", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_movement", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口缩放（window-resize）"
            subtitle: "调整窗口大小时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("window_resize", "damping_ratio")
                value: page.dampingFromValue(page.animValue("window_resize", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_resize", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("window_resize", "stiffness")
                value: page.stiffnessFromValue(page.animValue("window_resize", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_resize", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("window_resize", "epsilon")
                value: page.epsilonFromValue(page.animValue("window_resize", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("window_resize", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "概览开关（overview-open-close）"
            subtitle: "打开/关闭窗口概览时的弹簧动画"

            Controls.TahoeSlider {
                theme: page.theme
                label: "阻尼比（damping-ratio）"
                valueText: page.animValue("overview_open_close", "damping_ratio")
                value: page.dampingFromValue(page.animValue("overview_open_close", "damping_ratio"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("overview_open_close", "damping_ratio", page.dampingToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "刚度（stiffness）"
                valueText: page.animValue("overview_open_close", "stiffness")
                value: page.stiffnessFromValue(page.animValue("overview_open_close", "stiffness"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("overview_open_close", "stiffness", page.stiffnessToValue(r));
                }
            }
            Controls.TahoeSlider {
                theme: page.theme
                label: "阈值（epsilon）"
                valueText: page.animValue("overview_open_close", "epsilon")
                value: page.epsilonFromValue(page.animValue("overview_open_close", "epsilon"))
                enabled: page.ready
                onUserSet: function(r) {
                    if (page.svc)
                        page.svc.setAnimParam("overview_open_close", "epsilon", page.epsilonToValue(r));
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "这些选项写入 niri 的 config.kdl 并在写入后立即热重载，重启 niri 后仍然生效。窗口打开/关闭动画使用自定义着色器，此处不提供修改。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
