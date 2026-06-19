pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
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

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            radius: 18
            color: "#2affffff"
            border.color: "#42ffffff"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Image {
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 54
                    source: Quickshell.shellPath("assets/icons/niri-icon-smol.png")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: "niri Tahoe Desktop"
                        color: page.theme ? page.theme.textPrimary : "#1d1d1f"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "当前 shell、子模块、运行时、GPU 和会话信息"
                        color: page.theme ? page.theme.textSecondary : "#721d1d1f"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }
        }

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
