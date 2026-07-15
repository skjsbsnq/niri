import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color trackColor: "#30ffffff"
    property color controlFill: "#20ffffff"

    readonly property bool expanded: String(model && model.kind) === "timer_expanded"
    readonly property real progress: Math.max(0, Math.min(1, Number(model && model.progress) || 0))

    // Compact
    Row {
        visible: !root.expanded
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: "⏱"
            font.pixelSize: 14
        }

        Text {
            text: String(root.model.remainingLabel || "")
            color: root.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }
    }

    // Expanded
    Column {
        visible: root.expanded
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(root.model.remainingLabel || "")
            color: root.textPrimary
            font.pixelSize: 30
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(root.model.statusLabel || (!!(root.model && root.model.running) ? "Running" : "Paused"))
            color: root.textSecondary
            font.pixelSize: 12
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }

        Rectangle {
            width: 180
            height: 4
            radius: 2
            color: root.trackColor
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                radius: 2
                color: root.accentColor
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Rectangle {
                width: 72
                height: 32
                radius: 10
                color: root.controlFill
                Text {
                    anchors.centerIn: parent
                    text: String(root.model.pauseLabel || "Pause")
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.family: "Noto Sans CJK SC"
                }
            }

            Rectangle {
                width: 72
                height: 32
                radius: 10
                color: root.controlFill
                Text {
                    anchors.centerIn: parent
                    text: String(root.model.cancelLabel || "Cancel")
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.family: "Noto Sans CJK SC"
                }
            }
        }
    }
}
