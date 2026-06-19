pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Material Icons glyph on a solid brand-color rounded square — the macOS
// System Settings category icon idiom. Used by the sidebar buttons and the
// overview summary tiles so a category keeps one identity color in both
// places. No spring on geometry (VM/software-renderer safe, guardrail E).
Item {
    id: icon

    property var theme
    property string iconCode: ""
    property color accentColor: theme ? theme.accentBlue : "#007ff7"
    property real square: 24
    property real radius: Math.round(square * 0.26)
    property real glyphSize: Math.round(square * 0.62)

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"

    Layout.preferredWidth: square
    Layout.preferredHeight: square

    Rectangle {
        anchors.fill: parent
        radius: icon.radius
        color: icon.accentColor
        // Subtle inner top-left light edge so the solid fill reads as glassy
        // in both light and dark modes.
        border.color: "#59ffffff"
        border.width: 1
    }

    Text {
        anchors.centerIn: parent
        text: icon.iconCode
        color: "#ffffff"
        font.family: icon.iconFont
        font.pixelSize: icon.glyphSize
        // Glyphs sit slightly high optically; nudge down a hair.
        anchors.verticalCenterOffset: 1
    }
}
