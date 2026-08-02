pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Motion.js" as Motion

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

    // S-L6: footprint of the popup that most recently closed, used to ignore
    // dismiss clicks that land on its afterimage within the suppress window.
    property rect lastOpenRect: Qt.rect(0, 0, 1, 1)
    property rect lastClosedRect: Qt.rect(0, 0, 1, 1)
    property bool suppressAfterimage: false

    Timer {
        id: afterimageSuppressTimer
        // Outlasts the popup close animation so a click landing on a
        // just-closed popup's footprint does not immediately dismiss the
        // popup that opens in the same spot (S-L6).
        interval: Motion.popupDismissAfterimageMs
        repeat: false
        onTriggered: root.suppressAfterimage = false
    }

    // Latch the live popup geometry while open; the width/height guard means
    // the close tick's geometry clear (→ 0/1) does not overwrite the last real
    // footprint, so onOpenChanged snapshots the just-closed popup's rect.
    function refreshLastOpenRect() {
        if (root.open && root.popupWidth > 1 && root.popupHeight > 1)
            root.lastOpenRect = Qt.rect(root.popupLeft, root.popupTop, root.popupWidth, root.popupHeight);
    }
    onPopupLeftChanged: root.refreshLastOpenRect()
    onPopupTopChanged: root.refreshLastOpenRect()
    onPopupWidthChanged: root.refreshLastOpenRect()
    onPopupHeightChanged: root.refreshLastOpenRect()
    onOpenChanged: {
        if (root.open) {
            // S-L6: latch the live footprint now that open is true. The
            // geometry-change handlers above early-return while open is false,
            // so without this a popup whose geometry already settled before
            // open flipped would leave lastOpenRect at the 1×1 default and
            // the afterimage suppressor would protect only a corner box.
            root.refreshLastOpenRect();
        } else {
            root.lastClosedRect = root.lastOpenRect;
            root.suppressAfterimage = true;
            afterimageSuppressTimer.restart();
        }
    }

    // S-L6 gate shared by the left/right dismiss clicks. Must live on root:
    // the onClicked handler calls it as root.dismissFor() — defined on the
    // MouseArea instead, that call threw TypeError on every click and the
    // layer swallowed all outside input without ever emitting closeRequested
    // (T-29 regression: popups stopped dismissing, windows unclickable).
    function dismissFor(mouse) {
        if (root.suppressAfterimage) {
            var pad = root.cutoutPadding;
            var r = root.lastClosedRect;
            if (mouse.x >= r.x - pad && mouse.x <= r.x + r.width + pad
                    && mouse.y >= r.y - pad && mouse.y <= r.y + r.height + pad) {
                // S-L6: the click lands on the footprint of a popup that
                // just closed (its visual afterimage) within the suppress
                // window — ignore it so it does not dismiss the popup that
                // opened in the same spot.
                return false;
            }
        }
        return true;
    }

    visible: open
    // P02: freeze scene-graph frames while this surface is unmapped/faded out.
    // Extends the existing visible gate onto updatesEnabled (not a parallel path).
    updatesEnabled: visible
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
        // F-13: left-click and right-click are both explicit dismiss
        // gestures on the outside region. Wheel is deliberately inert: a
        // scroll must never close a popup (the layer owns the input region,
        // so it cannot reach the window underneath either — it is consumed
        // here, documented as the policy rather than left implicit).
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: function(mouse) {
            if (root.dismissFor(mouse))
                root.closeRequested();
        }
        onWheel: function(wheel) {
            // F-13: never dismiss on scroll; consume so the gesture is inert.
            wheel.accepted = true;
        }
    }
}
