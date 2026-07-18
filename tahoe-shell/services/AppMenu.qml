pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var windowsService
    property var appsService
    property var commandRunner
    property bool registrarAvailable: false
    property string registrarOwner: ""
    property bool probing: false
    property var nativeMenuItems: []
    // Stable QtObject cache for nativeMenuItems so ScriptModel objectProp reuse
    // survives refresh() without rebuilding every MenuRow delegate (R06 #19).
    property var nativeMenuItemCache: Object.create(null)

    property string nativeMenuService: ""
    property string nativeMenuPath: ""
    property string nativeMenuStatus: "尚未检测"
    property string nativeMenuDetail: ""
    // Monotonic request generation for the single probe pipeline.
    // probeGeneration: latest refresh intent; probeInFlightGeneration: running Process.
    // probePending: newest intent arrived while Process was still running.
    // probeStdout* caches the collector output for the in-flight generation only.
    property int probeGeneration: 0
    property int probeInFlightGeneration: 0
    property string probeTargetIdentity: ""
    property string probeInFlightIdentity: ""
    property string menuOwnerIdentity: ""
    property bool probePending: false
    property string probeStdoutText: ""
    property int probeStdoutGeneration: 0

    Component {
        id: nativeMenuItemFactory

        QtObject {
            property string modelKey: ""
            property int itemId: -1
            property string text: ""
            property string kind: "item"
            property bool enabled: true
            property int indent: 0
            property string group: ""
            property string icon: ""
            property string toggleType: ""
            property bool checked: false
            property bool hasChildren: false
            // Compat for older tests that read label.
            property string label: ""
        }
    }

    readonly property var focusedWindow: windowsService ? windowsService.focusedWindow : null
    readonly property string activeTitle: appsService ? appsService.windowAppLabel(focusedWindow) : "桌面"
    readonly property string activeWindowTitle: appsService ? appsService.toplevelLabel(focusedWindow) : "桌面"
    readonly property string activeAppId: focusedWindow ? String(focusedWindow.appId || "") : ""
    readonly property string activePid: focusedWindow && focusedWindow.pid !== undefined && focusedWindow.pid !== null ? String(focusedWindow.pid) : ""
    readonly property string activeWindowId: focusedWindow && focusedWindow.id !== undefined && focusedWindow.id !== null ? String(focusedWindow.id) : ""
    readonly property bool hasFocusedWindow: !!focusedWindow
    readonly property bool nativeMenuAvailable: menuOwnerIdentity === probeTargetIdentity
        && nativeMenuItems && nativeMenuItems.length > 0
    readonly property string menuTitle: hasFocusedWindow ? "应用菜单" : "桌面"
    readonly property string menuStatusText: nativeMenuAvailable
        ? nativeMenuDetail
        : nativeMenuStatus

    // explicitDemand: menu open / registrar recovery / other freshness requests that
    // must not be swallowed by a same-identity in-flight health/focus probe.
    // Optional argument keeps a single refresh() entry (no demandRefresh parallel API).
    function refresh(explicitDemand) {
        var demand = !!explicitDemand;
        var targetIdentity = JSON.stringify([activeWindowId, activePid, activeAppId]);
        var targetChanged = targetIdentity !== probeTargetIdentity;
        if (targetChanged) {
            probeTargetIdentity = targetIdentity;
            if (menuOwnerIdentity !== targetIdentity) {
                menuOwnerIdentity = "";
                nativeMenuService = "";
                nativeMenuPath = "";
                nativeMenuItems = root.clearNativeMenuItems();
                nativeMenuStatus = "正在检测";
                nativeMenuDetail = "";
            }
        }

        if (commandRunner && commandRunner.revision === 0)
            commandRunner.refreshDependencies();

        if (commandRunner && commandRunner.revision > 0 && commandRunner.dependency) {
            var appmenuDependency = commandRunner.dependency("appmenu");
            var appmenuState = appmenuDependency ? String(appmenuDependency.state || "") : "";
            if (appmenuState === "missing" || appmenuState === "broken") {
                // Bump generation so any in-flight probe cannot overwrite this sync result.
                probeGeneration += 1;
                probePending = false;
                probing = false;
                if (probe.running)
                    probe.running = false;
                applyProbe(JSON.stringify({
                    "status": "应用菜单不可用",
                    "detail": String(appmenuDependency.detail || "") + (appmenuDependency.action ? "；" + String(appmenuDependency.action) : "")
                }), probeGeneration, targetIdentity);
                return;
            }
        }

        if (commandRunner && commandRunner.revision > 0 && commandRunner.missingCommands) {
            var missing = commandRunner.missingCommands(["python3", "busctl"]);
            if (missing.length > 0) {
                probeGeneration += 1;
                probePending = false;
                probing = false;
                if (probe.running)
                    probe.running = false;
                applyProbe("{\"status\":\"应用菜单不可用\",\"detail\":\"缺少 " + missing.join(" ") + "\"}", probeGeneration, targetIdentity);
                return;
            }
        }

        // Window services may replace the focused object without changing the
        // stable target identity. Keep an already-applied result in that case.
        if (!demand
                && !targetChanged
                && !probe.running
                && menuOwnerIdentity === targetIdentity)
            return;

        if (probe.running) {
            // Same-identity health/focus probes may coalesce into the in-flight run.
            // Explicit demand (menu open) and target changes must supersede that run so
            // a probe that already read a stale snapshot cannot become the final menu.
            // Multiple same-identity demands collapse to one pending follow-up generation.
            if (targetChanged || demand) {
                if (!probePending || targetChanged)
                    probeGeneration += 1;
                probePending = true;
            }
            return;
        }

        probeGeneration += 1;
        startProbe(probeGeneration, targetIdentity);
    }

    function startProbe(generation, identity) {
        // Never start a superseded generation; keep pending so a later exit can re-run latest.
        if (Number(generation) !== Number(probeGeneration))
            return;
        if (String(identity) !== probeTargetIdentity)
            return;
        if (probe.running) {
            probePending = true;
            return;
        }

        probePending = false;
        probeInFlightGeneration = generation;
        probeInFlightIdentity = identity;
        probeStdoutText = "";
        probeStdoutGeneration = 0;
        // Capture command args at start so a later focus change cannot rebind identity mid-flight.
        probe.command = root.commandRunner && root.commandRunner.appMenuProbeCommand
            ? root.commandRunner.appMenuProbeCommand(
                root.activeWindowId,
                root.activePid,
                root.activeAppId,
                root.activeWindowTitle
            )
            : [
                "python3",
                Quickshell.shellPath("services/appmenu_probe.py"),
                root.activeWindowId,
                root.activePid,
                root.activeAppId,
                root.activeWindowTitle
            ];
        probing = true;
        probe.running = true;
    }

    function applyProbe(text, generation, identity) {
        // Generation is mandatory: missing or stale generations never write menu state.
        if (generation === undefined || generation === null)
            return;
        if (Number(generation) !== Number(probeGeneration))
            return;
        if (String(identity) !== probeTargetIdentity)
            return;

        var fallback = {
            "registrarAvailable": false,
            "registrarOwner": "",
            "menuService": "",
            "menuPath": "",
            "items": [],
            "status": "应用菜单检测失败",
            "detail": ""
        };
        var parsed = fallback;

        try {
            var raw = String(text || "").trim();
            if (raw.length > 0)
                parsed = JSON.parse(raw);
        } catch (error) {
            parsed = fallback;
            parsed.detail = String(error);
        }

        registrarOwner = String(parsed.registrarOwner || "");
        registrarAvailable = !!parsed.registrarAvailable || registrarOwner.length > 0;
        nativeMenuService = String(parsed.menuService || "");
        nativeMenuPath = String(parsed.menuPath || "");
        nativeMenuItems = root.mergeNativeMenuItems(Array.isArray(parsed.items) ? parsed.items : []);
        nativeMenuStatus = String(parsed.status || "");
        nativeMenuDetail = String(parsed.detail || "");
        menuOwnerIdentity = identity;
    }

    function schedulePendingProbe() {
        // Defer restart until after Process exit handling settles (same pattern as Search.qml).
        Qt.callLater(function() {
            if (!root.probePending)
                return;
            if (probe.running)
                return;
            root.startProbe(root.probeGeneration, root.probeTargetIdentity);
        });
    }

    function finishProbe(code, generation, identity, text) {
        // Apply success/error with the generation frozen at exit entry.
        var gen = Number(generation);
        // onRunningChanged is the failed-to-start fallback.  Ignore duplicate or
        // obsolete completion signals after onExited has already consumed this run.
        if (gen <= 0 || gen !== Number(probeInFlightGeneration))
            return;
        probeInFlightGeneration = 0;
        probeInFlightIdentity = "";
        if (code !== 0)
            applyProbe("{\"status\":\"应用菜单检测失败\",\"detail\":\"helper exit " + String(code) + "\"}", gen, identity);
        else
            applyProbe(text, gen, identity);

        // Only the latest generation may clear loading; keep probing while a newer intent is pending.
        if (gen === Number(probeGeneration) && !probePending)
            probing = false;

        // Unified pending re-run for both stale and latest exits (deferred; never re-enter Process here).
        if (probePending)
            schedulePendingProbe();
    }


    function nativeMenuModelKey(item) {
        var kind = String(item && item.kind || "item");
        var rawId = item && item.itemId !== undefined && item.itemId !== null
            ? item.itemId
            : (item && item.id !== undefined && item.id !== null ? item.id : "");
        var id = String(rawId);
        var text = String(item && (item.text || item.label) || "");
        var indent = String(item && item.indent !== undefined ? item.indent : 0);
        if (kind === "separator")
            return "sep:" + indent + ":" + id + ":" + text;
        if (kind === "header")
            return "hdr:" + indent + ":" + id + ":" + text;
        return "item:" + indent + ":" + id + ":" + text;
    }

    function clearNativeMenuItems() {
        var cache = root.nativeMenuItemCache || Object.create(null);
        for (var key in cache) {
            var entry = cache[key];
            if (entry && entry.destroy)
                entry.destroy(1000);
        }
        root.nativeMenuItemCache = Object.create(null);
        return [];
    }

    function mergeNativeMenuItems(rawItems) {
        var list = Array.isArray(rawItems) ? rawItems : [];
        var cache = root.nativeMenuItemCache || Object.create(null);
        var nextCache = Object.create(null);
        var result = [];

        for (var i = 0; i < list.length; i++) {
            var raw = list[i] || {};
            // Normalize probe payloads that still use label instead of text.
            if ((raw.text === undefined || raw.text === null || String(raw.text).length === 0)
                    && raw.label !== undefined && raw.label !== null)
                raw = {
                    "id": raw.id,
                    "text": raw.label,
                    "kind": raw.kind,
                    "enabled": raw.enabled,
                    "indent": raw.indent,
                    "group": raw.group,
                    "icon": raw.icon,
                    "toggleType": raw.toggleType,
                    "checked": raw.checked,
                    "hasChildren": raw.hasChildren,
                    "label": raw.label
                };
            var key = root.nativeMenuModelKey(raw);
            var entry = cache[key];
            if (!entry) {
                entry = nativeMenuItemFactory.createObject(root);
                if (!entry)
                    continue;
            }
            entry.modelKey = key;
            entry.itemId = raw.id !== undefined && raw.id !== null ? Number(raw.id) : -1;
            entry.text = String(raw.text || raw.label || "");
            entry.kind = String(raw.kind || "item");
            entry.enabled = raw.enabled === undefined ? true : !!raw.enabled;
            entry.indent = Math.max(0, Number(raw.indent || 0));
            entry.group = String(raw.group || "");
            entry.icon = String(raw.icon || "");
            entry.toggleType = String(raw.toggleType || "");
            entry.checked = !!raw.checked;
            entry.hasChildren = !!raw.hasChildren;
            entry.label = entry.text;
            nextCache[key] = entry;
            result.push(entry);
        }

        for (var oldKey in cache) {
            if (!nextCache[oldKey]) {
                var stale = cache[oldKey];
                if (stale && stale.destroy)
                    stale.destroy(1000);
            }
        }
        root.nativeMenuItemCache = nextCache;
        return result;
    }

    function activateNativeItem(item) {
        if (!item || !nativeMenuAvailable || nativeMenuService.length === 0 || nativeMenuPath.length === 0)
            return;
        if (item.kind !== "item" || !item.enabled)
            return;
        if (trigger.running)
            return;

        if (commandRunner && commandRunner.revision > 0 && commandRunner.missingCommands) {
            var missing = commandRunner.missingCommands(["busctl"]);
            if (missing.length > 0) {
                nativeMenuStatus = "应用菜单动作不可用";
                nativeMenuDetail = "缺少 " + missing.join(" ");
                return;
            }
        }

        var itemId = item.itemId !== undefined && item.itemId !== null ? item.itemId : item.id;
        trigger.command = commandRunner && commandRunner.appMenuTriggerCommand
            ? commandRunner.appMenuTriggerCommand(nativeMenuService, nativeMenuPath, itemId)
            : [
                "busctl",
                "--user",
                "call",
                nativeMenuService,
                nativeMenuPath,
                "com.canonical.dbusmenu",
                "Event",
                "isvu",
                String(itemId),
                "clicked",
                "i",
                "0",
                "0"
            ];
        trigger.running = true;
    }

    function pinFocusedApp() {
        if (appsService && focusedWindow)
            appsService.pinWindow(focusedWindow);
    }

    function minimizeFocusedWindow() {
        if (windowsService && focusedWindow)
            windowsService.minimize(focusedWindow);
    }

    function activateFocusedWindow() {
        if (windowsService && focusedWindow)
            windowsService.activate(focusedWindow);
    }

    Process {
        id: probe
        running: false
        // command is assigned in startProbe() so identity is frozen for this generation.
        command: []
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: {
                // Cache stdout against the in-flight generation before exit reordering.
                root.probeStdoutText = probeOut.text;
                root.probeStdoutGeneration = root.probeInFlightGeneration;
            }
        }
        onExited: function(code, exitStatus) {
            // Freeze identity and payload at exit entry; never start the next probe in this stack.
            var gen = root.probeInFlightGeneration;
            var identity = root.probeInFlightIdentity;
            var text = root.probeStdoutGeneration === gen
                ? root.probeStdoutText
                : probeOut.text;
            root.finishProbe(code, gen, identity, text);
        }
        onRunningChanged: {
            // QuickShell Process does not emit exited when QProcess fails to start.
            // In that path runningChanged is the only completion signal.
            if (!probe.running && root.probeInFlightGeneration > 0)
                root.finishProbe(-1, root.probeInFlightGeneration, root.probeInFlightIdentity, "");
        }
    }

    Process {
        id: trigger
        running: false
    }

    // Recovery-only probe: catch registrar appear/disappear or dependency
    // recovery while idle. Must not be a high-rate authority path (old 5s
    // poll ≈ 720 Python/D-Bus starts per idle hour). Primary drivers remain
    // focused-window identity, menu open (AppMenuPopup), and initial load —
    // all still call the single Task-03 refresh()/probe generation pipeline.
    Timer {
        id: healthRecoveryTimer
        interval: 300000
        running: true
        repeat: true
        onTriggered: root.refresh(true)
    }

    onFocusedWindowChanged: root.refresh()

    Component.onCompleted: root.refresh()
}
