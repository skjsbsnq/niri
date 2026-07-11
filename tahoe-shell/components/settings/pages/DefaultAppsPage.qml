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
    property var appsSettingsService
    property string expandedCategoryId: ""

    readonly property int serviceRevision: appsSettingsService ? appsSettingsService.revision : 0
    readonly property var rows: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.defaultRows : []
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
    readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

    signal backRequested()

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: settingsColumn

        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "默认应用"
            subtitle: page.appsSettingsService
                ? page.appsSettingsService.defaultsDetail
                : "应用设置服务不可用"

            Controls.TahoeListRow {
                theme: page.theme
                label: "默认应用"
                detail: page.appsSettingsService && page.appsSettingsService.defaultsRefreshing
                    ? "正在读取 xdg-mime"
                    : (page.appsSettingsService ? page.appsSettingsService.defaultsDetail : "服务不可用")
                iconCode: "\ue5c3"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "返回"
                    iconCode: "\ue5cb"
                    onActivated: page.backRequested()
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: page.appsSettingsService && page.appsSettingsService.defaultsRefreshing ? "刷新中" : "刷新"
                    iconCode: "\ue5d5"
                    enabled: !!page.appsSettingsService && !page.appsSettingsService.defaultsRefreshing
                    onActivated: page.appsSettingsService.refreshDefaults()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "写入状态"
                detail: page.appsSettingsService && page.appsSettingsService.lastActionText.length > 0
                    ? page.appsSettingsService.lastActionText
                    : "尚未修改"
                iconCode: "\ue86c"
                visible: !!page.appsSettingsService
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "类别"
            subtitle: "Web、Mail、Calendar、Music、Video、Photos、Files 和 Removable Media"

            Controls.TahoeListRow {
                theme: page.theme
                label: "无数据"
                detail: page.appsSettingsService
                    ? page.appsSettingsService.defaultsDetail
                    : "应用设置服务不可用"
                iconCode: "\ue002"
                visible: page.rows.length === 0
            }

            Repeater {
                model: ScriptModel {
                    values: page.rows
                }

                delegate: DefaultCategoryRow {
                    required property var modelData

                    Layout.fillWidth: true
                    theme: page.theme
                    entry: modelData
                    appsSettingsService: page.appsSettingsService
                    expanded: page.expandedCategoryId === modelData.id
                    setting: page.appsSettingsService
                        && page.appsSettingsService.settingDefault
                        && page.appsSettingsService.settingCategoryId === modelData.id
                    onToggleExpanded: function(id) {
                        page.expandedCategoryId = page.expandedCategoryId === id ? "" : id;
                    }
                    onSetDefaultRequested: function(categoryId, desktopId) {
                        if (page.appsSettingsService)
                            page.appsSettingsService.setDefaultCategory(categoryId, desktopId);
                    }
                }
            }
        }
    }

    component DefaultCategoryRow: Item {
        id: row

        property var theme
        property var entry
        property var appsSettingsService
        property bool expanded: false
        property bool setting: false

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

        signal toggleExpanded(string id)
        signal setDefaultRequested(string categoryId, string desktopId)

        Layout.fillWidth: true
        Layout.preferredHeight: frame.implicitHeight

        function currentDesktopId() {
            return row.entry ? String(row.entry.currentDesktopId || "") : "";
        }

        function currentLabel() {
            if (!row.appsSettingsService)
                return "未知";
            return row.appsSettingsService.labelForDesktopId(row.currentDesktopId());
        }

        function detailText() {
            if (!row.entry)
                return "";
            if (row.currentDesktopId().length === 0)
                return "未设置";
            var detail = row.currentDesktopId();
            if (!row.entry.consistent)
                detail += " · " + row.entry.matchedMimeCount + "/" + row.entry.mimeCount + " MIME";
            return detail;
        }

        Rectangle {
            id: frame

            width: parent.width
            implicitHeight: content.implicitHeight + 14
            radius: 8
            color: row.expanded ? row.rowFillHover : row.rowFill
            border.color: row.rowStroke
            border.width: 1

            ColumnLayout {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    TahoeSymbol {
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        name: row.entry ? row.entry.icon : "\ue5c3"
                        color: row.textPrimary
                        size: 18
                    }

                    Image {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        source: row.appsSettingsService ? row.appsSettingsService.iconForDesktopId(row.currentDesktopId()) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        sourceSize.width: 80
                        sourceSize.height: 80
                        asynchronous: true
                        visible: row.currentDesktopId().length > 0
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
                            text: row.currentLabel() + " · " + row.detailText()
                            color: row.textSecondary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Controls.TahoeButton {
                        theme: row.theme
                        label: row.setting ? "写入中" : (row.expanded ? "收起" : "选择")
                        iconCode: row.expanded ? "\ue5ce" : "\ue5cf"
                        enabled: !row.setting
                        onActivated: row.toggleExpanded(row.entry ? row.entry.id : "")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    visible: row.expanded

                    Controls.TahoeListRow {
                        theme: row.theme
                        label: "无候选应用"
                        detail: "没有找到声明支持这些 MIME type 的桌面应用"
                        iconCode: "\ue8b6"
                        visible: row.entry && row.entry.candidates && row.entry.candidates.length === 0
                    }

                    Repeater {
                        model: ScriptModel {
                            values: row.entry && row.entry.candidates ? row.entry.candidates : []
                        }

                        delegate: CandidateRow {
                            required property var modelData

                            Layout.fillWidth: true
                            theme: row.theme
                            candidate: modelData
                            current: modelData.desktopId === row.currentDesktopId()
                            appsSettingsService: row.appsSettingsService
                            onSetRequested: function(desktopId) {
                                row.setDefaultRequested(row.entry ? row.entry.id : "", desktopId);
                            }
                        }
                    }
                }
            }
        }
    }

    component CandidateRow: Item {
        id: row

        property var theme
        property var candidate
        property bool current: false
        property var appsSettingsService

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"

        signal setRequested(string desktopId)

        Layout.fillWidth: true
        Layout.preferredHeight: 48

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

            Image {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                source: row.appsSettingsService && row.candidate ? row.appsSettingsService.iconForDesktopId(row.candidate.desktopId) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                sourceSize.width: 80
                sourceSize.height: 80
                asynchronous: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.appsSettingsService && row.candidate
                        ? row.appsSettingsService.labelForDesktopId(row.candidate.desktopId)
                        : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.candidate
                        ? row.candidate.desktopId + " · " + row.candidate.supportedMimeCount + " MIME"
                        : ""
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Controls.TahoeButton {
                theme: row.theme
                label: row.current ? "已选择" : "设为默认"
                iconCode: row.current ? "\ue5ca" : "\ue86c"
                active: row.current
                enabled: !row.current
                onActivated: {
                    if (row.candidate)
                        row.setRequested(row.candidate.desktopId);
                }
            }
        }
    }
}
