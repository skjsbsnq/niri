import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"

    Row {
        anchors.centerIn: parent
        spacing: 9

        Text {
            text: String(root.model.weekday || "")
            color: root.textSecondary
            font.pixelSize: 13
            font.weight: Font.Normal
            font.family: "Noto Sans CJK SC"
        }

        Text {
            text: String(root.model.time || "")
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }
    }
}
