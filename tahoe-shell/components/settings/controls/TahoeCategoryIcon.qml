pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Material Icons glyph on a vertically-graded brand-color rounded square —
// the macOS System Settings category icon idiom (a glossy squircle whose top
// reads lighter than its base). Used by the sidebar buttons and the overview
// summary tiles so a category keeps one identity color in both places.
//
// The gradient uses Rectangle's native `gradient` (basic QtQuick, not a shader
// effect) and Qt.lighter for the top stop, so it is safe on the VM /
// software-renderer path. No spring on geometry and no Image, so neither
// guardrail E (useSpring) nor the VMware icon-vanish failure mode applies.
Item {
    id: icon

    property var theme
    property string iconCode: ""
    property color accentColor: theme ? theme.accentBlue : "#007ff7"
    property real square: 24
    property real radius: Math.round(square * 0.26)
    property real glyphSize: Math.round(square * 0.62)

    // Top of the gradient is the brand color lifted ~20% toward white; the
    // bottom is the raw brand color. Qt.lighter composes well across the whole
    // category palette (indigo/red/coral/blue/orange/green/gray/teal).
    readonly property color topColor: Qt.lighter(icon.accentColor, 1.2)

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"

    Layout.preferredWidth: square
    Layout.preferredHeight: square

    Rectangle {
        anchors.fill: parent
        radius: icon.radius
        gradient: Gradient {
            orientation: Qt.Vertical
            GradientStop { position: 0.0; color: icon.topColor }
            GradientStop { position: 1.0; color: icon.accentColor }
        }
        // Subtle inner top-left light edge so the fill reads as glassy in both
        // light and dark modes.
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
