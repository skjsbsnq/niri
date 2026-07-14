import QtQuick

QtObject {
    id: root
    property bool running: false
    property var command: []
    property var activeCommand: []
    property var stdout: null
    signal exited(int code, int exitStatus)

    property Timer completionTimer: Timer {
        interval: 0
        repeat: false
        onTriggered: {
            if (!root.running)
                return;
            // Mirrors QuickShell: FailedToStart emits runningChanged only, never exited.
            if (root.activeCommand[0] === "test-failed-start"
                    || TestProcessRegistry.shouldFailStart(root.activeCommand)) {
                root.running = false;
                return;
            }
            if (root.stdout) {
                root.stdout.text = TestProcessRegistry.payloadFor(root.activeCommand);
                root.stdout.streamFinished();
            }
            var code = TestProcessRegistry.exitCodeFor(root.activeCommand);
            root.exited(code, 0);
            root.running = false;
        }
    }

    onRunningChanged: {
        if (running) {
            activeCommand = command.slice(0);
            TestProcessRegistry.record(activeCommand);
            var delay = TestProcessRegistry.delayMsFor(activeCommand);
            // Async FailedToStart: running reads true first, then drops without exited.
            if (delay <= 0
                    && (activeCommand[0] === "test-failed-start"
                        || TestProcessRegistry.shouldFailStart(activeCommand)))
                delay = 1;
            completionTimer.interval = Math.max(0, delay);
            completionTimer.restart();
        } else {
            completionTimer.stop();
        }
    }
}
