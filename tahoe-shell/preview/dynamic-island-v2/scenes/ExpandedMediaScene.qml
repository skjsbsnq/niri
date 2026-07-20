import QtQuick 2.15

Item {
    id: root
    property var model: ({})
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color accentColor: "#0a84ff"
    property color progressFillColor: "#f7f8fa"
    property color trackColor: "#30ffffff"
    property color controlFill: "#20ffffff"

    readonly property real progress: Math.max(0, Math.min(1, Number(model && model.progress) || 0))

    function formatTime(seconds) {
        var s = Math.max(0, Math.floor(Number(seconds) || 0));
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    Item {
        anchors.fill: parent
        anchors.margins: 16

        Rectangle {
            id: art
            width: 64
            height: 64
            radius: 12
            color: "#28ffffff"
            anchors.left: parent.left
            anchors.top: parent.top

            Text {
                anchors.centerIn: parent
                text: "♪"
                color: root.textSecondary
                font.pixelSize: 26
            }
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.verticalCenter: art.verticalCenter
            spacing: 4

            Text {
                width: parent.width
                text: String(root.model.title || "")
                color: root.textPrimary
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.family: "Noto Sans CJK SC"
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: String(root.model.artist || "")
                color: root.textSecondary
                font.pixelSize: 12
                font.family: "Noto Sans CJK SC"
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Item {
            id: timeline
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: art.bottom
            anchors.topMargin: 14
            height: 18

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: 2
                color: root.trackColor

                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: 2
                    color: root.progressFillColor
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: root.formatTime(root.model.position)
                color: root.textSecondary
                font.pixelSize: 10
                font.letterSpacing: 0
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: root.formatTime(root.model.duration)
                color: root.textSecondary
                font.pixelSize: 10
                font.letterSpacing: 0
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: 18

            // prev
            Item {
                width: 44
                height: 44
                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: 16
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "⏮"
                        color: root.textPrimary
                        font.pixelSize: 14
                    }
                }
            }

            // play/pause primary
            Item {
                width: 44
                height: 44
                Rectangle {
                    anchors.centerIn: parent
                    width: 36
                    height: 36
                    radius: 18
                    color: root.accentColor
                    Text {
                        anchors.centerIn: parent
                        text: !!(root.model && root.model.playing) ? "❚❚" : "▶"
                        color: "#ffffff"
                        font.pixelSize: 13
                    }
                }
            }

            // next
            Item {
                width: 44
                height: 44
                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: 16
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "⏭"
                        color: root.textPrimary
                        font.pixelSize: 14
                    }
                }
            }
        }
    }
}
