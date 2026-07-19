import QtQml
pragma Singleton

QtObject {

    enum Result {
        Success = 0,
        MaxTries = 1
    }

    readonly property int success: 0
    readonly property int maxTries: 1

    function toString(v) {
        return String(v);
    }

}
