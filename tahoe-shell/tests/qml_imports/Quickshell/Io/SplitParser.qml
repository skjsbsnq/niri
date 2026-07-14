import QtQuick

// Minimal SplitParser stub for ClipboardHistory watcher tests.
QtObject {
    property string splitMarker: "\n"
    signal read(string line)
}
