pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool open: false
    property int popupLeft: 0
    property int popupTop: 0
    property int popupWidth: 1
    property int popupHeight: 1
    property bool usePopupCutout: true
    property bool useTopBarCutout: true
    readonly property int cutoutPadding: 8
    readonly property int screenWidth: Math.max(1, Number(root.screen && root.screen.width) || root.width)
    readonly property int screenHeight: Math.max(1, Number(root.screen && root.screen.height) || root.height)

    signal closeRequested()

    visible: open
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    implicitWidth: screenWidth
    implicitHeight: screenHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
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
            width: root.usePopupCutout ? Math.min(root.screenWidth - popupCutout.x, root.popupWidth + root.cutoutPadding * 2) : 0
            height: root.usePopupCutout ? Math.min(root.screenHeight - popupCutout.y, root.popupHeight + root.cutoutPadding * 2) : 0
            radius: 30
            intersection: Intersection.Subtract
        }

        Region {
            intersection: Intersection.Subtract
            x: 0
            y: 0
            width: root.screenWidth
            // TopBar's surface is 40px (its implicitHeight/exclusiveZone); a
            // taller cutout leaves a band where clicks neither hit the bar nor
            // dismiss the popup.
            height: root.useTopBarCutout ? 40 : 0
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
