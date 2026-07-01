pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme

    readonly property var battery: page.panel && page.panel.batteryService ? page.panel.batteryService : null
    readonly property var controls: page.panel && page.panel.controlsService ? page.panel.controlsService : null
    readonly property var profiles: page.panel && page.panel.powerProfileService ? page.panel.powerProfileService : null
    readonly property var power: page.panel && page.panel.powerService ? page.panel.powerService : null

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function formatSeconds(value) {
        var seconds = Math.max(0, Math.round(Number(value) || 0));
        if (seconds <= 0)
            return "关闭";
        var minutes = Math.round(seconds / 60);
        if (minutes < 60)
            return minutes + " 分钟";
        var hours = Math.floor(minutes / 60);
        var mins = minutes % 60;
        return mins > 0 ? hours + " 小时 " + mins + " 分钟" : hours + " 小时";
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "电池"
            subtitle: "电量和供电状态"

            Controls.TahoeListRow {
                theme: page.theme
                label: page.battery && page.battery.available ? page.battery.roundedPercentage + "%" : "未检测到电池"
                detail: page.battery && page.battery.available
                    ? page.battery.stateText + (page.battery.timeText.length > 0 ? " · " + page.battery.timeText : "")
                    : "台式机、虚拟机或 UPower 不可用"
                iconCode: page.battery && page.battery.charging ? "\ue1a3" : "\ue1a4"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "电源来源"
                detail: page.battery ? page.battery.powerSourceText : "不可用"
                iconCode: "\ue63c"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "电池健康"
                detail: page.battery && page.battery.healthText.length > 0 ? page.battery.healthText : "不可用"
                iconCode: "\ue86c"
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "亮度"
            subtitle: "屏幕背光"

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue518"
                label: "屏幕亮度"
                valueText: page.controls && page.controls.brightnessAvailable
                    ? Math.round(page.controls.brightness * 100) + "%"
                    : "不可用"
                value: page.controls ? page.controls.brightness : 0
                enabled: !!(page.controls && page.controls.brightnessAvailable)
                onUserSet: function(v) {
                    if (page.controls)
                        page.controls.setBrightness(v);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "亮度后端"
                detail: page.controls && page.controls.brightnessAvailable
                    ? "brightnessctl 可用"
                    : (page.controls && page.controls.brightnessErrorText.length > 0 ? page.controls.brightnessErrorText : "未检测到可写背光")
                iconCode: "\ue1ad"
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "电源模式"
            subtitle: page.profiles && page.profiles.available ? page.profiles.labelFor(page.profiles.profile) : "需要 power-profiles-daemon"

            Controls.TahoeListRow {
                theme: page.theme
                label: "模式"
                detail: page.profiles && page.profiles.available ? "当前为 " + page.profiles.labelFor(page.profiles.profile) : "不可用"
                iconCode: "\ue8b2"

                RowLayout {
                    spacing: 7

                    Repeater {
                        model: page.profiles ? page.profiles.profiles : []

                        delegate: Controls.TahoeButton {
                            required property var modelData

                            theme: page.theme
                            label: modelData.label
                            iconCode: modelData.icon
                            active: page.profiles && page.profiles.profile === modelData.id
                            enabled: !!(page.profiles && page.profiles.available && page.profiles.supports(modelData.id) && !page.profiles.updating)
                            onActivated: {
                                if (page.profiles)
                                    page.profiles.setProfile(modelData.id);
                            }
                        }
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "空闲锁定"
            subtitle: "会话空闲后自动锁屏"

            Controls.TahoeListRow {
                theme: page.theme
                label: "空闲锁定"
                detail: page.panel && page.panel.idleLockEnabled
                    ? "空闲 " + page.formatSeconds(page.panel.idleLockTimeoutSeconds) + " 后锁定"
                    : "关闭"
                iconCode: "\ue897"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "立即锁定"
                    enabled: !!page.power
                    onActivated: {
                        if (page.power)
                            page.power.requestAction("lock");
                    }
                }
            }
        }
    }
}
