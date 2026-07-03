pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../SettingsModel.js" as SettingsModel
import "../../../services/StatusTypes.js" as StatusTypes
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme
    property string panelId: ""
    property string modeOverride: ""

    readonly property var info: SettingsModel.resolvedPanel(page.panelId)
    readonly property string capability: page.modeOverride.length > 0
        ? SettingsModel.normalizedCapability(page.modeOverride)
        : String(page.info.capability || "probe")
    readonly property string capabilityLabel: SettingsModel.capabilityLabel(page.capability)
    readonly property string capabilityDetail: SettingsModel.capabilityDetail(page.capability)
    readonly property string capabilityIcon: SettingsModel.capabilityIcon(page.capability)
    readonly property string backend: String(page.info.backend || "")
    readonly property string writeScope: String(page.info.writeScope || "")
    readonly property string externalPanelId: String(page.info.externalPanel || "")
    readonly property bool hasExternalSettings: page.externalPanelId.length > 0
    readonly property var features: page.panel ? page.panel.systemFeaturesService : null
    readonly property int featureRevision: features ? features.revision : 0

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function configuredFeatureIds() {
        return SettingsModel.featureIds(page.panelId);
    }

    function featureRows() {
        var ids = page.configuredFeatureIds();
        var out = [];
        for (var i = 0; i < ids.length; i++) {
            var item = page.features ? page.features.item(ids[i]) : null;
            out.push(item || StatusTypes.unknownStatus(ids[i], ids[i], "尚未检测", ""));
        }
        return out;
    }

    function featureSubtitle() {
        if (page.panelId === "sharing")
            return "远程登录、网络发现、文件共享和媒体共享";
        if (page.panelId === "privacy")
            return "Portal 权限、截图、位置、摄像头和麦克风的后端状态";
        return page.info.subtitle;
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: page.info.title
            subtitle: page.info.subtitle

            Controls.TahoeListRow {
                theme: page.theme
                label: "能力级别"
                detail: page.capabilityLabel + " · " + page.capabilityDetail
                iconCode: page.capabilityIcon
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "后端"
                detail: page.backend.length > 0 ? page.backend : "未声明后端"
                iconCode: "\uea77"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "写入范围"
                detail: page.writeScope.length > 0 ? page.writeScope : "未声明写入范围"
                iconCode: "\ue897"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "探测状态"
                detail: page.features
                    ? "最后检测 " + page.features.lastUpdatedText
                    : "系统功能探测服务不可用"
                iconCode: page.info.icon

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.features && page.features.refreshing ? "刷新中" : "刷新"
                    iconCode: "\ue5d5"
                    enabled: !!page.features && !page.features.refreshing
                    onActivated: {
                        if (page.features)
                            page.features.refresh();
                    }
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "外部设置"
                    iconCode: "\ue89e"
                    visible: page.hasExternalSettings
                    enabled: !!page.features
                    onActivated: {
                        if (page.features)
                            page.features.openExternal("gnome-control-center", [page.externalPanelId], "settings." + page.panelId);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: page.capability === "external" ? "外部后端" : "子项"
            subtitle: page.featureSubtitle()
            visible: page.configuredFeatureIds().length > 0

            Repeater {
                model: ScriptModel {
                    values: page.featureRevision >= 0 ? page.featureRows() : []
                }

                delegate: FeatureRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "健康使用"
            subtitle: "屏幕时间后端未内置；这里只显示 Tahoe 已有会话状态"
            visible: page.panelId === "wellbeing"

            Controls.TahoeListRow {
                theme: page.theme
                label: "空闲锁定"
                detail: page.panel && page.panel.idleLockEnabled
                    ? Math.round(page.panel.idleLockTimeoutSeconds) + " 秒后锁定"
                    : "未启用"
                iconCode: "\ue897"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "勿扰"
                detail: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled
                    ? "已开启"
                    : "关闭"
                iconCode: "\ue7f4"
                checkable: true
                checked: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled
                enabled: !!(page.panel && page.panel.notificationsService)
                onToggled: function(checked) {
                    if (page.panel && page.panel.notificationsService)
                        page.panel.notificationsService.dndEnabled = checked;
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "相关入口"
            subtitle: "跳转到已内置的 Tahoe 设置页"
            visible: page.panelId === "privacy" || page.panelId === "search"

            Controls.TahoeListRow {
                theme: page.theme
                label: page.panelId === "privacy" ? "应用权限" : "应用搜索"
                detail: page.panelId === "privacy"
                    ? "查看 Flatpak/Snap/Portal 权限和存储"
                    : "已安装应用和默认应用搜索"
                iconCode: page.panelId === "privacy" ? "\ue897" : "\ue8b6"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    iconCode: "\ue5cc"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("apps");
                    }
                }
            }
        }
    }

    component FeatureRow: Item {
        id: row

        property var theme
        property var entry
        readonly property string statusText: StatusTypes.availabilityLabel(row.entry)
        readonly property string iconCode: StatusTypes.iconCode(row.entry)

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
        readonly property color danger: theme ? theme.danger : "#ff453a"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property string iconFont: theme ? theme.iconFont : "Material Icons"

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(52, featureContent.implicitHeight + 14)

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

            Text {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                text: row.iconCode
                color: row.textPrimary
                font.family: row.iconFont
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                id: featureContent

                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.title : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.detail : ""
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.impact : ""
                    color: row.textMuted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text.length > 0
                }

                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.action : ""
                    color: row.danger
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: row.statusText
                color: row.textPrimary
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
}
