pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Power profile bridge.
//
// Preferred truth on firmware-backed laptops is
// /sys/firmware/acpi/platform_profile (Bitland/Mechrevo, ASUS, etc.).
// power-profiles-daemon remains the write path for power-saver/balanced
// when it works, but:
//   1. PPD 0.30 does not map sysfs `balanced-performance` (hyphen), so Fn
//      beast mode looks like "balanced".
//   2. On Mechrevo/Bitland, PPD `performance` often snaps back immediately;
//      the useful high tier is `balanced-performance` written via sysfs.
//
// UI keeps three buttons: 省电 / 均衡 / 性能.
// 性能 maps to balanced-performance when that choice exists.
Item {
    id: root
    visible: false

    property bool available: false
    property bool pollingActive: true
    property bool updating: false
    property string profile: ""
    property string platformProfile: ""
    property string errorText: ""
    property string backend: ""
    property var availableProfileIds: []
    property var platformChoices: []
    property var commandRunner
    property string pendingProfile: ""
    property int verifyAttempts: 0

    readonly property string helperPath: {
        if (root.commandRunner && root.commandRunner.platformProfileHelperPath)
            return root.commandRunner.platformProfileHelperPath();
        return Quickshell.shellPath("scripts/tahoe-platform-profile");
    }

    readonly property string installedHelperPath: "/usr/local/lib/tahoe/tahoe-platform-profile"

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

    function mapSysfsToUi(value) {
        var raw = String(value || "").trim();
        if (raw === "low-power" || raw === "quiet" || raw === "power-saver")
            return "power-saver";
        if (raw === "balanced" || raw === "cool" || raw === "balanced_performance")
            return "balanced";
        // Kernel hyphen form is the Mechrevo/Bitland beast tier.
        if (raw === "balanced-performance" || raw === "performance")
            return "performance";
        return "";
    }

    function labelFor(id) {
        var sys = String(root.platformProfile || "").trim();
        if (id === "performance" && sys === "balanced-performance")
            return "性能(野兽)";
        if (id === "performance" && sys === "performance")
            return "性能(满血)";
        for (var i = 0; i < root.profiles.length; i++) {
            if (root.profiles[i].id === id)
                return root.profiles[i].label;
        }
        return id.length > 0 ? id : "未知";
    }

    function hasPlatformChoice(name) {
        if (!root.platformChoices || root.platformChoices.length === 0)
            return false;
        return root.platformChoices.indexOf(name) >= 0;
    }

    function platformSupportsUi(id) {
        if (id === "power-saver")
            return root.hasPlatformChoice("low-power") || root.hasPlatformChoice("quiet") || root.hasPlatformChoice("power-saver");
        if (id === "balanced")
            return root.hasPlatformChoice("balanced") || root.hasPlatformChoice("cool");
        if (id === "performance")
            return root.hasPlatformChoice("balanced-performance")
                || root.hasPlatformChoice("performance")
                || root.hasPlatformChoice("balanced_performance");
        return false;
    }

    function supports(id) {
        if (!root.available)
            return false;
        if (root.platformChoices && root.platformChoices.length > 0)
            return root.platformSupportsUi(id);
        if (!root.availableProfileIds || root.availableProfileIds.length === 0)
            return true;
        return root.availableProfileIds.indexOf(id) >= 0;
    }

    function rebuildAvailableIds() {
        var found = [];
        if (root.platformChoices && root.platformChoices.length > 0) {
            if (root.platformSupportsUi("power-saver"))
                found.push("power-saver");
            if (root.platformSupportsUi("balanced"))
                found.push("balanced");
            if (root.platformSupportsUi("performance"))
                found.push("performance");
        } else if (root.availableProfileIds && root.availableProfileIds.length > 0) {
            found = root.availableProfileIds.slice();
        } else {
            found = ["power-saver", "balanced", "performance"];
        }
        if (!root.sameStringArray(root.availableProfileIds, found))
            root.availableProfileIds = found;
    }

    function applySysfsProfile(text, source) {
        if (!root.pollingActive && !root.updating)
            return;

        var raw = String(text || "").trim().split(/\s+/)[0];
        if (!raw)
            return;

        var ui = root.mapSysfsToUi(raw);
        if (!ui)
            return;

        root.setValue("platformProfile", raw);
        root.setValue("profile", ui);
        root.setValue("available", true);
        if (source)
            root.setValue("backend", source);

        // Complete in-flight verify as soon as firmware reports the expected tier.
        if (root.updating && root.pendingProfile && ui === root.pendingProfile) {
            if (verifyTimer.running)
                verifyTimer.stop();
            root.finishUpdate(true, "");
            return;
        }

        if (!root.updating)
            root.setValue("errorText", "");
    }

    function parsePlatformChoices(text) {
        if (!root.pollingActive && root.platformChoices.length > 0 && !root.updating)
            return;

        var raw = String(text || "").trim();
        if (!raw)
            return;

        var parts = raw.split(/\s+/).filter(function(item) {
            return item && item.length > 0;
        });
        if (parts.length === 0)
            return;

        if (!root.sameStringArray(root.platformChoices, parts))
            root.platformChoices = parts;
        root.rebuildAvailableIds();
        root.setValue("available", true);
        if (!root.backend)
            root.setValue("backend", "platform_profile");
    }

    function parsePpdProfile(text, source) {
        // Sysfs is preferred when present; only fill gaps from PPD.
        if (root.platformProfile && root.platformProfile.length > 0)
            return;
        if (!root.pollingActive)
            return;

        var raw = String(text || "").trim();
        var match = raw.match(/(power-saver|balanced|performance)/);
        if (!match)
            return;

        root.setValue("profile", match[1]);
        root.setValue("available", true);
        root.setValue("backend", source || "powerprofilesctl");
        if (!root.updating)
            root.setValue("errorText", "");
    }

    function parsePpdProfileList(text) {
        if (root.platformChoices && root.platformChoices.length > 0)
            return;
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

    function helperExists(path) {
        // FileView/Process based existence would be async; shellPath always
        // points at the deployed tree. Prefer installed helper for polkit.
        return String(path || "").length > 0;
    }

    function resolveHelperCommand() {
        // Installed path matches the polkit annotation (passwordless active session).
        // Fallback to the shell tree copy (pkexec may prompt once).
        if (root.helperPath && root.helperPath.indexOf("/usr/local/lib/tahoe/") === 0)
            return root.helperPath;
        return root.installedHelperPath;
    }

    function shellHelperCommand() {
        return root.helperPath;
    }

    function setProfile(id) {
        if (!id || !root.available || !root.supports(id) || root.updating)
            return;

        root.setValue("pendingProfile", id);
        root.setValue("profile", id);
        root.setValue("updating", true);
        root.setValue("errorText", "");
        root.verifyAttempts = 0;

        // Performance on Bitland/Mechrevo must go through platform_profile so we
        // can target balanced-performance. power-saver/balanced stay on PPD when
        // available (no polkit prompt).
        if (id === "performance" || root.shouldUsePlatformSetter(id)) {
            root.startPlatformSet(id);
            return;
        }

        root.startPpdSet(id);
    }

    function shouldUsePlatformSetter(id) {
        // If PPD cannot express the firmware tier we need, always use sysfs.
        if (id === "performance" && root.hasPlatformChoice("balanced-performance"))
            return true;
        // No PPD backend detected yet, but sysfs works.
        if (root.backend === "platform_profile" || root.backend === "platform_profile+pkexec")
            return true;
        return false;
    }

    function startPpdSet(id) {
        profileSetter.command = root.backend === "busctl"
            ? (root.commandRunner && root.commandRunner.powerProfileBusSetCommand
                ? root.commandRunner.powerProfileBusSetCommand(id)
                : [
                    "busctl", "set-property",
                    "net.hadess.PowerProfiles",
                    "/net/hadess/PowerProfiles",
                    "net.hadess.PowerProfiles",
                    "ActiveProfile", "s", id
                ])
            : (root.commandRunner && root.commandRunner.powerProfileCliSetCommand
                ? root.commandRunner.powerProfileCliSetCommand(id)
                : ["powerprofilesctl", "set", id]);
        profileSetter.running = true;
    }

    function startPlatformSet(id) {
        // Prefer the polkit-annotated install path, then the bundled shell tree copy.
        if (root.commandRunner && root.commandRunner.platformProfileSetCommand) {
            platformSetter.command = root.commandRunner.platformProfileSetCommand(id);
        } else {
            platformSetter.command = ["pkexec", root.resolveHelperCommand(), "set", id];
        }
        platformSetter.running = true;
    }

    function finishUpdate(ok, message) {
        root.setValue("updating", false);
        if (!ok)
            root.setValue("errorText", message || "切换电源模式失败");
        else if (message)
            root.setValue("errorText", message);
        else
            root.setValue("errorText", "");
        root.pendingProfile = "";
        root.refresh();
    }

    function beginVerify(expectedUi) {
        root.pendingProfile = expectedUi;
        root.verifyAttempts = 0;
        verifyTimer.restart();
    }

    function runVerifyTick() {
        if (!root.pendingProfile) {
            root.setValue("updating", false);
            return;
        }

        root.verifyAttempts += 1;
        if (!platformGetProbe.running)
            platformGetProbe.running = true;

        // Give firmware a moment to settle; PPD performance snaps back ~immediately.
        if (root.verifyAttempts >= 4) {
            var expected = root.pendingProfile;
            var actual = root.profile;
            if (actual !== expected) {
                root.finishUpdate(false, root.verifyFailureMessage(expected, root.platformProfile));
            } else {
                root.finishUpdate(true, "");
            }
            verifyTimer.stop();
            return;
        }
    }

    function verifyFailureMessage(expected, sysfsValue) {
        if (expected === "performance") {
            if (root.hasPlatformChoice("balanced-performance")) {
                return "无法切换到性能/野兽模式。可试 Fn 热键，或安装 helper：bash scripts/install-platform-profile-helper.sh";
            }
            return "无法切换到性能模式（固件拒绝了 performance）。";
        }
        if (sysfsValue && String(sysfsValue).length > 0)
            return "切换失败，当前固件模式为 " + sysfsValue;
        return "切换电源模式失败";
    }

    function refresh() {
        if (!root.pollingActive && !root.updating)
            return;

        if (!platformGetProbe.running)
            platformGetProbe.running = true;
        if (!platformChoicesProbe.running)
            platformChoicesProbe.running = true;
        if (!busProfileProbe.running)
            busProfileProbe.running = true;
        if (!busListProbe.running)
            busListProbe.running = true;
    }

    Process {
        id: platformGetProbe
        running: false
        command: root.commandRunner && root.commandRunner.platformProfileGetCommand
            ? root.commandRunner.platformProfileGetCommand()
            : ["cat", "/sys/firmware/acpi/platform_profile"]
        stdout: StdioCollector {
            id: platformGetOut
            onStreamFinished: root.applySysfsProfile(platformGetOut.text, "platform_profile")
        }
        onExited: function(code, exitStatus) {
            if (code === 0)
                return;
            // Fall back to PPD-only machines without platform_profile.
            if (root.pollingActive && !cliProfileProbe.running && !root.platformProfile)
                cliProfileProbe.running = true;
        }
    }

    Process {
        id: platformChoicesProbe
        running: false
        command: root.commandRunner && root.commandRunner.platformProfileChoicesCommand
            ? root.commandRunner.platformProfileChoicesCommand()
            : ["cat", "/sys/firmware/acpi/platform_profile_choices"]
        stdout: StdioCollector {
            id: platformChoicesOut
            onStreamFinished: root.parsePlatformChoices(platformChoicesOut.text)
        }
    }

    Process {
        id: busProfileProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileBusGetCommand
            ? root.commandRunner.powerProfileBusGetCommand("ActiveProfile")
            : [
                "busctl", "get-property",
                "net.hadess.PowerProfiles",
                "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles",
                "ActiveProfile"
            ]
        stdout: StdioCollector {
            id: busProfileProbeOut
            onStreamFinished: root.parsePpdProfile(busProfileProbeOut.text, "busctl")
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !cliProfileProbe.running && !root.platformProfile)
                cliProfileProbe.running = true;
        }
    }

    Process {
        id: busListProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileBusGetCommand
            ? root.commandRunner.powerProfileBusGetCommand("Profiles")
            : [
                "busctl", "get-property",
                "net.hadess.PowerProfiles",
                "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles",
                "Profiles"
            ]
        stdout: StdioCollector {
            id: busListProbeOut
            onStreamFinished: root.parsePpdProfileList(busListProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !cliListProbe.running && root.platformChoices.length === 0)
                cliListProbe.running = true;
        }
    }

    Process {
        id: cliProfileProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileCliGetCommand
            ? root.commandRunner.powerProfileCliGetCommand()
            : ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            id: cliProfileProbeOut
            onStreamFinished: root.parsePpdProfile(cliProfileProbeOut.text, "powerprofilesctl")
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !root.available) {
                root.setValue("backend", "");
                root.setValue("errorText", "需要 power-profiles-daemon 或 platform_profile");
            }
        }
    }

    Process {
        id: cliListProbe
        running: false
        command: root.commandRunner && root.commandRunner.powerProfileCliListCommand
            ? root.commandRunner.powerProfileCliListCommand()
            : ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            id: cliListProbeOut
            onStreamFinished: root.parsePpdProfileList(cliListProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            if (root.pollingActive && code !== 0 && !root.available && root.availableProfileIds.length > 0 && root.platformChoices.length === 0)
                root.availableProfileIds = [];
        }
    }

    Process {
        id: profileSetter
        running: false
        onExited: function(code, exitStatus) {
            // Always re-check sysfs: PPD performance can "succeed" then snap back.
            root.beginVerify(root.pendingProfile || root.profile);
        }
    }

    Process {
        id: platformSetter
        running: false
        stdout: StdioCollector {
            id: platformSetterOut
        }
        stderr: StdioCollector {
            id: platformSetterErr
        }
        onExited: function(code, exitStatus) {
            if (code !== 0) {
                var err = String(platformSetterErr.text || platformSetterOut.text || "").trim();
                var cmd = platformSetter.command || [];
                var usedHelper = cmd.length > 1 ? String(cmd[1]) : "";
                // Retry once with the bundled helper if the installed path is missing.
                if (usedHelper === root.installedHelperPath) {
                    platformSetter.command = ["pkexec", root.shellHelperCommand(), "set", root.pendingProfile || "performance"];
                    platformSetter.running = true;
                    return;
                }
                if (root.pendingProfile && root.pendingProfile !== "performance") {
                    root.startPpdSet(root.pendingProfile);
                    return;
                }
                root.finishUpdate(false, err.length > 0
                    ? err
                    : "写入 platform_profile 失败（需要 polkit/pkexec）。可运行：bash tahoe-shell/scripts/install-platform-profile-helper.sh");
                return;
            }
            root.setValue("backend", "platform_profile+pkexec");
            root.beginVerify(root.pendingProfile || "performance");
        }
    }

    Timer {
        id: verifyTimer
        interval: 200
        repeat: true
        running: false
        onTriggered: root.runVerifyTick()
    }

    Timer {
        id: profileRefreshTimer
        interval: 5000
        running: root.pollingActive
        repeat: true
        onTriggered: root.refresh()
    }

    onPollingActiveChanged: {
        if (root.pollingActive) {
            root.refresh();
            return;
        }
        if (busProfileProbe.running)
            busProfileProbe.running = false;
        if (busListProbe.running)
            busListProbe.running = false;
        if (cliProfileProbe.running)
            cliProfileProbe.running = false;
        if (cliListProbe.running)
            cliListProbe.running = false;
        if (platformGetProbe.running)
            platformGetProbe.running = false;
        if (platformChoicesProbe.running)
            platformChoicesProbe.running = false;
        if (verifyTimer.running)
            verifyTimer.stop();
    }

    Component.onCompleted: {
        if (root.pollingActive)
            root.refresh();
    }
}
