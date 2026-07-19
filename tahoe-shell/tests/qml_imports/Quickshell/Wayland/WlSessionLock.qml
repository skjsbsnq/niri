import QtQuick

// Production-shaped test double: the default property is a Component that is
// instantiated once per output while locked, then destroyed on release.
Item {
    id: root

    default property Component surface
    property bool locked: false
    property bool secure: false
    property int screenCount: 2
    property int unlockCount: 0
    property var surfaceInstances: []

    function realizeSurfaces() {
        if (!root.surface || root.surfaceInstances.length > 0)
            return;
        var next = [];
        for (var i = 0; i < root.screenCount; i++) {
            var instance = root.surface.createObject(root);
            if (instance)
                next.push(instance);
        }
        root.surfaceInstances = next;
    }

    function releaseSurfaces() {
        var current = root.surfaceInstances;
        root.surfaceInstances = [];
        for (var i = 0; i < current.length; i++) {
            if (current[i])
                current[i].destroy();
        }
    }

    onLockedChanged: {
        if (locked) {
            root.realizeSurfaces();
            // Model the compositor acknowledgement after all surfaces exist.
            root.secure = root.surfaceInstances.length === root.screenCount;
        } else {
            if (root.secure || root.surfaceInstances.length > 0)
                root.unlockCount += 1;
            root.secure = false;
            root.releaseSurfaces();
        }
    }

    function unlock() {
        root.locked = false;
    }
}
