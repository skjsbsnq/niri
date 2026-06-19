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
            title: "截图"
            subtitle: "保存目录、复制和通知动作"

            Controls.TahoeListRow {
                theme: page.theme
                label: "保存目录"
                detail: page.panel ? page.panel.screenshotPathText() : ""
                iconCode: "\ue2c7"

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 420

                    Controls.TahoeTextField {
                        id: screenshotDirectoryInput
                        theme: page.theme
                        text: page.panel && page.panel.settingsService ? page.panel.settingsService.screenshotDirectory : ""
                        onEditingFinished: {
                            if (page.panel.settingsService)
                                page.panel.settingsService.setScreenshotDirectory(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.setScreenshotDirectory(screenshotDirectoryInput.text)
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "默认"
                        enabled: !!(page.panel && page.panel.settingsService)
                        onActivated: page.panel.settingsService.resetScreenshotDirectory()
                    }
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "截图后复制"
                detail: "保存 PNG 后写入 Wayland 剪贴板"
                iconCode: "\ue14f"
                checkable: true
                checked: page.panel && page.panel.settingsService && page.panel.settingsService.screenshotCopyToClipboard
                enabled: !!(page.panel && page.panel.settingsService)
                onToggled: function(checked) {
                    if (page.panel.settingsService)
                        page.panel.settingsService.setScreenshotCopyToClipboard(checked);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "保存通知动作"
                detail: "通知里显示标注、打开、复制动作"
                iconCode: "\ue3b0"
                checkable: true
                checked: page.panel && page.panel.settingsService && page.panel.settingsService.screenshotOfferActions
                enabled: !!(page.panel && page.panel.settingsService)
                onToggled: function(checked) {
                    if (page.panel.settingsService)
                        page.panel.settingsService.setScreenshotOfferActions(checked);
                }
            }
        }
    }
}
