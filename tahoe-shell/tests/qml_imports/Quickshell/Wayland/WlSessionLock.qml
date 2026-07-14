import QtQuick

// Test double for Quickshell.Wayland.WlSessionLock. Production type is C++.
Item {
    id: root
    property bool locked: false
    property bool secure: false
    default property alias data: content.data

    Item {
        id: content
    }

    function unlock() {
        root.locked = false;
    }
}
