pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

Item {
    id: root

    property string displayText: ""
    property bool darkMode: false
    property bool interactive: true
    readonly property bool hovered: interactive && chipMouse.containsMouse
    readonly property bool pressed: interactive && chipMouse.pressed
    readonly property color surfaceColor: darkMode ? "#e61d1f24" : "#ecf8fbff"
    readonly property color hoverSurfaceColor: darkMode ? "#f0252830" : "#f6ffffff"
    readonly property color pressSurfaceColor: darkMode ? "#fa15171d" : "#ffffffff"
    readonly property color strokeColor: darkMode ? "#46ffffff" : "#ccffffff"
    readonly property color textColor: darkMode ? "#f5f7fb" : "#1f2328"

    signal clicked(int button)
    signal hoverEntered()
    signal hoverExited()

    implicitWidth: Math.max(116, Math.min(156, timeLabel.implicitWidth + 44))
    implicitHeight: 24
    transformOrigin: Item.Center
    scale: pressed ? 0.982 : (hovered ? 1.012 : 1)

    Behavior on scale {
        NumberAnimation {
            duration: IslandMotion.chipScaleDuration
            easing.type: IslandMotion.chipSettleEasing
        }
    }

    Rectangle {
        id: softShadow

        x: chipSurface.x
        y: chipSurface.y + 1
        width: chipSurface.width
        height: chipSurface.height
        radius: chipSurface.radius
        color: "#30000000"
        opacity: root.darkMode ? 0.36 : 0.18
    }

    Rectangle {
        id: chipSurface

        anchors.fill: parent
        radius: height / 2
        color: root.pressed ? root.pressSurfaceColor : (root.hovered ? root.hoverSurfaceColor : root.surfaceColor)
        border.color: root.strokeColor
        border.width: 1

        Behavior on color {
            ColorAnimation {
                duration: IslandMotion.chipColorDuration
                easing.type: IslandMotion.chipColorEasing
            }
        }
    }

    Text {
        id: timeLabel

        anchors.centerIn: parent
        width: parent.width - 24
        text: root.displayText
        color: root.textColor
        font.pixelSize: 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        opacity: root.displayText.length > 0 ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: IslandMotion.chipContentDuration
                easing.type: IslandMotion.chipColorEasing
            }
        }
    }

    MouseArea {
        id: chipMouse

        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hoverEntered()
        onExited: root.hoverExited()
        onClicked: function(mouse) {
            root.clicked(mouse.button);
        }
    }
}
