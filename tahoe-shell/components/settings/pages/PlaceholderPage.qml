pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../SettingsModel.js" as SettingsModel
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme
    property string panelId: ""

    readonly property var info: SettingsModel.resolvedPanel(page.panelId)

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
            title: page.info.title
            subtitle: page.info.subtitle

            Controls.TahoeListRow {
                theme: page.theme
                label: "状态"
                detail: page.info.statusBadge && page.info.statusBadge.length > 0
                    ? "已纳入设置中心导航；功能实现排在 " + page.info.statusBadge
                    : "已纳入设置中心导航"
                iconCode: page.info.icon
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "范围"
                detail: "已保留在 GNOME 型信息架构中；后续阶段会接入完整后端。"
                iconCode: "\ue8b8"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "相关入口"
                detail: page.info.related && page.info.related.length > 0 ? "可先打开现有 Tahoe 页面" : "后续阶段会补齐内置功能页"
                iconCode: "\ue89e"
                visible: true

                RowLayout {
                    spacing: 7
                    visible: !!(page.info.related && page.info.related.length > 0)

                    Repeater {
                        model: page.info.related || []

                        delegate: Controls.TahoeButton {
                            required property var modelData

                            theme: page.theme
                            label: modelData.title
                            onActivated: {
                                if (page.panel)
                                    page.panel.selectedPage = modelData.id;
                            }
                        }
                    }
                }
            }
        }
    }
}
