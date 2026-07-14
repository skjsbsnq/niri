import QtQuick

// Minimal test stub: production Weather uses FileView only for cache load/save.
// Geocode identity tests never exercise cache I/O.
QtObject {
    id: root
    property string path: ""
    property bool blockLoading: false
    property bool blockWrites: false
    property bool printErrors: false
    property bool preload: false

    signal loaded()
    signal loadFailed(var error)
    signal saved()
    signal saveFailed(var error)

    function text() { return ""; }
    function data() { return ""; }
    function reload() {}
    function writeAdapter() {}
    function setText(value) {}
}
