pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

ButtonSurface {
    id: control

    property string iconCode: ""
    property bool danger: false
    property color iconColor: "#1d1d1f"
    property color dangerColor: "#ccff453a"
    property color activeIconColor: "#ffffff"
    property int iconSize: 16
    property bool iconSpinning: false
    property int iconSpinDuration: 900

    Layout.preferredWidth: 26
    Layout.preferredHeight: 24
    Layout.alignment: Qt.AlignVCenter

    TahoeSymbol {
        id: iconGlyph
        anchors.centerIn: parent
        name: control.iconCode
        color: control.active || control.prominent
            ? control.activeIconColor
            : (control.danger ? control.dangerColor : control.iconColor)
        size: control.iconSize
    }

    RotationAnimation {
        id: iconSpin
        target: iconGlyph
        property: "rotation"
        from: 0
        to: 360
        duration: control.iconSpinDuration
        loops: Animation.Infinite
        running: control.iconSpinning && control.visible
        onRunningChanged: {
            if (!running)
                iconGlyph.rotation = 0;
        }
    }
}
