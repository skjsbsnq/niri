pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// Expanded summary page for the island: a compact grid of battery, volume,
// brightness and current workspace. Shown when the island is in
// expanded_summary, or as the left-swipe page. Mirrors the Tide "custom info"
// density without copying its backend.
Item {
    id: root

    property int batteryPercent: 0
    property bool batteryCharging: false
    property real volume: 0
    property bool muted: false
    property real brightness: 0
    property bool brightnessAvailable: false
    property string workspaceLabel: ""
    property color textPrimary: "#f7f9fc"
    property color textSecondary: "#b9c0cc"
    property color trackColor: "#31ffffff"
    property color fillColor: "#f0ffffff"
    property color accent: "#9fd0ff"

    readonly property int fadeDuration: IslandMotion.overlayContentDuration + 90
    readonly property real contentOpacity: visible ? 1 : 0
    readonly property string batteryIcon: batteryCharging ? "\ue1a3" : (batteryPercent <= 15 ? "\ue19c" : "\ue1a5")

    anchors.fill: parent
    opacity: root.contentOpacity
    visible: true

    Behavior on opacity {
        NumberAnimation {
            duration: root.fadeDuration
            easing.type: IslandMotion.overlayColorEasing
        }
    }

    Grid {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 18
            rightMargin: 18
            topMargin: 18
        }
        columns: 2
        spacing: 14
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        SummaryTile {
            width: Math.floor((parent.width - 14) / 2)
            height: 40
            icon: root.batteryIcon
            label: root.batteryCharging ? "充电" : "电池"
            value: root.batteryPercent + "%"
            progress: root.batteryPercent / 100
            showProgress: true
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            trackColor: root.trackColor
            fillColor: root.fillColor
        }

        SummaryTile {
            width: Math.floor((parent.width - 14) / 2)
            height: 40
            icon: root.muted ? "\ue04f" : "\ue050"
            label: "音量"
            value: root.muted ? "静音" : Math.round(root.volume * 100) + "%"
            progress: root.muted ? 0 : root.volume
            showProgress: true
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            trackColor: root.trackColor
            fillColor: root.fillColor
        }

        SummaryTile {
            width: Math.floor((parent.width - 14) / 2)
            height: 40
            icon: "\ue518"
            label: "亮度"
            value: root.brightnessAvailable ? Math.round(root.brightness * 100) + "%" : "不可用"
            progress: root.brightnessAvailable ? root.brightness : 0
            showProgress: root.brightnessAvailable
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            trackColor: root.trackColor
            fillColor: root.fillColor
        }

        SummaryTile {
            width: Math.floor((parent.width - 14) / 2)
            height: 40
            icon: "\ue1b1"
            label: "工作区"
            value: root.workspaceLabel.length > 0 ? root.workspaceLabel : "-"
            showProgress: false
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            trackColor: root.trackColor
            fillColor: root.fillColor
        }
    }

    component SummaryTile: Item {
        id: tile
        property string icon: ""
        property string label: ""
        property string value: ""
        property real progress: 0
        property bool showProgress: false
        property color textPrimary: "#ffffff"
        property color textSecondary: "#ffffff"
        property color trackColor: "#33ffffff"
        property color fillColor: "#ffffff"

        Row {
            anchors.fill: parent
            spacing: 8

            Text {
                width: 22
                height: parent.height
                text: tile.icon
                color: tile.textPrimary
                font.family: "Material Icons"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Column {
                width: parent.width - 30
                height: parent.height
                spacing: 1

                Text {
                    width: parent.width
                    text: tile.label
                    color: tile.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    text: tile.value
                    color: tile.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 2
                    color: tile.trackColor
                    visible: tile.showProgress

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, tile.progress))
                        height: parent.height
                        radius: parent.radius
                        color: tile.fillColor
                    }
                }
            }
        }
    }
}
