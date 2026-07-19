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

    Layout.preferredWidth: 26
    Layout.preferredHeight: 24
    Layout.alignment: Qt.AlignVCenter

    TahoeSymbol {
        anchors.centerIn: parent
        name: control.iconCode
        color: control.active || control.prominent
            ? control.activeIconColor
            : (control.danger ? control.dangerColor : control.iconColor)
        size: control.iconSize
    }
}
