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
            title: "外观"
            subtitle: "深浅色、夜览和色温"

            Controls.TahoeListRow {
                theme: page.theme
                label: "深色模式"
                detail: page.panel && page.panel.appearanceService && page.panel.appearanceService.darkMode ? "当前偏好深色" : "当前偏好浅色"
                iconCode: "\ue51c"
                checkable: true
                checked: page.panel && page.panel.appearanceService && page.panel.appearanceService.darkMode
                enabled: !!(page.panel && page.panel.appearanceService)
                onToggled: function(checked) {
                    if (page.panel.appearanceService)
                        page.panel.appearanceService.setDarkMode(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "夜览"
                detail: page.panel && page.panel.appearanceService && page.panel.appearanceService.nightMode
                    ? "色温 " + page.panel.appearanceService.colorTemperature + "K"
                    : "关闭"
                iconCode: "\ue3a9"
                checkable: true
                checked: page.panel && page.panel.appearanceService && page.panel.appearanceService.nightMode
                enabled: !!(page.panel && page.panel.appearanceService)
                onToggled: function(checked) {
                    if (page.panel.appearanceService)
                        page.panel.appearanceService.setNightMode(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "夜览色温"
                detail: page.panel && page.panel.appearanceService ? page.panel.appearanceService.colorTemperature + "K" : "不可用"
                iconCode: "\ueb37"

                RowLayout {
                    spacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "-250"
                        enabled: !!(page.panel && page.panel.appearanceService)
                        onActivated: page.panel.appearanceService.setColorTemperature(page.panel.appearanceService.colorTemperature - 250)
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "+250"
                        enabled: !!(page.panel && page.panel.appearanceService)
                        onActivated: page.panel.appearanceService.setColorTemperature(page.panel.appearanceService.colorTemperature + 250)
                    }
                }
            }
        }
    }
}
