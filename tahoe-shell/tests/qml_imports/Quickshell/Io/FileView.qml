import QtQuick

// Minimal test stub for FileView consumers (Weather cache, Apps pinned state).
QtObject {
    id: root
    default property list<QtObject> data
    property string path: ""
    property bool blockLoading: false
    property bool blockWrites: false
    property bool blockAllReads: false
    property bool printErrors: false
    property bool preload: false
    property bool watchChanges: false
    property string _text: ""

    signal loaded()
    signal loadFailed(var error)
    signal saved()
    signal saveFailed(var error)
    signal fileChanged()

    function text() { return _text; }
    function data() { return _text; }
    function reload() {}
    function waitForJob() {}
    function writeAdapter() {}
    function setText(value) { _text = value === undefined || value === null ? "" : String(value); }
}
