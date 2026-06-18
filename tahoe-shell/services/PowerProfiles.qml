pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// power-profiles-daemon bridge. Exposes the standard Linux laptop profiles:
// power-saver, balanced and performance.
Item {
    id: root
    visible: false

    property bool available: false
    property bool updating: false
    property string profile: ""
    property string errorText: ""
    property string backend: ""
    property var availableProfileIds: []

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
            ? [
                "busctl",
                "set-property",
                "net.hadess.PowerProfiles",
                "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles",
                "ActiveProfile",
                "s",
                id
            ]
            : ["powerprofilesctl", "set", id];
        profileSetter.running = true;
    }

    function parseProfile(text, source) {
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
        command: [
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
            if (code !== 0 && !cliProfileProbe.running)
                cliProfileProbe.running = true;
        }
    }

    Process {
        id: busListProbe
        running: false
        command: [
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
            if (code !== 0 && !cliListProbe.running)
                cliListProbe.running = true;
        }
    }

    Process {
        id: cliProfileProbe
        running: false
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            id: cliProfileProbeOut
            onStreamFinished: root.parseProfile(cliProfileProbeOut.text, "powerprofilesctl")
        }
        onExited: function(code, exitStatus) {
            if (code !== 0 && !root.available) {
                root.setValue("backend", "");
                root.setValue("errorText", "需要 power-profiles-daemon");
            }
        }
    }

    Process {
        id: cliListProbe
        running: false
        command: ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            id: cliListProbeOut
            onStreamFinished: root.parseProfileList(cliListProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (code !== 0 && !root.available && root.availableProfileIds.length > 0)
                root.availableProfileIds = [];
        }
    }

    Process {
        id: profileSetter
        running: false
        onExited: function(code, exitStatus) {
            root.setValue("updating", false);
            root.refresh();
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
