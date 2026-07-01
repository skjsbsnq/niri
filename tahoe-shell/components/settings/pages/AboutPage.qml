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
    contentHeight: aboutColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: aboutColumn
        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            Layout.fillWidth: true
            theme: page.theme
            title: "关于"
            subtitle: "当前 shell、子模块、运行时、GPU 和会话信息"

            Repeater {
                model: page.panel && page.panel.systemStatusService ? page.panel.systemStatusService.aboutItems : []

                delegate: Controls.TahoeAboutRow {
                    required property var modelData
                    theme: page.theme
                    item: modelData
                }
            }
        }
    }
}
