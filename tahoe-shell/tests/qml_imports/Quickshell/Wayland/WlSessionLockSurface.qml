import QtQuick

// Test double for WlSessionLockSurface — Item with color so LockScreen content loads.
Item {
    id: root
    property color color: "#000000"
    property var screen: null
    width: 800
    height: 600
    visible: true
}
