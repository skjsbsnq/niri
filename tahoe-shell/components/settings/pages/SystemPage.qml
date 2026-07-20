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

    function open(id) {
        if (page.panel)
            page.panel.openPage(id);
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 10

        Controls.TahoeSection {
            theme: page.theme
            title: "系统"
            subtitle: "会话状态、启动项和关于本机"

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
                    onActivated: page.open("health")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "启动项"
                detail: "登录时自动启动的应用"
                iconCode: "\ue89e"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("startup")
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
                    onActivated: page.open("about")
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "更多"
            subtitle: "尚未内置完整界面；可查看状态或打开系统设置"

            Controls.TahoeListRow {
                theme: page.theme
                label: "在线账号"
                detail: "账号登录与同步"
                iconCode: "\ue7fd"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("online-accounts")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "共享"
                detail: "远程访问与文件共享状态"
                iconCode: "\ue80d"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("sharing")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "色彩管理"
                detail: "显示器色彩配置"
                iconCode: "\ue3b7"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("color")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "打印机"
                detail: "打印设备与队列"
                iconCode: "\ue8ad"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("printers")
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "辅助功能"
                detail: "无障碍访问选项"
                iconCode: "\ue84e"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    onActivated: page.open("accessibility")
                }
            }
        }
    }
}
