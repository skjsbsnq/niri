pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../SettingsModel.js" as SettingsModel
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme
    property string panelId: ""

    readonly property var info: SettingsModel.resolvedPanel(page.panelId)
    readonly property var features: page.panel ? page.panel.systemFeaturesService : null
    readonly property int featureRevision: features ? features.revision : 0

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function featureIds() {
        if (page.panelId === "search")
            return ["search-index"];
        if (page.panelId === "online-accounts")
            return ["online-accounts", "gnome-control-center"];
        if (page.panelId === "sharing")
            return ["remote-login", "discovery", "file-sharing", "media-sharing"];
        if (page.panelId === "privacy")
            return ["portal-permissions", "desktop-portal"];
        if (page.panelId === "color")
            return ["color"];
        if (page.panelId === "printers")
            return ["printers"];
        if (page.panelId === "accessibility")
            return ["accessibility"];
        return [];
    }

    function featureRows() {
        var ids = page.featureIds();
        var out = [];
        for (var i = 0; i < ids.length; i++) {
            var item = page.features ? page.features.item(ids[i]) : null;
            out.push(item || {
                "id": ids[i],
                "state": "unknown",
                "title": ids[i],
                "detail": "尚未检测"
            });
        }
        return out;
    }

    function stateIcon(state) {
        if (state === "ok")
            return "\ue5ca";
        if (state === "warn")
            return "\ue002";
        if (state === "missing")
            return "\ue14b";
        return "\ue8b8";
    }

    function stateText(state) {
        if (state === "ok")
            return "可用";
        if (state === "warn")
            return "部分可用";
        if (state === "missing")
            return "缺失";
        return "未知";
    }

    function externalPanel() {
        if (page.panelId === "accessibility")
            return "universal-access";
        if (page.panelId === "privacy")
            return "privacy";
        return page.panelId;
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
                label: "状态"
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
                    visible: page.panelId !== "wellbeing"
                    enabled: !!page.features
                    onActivated: {
                        if (page.features)
                            page.features.openExternal("gnome-control-center", [page.externalPanel()], "settings." + page.panelId);
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "子项"
            subtitle: page.panelId === "sharing"
                ? "远程登录、网络发现、文件共享和媒体共享"
                : page.panelId === "privacy"
                    ? "Portal 权限、截图、位置、摄像头和麦克风的后端状态"
                    : page.info.subtitle
            visible: page.panelId !== "wellbeing"

            Repeater {
                model: ScriptModel {
                    values: page.featureRevision >= 0 ? page.featureRows() : []
                }

                delegate: FeatureRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    statusText: page.stateText(modelData.state)
                    iconCode: page.stateIcon(modelData.state)
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "健康使用"
            subtitle: "屏幕时间后端未内置；先提供 Tahoe 可控制的休息相关开关"
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
        property string statusText: ""
        property string iconCode: ""

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property string iconFont: theme ? theme.iconFont : "Material Icons"

        Layout.fillWidth: true
        Layout.preferredHeight: 52

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
