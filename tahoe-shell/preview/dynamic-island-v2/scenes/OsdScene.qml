import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color trackColor: "#30ffffff"
    property color progressFillColor: "#f7f8fa"

    readonly property real value: Math.max(0, Math.min(1, Number(model && model.value) || 0))
    readonly property bool muted: !!(model && model.muted)
    readonly property string iconGlyph: {
        var kind = String(model && model.osdKind || "volume");
        if (root.muted)
            return "🔇";
        if (kind === "brightness")
            return "☀";
        return "🔊";
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        Item {
            width: 20
            height: parent.height
            Text {
                anchors.centerIn: parent
                text: root.iconGlyph
                font.pixelSize: 16
            }
        }

        Item {
            width: 120
            height: parent.height

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: root.trackColor

                Rectangle {
                    width: parent.width * (root.muted ? 0 : root.value)
                    height: parent.height
                    radius: 3
                    color: root.muted ? "#70ffffff" : root.progressFillColor
                }
            }
        }

        Text {
            width: 40
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: root.muted
                  ? String((model && model.mutedLabel) || (model && model.label) || "Muted")
                  : String(model.percentLabel || Math.round(root.value * 100))
            color: root.textPrimary
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.family: "Noto Sans CJK SC"
            font.letterSpacing: 0
        }
    }
}
