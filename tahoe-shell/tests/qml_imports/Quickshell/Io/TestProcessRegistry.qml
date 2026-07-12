pragma Singleton
import QtQml

QtObject {
    property var startedIds: []
    function reset() { startedIds = []; }
    function record(command) {
        startedIds = startedIds.concat([String(command.length > 1 ? command[1] : "")]);
    }
}
