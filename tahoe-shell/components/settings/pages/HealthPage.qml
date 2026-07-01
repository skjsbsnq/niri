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

        Controls.TahoeSection {
            Layout.fillWidth: true
            theme: page.theme
            title: "摘要"
            subtitle: page.panel && page.panel.systemStatusService ? "最后检测 " + page.panel.systemStatusService.lastUpdatedText : "系统状态检测"

            Controls.TahoeListRow {
                theme: page.theme
                label: "正常"
                detail: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.okCount + " 项" : "0 项"
                iconCode: "\ue86c"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "注意"
                detail: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.warnCount + " 项" : "0 项"
                iconCode: "\ue002"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "缺失"
                detail: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.missingCount + " 项" : "0 项"
                iconCode: "\ue14c"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "检测状态"
                detail: page.panel && page.panel.systemStatusService && page.panel.systemStatusService.refreshing ? "检测中" : "已刷新"
                iconCode: "\ue5d5"
            }
        }

        Text {
            Layout.fillWidth: true
            text: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.lastError : ""
            color: page.theme ? page.theme.danger : "#ff453a"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            visible: text.length > 0
            wrapMode: Text.WordWrap
        }

        Controls.TahoeSection {
            Layout.fillWidth: true
            theme: page.theme
            title: "诊断项"
            subtitle: "依赖项、服务和 Tahoe 会话状态"

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
}
