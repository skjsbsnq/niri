pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion
import "../SettingsTheme.js" as Theme
import "../.."

Item {
    id: row

    property var theme
    property string label: ""
    property string detail: ""
    property string iconCode: ""
    property bool checkable: false
    property bool checked: false
    default property alias controlData: controlSlot.data

    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color separator: theme && theme.darkMode !== undefined
        ? Theme.separator(theme.darkMode)
        : Theme.separator(false)

    signal toggled(bool checked)

    // T16: row height 40, inset separator (no full-row border chrome).
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(40, rowContent.implicitHeight + 12)
    opacity: checkable && !enabled ? 0.48 : 1
    scale: Motion.pressScaleFor(theme && theme.settingsService ? theme.settingsService : null, rowMouse.pressed && row.checkable && row.enabled)

    Behavior on scale {
        NumberAnimation {
            duration: Motion.pressDurationFor(row.theme && row.theme.settingsService ? row.theme.settingsService : null)
            easing.type: Motion.pressEasing
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: rowMouse.pressed && row.checkable && row.enabled
            ? Qt.darker(row.rowFill, 1.12)
            : (rowMouse.containsMouse && row.checkable ? row.rowFill : "transparent")
        border.width: 0
    }

    // Inset separator along the bottom edge (macOS list idiom).
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 1
        color: row.separator
    }

    RowLayout {
        id: rowContent
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        TahoeSymbol {
            Layout.preferredWidth: 22
            Layout.alignment: Qt.AlignVCenter
            name: row.iconCode
            color: row.textPrimary
            size: 18
            visible: row.iconCode.length > 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: row.label
                color: row.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: row.detail
                color: row.textSecondary
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }
        }

        RowLayout {
            id: controlSlot
            Layout.alignment: Qt.AlignVCenter
            spacing: 7
        }

        TahoeSwitch {
            theme: row.theme
            settingsService: row.theme && row.theme.settingsService ? row.theme.settingsService : null
            checked: row.checked
            pressed: rowMouse.pressed && row.checkable
            visible: row.checkable
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: row.checkable
        hoverEnabled: true
        cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (row.enabled)
                row.toggled(!row.checked);
        }
    }
}
