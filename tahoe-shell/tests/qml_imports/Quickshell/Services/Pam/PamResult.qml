pragma Singleton
import QtQml

QtObject {
    // QML property names must be lower-case; expose enum-like values used by LockScreen.
    readonly property int success: 0
    readonly property int maxTries: 1

    // Bridge production-style PamResult.Success lookups via JS property names on the
    // singleton object (not Q_PROPERTY). Attached after construction below.
    Component.onCompleted: {
        // QtObject can receive dynamic JS properties.
        PamResult["Success"] = 0;
        PamResult["MaxTries"] = 1;
    }

    function toString(v) { return String(v); }
}
