import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color trackColor: "#30ffffff"

    readonly property bool playing: !!(model && model.playing)
    readonly property real progress: Math.max(0, Math.min(1, Number(model && model.progress) || 0))

    Item {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 6
        anchors.bottomMargin: 6

        Rectangle {
            id: art
            width: 22
            height: 22
            radius: 6
            color: "#28ffffff"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: "♪"
                color: root.textSecondary
                font.pixelSize: 12
            }
        }

        Text {
            id: title
            anchors.left: art.right
            anchors.leftMargin: 8
            anchors.right: status.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.model.title || "")
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            id: status
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            horizontalAlignment: Text.AlignHCenter
            text: root.playing ? "▶" : "❚❚"
            color: root.textSecondary
            font.pixelSize: 11
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            height: 2
            radius: 1
            color: root.trackColor

            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                radius: 1
                color: root.accentColor
            }
        }
    }
}
