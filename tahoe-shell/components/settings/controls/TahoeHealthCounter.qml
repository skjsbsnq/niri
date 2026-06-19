pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: counter

    property var theme
    property string label: ""
    property int value: 0
    property color colorValue: "#2c9cf2"

    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"

    Layout.preferredWidth: 92
    Layout.fillHeight: true

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 2

        Text {
            text: String(counter.value)
            color: counter.colorValue
            font.pixelSize: 22
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: counter.label
            color: counter.textSecondary
            font.pixelSize: 11
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
