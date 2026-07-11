pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../controls" as Controls
import "../.."

Item {
    id: page

    property var panel
    property var theme
    property var appsSettingsService
    property string query: ""
    property string subpage: "list"
    property var detailApp: null

    readonly property int serviceRevision: appsSettingsService ? appsSettingsService.revision : 0
    readonly property var filteredApps: serviceRevision >= 0 && appsSettingsService ? appsSettingsService.filteredApps(query) : []
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
    readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
    readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"
    readonly property color fieldFill: theme ? theme.fieldFill : "#3fffffff"
    readonly property color fieldStroke: theme ? theme.fieldStroke : "#4cffffff"
    readonly property color fieldStrokeFocus: theme ? theme.fieldStrokeFocus : "#007ff7"
    readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

    Layout.fillWidth: true
    Layout.fillHeight: true

    function subpageIndex() {
        if (page.subpage === "defaults")
            return 1;
        if (page.subpage === "detail")
            return 2;
        return 0;
    }

    function openDetails(app) {
        page.detailApp = app;
        if (page.appsSettingsService)
            page.appsSettingsService.selectApp(app);
        page.subpage = "detail";
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: page.subpageIndex()

        Flickable {
            id: listPage

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: listColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: listColumn

                width: parent.width
                spacing: 10

                Controls.TahoeSection {
                    theme: page.theme
                    title: "应用"
                    subtitle: page.appsSettingsService
                        ? page.appsSettingsService.applicationCount + " 个可启动应用"
                        : "应用设置服务不可用"

                    Controls.TahoeListRow {
                        theme: page.theme
                        label: "默认应用"
                        detail: page.appsSettingsService
                            ? page.appsSettingsService.defaultsDetail
                            : "默认应用服务不可用"
                        iconCode: "\ue5c3"

                        Controls.TahoeButton {
                            theme: page.theme
                            label: "打开"
                            iconCode: "\ue5cc"
                            enabled: !!page.appsSettingsService
                            onActivated: page.subpage = "defaults"
                        }
                    }

                    Controls.TahoeListRow {
                        theme: page.theme
                        label: "搜索"
                        detail: page.query.length > 0
                            ? page.filteredApps.length + " 个匹配"
                            : "按名称、分类、关键词和命令过滤"
                        iconCode: "\ue8b6"

                        SearchField {
                            theme: page.theme
                            query: page.query
                            onQueryChangedByUser: function(value) {
                                page.query = value;
                            }
                        }
                    }
                }

                Controls.TahoeSection {
                    theme: page.theme
                    title: "应用列表"
                    subtitle: page.query.length > 0
                        ? page.filteredApps.length + " 个匹配"
                        : "已安装的可启动桌面应用"

                    Controls.TahoeListRow {
                        theme: page.theme
                        label: "无结果"
                        detail: "没有匹配的应用"
                        iconCode: "\ue8b6"
                        visible: page.filteredApps.length === 0
                    }

                    Repeater {
                        model: ScriptModel {
                            values: page.filteredApps
                        }

                        delegate: AppRow {
                            required property var modelData

                            Layout.fillWidth: true
                            theme: page.theme
                            app: modelData
                            appsSettingsService: page.appsSettingsService
                            onOpenRequested: function(app) {
                                if (page.appsSettingsService)
                                    page.appsSettingsService.launchApp(app);
                            }
                            onDetailsRequested: function(app) {
                                page.openDetails(app);
                            }
                        }
                    }
                }
            }
        }

        DefaultAppsPage {
            panel: page.panel
            theme: page.theme
            appsSettingsService: page.appsSettingsService
            onBackRequested: page.subpage = "list"
        }

        AppPermissionsPage {
            panel: page.panel
            theme: page.theme
            app: page.detailApp
            appsSettingsService: page.appsSettingsService
            onBackRequested: page.subpage = "list"
        }
    }

    component SearchField: Rectangle {
        id: search

        property var theme
        property string query: ""

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textMuted: theme ? theme.textMuted : "#5f6870"
        readonly property color fieldFill: theme ? theme.fieldFill : "#3fffffff"
        readonly property color fieldStroke: theme ? theme.fieldStroke : "#4cffffff"
        readonly property color fieldStrokeFocus: theme ? theme.fieldStrokeFocus : "#007ff7"
        readonly property color accentBlue: theme ? theme.accentBlue : "#007ff7"

        signal queryChangedByUser(string value)

        Layout.preferredWidth: 260
        Layout.preferredHeight: 30
        radius: 8
        color: search.fieldFill
        border.color: input.activeFocus ? search.fieldStrokeFocus : search.fieldStroke
        border.width: input.activeFocus ? 2 : 1

        TahoeSymbol {
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            name: "\ue8b6"
            color: search.textMuted
            size: 15
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 32
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "搜索应用"
            color: search.textMuted
            font.pixelSize: 12
            visible: input.text.length === 0
            elide: Text.ElideRight
        }

        TextInput {
            id: input

            anchors.left: parent.left
            anchors.leftMargin: 32
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            text: search.query
            color: search.textPrimary
            selectionColor: search.accentBlue
            selectedTextColor: "#ffffff"
            font.pixelSize: 12
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            onTextChanged: search.queryChangedByUser(text)
            Keys.onEscapePressed: {
                text = "";
                search.queryChangedByUser("");
            }
        }
    }

    component AppRow: Item {
        id: row

        property var theme
        property var app
        property var appsSettingsService

        readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
        readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
        readonly property color rowFill: theme ? theme.rowFill : "#66ffffff"
        readonly property color rowFillHover: theme ? theme.rowFillHover : "#86ffffff"
        readonly property color rowStroke: theme ? theme.rowStroke : "#72ffffff"

        signal openRequested(var app)
        signal detailsRequested(var app)

        Layout.fillWidth: true
        Layout.preferredHeight: 58

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: rowMouse.containsMouse ? row.rowFillHover : row.rowFill
            border.color: row.rowStroke
            border.width: 1
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Image {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                source: row.appsSettingsService ? row.appsSettingsService.iconForApp(row.app) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                sourceSize.width: 96
                sourceSize.height: 96
                asynchronous: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.appsSettingsService ? row.appsSettingsService.appLabel(row.app) : ""
                    color: row.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.appsSettingsService ? row.appsSettingsService.appGenericName(row.app) : ""
                    color: row.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Controls.TahoeButton {
                theme: row.theme
                label: "打开"
                iconCode: "\ue89e"
                onActivated: row.openRequested(row.app)
            }

            Controls.TahoeButton {
                theme: row.theme
                label: "详情"
                iconCode: "\ue88e"
                onActivated: row.detailsRequested(row.app)
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }
}
