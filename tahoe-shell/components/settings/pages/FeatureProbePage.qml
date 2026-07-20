pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../SettingsModel.js" as SettingsModel
import "../../../services/StatusTypes.js" as StatusTypes
import "../controls" as Controls
import "../.."

// User-facing shell for non-native settings domains.
// Capability / backend / writeScope stay in SettingsModel for search, registry
// tests, and external-panel routing — they are not rendered as developer notes.
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

    function summaryTitle() {
        if (page.capability === "external")
            return "由系统设置管理";
        if (page.capability === "readonly")
            return "当前可查看状态";
        if (page.capability === "probe")
            return "当前可用情况";
        return page.info.title;
    }

    function summaryDetail() {
        if (page.panelId === "privacy")
            return "权限记录和相关入口可在这里查看；完整控制取决于应用类型。";
        if (page.panelId === "wellbeing")
            return "屏幕时间尚未内置。可使用勿扰和空闲锁定减少打扰。";
        if (page.panelId === "search")
            return "显示搜索索引相关状态。排序和索引策略稍后提供。";
        if (page.panelId === "sharing")
            return "显示远程登录、网络发现和共享相关服务是否可用。";
        if (page.capability === "external")
            return "Tahoe 提供入口和状态说明；详细配置请在系统设置中完成。";
        if (page.capability === "readonly")
            return "本页只展示状态，不会伪装成完整控制面。";
        return "显示相关组件是否可用。需要调整时请使用系统设置。";
    }

    function featureSectionTitle() {
        if (page.capability === "external")
            return "相关组件";
        return "状态";
    }

    function featureSectionSubtitle() {
        if (page.panelId === "sharing")
            return "远程登录、网络发现、文件共享和媒体共享";
        if (page.panelId === "privacy")
            return "截图、位置、摄像头、麦克风等权限相关状态";
        if (page.panelId === "search")
            return "搜索索引服务";
        return page.info.subtitle;
    }

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: page.summaryTitle()
            subtitle: page.summaryDetail()

            Controls.TahoeListRow {
                theme: page.theme
                label: page.info.title
                detail: page.features
                    ? "上次检查 " + page.features.lastUpdatedText
                    : "状态检查不可用"
                iconCode: page.info.icon

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.features && page.features.refreshing ? "检查中" : "检查"
                    iconCode: "\ue5d5"
                    enabled: !!page.features && !page.features.refreshing
                    onActivated: {
                        if (page.features)
                            page.features.refresh();
                    }
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开系统设置"
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
            title: page.featureSectionTitle()
            subtitle: page.featureSectionSubtitle()
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
            title: "已有选项"
            subtitle: "可直接调整的会话偏好"
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
            title: "相关设置"
            subtitle: "跳转到已提供的 Tahoe 设置"
            visible: page.panelId === "privacy" || page.panelId === "search"

            Controls.TahoeListRow {
                theme: page.theme
                label: page.panelId === "privacy" ? "应用权限" : "应用"
                detail: page.panelId === "privacy"
                    ? "查看应用权限记录与可管理范围"
                    : "已安装应用和默认应用"
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

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(44, featureContent.implicitHeight + 12)

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 0
        }

        // Inset separator (same list idiom as TahoeListRow).
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 1
            color: theme && theme.darkMode !== undefined
                ? (theme.darkMode ? "#1affffff" : "#14000000")
                : "#14000000"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            TahoeSymbol {
                Layout.preferredWidth: 22
                Layout.alignment: Qt.AlignVCenter
                name: row.iconCode
                color: row.textPrimary
                size: 18
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
