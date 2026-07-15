pragma ComponentBehavior: Bound

import QtQuick
import "DynamicIslandMotion.js" as IslandMotion

// V2 compact notification (T14). Expanded chrome lands in T15.
// App icon URL + appName + summary + body; content-driven width hints.
Item {
    id: root

    property string appName: ""
    property string summary: ""
    property string body: ""
    property string iconUrl: ""
    property string urgency: "normal" // normal | critical
    property bool hasOverflow: false
    property color textPrimary: "#f7f8fa"
    property color textSecondary: "#aeb6c2"
    property color textMuted: "#7f8996"
    property color criticalColor: "#ff453a"
    property color iconFallbackFill: "#28ffffff"

    readonly property bool critical: String(root.urgency) === "critical"
    // Measured content width for Overlay clamp (icon + texts + paddings).
    readonly property int contentWidth: Math.ceil(
        12 + 32 + 10 + textColumn.implicitWidth + 12 + (root.hasOverflow ? 44 : 0))
    readonly property int contentHeight: Math.ceil(
        Math.max(52, textColumn.implicitHeight + 20))

    signal bodyClicked()
    signal dismissRequested()

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

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: root.critical ? 16 : 12
        anchors.rightMargin: 12
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
                visible: !appImage.visible
            }

            Text {
                anchors.centerIn: parent
                visible: !appImage.visible
                text: {
                    var name = String(root.appName || "?").trim();
                    return name.length > 0 ? name.charAt(0) : "?";
                }
                color: root.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Image {
                id: appImage
                anchors.fill: parent
                // Only allow image:// and file:// style local/themed icons from the service.
                source: root.safeIconUrl(root.iconUrl)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                visible: status === Image.Ready && source.toString().length > 0
            }

            // Fallback glyph when no usable icon URL.
            TahoeSymbol {
                anchors.centerIn: parent
                visible: !appImage.visible && String(root.appName || "").length === 0
                name: "\ue7f4"
                color: root.textPrimary
                size: 18
            }
        }

        Column {
            id: textColumn
            width: Math.max(40, parent.width - 32 - 10 - (root.hasOverflow ? 54 : 0))
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
                // Compact: one line; long content may use two when hasOverflow (T14).
                maximumLineCount: root.hasOverflow ? 2 : 1
                wrapMode: root.hasOverflow ? Text.WordWrap : Text.NoWrap
                visible: text.length > 0
            }
        }
    }

    // Body click → default action (T14 freeze; T15 must not rewrite).
    // Horizontal swipe → dismiss on the same pointer session (must not rely on
    // the capsule MouseArea under contentHost z=1, which cannot receive events).
    MouseArea {
        id: bodyClick
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // Leave room for future expand chevron (T15) on the trailing edge.
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
        }
        onPositionChanged: function(mouse) {
            if (!pressed || dismissed)
                return;
            var dx = mouse.x - pressX;
            var dy = mouse.y - pressY;
            if (Math.abs(dx) >= IslandMotion.swipeArmThresholdPx
                    && Math.abs(dx) > Math.abs(dy))
                moved = true;
            // Commit dismiss once past 2× arm threshold with horizontal dominance.
            if (Math.abs(dx) >= IslandMotion.swipeArmThresholdPx * 2
                    && Math.abs(dx) > Math.abs(dy)) {
                dismissed = true;
                root.dismissRequested();
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
        }
    }

    function safeIconUrl(url) {
        var s = String(url || "").trim();
        if (s.length === 0)
            return "";
        // Allow themed/local icons from Notifications.iconUrlFor only.
        if (s.indexOf("image://") === 0
                || s.indexOf("file://") === 0
                || s.indexOf("qrc:") === 0
                || s.indexOf("/") === 0)
            return s;
        // Reject arbitrary http(s) or other schemes in the island surface.
        return "";
    }
}
