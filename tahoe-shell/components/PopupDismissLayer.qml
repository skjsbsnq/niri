pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "PopupGeometry.js" as PopupGeometry

PanelWindow {
    id: root

    property bool open: false
    property var anchorRect: null
    property int popupWidth: 1
    property int popupHeight: 1
    property int fallbackRight: 12
    property int fallbackTop: 28
    property int popupGap: 8
    property int edgePadding: 8
    readonly property int popupLeft: PopupGeometry.popupLeft(anchorRect, popupWidth, screenWidth, edgePadding, fallbackRight)
    readonly property int popupTop: PopupGeometry.popupTop(anchorRect, fallbackTop, popupGap)
    readonly property int cutoutPadding: 8
    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)

    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.namespace: "tahoe-popup-dismiss"

    mask: Region {
        x: 0
        y: 0
        width: root.screenWidth
        height: root.screenHeight

        Region {
            id: popupCutout

            x: Math.max(0, root.popupLeft - root.cutoutPadding)
            y: Math.max(0, root.popupTop - root.cutoutPadding)
            width: Math.min(root.screenWidth - popupCutout.x, root.popupWidth + root.cutoutPadding * 2)
            height: Math.min(root.screenHeight - popupCutout.y, root.popupHeight + root.cutoutPadding * 2)
            radius: 30
            intersection: Intersection.Subtract
        }

        Region {
            intersection: Intersection.Subtract
            x: 0
            y: 0
            width: root.screenWidth
            height: 44
        }
    }

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeRequested()
    }
}
