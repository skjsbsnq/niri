pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../Motion.js" as Motion

Item {
    id: row

    property var theme
    property string label: ""
    property string detail: ""
    property string iconCode: ""
    property bool checkable: false
    property bool checked: false
    default property alias controlData: controlSlot.data

    readonly property string iconFont: theme ? theme.iconFont : "Material Icons"
    readonly property color textPrimary: theme ? theme.textPrimary : "#1d1d1f"
    readonly property color textSecondary: theme ? theme.textSecondary : "#721d1d1f"
    readonly property color rowFill: theme ? theme.rowFill : "#28ffffff"
    readonly property color rowStroke: theme ? theme.rowStroke : "#32ffffff"

    signal toggled(bool checked)

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(46, rowContent.implicitHeight + 14)
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
        color: rowMouse.pressed && row.checkable && row.enabled ? Qt.darker(row.rowFill, 1.18) : row.rowFill
        border.color: row.rowStroke
        border.width: 1
    }

    RowLayout {
        id: rowContent
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Text {
            Layout.preferredWidth: 22
            Layout.alignment: Qt.AlignVCenter
            text: row.iconCode
            color: row.textPrimary
            font.family: row.iconFont
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: row.label
                color: row.textPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: row.detail
                color: row.textSecondary
                font.pixelSize: 11
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
            checked: row.checked
            visible: row.checkable
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: row.checkable
        cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (row.enabled)
                row.toggled(!row.checked);
        }
    }
}
