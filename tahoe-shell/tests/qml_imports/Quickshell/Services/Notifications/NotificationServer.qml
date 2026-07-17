import QtQml

QtObject {
    property bool keepOnReload: false
    property bool bodySupported: false
    property bool actionsSupported: false
    property bool imageSupported: false

    signal notification(var notification)
}
