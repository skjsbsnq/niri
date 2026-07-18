pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion
import "Motion.js" as Motion

// V2 notification scene (T14 compact + T15 expand/actions).
// Body click → default action (T14 freeze). Chevron-only expand toggle.
// R07: compact↔expanded crossfade in place (no visible hard switch) and
// finger-following horizontal swipe-to-dismiss with fly-out / settle-back.
Item {
    id: root

    property string appName: ""
    property string summary: ""
    property string body: ""
    property string iconUrl: ""
    property string urgency: "normal"
    property bool hasOverflow: false
    property bool expanded: false
    // [{ "id": "...", "label": "..." }, ...] — default action already filtered by service.
    property var actions: []
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color textMuted: "#7f8996"
    property color criticalColor: "#ff453a"
    property color iconFallbackFill: "#28ffffff"
    property color controlFill: "#20ffffff"
    property var settingsService
    // Spring settle only behind the useSpring gate (content transform, no glass).
    property bool useSpring: false
    // Finger-following horizontal offset for compact swipe-to-dismiss.
    property real swipeOffsetX: 0
    // Bumps once per fresh notification lease (service presentation epoch). A
    // reused view instance (dismiss → next queued notif in the same stack,
    // within the Loader hold window) must reset leftover swipe offset so the
    // new notification renders centered instead of flown-out / off-capsule.
    property int notificationEpoch: 0

    onNotificationEpochChanged: resetSwipeState()

    readonly property bool critical: String(root.urgency) === "critical"
    readonly property int actionCount: root.actions && root.actions.length ? root.actions.length : 0
    readonly property int layoutFadeInMs: IslandMotion.contentEnterMs(root.settingsService)
    readonly property int layoutFadeOutMs: IslandMotion.contentExitMs(root.settingsService)

    signal bodyClicked()
    signal dismissRequested()
    signal expandToggleRequested()
    signal actionInvoked(string actionId)
    signal interactionBegan()
    signal interactionEnded()

    function settleSwipeBack() {
        notifFlyOut.stop();
        if (root.useSpring)
            settleSpring.restart();
        else
            settleEase.restart();
    }

    function flyOutAndDismiss(direction) {
        settleSpring.stop();
        settleEase.stop();
        flyOutX.to = direction * Math.max(root.width, 200);
        notifFlyOut.restart();
    }

    function resetSwipeState() {
        // New lease on a reused instance: stop every swipe animation before
        // its side effects can leak into the new notification (a still-running
        // notifFlyOut ScriptAction would dismiss the *new* lease), zero the
        // offset, and clear the click-phase flags so the first tap is not
        // eaten by a stale `dismissed`.
        notifFlyOut.stop();
        settleSpring.stop();
        settleEase.stop();
        root.swipeOffsetX = 0;
        bodyClick.moved = false;
        bodyClick.dismissed = false;
    }

    NumberAnimation {
        id: settleEase
        target: root
        property: "swipeOffsetX"
        to: 0
        duration: IslandMotion.swipeSettleDuration
        easing.type: IslandMotion.swipeSettleEasing
    }

    SpringAnimation {
        id: settleSpring
        target: root
        property: "swipeOffsetX"
        to: 0
        spring: Motion.springSnappy.spring
        damping: Motion.springSnappy.damping
        epsilon: 0.5
    }

    SequentialAnimation {
        id: notifFlyOut
        NumberAnimation {
            id: flyOutX
            target: root
            property: "swipeOffsetX"
            duration: IslandMotion.notificationFlyOutMs
            easing.type: IslandMotion.v2ContentEasing
        }
        ScriptAction {
            script: root.dismissRequested()
        }
    }

    // Critical accent edge.
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

    // ---- Compact layout ----
    Row {
        id: compactRow
        // R07 crossfade: opacity swap with the expanded layout, no hard switch.
        opacity: root.expanded ? 0 : 1
        visible: opacity > 0.01
        enabled: !root.expanded
        transform: Translate { x: root.swipeOffsetX }
        Behavior on opacity {
            NumberAnimation {
                duration: root.expanded ? root.layoutFadeOutMs : root.layoutFadeInMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        anchors.fill: parent
        anchors.leftMargin: root.critical ? 16 : 12
        // No trailing margin: chevron owns the full 44px trailing strip.
        anchors.rightMargin: 0
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 10

        Item {
            width: 32
            height: 32
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: root.iconFallbackFill
                visible: !compactImage.visible
            }

            Text {
                anchors.centerIn: parent
                visible: !compactImage.visible
                text: {
                    var name = String(root.appName || "?").trim();
                    return name.length > 0 ? name.charAt(0) : "?";
                }
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Image {
                id: compactImage
                anchors.fill: parent
                source: root.safeIconUrl(root.iconUrl)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                visible: status === Image.Ready && source.toString().length > 0
            }

            TahoeSymbol {
                anchors.centerIn: parent
                visible: !compactImage.visible && String(root.appName || "").length === 0
                name: "\ue7f4"
                color: root.textPrimary
                size: 18
            }
        }

        Column {
            width: Math.max(40, parent.width - 32 - 10 - (root.hasOverflow ? 48 : 0))
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.appName
                color: root.textMuted
                font.pixelSize: 11
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }

            Text {
                width: parent.width
                text: root.summary
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: root.body
                color: root.textSecondary
                font.pixelSize: 12
                font.letterSpacing: 0
                elide: Text.ElideRight
                maximumLineCount: root.hasOverflow ? 2 : 1
                wrapMode: root.hasOverflow ? Text.WordWrap : Text.NoWrap
                visible: text.length > 0
            }
        }

        // Trailing expand chevron — only when overflow (T15).
        // Hit target is the last 44px of the capsule; bodyClick reserves the same strip.
        Item {
            id: expandChevron
            visible: root.hasOverflow
            width: 44
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            z: 2

            Text {
                anchors.centerIn: parent
                text: "▾"
                color: root.textSecondary
                font.pixelSize: 16
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                // Must not propagate to body click / default action.
                onClicked: function(mouse) {
                    mouse.accepted = true;
                    root.expandToggleRequested();
                }
            }
        }
    }

    // Expanded: absorb all blank hits so capsule handleChipClick cannot steal the lease.
    MouseArea {
        id: expandedAbsorb
        anchors.fill: parent
        visible: root.expanded
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Swallow; collapse/actions sit above at higher z.
        onClicked: function(mouse) { mouse.accepted = true; }
        onPressed: function(mouse) { mouse.accepted = true; }
    }

    // ---- Expanded layout ----
    Column {
        id: expandedColumn
        // R07 crossfade + slight settle-down travel while the capsule grows.
        opacity: root.expanded ? 1 : 0
        visible: opacity > 0.01
        enabled: root.expanded
        transform: Translate {
            y: root.expanded ? 0 : -IslandMotion.contentTravelPx(root.settingsService)
            Behavior on y {
                NumberAnimation {
                    duration: root.expanded ? root.layoutFadeInMs : root.layoutFadeOutMs
                    easing.type: IslandMotion.v2ContentEasing
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: root.expanded ? root.layoutFadeInMs : root.layoutFadeOutMs
                easing.type: IslandMotion.v2ContentEasing
            }
        }
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        z: 1

        Row {
            width: parent.width
            spacing: 10

            Item {
                width: 28
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: root.iconFallbackFill
                    visible: !expandedImage.visible
                }

                Text {
                    anchors.centerIn: parent
                    visible: !expandedImage.visible
                    text: {
                        var name = String(root.appName || "?").trim();
                        return name.length > 0 ? name.charAt(0) : "?";
                    }
                    color: root.textPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Image {
                    id: expandedImage
                    anchors.fill: parent
                    source: root.safeIconUrl(root.iconUrl)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready && source.toString().length > 0
                }
            }

            Column {
                width: parent.width - 38 - 44
                spacing: 1

                Text {
                    width: parent.width
                    text: root.appName
                    color: root.textMuted
                    font.pixelSize: 11
                    font.letterSpacing: 0
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.summary
                    color: root.textPrimary
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // Collapse chevron.
            Item {
                width: 44
                height: 44

                Text {
                    anchors.centerIn: parent
                    text: "▴"
                    color: root.textSecondary
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        mouse.accepted = true;
                        root.expandToggleRequested();
                    }
                }
            }
        }

        Flickable {
            id: bodyFlick
            width: parent.width
            height: Math.min(54, contentHeight)
            contentWidth: width
            contentHeight: expandedBody.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: expandedBody.implicitHeight > height + 1
            // Avoid fighting capsule horizontal swipe: only vertical flick.
            flickableDirection: Flickable.VerticalFlick

            Text {
                id: expandedBody
                width: bodyFlick.width
                text: root.body
                color: root.textSecondary
                font.pixelSize: 12
                font.letterSpacing: 0
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 3
            }

            onMovementStarted: root.interactionBegan()
            onMovementEnded: root.interactionEnded()
        }

        Row {
            id: actionRow
            spacing: 8
            visible: root.actionCount > 0

            Repeater {
                model: root.actions
                delegate: Rectangle {
                    required property var modelData
                    width: Math.max(64, actionLabel.implicitWidth + 20)
                    height: 32
                    radius: 10
                    color: root.controlFill
                    border.width: 1
                    border.color: "#24ffffff"

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: String(modelData && modelData.label ? modelData.label : "")
                        color: root.textPrimary
                        font.pixelSize: 12
                        font.letterSpacing: 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        // Prefer 44px hit target vertically around 32px chrome.
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.interactionBegan()
                        onReleased: root.interactionEnded()
                        onCanceled: root.interactionEnded()
                        onClicked: {
                            var id = modelData && modelData.id !== undefined
                                ? String(modelData.id)
                                : "";
                            if (id.length > 0)
                                root.actionInvoked(id);
                        }
                    }
                }
            }
        }
    }

    // Body click / swipe only in compact mode and outside chevron.
    // z below chevron (chevron is inside compactRow with z:2); rightMargin = 44
    // matches expandChevron width with compactRow rightMargin 0.
    MouseArea {
        id: bodyClick
        anchors.fill: parent
        visible: !root.expanded
        z: 1
        acceptedButtons: Qt.LeftButton
        anchors.rightMargin: root.hasOverflow ? 44 : 0
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: false
        property real pressX: 0
        property real pressY: 0
        property bool moved: false
        property bool dismissed: false

        onPressed: function(mouse) {
            pressX = mouse.x;
            pressY = mouse.y;
            moved = false;
            dismissed = false;
            // Also stop an in-flight fly-out: the finger owns the offset now
            // (otherwise flyOutX and positionChanged fight over swipeOffsetX).
            notifFlyOut.stop();
            settleEase.stop();
            settleSpring.stop();
        }
        onPositionChanged: function(mouse) {
            if (!pressed || dismissed)
                return;
            var dx = mouse.x - pressX;
            var dy = mouse.y - pressY;
            if (Math.abs(dx) >= IslandMotion.swipeArmThresholdPx
                    && Math.abs(dx) > Math.abs(dy))
                moved = true;
            // Finger-following: content tracks the pointer once armed.
            if (moved)
                root.swipeOffsetX = dx;
        }
        onReleased: {
            if (!moved || dismissed)
                return;
            if (Math.abs(root.swipeOffsetX) >= IslandMotion.notificationDismissThresholdPx) {
                // Past threshold: fly out, then dismiss.
                dismissed = true;
                root.flyOutAndDismiss(root.swipeOffsetX >= 0 ? 1 : -1);
            } else {
                // Under threshold: settle back (spring behind useSpring gate).
                root.settleSwipeBack();
            }
        }
        onClicked: function(mouse) {
            if (moved || dismissed)
                return;
            root.bodyClicked();
        }
        onCanceled: {
            moved = false;
            dismissed = false;
            root.settleSwipeBack();
        }
    }

    function safeIconUrl(url) {
        var s = String(url || "").trim();
        if (s.length === 0)
            return "";
        if (s.indexOf("image://") === 0
                || s.indexOf("file://") === 0
                || s.indexOf("qrc:") === 0
                || s.indexOf("/") === 0)
            return s;
        return "";
    }
}
