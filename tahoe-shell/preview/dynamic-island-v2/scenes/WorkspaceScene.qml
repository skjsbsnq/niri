import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"

    Row {
        anchors.centerIn: parent
        spacing: 10

        Text {
            text: String(root.model.index || "")
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }

        Text {
            text: String(root.model.name || "")
            color: root.textSecondary
            font.pixelSize: 13
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }

        Row {
            spacing: 5
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width: 5
                    height: 5
                    radius: 2.5
                    color: index + 1 === Number(root.model.index) ? root.accentColor : "#40ffffff"
                }
            }
        }
    }
}
