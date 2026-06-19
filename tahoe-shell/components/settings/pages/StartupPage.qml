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
            title: "启动项"
            subtitle: "XDG autostart 管理入口"

            Controls.TahoeListRow {
                theme: page.theme
                label: "自动启动文件夹"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.homeDir.length > 0
                    ? page.panel.settingsService.homeDir + "/.config/autostart"
                    : "不可用"
                iconCode: "\ue89e"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    enabled: !!(page.panel && page.panel.settingsService)
                    onActivated: page.panel.settingsService.openAutostartFolder()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "启动项备注"
                detail: page.panel && page.panel.settingsService && page.panel.settingsService.startupNote.length > 0
                    ? page.panel.settingsService.startupNote
                    : "未设置"
                iconCode: "\ue873"

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 420

                    Controls.TahoeTextField {
                        id: startupNoteInput
                        theme: page.theme
                        text: page.panel && page.panel.settingsService ? page.panel.settingsService.startupNote : ""
                        onEditingFinished: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setStartupNote(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setStartupNote(startupNoteInput.text)
                    }
                }
            }
        }
    }
}
