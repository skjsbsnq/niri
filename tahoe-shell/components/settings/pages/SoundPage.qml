pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../controls" as Controls
import "../.."

Flickable {
    id: page

    property var panel
    property var theme

    readonly property var controlsService: page.panel ? page.panel.controlsService : null
    readonly property var soundService: page.panel ? page.panel.soundService : null
    readonly property int soundRevision: soundService ? soundService.revision : 0
    readonly property var outputs: soundRevision >= 0 && soundService ? soundService.outputDevices : []
    readonly property var inputs: soundRevision >= 0 && soundService ? soundService.inputDevices : []

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function percent(value) {
        return Math.round(Math.max(0, Math.min(1, Number(value) || 0)) * 100);
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "声音"
            subtitle: page.controlsService && page.controlsService.audioReady
                ? "默认输出可用"
                : "PipeWire 默认输出不可用"

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue050"
                label: "输出音量"
                valueText: page.controlsService ? page.percent(page.controlsService.volume) + "%" : "-"
                value: page.controlsService ? page.controlsService.volume : 0
                enabled: !!(page.controlsService && page.controlsService.audioReady)
                onUserSet: function(value) {
                    if (page.controlsService)
                        page.controlsService.setVolume(value);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "静音"
                detail: page.controlsService && page.controlsService.muted ? "已静音" : "声音输出开启"
                iconCode: "\ue04f"
                checkable: true
                checked: page.controlsService && page.controlsService.muted
                enabled: !!(page.controlsService && page.controlsService.audioReady)
                onToggled: {
                    if (page.controlsService)
                        page.controlsService.toggleMute();
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "事件音"
                detail: page.soundService && page.soundService.eventSoundsMuted ? "已关闭" : "使用 freedesktop 声音主题"
                iconCode: "\ue91f"
                checkable: true
                checked: !(page.soundService && page.soundService.eventSoundsMuted)
                enabled: !!page.soundService
                onToggled: function(checked) {
                    if (page.soundService)
                        page.soundService.setEventSoundsMuted(!checked);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "输出设备"
            subtitle: page.soundService ? page.soundService.deviceDetail : "声音服务不可用"

            Controls.TahoeListRow {
                theme: page.theme
                label: "设备"
                detail: page.soundService && page.soundService.refreshingDevices ? "正在刷新" : page.outputs.length + " 个输出设备"
                iconCode: "\ue5d5"

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.soundService && page.soundService.refreshingDevices ? "刷新中" : "刷新"
                    iconCode: "\ue5d5"
                    enabled: !!page.soundService && !page.soundService.refreshingDevices
                    onActivated: {
                        if (page.soundService)
                            page.soundService.refreshDevices();
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "无输出设备"
                detail: page.soundService ? page.soundService.deviceDetail : "声音服务不可用"
                iconCode: "\ue002"
                visible: page.outputs.length === 0
            }

            Repeater {
                model: ScriptModel { values: page.outputs }

                delegate: AudioDeviceRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    buttonLabel: "设为输出"
                    onSetRequested: function(entry) {
                        if (page.soundService)
                            page.soundService.setDefaultOutput(entry);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "输入设备"
            subtitle: "麦克风和采集源"

            Controls.TahoeListRow {
                theme: page.theme
                label: "无输入设备"
                detail: page.soundService ? page.soundService.deviceDetail : "声音服务不可用"
                iconCode: "\ue002"
                visible: page.inputs.length === 0
            }

            Repeater {
                model: ScriptModel { values: page.inputs }

                delegate: AudioDeviceRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    buttonLabel: "设为输入"
                    onSetRequested: function(entry) {
                        if (page.soundService)
                            page.soundService.setDefaultInput(entry);
                    }
                }
            }
        }
    }

    component AudioDeviceRow: Item {
        id: row

        property var theme
        property var entry
        property string buttonLabel: ""

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"

        signal setRequested(var entry)

        Layout.fillWidth: true
        Layout.preferredHeight: 54

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: row.rowFill
            border.color: row.rowStroke
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            TahoeSymbol {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                name: row.entry && row.entry.type === "source" ? "\ue029" : "\ue050"
                color: row.textPrimary
                size: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.description : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.name + " · " + row.entry.state : ""
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Controls.TahoeButton {
                theme: row.theme
                label: row.buttonLabel
                iconCode: "\ue5ca"
                onActivated: row.setRequested(row.entry)
            }
        }
    }
}
