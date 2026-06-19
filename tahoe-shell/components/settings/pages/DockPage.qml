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
            title: "Dock"
            subtitle: "窗口按钮显示偏好"

            Controls.TahoeListRow {
                theme: page.theme
                label: "窗口标题"
                detail: "空间不足时始终保留阶段 2 的不出屏约束"
                iconCode: "\ue8d0"

                RowLayout {
                    spacing: 7

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "自动"
                        active: page.panel && page.panel.dockTitleMode() === "auto"
                        minimumWidth: Math.max(72, label.length * 8 + 20)
                        onActivated: page.panel.setDockTitleMode("auto")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "仅图标"
                        active: page.panel && page.panel.dockTitleMode() === "icons"
                        minimumWidth: Math.max(72, label.length * 8 + 20)
                        onActivated: page.panel.setDockTitleMode("icons")
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "标题优先"
                        active: page.panel && page.panel.dockTitleMode() === "titles"
                        minimumWidth: Math.max(72, label.length * 8 + 20)
                        onActivated: page.panel.setDockTitleMode("titles")
                    }
                }
            }
        }
    }
}
