pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

ButtonSurface {
    id: control

    property string label: ""
    property string iconCode: ""
    property bool danger: false
    property bool primary: false
    property color foregroundColor: "#1d1d1f"
    property color dangerColor: "#ccff453a"
    property color selectedForegroundColor: "#ffffff"
    property real minimumWidth: 0
    property real horizontalPadding: 18
    property real contentSpacing: 4
    property int fontPixelSize: 12
    property int iconSize: 15
    property int fontWeight: Font.DemiBold

    prominent: primary
    prominentColor: danger ? "#d8ff453a" : activeColor
    prominentHoverColor: danger ? "#e0ff453a" : activeHoverColor

    Layout.preferredWidth: Math.max(minimumWidth,
        labelText.implicitWidth + horizontalPadding
            + (iconCode.length > 0 ? iconSize + contentSpacing : 0))
    Layout.preferredHeight: 24
    Layout.alignment: Qt.AlignVCenter

    Row {
        anchors.centerIn: parent
        spacing: control.contentSpacing

        TahoeSymbol {
            name: control.iconCode
            color: control.active || control.prominent
                ? control.selectedForegroundColor
                : (control.danger ? control.dangerColor : control.foregroundColor)
            size: control.iconSize
            visible: control.iconCode.length > 0
        }

        Text {
            id: labelText

            text: control.label
            color: control.active || control.prominent
                ? control.selectedForegroundColor
                : (control.danger ? control.dangerColor : control.foregroundColor)
            font.pixelSize: control.fontPixelSize
            font.weight: control.fontWeight
            elide: Text.ElideRight
        }
    }
}
