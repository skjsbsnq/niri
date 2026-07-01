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
    property string permissionStatus: "unknown"
    property string permissionDetail: "尚未读取权限"
    property bool permissionsRefreshing: false
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
            "id": String(meta.sandboxId || ""),
            "fullyEnforceable": meta.sandboxType === "flatpak" || meta.sandboxType === "snap"
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
        root.selectedApp = app;
        root.selectedDesktopId = desktopIdForApp(app);
        root.refreshPermissions();
    }

    function refreshPermissions() {
        if (!root.selectedDesktopId || root.selectedDesktopId.length === 0) {
            root.permissionStatus = "unknown";
            root.permissionDetail = "未选择应用";
            root.permissionItems = [];
            root.staticPermissionItems = [];
            root.snapConnectionItems = [];
            root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
            root.sandboxInfo = ({});
            root.revision += 1;
            return;
        }
        if (!root.commandRunner || !root.commandRunner.appsPermissionsCommand) {
            root.permissionStatus = "missing";
            root.permissionDetail = "CommandRunner 未注入，应用权限不可用。";
            root.permissionItems = [];
            root.staticPermissionItems = [];
            root.snapConnectionItems = [];
            root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
            root.sandboxInfo = sandboxForDesktopId(root.selectedDesktopId);
            root.revision += 1;
            return;
        }
        if (permissionsProbe.running)
            return;

        root.permissionsRefreshing = true;
        permissionsProbe.command = root.commandRunner.appsPermissionsCommand(root.selectedDesktopId);
        permissionsProbe.running = true;
    }

    function parsePermissions(text) {
        try {
            var parsed = JSON.parse(String(text || "{}"));
            root.permissionStatus = parsed.portal ? String(parsed.portal.status || "unknown") : "unknown";
            root.permissionDetail = parsed.portal ? String(parsed.portal.detail || "") : "";
            root.permissionItems = parsed.permissions || [];
            root.staticPermissionItems = parsed.staticPermissions || [];
            root.snapConnectionItems = parsed.snapConnections || [];
            root.storageInfo = parsed.storage || ({ "total": "0 B", "totalBytes": 0, "items": [] });
            root.sandboxInfo = parsed.sandbox || sandboxForDesktopId(root.selectedDesktopId);
        } catch (e) {
            root.permissionStatus = "error";
            root.permissionDetail = "权限数据解析失败：" + String(e);
            root.permissionItems = [];
            root.staticPermissionItems = [];
            root.snapConnectionItems = [];
            root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
            root.sandboxInfo = sandboxForDesktopId(root.selectedDesktopId);
        }
        root.revision += 1;
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
        stdout: StdioCollector {
            id: permissionsOut
            onStreamFinished: root.parsePermissions(permissionsOut.text)
        }
        onExited: function(code, exitStatus) {
            root.permissionsRefreshing = false;
            if (code !== 0) {
                root.permissionStatus = "error";
                root.permissionDetail = "权限读取失败，退出码 " + String(code);
                root.permissionItems = [];
                root.staticPermissionItems = [];
                root.snapConnectionItems = [];
                root.storageInfo = ({ "total": "0 B", "totalBytes": 0, "items": [] });
                root.sandboxInfo = root.sandboxForDesktopId(root.selectedDesktopId);
                root.revision += 1;
            }
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
