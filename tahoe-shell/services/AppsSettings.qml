pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var appsService
    property var commandRunner
    property var defaultRows: []
    property var desktopMeta: ({})
    property string defaultsStatus: "unknown"
    property string defaultsDetail: "尚未检测"
    property bool defaultsRefreshing: false
    property bool settingDefault: false
    property string settingCategoryId: ""
    property string lastActionText: ""
    property var selectedApp: null
    property string selectedDesktopId: ""
    property var permissionItems: []
    property var staticPermissionItems: []
    property var snapConnectionItems: []
    property var storageInfo: ({ "total": "0 B", "totalBytes": 0, "items": [] })
    property var sandboxInfo: ({})
    property var permissionCapability: ({})
    property string permissionStatus: "unknown"
    property string permissionDetail: "尚未读取权限"
    property bool permissionsRefreshing: false
    // Monotonic request generation for the single permissionsProbe pipeline.
    // permissionsProbeGeneration: latest refresh intent.
    // permissionsProbeInFlightGeneration / DesktopId: frozen identity of the running Process.
    // permissionsProbePending: newest selection arrived while Process was still running.
    // permissionsStdout*: caches collector output for the in-flight generation only.
    property int permissionsProbeGeneration: 0
    property int permissionsProbeInFlightGeneration: 0
    property string permissionsProbeInFlightDesktopId: ""
    // Desktop ID that currently owns permission* display fields (empty when cleared / pending).
    property string permissionsOwnerDesktopId: ""
    property bool permissionsProbePending: false
    property string permissionsStdoutText: ""
    property int permissionsStdoutGeneration: 0
    property int revision: 0

    readonly property var applications: root.appsService ? root.appsService.launchpadApps : []
    readonly property int applicationCount: root.applications ? root.applications.length : 0

    function filteredApps(query) {
        if (!root.appsService)
            return [];
        return root.appsService.filteredLaunchpadApps(query, "all");
    }

    function appLabel(app) {
        if (root.appsService)
            return root.appsService.appLabel(app);
        if (!app)
            return "应用";
        return String(app.name || app.id || "应用");
    }

    function appGenericName(app) {
        if (!app)
            return "";
        if (app.desktopEntry)
            app = app.desktopEntry;
        return String(app.genericName || app.comment || app.id || "");
    }

    function iconForApp(app) {
        return root.appsService ? root.appsService.iconForApp(app) : "";
    }

    function launchApp(app) {
        if (root.appsService)
            root.appsService.launchApp(app);
    }

    function normalizedDesktopId(value) {
        var id = String(value || "").trim();
        if (id.length === 0)
            return "";
        return id.slice(-8) === ".desktop" ? id : id + ".desktop";
    }

    function desktopIdForApp(app) {
        if (!app)
            return "";
        if (typeof app === "string")
            return normalizedDesktopId(app);
        if (app.desktopEntry)
            app = app.desktopEntry;

        var id = String(app.id || app.desktopId || app.pinnedId || app.fallbackId || "").trim();
        if (id.length === 0 && root.appsService)
            id = String(root.appsService.appStableId(app) || "").trim();
        return normalizedDesktopId(id);
    }

    function appForDesktopId(desktopId) {
        if (!root.appsService)
            return null;
        var id = String(desktopId || "").trim();
        var base = id.replace(/\.desktop$/, "");
        return root.appsService.findApplication([id, base, base.toLowerCase()]);
    }

    function metadataForDesktopId(desktopId) {
        var id = normalizedDesktopId(desktopId);
        return root.desktopMeta && root.desktopMeta[id] ? root.desktopMeta[id] : null;
    }

    function labelForDesktopId(desktopId) {
        var id = normalizedDesktopId(desktopId);
        if (id.length === 0)
            return "未设置";
        var app = appForDesktopId(id);
        if (app)
            return appLabel(app);
        var meta = metadataForDesktopId(id);
        if (meta && String(meta.name || "").length > 0)
            return String(meta.name);
        return id;
    }

    function iconForDesktopId(desktopId) {
        var id = normalizedDesktopId(desktopId);
        var app = appForDesktopId(id);
        if (app)
            return iconForApp(app);

        var meta = metadataForDesktopId(id);
        if (meta && String(meta.icon || "").length > 0) {
            var icon = String(meta.icon);
            if (icon.charAt(0) === "/")
                return icon;
            var themed = Quickshell.iconPath(icon, true);
            if (themed && themed.length > 0)
                return themed;
        }

        return root.appsService ? root.appsService.iconForAppId(id.replace(/\.desktop$/, "")) : "";
    }

    function sandboxForDesktopId(desktopId) {
        var meta = metadataForDesktopId(desktopId);
        if (!meta)
            return { "type": "unknown", "id": "", "fullyEnforceable": false };
        return {
            "type": String(meta.sandboxType || "none"),
            "sandboxType": String(meta.sandboxType || "none"),
            "id": String(meta.sandboxId || ""),
            "sandboxId": String(meta.sandboxId || ""),
            "fullyEnforceable": meta.sandboxType === "flatpak" || meta.sandboxType === "snap",
            "writeScope": "none",
            "enforcementScope": meta.sandboxType === "flatpak" || meta.sandboxType === "snap" ? "runtime-sandbox" : "none"
        };
    }

    function defaultRow(categoryId) {
        for (var i = 0; i < root.defaultRows.length; i++) {
            if (root.defaultRows[i] && root.defaultRows[i].id === categoryId)
                return root.defaultRows[i];
        }
        return null;
    }

    function refreshDefaults() {
        if (!root.commandRunner || !root.commandRunner.appsDefaultsProbeCommand) {
            root.defaultsStatus = "missing";
            root.defaultsDetail = "CommandRunner 未注入，默认应用不可用。";
            root.defaultRows = [];
            root.revision += 1;
            return;
        }

        if (root.commandRunner.revision === 0)
            root.commandRunner.refreshDependencies();
        if (defaultsProbe.running)
            return;

        root.defaultsRefreshing = true;
        defaultsProbe.command = root.commandRunner.appsDefaultsProbeCommand();
        defaultsProbe.running = true;
    }

    function parseDefaults(text) {
        try {
            var parsed = JSON.parse(String(text || "{}"));
            root.defaultsStatus = String(parsed.status || "unknown");
            root.defaultsDetail = String(parsed.detail || "");
            root.defaultRows = parsed.categories || [];
            root.desktopMeta = parsed.desktopMeta || ({});
        } catch (e) {
            root.defaultsStatus = "error";
            root.defaultsDetail = "默认应用数据解析失败：" + String(e);
            root.defaultRows = [];
            root.desktopMeta = ({});
        }
        root.revision += 1;
    }

    function setDefaultCategory(categoryId, desktopId) {
        var row = defaultRow(categoryId);
        if (!row || !root.commandRunner || !root.commandRunner.appsSetDefaultCommand)
            return;
        if (setDefaultProcess.running)
            return;

        root.settingDefault = true;
        root.settingCategoryId = String(categoryId || "");
        root.lastActionText = "";
        setDefaultProcess.command = root.commandRunner.appsSetDefaultCommand(desktopId, row.mimes || []);
        setDefaultProcess.running = true;
    }

    function parseSetDefaultResult(text) {
        try {
            var parsed = JSON.parse(String(text || "{}"));
            root.lastActionText = String(parsed.message || "");
        } catch (e) {
            root.lastActionText = "默认应用写入结果解析失败：" + String(e);
        }
    }

    function selectApp(app) {
        var nextId = desktopIdForApp(app);
        root.selectedApp = app;
        root.selectedDesktopId = nextId;
        // Close display identity when selection changes so B never shows A's rows.
        if (String(root.permissionsOwnerDesktopId || "") !== String(nextId || ""))
            root.invalidateStalePermissionDisplay();
        root.refreshPermissions();
    }

    function clearPermissionsState(status, detail, sandbox) {
        // sandbox === null/undefined means "no sandbox object" (unselected path keeps empty capability).
        // A truthy sandbox object (including empty {}) builds capability from that sandbox.
        var hasSandbox = sandbox !== null && sandbox !== undefined;
        root.permissionsOwnerDesktopId = "";
        root.permissionStatus = status;
        root.permissionDetail = detail;
        root.permissionItems = [];
        root.staticPermissionItems = [];
        root.snapConnectionItems = [];
        root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
        root.sandboxInfo = hasSandbox ? sandbox : ({});
        root.permissionCapability = hasSandbox ? ({
            "sandboxType": sandbox.type || "unknown",
            "fullyEnforceable": sandbox.fullyEnforceable === true,
            "portalStatus": status,
            "defaultControl": "warning",
            "canTogglePortalPermissions": false,
            "writeScope": "none",
            "ordinaryAppWarning": sandbox.type === "none"
        }) : ({});
        root.revision += 1;
    }

    function invalidateStalePermissionDisplay() {
        // Selection moved away from the desktop that owns current permission* fields.
        // Clear payload immediately (AppMenu-style owner close); keep loading until latest probe lands.
        root.permissionsOwnerDesktopId = "";
        root.permissionStatus = "unknown";
        root.permissionDetail = "正在读取权限";
        root.permissionItems = [];
        root.staticPermissionItems = [];
        root.snapConnectionItems = [];
        root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
        if (root.selectedDesktopId && root.selectedDesktopId.length > 0) {
            root.sandboxInfo = sandboxForDesktopId(root.selectedDesktopId);
            root.permissionCapability = ({
                "sandboxType": root.sandboxInfo.type || "unknown",
                "fullyEnforceable": root.sandboxInfo.fullyEnforceable === true,
                "portalStatus": "unknown",
                "defaultControl": "warning",
                "canTogglePortalPermissions": false,
                "writeScope": "none",
                "ordinaryAppWarning": root.sandboxInfo.type === "none"
            });
        } else {
            root.sandboxInfo = ({});
            root.permissionCapability = ({});
        }
        root.revision += 1;
    }

    function permissionsIdentityMatches(generation, desktopId) {
        if (generation === undefined || generation === null)
            return false;
        if (Number(generation) !== Number(root.permissionsProbeGeneration))
            return false;
        if (String(desktopId || "") !== String(root.selectedDesktopId || ""))
            return false;
        return true;
    }

    function refreshPermissions() {
        if (!root.selectedDesktopId || root.selectedDesktopId.length === 0) {
            // Bump generation so any in-flight A result cannot write after clear.
            root.permissionsProbeGeneration += 1;
            root.permissionsProbePending = false;
            root.permissionsRefreshing = false;
            if (permissionsProbe.running)
                permissionsProbe.running = false;
            // null sandbox preserves historical unselected capability = {}.
            root.clearPermissionsState("unknown", "未选择应用", null);
            return;
        }
        if (!root.commandRunner || !root.commandRunner.appsPermissionsCommand) {
            root.permissionsProbeGeneration += 1;
            root.permissionsProbePending = false;
            root.permissionsRefreshing = false;
            if (permissionsProbe.running)
                permissionsProbe.running = false;
            root.clearPermissionsState(
                "missing",
                "CommandRunner 未注入，应用权限不可用。",
                sandboxForDesktopId(root.selectedDesktopId)
            );
            // missing path still owns the selected desktop's capability view.
            root.permissionsOwnerDesktopId = root.selectedDesktopId;
            return;
        }
        if (permissionsProbe.running) {
            // Discarding a newer selection permanently was the old race; keep latest pending.
            if (String(root.permissionsProbeInFlightDesktopId) !== String(root.selectedDesktopId)) {
                root.permissionsProbeGeneration += 1;
                root.permissionsProbePending = true;
                root.permissionsRefreshing = true;
                if (String(root.permissionsOwnerDesktopId || "") !== String(root.selectedDesktopId || ""))
                    root.invalidateStalePermissionDisplay();
            }
            return;
        }

        root.permissionsProbeGeneration += 1;
        root.startPermissionsProbe(root.permissionsProbeGeneration, root.selectedDesktopId);
    }

    function startPermissionsProbe(generation, desktopId) {
        // Never start a superseded generation; keep pending so a later exit can re-run latest.
        if (Number(generation) !== Number(root.permissionsProbeGeneration))
            return;
        if (String(desktopId || "") !== String(root.selectedDesktopId || ""))
            return;
        if (permissionsProbe.running) {
            root.permissionsProbePending = true;
            return;
        }

        root.permissionsProbePending = false;
        root.permissionsProbeInFlightGeneration = generation;
        root.permissionsProbeInFlightDesktopId = String(desktopId || "");
        root.permissionsStdoutText = "";
        root.permissionsStdoutGeneration = 0;
        // Freeze desktop ID into the command at start so later selection cannot rebind mid-flight.
        permissionsProbe.command = root.commandRunner.appsPermissionsCommand(desktopId);
        root.permissionsRefreshing = true;
        permissionsProbe.running = true;
    }

    function parsePermissions(text, generation, desktopId) {
        // Generation and desktop identity are mandatory: missing or stale never write permission state.
        if (!root.permissionsIdentityMatches(generation, desktopId))
            return;

        try {
            var parsed = JSON.parse(String(text || "{}"));
            root.permissionStatus = parsed.portal ? String(parsed.portal.status || "unknown") : "unknown";
            root.permissionDetail = parsed.portal ? String(parsed.portal.detail || "") : "";
            root.permissionItems = parsed.permissions || [];
            root.staticPermissionItems = parsed.staticPermissions || [];
            root.snapConnectionItems = parsed.snapConnections || [];
            root.storageInfo = parsed.storage || ({ "total": "0 B", "totalBytes": 0, "items": [] });
            root.sandboxInfo = parsed.sandbox || sandboxForDesktopId(desktopId);
            root.permissionCapability = parsed.capability || ({
                "sandboxType": root.sandboxInfo.type || "unknown",
                "fullyEnforceable": root.sandboxInfo.fullyEnforceable === true,
                "portalStatus": root.permissionStatus,
                "defaultControl": root.permissionStatus === "ok" ? "readonly" : "warning",
                "canTogglePortalPermissions": false,
                "writeScope": "none",
                "ordinaryAppWarning": root.sandboxInfo.type === "none"
            });
        } catch (e) {
            root.permissionStatus = "error";
            root.permissionDetail = "权限数据解析失败：" + String(e);
            root.permissionItems = [];
            root.staticPermissionItems = [];
            root.snapConnectionItems = [];
            root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
            root.sandboxInfo = sandboxForDesktopId(desktopId);
            root.permissionCapability = ({
                "sandboxType": root.sandboxInfo.type || "unknown",
                "fullyEnforceable": root.sandboxInfo.fullyEnforceable === true,
                "portalStatus": "error",
                "defaultControl": "warning",
                "canTogglePortalPermissions": false,
                "writeScope": "none",
                "ordinaryAppWarning": root.sandboxInfo.type === "none"
            });
        }
        root.permissionsOwnerDesktopId = String(desktopId || "");
        root.revision += 1;
    }

    function applyPermissionsFailure(code, generation, desktopId) {
        if (!root.permissionsIdentityMatches(generation, desktopId))
            return;

        var sandbox = sandboxForDesktopId(desktopId);
        root.permissionStatus = "error";
        root.permissionDetail = "权限读取失败，退出码 " + String(code);
        root.permissionItems = [];
        root.staticPermissionItems = [];
        root.snapConnectionItems = [];
        root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
        root.sandboxInfo = sandbox;
        root.permissionCapability = ({
            "sandboxType": sandbox.type || "unknown",
            "fullyEnforceable": sandbox.fullyEnforceable === true,
            "portalStatus": "error",
            "defaultControl": "warning",
            "canTogglePortalPermissions": false,
            "writeScope": "none",
            "ordinaryAppWarning": sandbox.type === "none"
        });
        root.permissionsOwnerDesktopId = String(desktopId || "");
        root.revision += 1;
    }

    function schedulePendingPermissionsProbe() {
        // Defer restart until after Process exit handling settles.
        Qt.callLater(function() {
            if (!root.permissionsProbePending)
                return;
            if (permissionsProbe.running)
                return;
            root.startPermissionsProbe(root.permissionsProbeGeneration, root.selectedDesktopId);
        });
    }

    function finishPermissionsProbe(code, generation, desktopId, text) {
        var gen = Number(generation);
        // onRunningChanged is the failed-to-start fallback. Ignore duplicate or
        // obsolete completion after onExited has already consumed this run.
        if (gen <= 0 || gen !== Number(root.permissionsProbeInFlightGeneration))
            return;
        root.permissionsProbeInFlightGeneration = 0;
        root.permissionsProbeInFlightDesktopId = "";

        if (code !== 0)
            root.applyPermissionsFailure(code, gen, desktopId);
        else
            root.parsePermissions(text, gen, desktopId);

        // Only the latest generation may clear loading; keep refreshing while a newer intent is pending.
        if (gen === Number(root.permissionsProbeGeneration) && !root.permissionsProbePending)
            root.permissionsRefreshing = false;

        if (root.permissionsProbePending)
            root.schedulePendingPermissionsProbe();
    }

    Process {
        id: defaultsProbe
        running: false
        stdout: StdioCollector {
            id: defaultsOut
            onStreamFinished: root.parseDefaults(defaultsOut.text)
        }
        onExited: function(code, exitStatus) {
            root.defaultsRefreshing = false;
            if (code !== 0) {
                root.defaultsStatus = "error";
                root.defaultsDetail = "默认应用检测失败，退出码 " + String(code);
                root.defaultRows = [];
                root.revision += 1;
            }
        }
    }

    Process {
        id: setDefaultProcess
        running: false
        stdout: StdioCollector {
            id: setDefaultOut
            onStreamFinished: root.parseSetDefaultResult(setDefaultOut.text)
        }
        onExited: function(code, exitStatus) {
            root.settingDefault = false;
            root.settingCategoryId = "";
            if (code !== 0)
                root.lastActionText = "默认应用写入失败，退出码 " + String(code);
            root.refreshDefaults();
        }
    }

    Process {
        id: permissionsProbe
        running: false
        // command is assigned in startPermissionsProbe() so desktop identity is frozen for this generation.
        command: []
        stdout: StdioCollector {
            id: permissionsOut
            onStreamFinished: {
                // Cache stdout against the in-flight generation before exit reordering.
                root.permissionsStdoutText = permissionsOut.text;
                root.permissionsStdoutGeneration = root.permissionsProbeInFlightGeneration;
            }
        }
        onExited: function(code, exitStatus) {
            // Freeze identity and payload at exit entry; never start the next probe in this stack.
            var gen = root.permissionsProbeInFlightGeneration;
            var desktopId = root.permissionsProbeInFlightDesktopId;
            var text = root.permissionsStdoutGeneration === gen
                ? root.permissionsStdoutText
                : permissionsOut.text;
            root.finishPermissionsProbe(code, gen, desktopId, text);
        }
        onRunningChanged: {
            // QuickShell Process does not emit exited when QProcess fails to start.
            // In that path runningChanged is the only completion signal.
            if (!permissionsProbe.running && root.permissionsProbeInFlightGeneration > 0)
                root.finishPermissionsProbe(-1, root.permissionsProbeInFlightGeneration, root.permissionsProbeInFlightDesktopId, "");
        }
    }

    Connections {
        target: root.commandRunner
        function onRevisionChanged() {
            root.refreshDefaults();
        }
    }

    Connections {
        target: root.appsService
        function onDesktopEntriesRevisionChanged() {
            root.refreshDefaults();
        }
    }

    Component.onCompleted: root.refreshDefaults()
}
