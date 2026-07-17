pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// power-profiles-daemon bridge. Exposes the standard Linux laptop profiles:
// power-saver, balanced and performance.
Item {
    id: root
    visible: false

    property bool available: false
    property bool pollingActive: true
    property bool updating: false
    property string profile: ""
    property string errorText: ""
    property string backend: ""
    property var availableProfileIds: []
    property var commandRunner

    readonly property var profiles: [
        {
            "id": "power-saver",
            "label": "省电",
            "icon": "\uea35",
            "description": "低功耗"
        },
        {
            "id": "balanced",
            "label": "均衡",
            "icon": "\ue9e4",
            "description": "日常使用"
        },
        {
            "id": "performance",
            "label": "性能",
            "icon": "\ue8e5",
            "description": "最高性能"
        }
    ]

    function refresh() {
        if (!root.pollingActive)
            return;

        if (!busProfileProbe.running)
            busProfileProbe.running = true;
        if (!busListProbe.running)
            busListProbe.running = true;
    }

    function supports(id) {
        if (!root.available)
            return false;
        if (!root.availableProfileIds || root.availableProfileIds.length === 0)
            return true;
        return root.availableProfileIds.indexOf(id) >= 0;
    }

    function labelFor(id) {
        for (var i = 0; i < root.profiles.length; i++) {
            if (root.profiles[i].id === id)
                return root.profiles[i].label;
        }
        return id.length > 0 ? id : "未知";
    }

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function sameStringArray(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;

        for (var i = 0; i < a.length; i++) {
            if (String(a[i]) !== String(b[i]))
                return false;
        }

        return true;
    }

    function setProfile(id) {
        if (!id || !root.available || !root.supports(id) || root.updating)
            return;

        root.setValue("profile", id);
        root.setValue("updating", true);
        profileSetter.command = root.backend === "busctl"
            ? (root.commandRunner && root.commandRunner.powerProfileBusSetCommand ? root.commandRunner.powerProfileBusSetCommand(id) : [
                "busctl",
                "set-property",
                "net.hadess.PowerProfiles",
                "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles",
                "ActiveProfile",
                "s",
                id
            ])
            : (root.commandRunner && root.commandRunner.powerProfileCliSetCommand ? root.commandRunner.powerProfileCliSetCommand(id) : ["powerprofilesctl", "set", id]);
        profileSetter.running = true;
    }

    function parseProfile(text, source) {
        if (!root.pollingActive)
            return;

        var raw = String(text || "").trim();
        var match = raw.match(/(power-saver|balanced|performance)/);
        if (!match)
            return;

        root.setValue("profile", match[1]);
        root.setValue("available", true);
        root.setValue("backend", source || "");
        root.setValue("errorText", "");
    }

    function parseProfileList(text) {
        if (!root.pollingActive)
            return;

        var found = [];
        var raw = String(text || "");
        var re = /(power-saver|balanced|performance)/g;
        var match = null;
        while ((match = re.exec(raw)) !== null) {
            if (match && found.indexOf(match[1]) < 0)
                found.push(match[1]);
        }

        if (found.length > 0 && !root.sameStringArray(root.availableProfileIds, found))
            root.availableProfileIds = found;
    }

    Process {
        id: busProfileProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileBusGetCommand ? root.commandRunner.powerProfileBusGetCommand("ActiveProfile") : [
            "busctl",
            "get-property",
            "net.hadess.PowerProfiles",
            "/net/hadess/PowerProfiles",
            "net.hadess.PowerProfiles",
            "ActiveProfile"
        ]
        stdout: StdioCollector {
            id: busProfileProbeOut
            onStreamFinished: root.parseProfile(busProfileProbeOut.text, "busctl")
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !cliProfileProbe.running)
                cliProfileProbe.running = true;
        }
    }

    Process {
        id: busListProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileBusGetCommand ? root.commandRunner.powerProfileBusGetCommand("Profiles") : [
            "busctl",
            "get-property",
            "net.hadess.PowerProfiles",
            "/net/hadess/PowerProfiles",
            "net.hadess.PowerProfiles",
            "Profiles"
        ]
        stdout: StdioCollector {
            id: busListProbeOut
            onStreamFinished: root.parseProfileList(busListProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !cliListProbe.running)
                cliListProbe.running = true;
        }
    }

    Process {
        id: cliProfileProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileCliGetCommand ? root.commandRunner.powerProfileCliGetCommand() : ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            id: cliProfileProbeOut
            onStreamFinished: root.parseProfile(cliProfileProbeOut.text, "powerprofilesctl")
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !root.available) {
                root.setValue("backend", "");
                root.setValue("errorText", "需要 power-profiles-daemon");
            }
        }
    }

    Process {
        id: cliListProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileCliListCommand ? root.commandRunner.powerProfileCliListCommand() : ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            id: cliListProbeOut
            onStreamFinished: root.parseProfileList(cliListProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !root.available && root.availableProfileIds.length > 0)
                root.availableProfileIds = [];
        }
    }

    Process {
        id: profileSetter
        running: false
        onExited: function(code, exitStatus) {
            root.setValue("updating", false);
            if (root.pollingActive)
                root.refresh();
        }
    }

    Timer {
        id: profileRefreshTimer
        interval: 15000
        running: root.pollingActive
        repeat: true
        onTriggered: root.refresh()
    }

    onPollingActiveChanged: {
        if (root.pollingActive) {
            root.refresh();
        } else {
            if (busProfileProbe.running)
                busProfileProbe.running = false;
            if (busListProbe.running)
                busListProbe.running = false;
            if (cliProfileProbe.running)
                cliProfileProbe.running = false;
            if (cliListProbe.running)
                cliListProbe.running = false;
        }
    }

    Component.onCompleted: {
        if (root.pollingActive)
            root.refresh();
    }
}
