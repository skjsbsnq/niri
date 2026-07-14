import QtQml

// Minimal SystemClock stand-in for qmltestrunner. Production uses C++ SystemClock;
// this only mirrors the QML surface (enabled/precision/date/resync) without a
// second parallel timer state machine in LockScreen itself.
QtObject {
    id: root

    enum Enum {
        Hours = 1,
        Minutes = 2,
        Seconds = 3
    }

    property bool enabled: true
    property int precision: 2 // Minutes
    property date date: new Date()
    property int hours: 0
    property int minutes: 0
    property int seconds: 0
    property int resyncCount: 0

    // Optional test inject: function returning Date.
    property var testNowProvider: null

    function wallNow() {
        if (typeof root.testNowProvider === "function")
            return root.testNowProvider();
        return new Date();
    }

    function applyPrecision(d) {
        var t = new Date(d.getTime());
        if (root.precision < SystemClock.Seconds)
            t.setSeconds(0, 0);
        if (root.precision < SystemClock.Minutes) {
            t.setMinutes(0);
            t.setSeconds(0, 0);
        }
        return t;
    }

    function resync() {
        root.resyncCount += 1;
        var t = applyPrecision(wallNow());
        root.date = t;
        root.hours = t.getHours();
        root.minutes = t.getMinutes();
        root.seconds = root.precision >= SystemClock.Seconds ? t.getSeconds() : 0;
    }

    onEnabledChanged: {
        if (root.enabled)
            root.resync();
    }

    onPrecisionChanged: root.resync()

    Component.onCompleted: root.resync()
}
