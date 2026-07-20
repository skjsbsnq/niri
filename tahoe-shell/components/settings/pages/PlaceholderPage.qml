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
                detail: "此分类已预留，完整选项将在后续版本提供。"
                iconCode: page.info.icon
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "相关设置"
                detail: page.info.related && page.info.related.length > 0
                    ? "可先打开已提供的相关页面"
                    : "暂无相关页面"
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
