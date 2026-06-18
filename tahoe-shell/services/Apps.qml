pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property string assetRoot: Quickshell.shellPath("assets")
    readonly property string backgroundRoot: assetRoot + "/backgrounds/"
    readonly property string dockIconRoot: assetRoot + "/icons/dock/"
    readonly property string launchpadIconRoot: assetRoot + "/icons/launchpad/"
    readonly property string symbolIconRoot: assetRoot + "/icons/symbols/"
    readonly property string defaultWindowIcon: dockIconRoot + "finder.png"
    readonly property string wallpaper: backgroundRoot + "iridescence.jpg"
    readonly property string pinnedConfigPath: Quickshell.stateDir + "/pinned-apps.json"
    // Older builds wrote user pins into the deployed QML directory. That path
    // can be wiped by rsync --delete during updates, so it is only a migration
    // source now.
    readonly property string legacyPinnedPath: configHome() + "/quickshell/tahoe/pinned-apps.json"

    readonly property var realApplications: [...DesktopEntries.applications.values].filter(isLaunchableApplication).sort(compareApplications)
    property bool pinnedInitialized: false
    property bool migratedLegacyConfig: false
    property bool loadingPinnedState: false
    property var pinnedIds: []
    property int pinnedRevision: 0
    readonly property var pinnedApps: buildPinnedApps(pinnedRevision)
    readonly property var launchpadApps: realApplications

    FileView {
        id: legacyPinnedFile
        path: root.legacyPinnedPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: pinnedFile
        path: root.pinnedConfigPath
        preload: false
        blockLoading: true
        blockAllReads: true
        blockWrites: true
        watchChanges: true
        onFileChanged: {
            reload();
            waitForJob();
            root.loadPinnedState();
        }
        onLoaded: root.loadPinnedState()
        onLoadFailed: root.loadPinnedState()
    }

    Component.onCompleted: loadPinnedState()

    function envString(name) {
        var value = Quickshell.env(name);
        return value === undefined || value === null ? "" : String(value);
    }

    function configHome() {
        var xdg = envString("XDG_CONFIG_HOME").trim();
        if (xdg.length > 0)
            return xdg;

        var home = envString("HOME").trim();
        return home.length > 0 ? home + "/.config" : Quickshell.stateDir;
    }

    function iconPath(iconSet, fileName) {
        if (!fileName || fileName.length === 0)
            return defaultWindowIcon;

        if (iconSet === "launchpad")
            return launchpadIconRoot + fileName;
        if (iconSet === "symbols")
            return symbolIconRoot + fileName;

        return dockIconRoot + fileName;
    }

    function themedIconPath(iconName) {
        var name = String(iconName || "").trim();
        if (name.length === 0)
            return "";

        if (name.charAt(0) === "/")
            return name;

        var themed = Quickshell.iconPath(name, true);
        return themed && themed.length > 0 ? themed : "";
    }

    function desktopEntryIcon(app) {
        if (!app)
            return "";

        if (app.desktopEntry)
            app = app.desktopEntry;

        return themedIconPath(app.icon || "");
    }

    function iconForApp(app) {
        if (!app)
            return defaultWindowIcon;

        if (app.desktopEntry)
            app = app.desktopEntry;

        var desktopIcon = desktopEntryIcon(app);
        if (desktopIcon.length > 0)
            return desktopIcon;

        if (app.iconSet)
            return iconPath(app.iconSet, app.icon || "");

        return iconForAppId(app.id || app.startupClass || app.name || "");
    }

    function appLabel(app) {
        if (!app)
            return "应用";

        if (app.desktopEntry)
            app = app.desktopEntry;

        function hasCJK(text) {
            return /[\u4e00-\u9fff]/.test(String(text || ""));
        }

        var primary = String(app.name || "").trim();
        var generic = String(app.genericName || "").trim();
        if (hasCJK(generic) && !hasCJK(primary))
            return generic;
        if (primary.length > 0)
            return primary;
        if (generic.length > 0)
            return generic;

        var id = String(app.id || "").trim();
        return id.length > 0 ? id : "应用";
    }

    function appSearchText(app) {
        if (!app)
            return "";

        if (app.desktopEntry)
            app = app.desktopEntry;

        var parts = [
            appLabel(app),
            app.id || "",
            app.genericName || "",
            app.startupClass || "",
            app.execString || ""
        ];

        if (app.categories)
            parts.push(String(app.categories));
        if (app.keywords)
            parts.push(String(app.keywords));

        return parts.join(" ").toLowerCase();
    }

    function appMatchesQuery(app, query) {
        var normalized = String(query || "").trim().toLowerCase();
        if (normalized.length === 0)
            return true;

        var haystack = appSearchText(app);
        var terms = normalized.split(/\s+/);
        for (var i = 0; i < terms.length; i++) {
            if (terms[i].length > 0 && haystack.indexOf(terms[i]) === -1)
                return false;
        }

        return true;
    }

    function appInCategory(app, category) {
        var normalized = String(category || "all").trim().toLowerCase();
        if (normalized.length === 0 || normalized === "all")
            return true;

        if (!app)
            return false;
        if (app.desktopEntry)
            app = app.desktopEntry;

        var categories = String(app.categories || "").toLowerCase();
        if (normalized === "development")
            return categories.indexOf("development") !== -1;
        if (normalized === "internet")
            return categories.indexOf("network") !== -1;
        if (normalized === "media")
            return categories.indexOf("audio") !== -1
                || categories.indexOf("video") !== -1
                || categories.indexOf("graphics") !== -1;
        if (normalized === "office")
            return categories.indexOf("office") !== -1;
        if (normalized === "games")
            return categories.indexOf("game") !== -1;
        if (normalized === "system")
            return categories.indexOf("system") !== -1
                || categories.indexOf("settings") !== -1
                || categories.indexOf("utility") !== -1;

        return true;
    }

    function filteredLaunchpadApps(query, category) {
        var normalized = String(query || "").trim();
        return launchpadApps.filter(function(app) {
            return appMatchesQuery(app, normalized) && appInCategory(app, category);
        });
    }

    function spotlightResults(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0)
            return [];

        var max = Math.max(1, limit || 6);
        var result = [];
        for (var i = 0; i < realApplications.length && result.length < max; i++) {
            if (appMatchesQuery(realApplications[i], normalized))
                result.push(realApplications[i]);
        }

        return result;
    }

    function iconForAppId(appId) {
        var raw = String(appId || "").trim();
        var normalized = raw.toLowerCase();

        var app = findApplication([
            raw,
            normalized,
            normalizedAppToken(raw)
        ]);
        var appIcon = desktopEntryIcon(app);
        if (appIcon.length > 0)
            return appIcon;

        if (normalized.indexOf("code") !== -1 || normalized.indexOf("vscodium") !== -1)
            return dockIconRoot + "vscode.png";
        if (normalized.indexOf("terminal") !== -1 || normalized.indexOf("alacritty") !== -1 || normalized.indexOf("kitty") !== -1 || normalized.indexOf("foot") !== -1 || normalized.indexOf("wezterm") !== -1)
            return dockIconRoot + "terminal.png";
        if (normalized.indexOf("nautilus") !== -1 || normalized.indexOf("thunar") !== -1 || normalized.indexOf("dolphin") !== -1 || normalized.indexOf("files") !== -1)
            return dockIconRoot + "finder.png";
        if (normalized.indexOf("settings") !== -1 || normalized.indexOf("control") !== -1 || normalized.indexOf("systemsettings") !== -1)
            return dockIconRoot + "preferences.png";

        var themed = themedIconPath(raw);
        if (themed.length > 0)
            return themed;

        return defaultWindowIcon;
    }

    function iconForToplevel(toplevel) {
        if (!toplevel)
            return defaultWindowIcon;

        return iconForAppId(toplevel.appId || "");
    }

    function toplevelLabel(toplevel) {
        if (!toplevel)
            return "桌面";

        var title = String(toplevel.title || "").trim();
        if (title.length > 0)
            return title;

        var appId = String(toplevel.appId || "").trim();
        return appId.length > 0 ? appId : "窗口";
    }

    function launchApp(app) {
        if (!app)
            return;

        if (app.desktopEntry)
            app = app.desktopEntry;

        if (app.execute) {
            app.execute();
            return;
        }

        if (!app.command || app.command.length === 0)
            return;

        Quickshell.execDetached({
            command: app.command,
            workingDirectory: app.workingDirectory || ""
        });
    }

    function appStableId(app) {
        if (!app)
            return "";
        if (app.desktopEntry)
            app = app.desktopEntry;

        var id = String(app.id || "").trim();
        if (id.length > 0)
            return id;
        var startup = String(app.startupClass || "").trim();
        if (startup.length > 0)
            return startup;
        var name = String(app.name || "").trim();
        return name;
    }

    function sanitizedPinnedIds(values) {
        var result = [];
        var seen = {};
        var list = Array.isArray(values) ? values : [];
        for (var i = 0; i < list.length; i++) {
            var id = String(list[i] || "").trim();
            if (id.length === 0 || seen[id])
                continue;
            seen[id] = true;
            result.push(id);
        }
        return result;
    }

    function mergePinnedIds(baseValues, extraValues) {
        var result = [];
        var seen = {};

        function add(value) {
            var id = String(value || "").trim();
            var key = normalizedAppToken(id);
            if (id.length === 0 || key.length === 0 || seen[key])
                return;

            seen[key] = true;
            result.push(id);
        }

        var base = sanitizedPinnedIds(baseValues);
        var extra = sanitizedPinnedIds(extraValues);
        for (var i = 0; i < base.length; i++)
            add(base[i]);
        for (var j = 0; j < extra.length; j++)
            add(extra[j]);

        return result;
    }

    function defaultPinnedIds() {
        var ids = [];
        var seen = {};

        function add(app) {
            var id = appStableId(app);
            if (id.length === 0 || seen[id])
                return;
            seen[id] = true;
            ids.push(id);
        }

        add(findApplication([
            "org.gnome.Nautilus",
            "nautilus",
            "org.kde.dolphin",
            "dolphin",
            "thunar",
            "pcmanfm",
            "files"
        ]));
        add(findApplication([
            "org.wezfurlong.wezterm",
            "wezterm",
            "org.gnome.Console",
            "kgx",
            "org.gnome.Terminal",
            "gnome-terminal",
            "org.kde.konsole",
            "konsole",
            "Alacritty",
            "alacritty",
            "kitty",
            "foot",
            "terminal"
        ]));
        add(findApplication([
            "firefox",
            "org.mozilla.firefox",
            "chromium",
            "google-chrome",
            "brave-browser",
            "browser"
        ]));
        add(findApplication([
            "org.gnome.Settings",
            "gnome-control-center",
            "systemsettings",
            "xfce4-settings-manager",
            "settings"
        ]));

        return ids;
    }

    function configuredPinnedIds() {
        var ids = sanitizedPinnedIds(pinnedIds);
        if (pinnedInitialized)
            return ids;

        if (ids.length > 0)
            return ids;

        var legacy = legacyPinnedIds();
        return legacy.length > 0 ? legacy : defaultPinnedIds();
    }

    function setPinnedIds(ids) {
        pinnedInitialized = true;
        migratedLegacyConfig = true;
        pinnedIds = sanitizedPinnedIds(ids);
        writePinnedState();
        bumpPinnedRevision();
    }

    function bumpPinnedRevision() {
        pinnedRevision += 1;
    }

    function readPinnedState() {
        try {
            var text = pinnedFile.text();
            if (!text || String(text).trim().length === 0)
                return null;

            var parsed = JSON.parse(String(text));
            return {
                "initialized": !!(parsed && parsed.initialized),
                "migratedLegacyConfig": !!(parsed && parsed.migratedLegacyConfig),
                "pinned": sanitizedPinnedIds(parsed && parsed.pinned ? parsed.pinned : [])
            };
        } catch (e) {
            return null;
        }
    }

    function loadPinnedState() {
        if (loadingPinnedState)
            return;

        loadingPinnedState = true;
        try {
            var state = readPinnedState();
            if (state) {
                pinnedInitialized = state.initialized || state.pinned.length > 0;
                migratedLegacyConfig = state.migratedLegacyConfig;
                pinnedIds = state.pinned;
            } else {
                pinnedInitialized = false;
                migratedLegacyConfig = false;
                pinnedIds = [];
            }

            ensurePinnedDefaults();
            bumpPinnedRevision();
        } finally {
            loadingPinnedState = false;
        }
    }

    function writePinnedState() {
        pinnedFile.setText(JSON.stringify({
            "initialized": pinnedInitialized,
            "migratedLegacyConfig": migratedLegacyConfig,
            "pinned": sanitizedPinnedIds(pinnedIds)
        }, null, 4) + "\n");
    }

    function legacyPinnedIds() {
        try {
            var text = legacyPinnedFile.text();
            if (!text || String(text).trim().length === 0)
                return [];

            var parsed = JSON.parse(String(text));
            return sanitizedPinnedIds(parsed && parsed.pinned ? parsed.pinned : []);
        } catch (e) {
            return [];
        }
    }

    function ensurePinnedDefaults() {
        if (!migratedLegacyConfig) {
            var current = sanitizedPinnedIds(pinnedIds);
            var legacyIds = legacyPinnedIds();
            if (legacyIds.length > 0) {
                setPinnedIds(mergePinnedIds(current, legacyIds));
                return;
            }

            migratedLegacyConfig = true;
        }

        if (!pinnedInitialized) {
            var existing = sanitizedPinnedIds(pinnedIds);
            if (existing.length > 0) {
                setPinnedIds(existing);
                return;
            }

            var legacy = legacyPinnedIds();
            setPinnedIds(legacy.length > 0 ? legacy : defaultPinnedIds());
        } else {
            writePinnedState();
        }
    }

    function isPinnedId(id) {
        id = String(id || "").trim();
        if (id.length === 0)
            return false;

        var ids = configuredPinnedIds();
        for (var i = 0; i < ids.length; i++) {
            if (normalizedAppToken(ids[i]) === normalizedAppToken(id))
                return true;
        }
        return false;
    }

    function isPinnedApp(app) {
        return isPinnedId(appStableId(app));
    }

    function pinAppId(id) {
        id = String(id || "").trim();
        if (id.length === 0 || isPinnedId(id))
            return;

        var ids = configuredPinnedIds().slice();
        ids.push(id);
        setPinnedIds(ids);
    }

    function pinApp(app) {
        if (!isLaunchableApplication(app))
            return;

        var id = appStableId(app);
        pinAppId(id);
    }

    function unpinApp(app) {
        var id = appStableId(app);
        if (id.length === 0)
            return;

        var target = normalizedAppToken(id);
        var ids = configuredPinnedIds();
        var next = [];
        for (var i = 0; i < ids.length; i++) {
            if (normalizedAppToken(ids[i]) !== target)
                next.push(ids[i]);
        }
        setPinnedIds(next);
    }

    function togglePinnedApp(app) {
        if (isPinnedApp(app))
            unpinApp(app);
        else
            pinApp(app);
    }

    function pinWindow(window) {
        if (!window)
            return;

        var appId = String(window.appId || window.app_id || "").trim();
        if (appId.length === 0 && window.toplevel)
            appId = String(window.toplevel.appId || window.toplevel.app_id || "").trim();
        var title = String(window.title || "").trim();
        if (title.length === 0 && window.toplevel)
            title = String(window.toplevel.title || "").trim();

        var app = findApplication([
            appId,
            normalizedAppToken(appId),
            appId + ".desktop",
            title
        ]);
        if (app) {
            pinApp(app);
            return;
        }

        pinAppId(appId);
    }

    function movePinnedApp(fromIndex, toIndex) {
        // Dock index 0 is the always-present Launchpad item. Persisted pins
        // start at visual index 1.
        var from = Number(fromIndex) - 1;
        var to = Number(toIndex) - 1;
        var ids = configuredPinnedIds().slice();
        if (from < 0 || to < 0 || from >= ids.length || to >= ids.length || from === to)
            return;

        var moved = ids.splice(from, 1)[0];
        ids.splice(to, 0, moved);
        setPinnedIds(ids);
    }

    function localPathFromDropUrl(url) {
        var text = String(url || "");
        if (text.indexOf("file://") === 0)
            return decodeURIComponent(text.replace(/^file:\/\//, ""));
        return text;
    }

    function openFilesWithApp(app, urls) {
        if (!app || !urls || urls.length === 0)
            return;

        if (app.desktopEntry)
            app = app.desktopEntry;

        var paths = [];
        for (var i = 0; i < urls.length; i++) {
            var path = localPathFromDropUrl(urls[i]);
            if (path.length > 0)
                paths.push(path);
        }
        if (paths.length === 0)
            return;

        if (app.command && app.command.length > 0) {
            Quickshell.execDetached({
                command: app.command.concat(paths),
                workingDirectory: app.workingDirectory || ""
            });
            return;
        }

        for (var j = 0; j < paths.length; j++)
            Quickshell.execDetached({ command: ["xdg-open", paths[j]] });
    }

    function normalizedAppToken(value) {
        var token = String(value || "").trim().toLowerCase();
        if (token.length === 0)
            return "";

        token = token.replace(/^application:\/\//, "");
        token = token.replace(/\\/g, "/");

        var slashIndex = token.lastIndexOf("/");
        if (slashIndex !== -1)
            token = token.substring(slashIndex + 1);

        token = token.replace(/\.desktop$/, "");
        return token;
    }

    function addAppToken(tokens, seen, value) {
        var token = normalizedAppToken(value);
        if (token.length === 0 || seen[token])
            return;

        seen[token] = true;
        tokens.push(token);

        var dotIndex = token.lastIndexOf(".");
        if (dotIndex !== -1 && dotIndex + 1 < token.length)
            addAppToken(tokens, seen, token.substring(dotIndex + 1));
    }

    function firstExecToken(execString) {
        var text = String(execString || "").trim();
        if (text.length === 0)
            return "";

        var pieces = text.split(/\s+/);
        for (var i = 0; i < pieces.length; i++) {
            var piece = pieces[i];
            if (piece.indexOf("=") !== -1 || piece === "env")
                continue;

            return piece;
        }

        return pieces.length > 0 ? pieces[0] : "";
    }

    function appIdentityTokens(app) {
        var tokens = [];
        var seen = {};

        if (!app)
            return tokens;

        if (app.desktopEntry)
            app = app.desktopEntry;

        addAppToken(tokens, seen, app.id || "");
        addAppToken(tokens, seen, app.startupClass || "");
        addAppToken(tokens, seen, app.name || "");

        if (app.command && app.command.length > 0)
            addAppToken(tokens, seen, app.command[0]);

        addAppToken(tokens, seen, firstExecToken(app.execString || ""));

        return tokens;
    }

    function tokensReferToSameApp(left, right) {
        if (left === right)
            return true;

        var leftSuffix = "." + right;
        var rightSuffix = "." + left;

        return (left.indexOf(".") !== -1 && left.slice(-leftSuffix.length) === leftSuffix)
            || (right.indexOf(".") !== -1 && right.slice(-rightSuffix.length) === rightSuffix);
    }

    function appMatchesToplevel(app, toplevel) {
        if (!app || !toplevel)
            return false;

        var toplevelAppId = normalizedAppToken(toplevel.appId || "");
        if (toplevelAppId.length === 0)
            return false;

        var tokens = appIdentityTokens(app);
        for (var i = 0; i < tokens.length; i++) {
            if (tokensReferToSameApp(tokens[i], toplevelAppId))
                return true;
        }

        return false;
    }

    function appHasRunningWindow(app, toplevels) {
        if (!toplevels)
            return false;

        for (var i = 0; i < toplevels.length; i++) {
            if (appMatchesToplevel(app, toplevels[i]))
                return true;
        }

        return false;
    }

    function isLaunchableApplication(app) {
        return !!app
            && !app.noDisplay
            && !!app.command
            && app.command.length > 0
            && String(app.name || "").trim().length > 0;
    }

    function compareApplications(a, b) {
        var left = appLabel(a).toLowerCase();
        var right = appLabel(b).toLowerCase();
        if (left < right)
            return -1;
        if (left > right)
            return 1;
        return 0;
    }

    function findApplication(candidates) {
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] || "").trim().length === 0)
                continue;

            var direct = DesktopEntries.byId(candidates[i]);
            if (isLaunchableApplication(direct))
                return direct;

            var guessed = DesktopEntries.heuristicLookup(candidates[i]);
            if (isLaunchableApplication(guessed))
                return guessed;
        }

        var lowered = candidates.map(function(candidate) {
            return String(candidate || "").trim().toLowerCase();
        }).filter(function(candidate) {
            return candidate.length > 0;
        });

        for (var j = 0; j < realApplications.length; j++) {
            var app = realApplications[j];
            var haystack = [
                app.id || "",
                app.name || "",
                app.genericName || "",
                app.startupClass || "",
                app.execString || ""
            ].join(" ").toLowerCase();

            for (var k = 0; k < lowered.length; k++) {
                if (haystack.indexOf(lowered[k]) !== -1)
                    return app;
            }
        }

        return null;
    }

    function appendApplication(target, seen, app) {
        if (!isLaunchableApplication(app))
            return;

        var key = normalizedAppToken(appStableId(app));
        if (key.length === 0 || seen[key])
            return;

        seen[key] = true;
        target.push(app);
    }

    function appendFallbackPinnedApplication(target, seen, id) {
        id = String(id || "").trim();
        var key = normalizedAppToken(id);
        if (key.length === 0 || seen[key])
            return;

        seen[key] = true;
        target.push({
            "id": id,
            "name": id,
            "startupClass": id,
            "icon": id,
            "command": [id]
        });
    }

    function appendPinnedId(target, seen, id) {
        var app = findApplication([id]);
        if (app)
            appendApplication(target, seen, app);
        else
            appendFallbackPinnedApplication(target, seen, id);
    }

    function buildPinnedApps(revision) {
        var result = [
            { "id": "launchpad", "name": "启动台", "iconSet": "dock", "icon": "launchpad.png", "shellAction": "launchpad" }
        ];
        var seen = {};

        var ids = configuredPinnedIds();
        for (var i = 0; i < ids.length; i++)
            appendPinnedId(result, seen, ids[i]);

        return result;
    }
}
