import QtQuick

QtObject {
    id: root
    property bool running: false
    property var command: []
    property var activeCommand: []
    property var stdout: null
    signal exited(int code, int exitStatus)

    property Timer completionTimer: Timer {
        interval: root.activeCommand.length > 2 ? Number(root.activeCommand[2]) : 0
        repeat: false
        onTriggered: {
            if (!root.running)
                return;
            if (root.activeCommand[0] === "test-failed-start") {
                root.running = false;
                return;
            }
            if (root.stdout) {
                root.stdout.text = String(root.activeCommand[3] || "");
                root.stdout.streamFinished();
            }
            var code = root.activeCommand.length > 4 ? Number(root.activeCommand[4]) : 0;
            root.exited(code, 0);
            root.running = false;
        }
    }

    onRunningChanged: {
        if (running) {
            activeCommand = command.slice(0);
            TestProcessRegistry.record(activeCommand);
            completionTimer.restart();
        } else
            completionTimer.stop();
    }
}
