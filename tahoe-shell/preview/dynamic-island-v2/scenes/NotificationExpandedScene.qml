import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color textMuted: "#7f8996"
    property color controlFill: "#20ffffff"
    property color accentColor: "#0a84ff"

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: 28
                height: 28
                radius: 7
                color: "#28ffffff"
                Text {
                    anchors.centerIn: parent
                    text: String(root.model.appName || "?").charAt(0)
                    color: root.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            Column {
                width: parent.width - 38
                spacing: 1
                Text {
                    width: parent.width
                    text: String(root.model.appName || "")
                    color: root.textMuted
                    font.pixelSize: 11
                    font.family: "Noto Sans CJK SC"
                    font.letterSpacing: 0
                }
                Text {
                    width: parent.width
                    text: String(root.model.summary || "")
                    color: root.textPrimary
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    font.family: "Noto Sans CJK SC"
                    font.letterSpacing: 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Text {
            width: parent.width
            height: 54
            text: String(root.model.body || "")
            color: root.textSecondary
            font.pixelSize: 12
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 3
        }

        Row {
            spacing: 8
            Repeater {
                model: (root.model && root.model.actions) ? root.model.actions : []
                delegate: Rectangle {
                    required property var modelData
                    width: Math.max(64, actionLabel.implicitWidth + 20)
                    height: 32
                    radius: 10
                    color: root.controlFill
                    border.width: 1
                    border.color: "#24ffffff"

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: String(modelData.label || "")
                        color: root.textPrimary
                        font.pixelSize: 12
                        font.family: "Noto Sans CJK SC"
                        font.letterSpacing: 0
                    }
                }
            }
        }
    }
}
