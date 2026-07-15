import QtQuick 2.15
import "../../components/settings/SettingsTheme.js" as Theme

// Shared dark-focus-glass capsule for the non-production V2 preview.
// Production Overlay still owns the real GlassPanel + TahoeGlass region.
Item {
    id: root

    property var model: ({})
    property bool darkMode: true
    property color accentColor: Theme.accent(true, "blue")

    readonly property int capsuleWidth: Math.max(1, Number(model && model.width) || 120)
    readonly property int capsuleHeight: Math.max(1, Number(model && model.height) || 32)
    readonly property real capsuleRadius: {
        var r = Number(model && model.radius);
        if (!isFinite(r) || r <= 0)
            return Math.min(16, capsuleHeight / 2);
        // Expanded must never become a full ellipse (height/2 on tall panels).
        if (String(model && model.fillRole) === "expanded")
            return Math.min(Math.max(28, r), 32, capsuleWidth / 2);
        return Math.min(r, capsuleWidth / 2, capsuleHeight / 2);
    }
    readonly property string fillRole: String((model && model.fillRole) || "compact")
    readonly property color fillColor: Theme.islandSurfaceFill(darkMode, fillRole)
    readonly property color strokeColor: Theme.islandSurfaceStroke(darkMode, fillRole)
    readonly property color textPrimary: Theme.islandTextPrimary(darkMode)
    readonly property color textSecondary: Theme.islandTextSecondary(darkMode)
    readonly property color textMuted: Theme.islandTextMuted(darkMode)

    width: capsuleWidth
    height: capsuleHeight

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: root.capsuleRadius
        color: root.fillColor
        border.width: 1
        border.color: root.strokeColor
    }

    // Soft inner highlight so the capsule reads as glass even without compositor blur.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.capsuleRadius - 1)
        color: "transparent"
        border.width: 1
        border.color: "#12ffffff"
        opacity: 0.9
    }
}
