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
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "通知"
            subtitle: "勿扰和通知历史"

            Controls.TahoeListRow {
                theme: page.theme
                label: "勿扰模式"
                detail: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled
                    ? "横幅和提示音已静音"
                    : "通知正常显示"
                iconCode: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled ? "\ue7f6" : "\ue7f4"
                checkable: true
                checked: page.panel && page.panel.notificationsService && page.panel.notificationsService.dndEnabled
                enabled: !!(page.panel && page.panel.notificationsService)
                onToggled: function(checked) {
                    if (page.panel.notificationsService && page.panel.notificationsService.dndEnabled !== checked)
                        page.panel.notificationsService.toggleDnd();
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "通知历史"
                detail: page.panel && page.panel.notificationsService ? page.panel.notificationsService.historyCount + " 项" : "不可用"
                iconCode: "\ue7f4"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "清空"
                    enabled: !!(page.panel && page.panel.notificationsService && page.panel.notificationsService.historyCount > 0)
                    onActivated: page.panel.notificationsService.clearEverything()
                }
            }

        }
    }
}
