pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion

// Shared menu row for every shell menu (T06).
// macOS signatures: height 26 / 13px / radius 6 / accent-blue hover + white text;
// click flashes the selection twice (~70ms) then emits activated so the parent
// can close the menu and run the action. Reduced motion skips the flash.
Item {
    id: row

    property string text: ""
    property string icon: ""
    property string iconFont: "Material Icons"
    property bool enabledRow: true
    property bool destructive: false
    property bool bold: false
    property bool separator: false
    property bool header: false
    property bool checked: false
    property bool showCheckColumn: false
    property bool hasSubmenu: false
    property int indent: 0
    property var settingsService
    property bool darkMode: false

    readonly property bool interactive: enabledRow && !separator && !header
    readonly property bool highlight: interactive
        && (forceHighlight || rowMouse.containsMouse || (rowMouse.pressed && !flashing))
    readonly property color accent: darkMode ? "#0a84ff" : "#007aff"
    readonly property color danger: darkMode ? "#ff6961" : "#ff453a"
    readonly property color labelColor: {
        if (separator)
            return "transparent";
        if (highlight)
            return "#ffffff";
        if (header)
            return darkMode ? "#94a0ad" : "#721d1d1f";
        if (destructive)
            return danger;
        return darkMode ? "#f5f7fb" : "#1d1d1f";
    }
    readonly property color iconColor: {
        if (highlight)
            return "#ffffff";
        if (header)
            return darkMode ? "#94a0ad" : "#721d1d1f";
        if (destructive)
            return danger;
        return darkMode ? "#c3ccd6" : "#202124";
    }
    readonly property color separatorColor: darkMode ? "#1affffff" : "#1a000000"
    readonly property int rowHeight: separator ? 9 : (header ? 22 : 26)
    readonly property int textLeft: showCheckColumn
        ? (30 + indent * 14)
        : (icon.length > 0 ? 34 : 10)

    property bool flashing: false
    property bool forceHighlight: false
    property int flashStep: 0

    signal activated()

    width: parent ? parent.width : implicitWidth
    height: implicitHeight
    implicitWidth: 200
    implicitHeight: rowHeight
    Layout.fillWidth: true
    Layout.preferredHeight: rowHeight
    opacity: interactive || header || separator ? 1 : 0.45
    scale: Motion.pressScaleFor(settingsService, rowMouse.pressed && interactive && !flashing)

    Behavior on scale {
        NumberAnimation {
            duration: Motion.pressDurationFor(row.settingsService)
            easing.type: Motion.pressEasing
        }
    }

    function cancelFlash() {
        flashTimer.stop();
        flashing = false;
        forceHighlight = false;
        flashStep = 0;
    }

    function requestActivate() {
        if (!interactive || flashing)
            return;

        if (Motion.reducedMotion(settingsService)) {
            activated();
            return;
        }

        flashing = true;
        forceHighlight = true;
        flashStep = 0;
        flashTimer.interval = Motion.menuFlashInterval;
        flashTimer.restart();
    }

    function advanceFlash() {
        if (!flashing)
            return;

        if (!row.visible) {
            cancelFlash();
            return;
        }

        flashStep += 1;
        // Two full flashes: ON → OFF → ON → OFF, then activate.
        // Starts ON at requestActivate; steps 1 OFF, 2 ON, 3 OFF, 4 done.
        var halfCycles = Motion.menuFlashCount * 2;
        if (flashStep >= halfCycles) {
            cancelFlash();
            activated();
            return;
        }

        forceHighlight = (flashStep % 2) === 0;
        flashTimer.restart();
    }

    Timer {
        id: flashTimer
        interval: Motion.menuFlashInterval
        repeat: false
        onTriggered: row.advanceFlash()
    }

    // Separator line (inset).
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: row.separatorColor
        visible: row.separator
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: row.highlight ? row.accent : "transparent"
        visible: !row.separator
    }

    // Optional checkmark column (tray / native app menus).
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8 + row.indent * 14
        anchors.verticalCenter: parent.verticalCenter
        text: row.checked ? "\ue5ca" : ""
        color: row.iconColor
        font.family: row.iconFont
        font.pixelSize: 15
        visible: !row.separator && row.showCheckColumn
        opacity: row.checked ? 1 : 0
    }

    // Leading Material icon (static shell menus).
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: row.icon
        color: row.iconColor
        font.family: row.iconFont
        font.pixelSize: 16
        visible: !row.separator && !row.showCheckColumn && row.icon.length > 0
    }

    Text {
        id: label

        anchors.left: parent.left
        anchors.leftMargin: row.textLeft
        anchors.right: submenuGlyph.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: row.text
        color: row.labelColor
        font.pixelSize: row.header ? 11 : 13
        font.weight: (row.bold || row.header) ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: !row.separator
    }

    Text {
        id: submenuGlyph

        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? implicitWidth : 0
        text: "\ue5cc"
        color: row.highlight ? "#ffffff" : (row.darkMode ? "#94a0ad" : "#661d1d1f")
        font.family: row.iconFont
        font.pixelSize: 15
        visible: !row.separator && row.hasSubmenu && !row.header
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: row.interactive && !row.flashing
        cursorShape: row.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.requestActivate()
    }

    Component.onDestruction: row.cancelFlash()
}
