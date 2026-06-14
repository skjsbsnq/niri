pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

QtObject {
    id: root

    readonly property string assetRoot: Quickshell.shellPath("assets")
    readonly property string backgroundRoot: assetRoot + "/backgrounds/"
    readonly property string dockIconRoot: assetRoot + "/icons/dock/"
    readonly property string launchpadIconRoot: assetRoot + "/icons/launchpad/"
    readonly property string symbolIconRoot: assetRoot + "/icons/symbols/"
    readonly property string defaultWindowIcon: dockIconRoot + "finder.png"
    readonly property string wallpaper: backgroundRoot + "iridescence.jpg"

    readonly property var realApplications: [...DesktopEntries.applications.values].filter(isLaunchableApplication).sort(compareApplications)
    readonly property var pinnedApps: buildPinnedApps()
    readonly property var launchpadApps: realApplications

    function iconPath(iconSet, fileName) {
        if (!fileName || fileName.length === 0)
            return defaultWindowIcon;

        if (iconSet === "launchpad")
            return launchpadIconRoot + fileName;
        if (iconSet === "symbols")
            return symbolIconRoot + fileName;

        return dockIconRoot + fileName;
    }

    function iconForApp(app) {
        if (!app)
            return defaultWindowIcon;

        if (app.desktopEntry)
            app = app.desktopEntry;

        if (app.icon) {
            var iconName = String(app.icon);
            if (iconName.length > 0) {
                if (iconName.charAt(0) === "/")
                    return iconName;

                var themed = Quickshell.iconPath(iconName, true);
                if (themed && themed.length > 0)
                    return themed;
            }
        }

        if (app.iconSet)
            return iconPath(app.iconSet, app.icon || "");

        return iconForAppId(app.id || app.startupClass || app.name || "");
    }

    function appLabel(app) {
        if (!app)
            return "App";

        if (app.desktopEntry)
            app = app.desktopEntry;

        var name = String(app.name || "").trim();
        if (name.length > 0)
            return name;

        var id = String(app.id || "").trim();
        return id.length > 0 ? id : "App";
    }

    function iconForAppId(appId) {
        var normalized = String(appId || "").toLowerCase();

        if (normalized.indexOf("code") !== -1 || normalized.indexOf("vscodium") !== -1)
            return dockIconRoot + "vscode.png";
        if (normalized.indexOf("terminal") !== -1 || normalized.indexOf("alacritty") !== -1 || normalized.indexOf("kitty") !== -1 || normalized.indexOf("foot") !== -1 || normalized.indexOf("wezterm") !== -1)
            return dockIconRoot + "terminal.png";
        if (normalized.indexOf("firefox") !== -1 || normalized.indexOf("browser") !== -1 || normalized.indexOf("chrom") !== -1 || normalized.indexOf("safari") !== -1)
            return dockIconRoot + "safari.png";
        if (normalized.indexOf("nautilus") !== -1 || normalized.indexOf("thunar") !== -1 || normalized.indexOf("dolphin") !== -1 || normalized.indexOf("files") !== -1)
            return dockIconRoot + "finder.png";
        if (normalized.indexOf("settings") !== -1 || normalized.indexOf("control") !== -1 || normalized.indexOf("systemsettings") !== -1)
            return dockIconRoot + "preferences.png";

        var themed = Quickshell.iconPath(appId || "", true);
        if (themed && themed.length > 0)
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
            return "Desktop";

        var title = String(toplevel.title || "").trim();
        if (title.length > 0)
            return title;

        var appId = String(toplevel.appId || "").trim();
        return appId.length > 0 ? appId : "Window";
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
            var direct = DesktopEntries.byId(candidates[i]);
            if (isLaunchableApplication(direct))
                return direct;

            var guessed = DesktopEntries.heuristicLookup(candidates[i]);
            if (isLaunchableApplication(guessed))
                return guessed;
        }

        var lowered = candidates.map(function(candidate) {
            return String(candidate).toLowerCase();
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

        var key = String(app.id || app.name || "");
        if (seen[key])
            return;

        seen[key] = true;
        target.push(app);
    }

    function buildPinnedApps() {
        var result = [
            { "id": "launchpad", "name": "Launchpad", "iconSet": "dock", "icon": "launchpad.png", "shellAction": "launchpad" }
        ];
        var seen = {};

        appendApplication(result, seen, findApplication([
            "org.gnome.Nautilus",
            "nautilus",
            "org.kde.dolphin",
            "dolphin",
            "thunar",
            "pcmanfm",
            "files"
        ]));
        appendApplication(result, seen, findApplication([
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
        appendApplication(result, seen, findApplication([
            "firefox",
            "org.mozilla.firefox",
            "chromium",
            "google-chrome",
            "brave-browser",
            "browser"
        ]));
        appendApplication(result, seen, findApplication([
            "org.gnome.Settings",
            "gnome-control-center",
            "systemsettings",
            "xfce4-settings-manager",
            "settings"
        ]));

        return result;
    }
}
