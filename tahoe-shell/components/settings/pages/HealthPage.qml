pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: healthColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: healthColumn
        width: parent.width
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 74
            radius: 18
            color: "#2affffff"
            border.color: "#42ffffff"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Controls.TahoeHealthCounter {
                    theme: page.theme
                    label: "正常"
                    value: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.okCount : 0
                    colorValue: "#34c759"
                }

                Controls.TahoeHealthCounter {
                    theme: page.theme
                    label: "注意"
                    value: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.warnCount : 0
                    colorValue: "#ff9f0a"
                }

                Controls.TahoeHealthCounter {
                    theme: page.theme
                    label: "缺失"
                    value: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.missingCount : 0
                    colorValue: "#ff453a"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: page.panel && page.panel.systemStatusService && page.panel.systemStatusService.refreshing ? "检测中" : "已刷新"
                    color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.lastError : ""
            color: "#ccff453a"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            visible: text.length > 0
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.statusItems : []

            delegate: Controls.TahoeStatusRow {
                required property var modelData
                theme: page.theme
                item: modelData
            }
        }
    }
}
