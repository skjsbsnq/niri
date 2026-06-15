pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as TahoeGlass

// Real notification toast.
//
// Driven entirely by the Notifications service: there is no fake Timer
// and no hardcoded "Session ready" text. The popup watches
// `notificationsService.current` (the head of the FIFO queue of live
// Notification objects). When a notification arrives the card springs in
// from the right, auto-dismisses after the client-requested timeout
// (handled by the service), and can be dismissed by click or by invoking
// an action button.
//
// The popup is a single card. If multiple notifications stack up, the
// service advances `current` to the next one when the head is dismissed,
// so the same card re-animates for the next one. This matches the
// single-toast behavior of the original placeholder while being real.
//
// `current` is a live Notification object, so we bind its properties
// directly (appName / summary / body / urgency / actions). A replace-id
// update mutates the same object and is reflected here automatically.

PanelWindow {
    id: root

    property var notificationsService
    property var current: notificationsService ? notificationsService.current : null
    property bool hasCurrent: !!current
    // Kept for shell.qml compatibility. The card is a glass/blur region item,
    // so Phase 3 forbids springing its geometry even on real GPUs.
    property bool useSpring: false
    // Resolved icon URL for the current notification. Recomputed whenever
    // `current` changes. Empty string means "no icon" -> show the bell glyph.
    readonly property string iconUrl: hasCurrent && notificationsService
        ? notificationsService.iconUrlFor(current)
        : ""
    readonly property bool hasIcon: iconUrl.length > 0

    visible: hasCurrent && card.opacity > 0.01
    aboveWindows: true
    exclusiveZone: 0
    implicitWidth: 318
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.namespace: "tahoe-notification-toast"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 48
        right: 16
    }

    // Urgency accent. Normal = neutral hairline; Critical gets a warm red
    // edge so it reads as urgent even before the user reads the summary.
    readonly property color accentColor: {
        if (!current)
            return "#70ffffff";
        try {
            return Number(current.urgency) === 2 ? "#ccff453a" : "#70ffffff";
        } catch (e) {
            return "#70ffffff";
        }
    }

    // Frosted-glass blur behind the card. The blur region's radius MUST
    // match the card's radius (18) or the blur leaks past the rounded
    // corners.
    //
    // IMPORTANT: this attached type lives under Quickshell.Wayland
    // (Quickshell.Wayland._BackgroundEffect), so the file MUST import
    // Quickshell.Wayland. Without that import the engine silently drops
    // the attached property -> the card renders as a flat translucent
    // rectangle with no blur. That was the real reason the toast had no
    // frost, NOT a geometry cycle.
    BackgroundEffect.blurRegion: Region {
        item: card
        radius: card.tahoeGlassRadius
    }

    Rectangle {
        id: card
        readonly property string tahoeGlassMaterial: TahoeGlass.MaterialToast
        readonly property real tahoeGlassRadius: TahoeGlass.RadiusToast

        // Slide + fade in from the right when a notification arrives.
        // x changes the blur/glass geometry, so it uses a bounded
        // NumberAnimation. Opacity remains independent of region geometry.
        x: root.hasCurrent ? 0 : root.width + 24
        y: 0
        width: parent.width
        implicitHeight: 86
        height: Math.max(86, column.implicitHeight + 28)
        radius: tahoeGlassRadius
        color: TahoeGlass.FillPanelBright
        opacity: root.hasCurrent ? 1 : 0

        // NOTE: no `border.width` on the card itself. A centered 1px
        // border on a large-radius Rectangle is antialiased against the
        // pixels OUTSIDE the rect and produces faint near-square corners
        // where the arc is tangent to the straight edges. The glass edges
        // are drawn instead by the two inset Rectangles below, whose
        // borders sit fully inside the card and never overshoot.
        Rectangle {
            // Top-left light edge (the Tahoe glass highlight).
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: root.accentColor
            border.width: 1
        }

        Rectangle {
            // Bottom-right shadow edge.
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: "#14000000"
            border.width: 1
            z: -1
        }

        // Slide + fade in from the right. This card is the blur-region item,
        // so geometry must never be driven by SpringAnimation.
        Behavior on x {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        Behavior on height {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 8

            Item {
                width: parent.width
                height: 36

                // App icon / notification image. Falls back to a generic
                // bell glyph when no icon is supplied (the common case
                // for notify-send without an icon name). The fallback
                // Text and the Image are siblings inside iconBox; exactly
                // one is visible at a time based on `root.hasIcon`.
                Rectangle {
                    id: iconBox
                    x: 0
                    y: 0
                    width: 36
                    height: 36
                    radius: 11
                    color: "#70ffffff"
                    border.color: "#60ffffff"

                    Text {
                        anchors.centerIn: parent
                        text: "\ue7f4" // Material Icons: notifications
                        color: "#3c4043"
                        font.family: "Material Icons"
                        font.pixelSize: 20
                        visible: !root.hasIcon
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 4
                        fillMode: Image.PreserveAspectCrop
                        source: root.iconUrl
                        visible: root.hasIcon
                        sourceSize.width: 64
                        sourceSize.height: 64
                        asynchronous: true
                    }
                }

                Text {
                    anchors.left: iconBox.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.verticalCenter: iconBox.verticalCenter
                    text: root.hasCurrent ? String(root.current.appName || "Notification") : ""
                    color: "#202124"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                text: root.hasCurrent ? String(root.current.summary || "") : ""
                color: "#202124"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
                visible: text.length > 0
            }

            Text {
                width: parent.width
                text: root.hasCurrent ? String(root.current.body || "") : ""
                color: "#5f6368"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 4
                visible: text.length > 0
            }

            // Action buttons row, if the client supplied any. Right-aligned
            // to mirror macOS / iOS notification action placement. Binds to
            // the live Notification.actions list directly.
            Row {
                width: parent.width
                spacing: 8
                layoutDirection: Qt.RightToLeft
                visible: root.hasCurrent && root.current.actions && root.current.actions.length > 0

                Repeater {
                    model: root.hasCurrent ? root.current.actions : []

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        height: 26
                        width: actionLabel.implicitWidth + 22
                        radius: 13
                        color: actionMouse.containsMouse ? "#a0ffffff" : "#60ffffff"
                        border.color: "#50ffffff"

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: {
                                var t = String(modelData.text || "");
                                if (t.length > 0)
                                    return t;
                                return String(modelData.identifier || "");
                            }
                            color: "#1a73e8"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.notificationsService)
                                    root.notificationsService.invokeAction(
                                        root.current.id, modelData.identifier);
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            // Click anywhere outside an action button to dismiss.
            // z:-1 keeps it behind the Column's interactive children.
            anchors.fill: parent
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.notificationsService)
                    root.notificationsService.dismissCurrent();
            }
        }
    }
}
