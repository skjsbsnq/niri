pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls
import "../.."

// S5.4: keyboard shortcuts viewer (read-only). niri's `binds {}` is a
// replace-on-conflict authoritative block — once present it is the whole set —
// so the GUI never writes it (guardrail 441b637: do not override the MRU /
// task-switcher binds, which run over IPC). This page lists every bind with
// its combo and first action, flags the task-switcher IPC binds as protected,
// and offers to open config.kdl in the user's editor for manual editing.
Flickable {
    id: page

    property var panel
    property var theme

    // Filled post-write to dodge the toolchain's \u escape handling.
    readonly property string lockGlyph: "\ue897"

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded
    readonly property var binds: page.svc && page.svc.bindsList ? page.svc.bindsList : []

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color danger: theme ? theme.danger : "#ff453a"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"

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
                ? page.danger
                : page.textSecondary
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "键盘快捷键"
            subtitle: "niri binds（只读查看）"

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: "niri 的 binds 是 replace-on-conflict 权威全集：一旦存在即覆盖全部默认键位。此处只读查看，改键请直接编辑 config.kdl。"
                        color: page.textSecondary
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "标注「受保护」的项是 Tahoe 任务切换/概览的 IPC binds（Mod+Ctrl+Tab 等），走 Quickshell IPC 而非 niri binds，请勿改动（441b637）。"
                        color: page.textSecondary
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                Controls.TahoeButton {
                    theme: page.theme
                    iconCode: "\ue25f"
                    label: "在编辑器打开"
                    enabled: page.ready
                    onActivated: {
                        if (page.svc)
                            page.svc.openConfigInEditor();
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "全部快捷键"
            subtitle: page.binds.length + " 条"

            ColumnLayout {
                id: bindsList
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: page.binds

                    delegate: Rectangle {
                        id: bindRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 8
                        color: bindRow.modelData.protected ? "#18ff9f0a" : page.rowFill
                        border.color: page.rowStroke
                        border.width: 1
                        opacity: bindRow.modelData.protected ? 0.85 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                Layout.preferredWidth: 180
                                text: bindRow.modelData.combo
                                color: page.textPrimary
                                font.family: "Monospace"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: bindRow.modelData.action
                                color: page.textSecondary
                                font.family: "Monospace"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            TahoeSymbol {
                                name: page.lockGlyph
                                color: page.danger
                                size: 14
                                visible: bindRow.modelData.protected
                            }

                            Text {
                                text: "受保护"
                                visible: bindRow.modelData.protected
                                color: page.danger
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: page.binds.length === 0
                    text: "未读取到 binds。"
                    color: page.textSecondary
                    font.pixelSize: 11
                }
            }
        }
    }
}
