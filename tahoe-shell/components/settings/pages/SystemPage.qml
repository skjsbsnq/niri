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
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "系统"
            subtitle: "系统健康、启动项和会话信息"

            Controls.TahoeListRow {
                theme: page.theme
                label: "系统健康"
                detail: page.panel && page.panel.systemStatusService
                    ? page.panel.systemStatusService.okCount + " 正常 · "
                        + page.panel.systemStatusService.warnCount + " 注意 · "
                        + page.panel.systemStatusService.missingCount + " 缺失"
                    : "等待检测"
                iconCode: page.panel && page.panel.systemStatusService && page.panel.systemStatusService.missingCount > 0 ? "\ue002" : "\ue86c"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel) {
                            page.panel.openPage("health");
                        }
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "启动项"
                detail: "XDG autostart 和会话备注"
                iconCode: "\ue89e"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("startup");
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "天气"
                detail: page.panel && page.panel.weatherService
                    ? page.panel.weatherService.locationName + " · " + page.panel.weatherService.status
                    : "定位、手动覆盖和温度单位"
                iconCode: "\ue2bd"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("weather");
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "关于"
                detail: "Tahoe Shell、niri、Quickshell 和当前会话"
                iconCode: "\ue88e"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: {
                        if (page.panel)
                            page.panel.openPage("about");
                    }
                }
            }
        }
    }
}
