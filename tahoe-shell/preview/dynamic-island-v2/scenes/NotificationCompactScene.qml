import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color textMuted: "#7f8996"
    property color criticalColor: "#ff453a"

    readonly property bool critical: String(model && model.urgency) === "critical"
    readonly property bool hasOverflow: !!(model && model.hasOverflow)

    Rectangle {
        visible: root.critical
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 2
        radius: 1
        color: root.criticalColor
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: root.critical ? 16 : 12
        anchors.rightMargin: 10
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 10

        Rectangle {
            width: 32
            height: 32
            radius: 8
            color: "#28ffffff"
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: String(root.model.appName || "?").charAt(0)
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
        }

        Column {
            width: Math.max(40, parent.width - 32 - 10 - (root.hasOverflow ? 44 : 0) - 10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: String(root.model.appName || "")
                color: root.textMuted
                font.pixelSize: 11
                font.family: "Noto Sans CJK SC"
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: String(root.model.summary || "")
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.family: "Noto Sans CJK SC"
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: String(root.model.body || "")
                color: root.textSecondary
                font.pixelSize: 12
                font.family: "Noto Sans CJK SC"
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: root.hasOverflow ? 2 : 1
                wrapMode: Text.NoWrap
                visible: text.length > 0
            }
        }

        Item {
            visible: root.hasOverflow
            width: 44
            height: 44
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: "▾"
                color: root.textSecondary
                font.pixelSize: 16
            }
        }
    }
}
