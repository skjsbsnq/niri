pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle
import "Motion.js" as Motion

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
    property var settingsService
    property var current: notificationsService ? notificationsService.current : null
    property bool hasCurrent: !!current
    readonly property bool suppressedByDynamicIsland: !!root.settingsService
        && !!root.settingsService.dynamicIslandEnabled
    readonly property bool shouldShowToast: hasCurrent && !suppressedByDynamicIsland
    // Kept for shell.qml compatibility. The card is a glass/blur region item,
    // so Phase 3 forbids springing its geometry even on real GPUs.
    property bool useSpring: false
    // Resolved icon URL for the current notification. Recomputed whenever
    // `current` changes. Empty string means "no icon" -> show the bell glyph.
    readonly property string iconUrl: hasCurrent && notificationsService
        ? notificationsService.iconUrlFor(current)
        : ""
    readonly property bool hasIcon: iconUrl.length > 0
    readonly property int screenWidth: Math.max(1, root.numberOr(root.screen && root.screen.width, 1))
    readonly property int toastLeftMargin: Math.round(Math.max(8, root.screenWidth - root.implicitWidth - 16))
    readonly property bool compositorLayerAnimations:
        root.settingsService && root.settingsService.compositorLayerAnimations

    function numberOr(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    visible: compositorLayerAnimations ? shouldShowToast : (shouldShowToast || card.opacity > 0.01)
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    implicitWidth: 318
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "tahoe-notification-toast"

    anchors {
        top: true
        left: true
    }

    margins {
        top: 48
        left: root.toastLeftMargin
    }

    // Urgency accent. Normal = neutral hairline; Critical gets a warm red
    // edge so it reads as urgent even before the user reads the summary.
    readonly property color accentColor: {
        if (!current)
            return GlassStyle.StrokeToast;
        try {
            return Number(current.urgency) === 2 ? "#ccff453a" : GlassStyle.StrokeToast;
        } catch (e) {
            return GlassStyle.StrokeToast;
        }
    }

    TahoeGlass.regions: [
        TahoeGlassRegion {
            item: card
            material: card.tahoeGlassMaterial
            radius: card.tahoeGlassRadius
            blur: true
            shadow: true
            clip: true
            interaction: root.compositorLayerAnimations ? 1 : card.opacity
            materialAlpha: root.compositorLayerAnimations ? 1 : card.opacity
            enabled: root.shouldShowToast || (!root.compositorLayerAnimations && card.opacity > 0.01)
        }
    ]

    Rectangle {
        id: card
        readonly property string tahoeGlassMaterial: GlassStyle.MaterialToast
        readonly property real tahoeGlassRadius: GlassStyle.RadiusToast

        // In compatibility mode QML keeps the legacy slide/fade. With
        // compositor layer animations enabled, niri owns the outer motion.
        x: root.compositorLayerAnimations ? 0 : (root.shouldShowToast ? 0 : root.width + 24)
        y: 0
        width: parent.width
        implicitHeight: 86
        height: Math.max(86, column.implicitHeight + 28)
        radius: tahoeGlassRadius
        color: GlassStyle.FillPanelBright
        opacity: root.compositorLayerAnimations ? 1 : (root.shouldShowToast ? 1 : 0)

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

        // Slide + fade in from the right. This card is the glass-region item,
        // so geometry must never be driven by SpringAnimation.
        Behavior on x {
            NumberAnimation { duration: Motion.panelEnterDuration; easing.type: Motion.emphasizedDecel }
        }

        Behavior on height {
            NumberAnimation { duration: Motion.elementResizeDuration; easing.type: Motion.emphasizedDecel }
        }

        Behavior on opacity {
            NumberAnimation { duration: Motion.fadeFastDuration; easing.type: Motion.standardDecel }
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
