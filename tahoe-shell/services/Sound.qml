pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root
    visible: false

    property bool eventSoundsMuted: false

    function run(command) {
        try {
            Quickshell.execDetached({
                command: command,
                workingDirectory: ""
            });
        } catch (e) {
            console.warn("[Sound] command failed:", command, e);
        }
    }

    function setEventSoundsMuted(muted) {
        var next = !!muted;
        if (root.eventSoundsMuted === next)
            return;

        root.eventSoundsMuted = next;

        root.run([
            "gsettings",
            "set",
            "org.gnome.desktop.sound",
            "event-sounds",
            next ? "false" : "true"
        ]);
        root.run([
            "gsettings",
            "set",
            "org.gnome.desktop.sound",
            "theme-name",
            next ? "__no_sounds" : "freedesktop"
        ]);
    }
}
