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

    readonly property var pinnedApps: [
        { "id": "finder", "name": "Finder", "iconSet": "dock", "icon": "finder.png", "command": ["sh", "-c", "xdg-open \"$HOME\""] },
        { "id": "launchpad", "name": "Launchpad", "iconSet": "dock", "icon": "launchpad.png", "command": [] },
        { "id": "safari", "name": "Browser", "iconSet": "dock", "icon": "safari.png", "command": ["sh", "-c", "xdg-open about:blank"] },
        { "id": "terminal", "name": "Terminal", "iconSet": "dock", "icon": "terminal.png", "command": ["sh", "-c", "foot || alacritty || kitty || xterm"] },
        { "id": "settings", "name": "Settings", "iconSet": "dock", "icon": "preferences.png", "command": ["sh", "-c", "XDG_CURRENT_DESKTOP=GNOME gnome-control-center || systemsettings || xfce4-settings-manager"] }
    ]

    readonly property var launchpadApps: [
        { "id": "finder", "name": "Finder", "iconSet": "dock", "icon": "finder.png", "command": ["sh", "-c", "xdg-open \"$HOME\""] },
        { "id": "browser", "name": "Browser", "iconSet": "dock", "icon": "safari.png", "command": ["sh", "-c", "xdg-open about:blank"] },
        { "id": "terminal", "name": "Terminal", "iconSet": "dock", "icon": "terminal.png", "command": ["sh", "-c", "foot || alacritty || kitty || xterm"] },
        { "id": "settings", "name": "Settings", "iconSet": "dock", "icon": "preferences.png", "command": ["sh", "-c", "XDG_CURRENT_DESKTOP=GNOME gnome-control-center || systemsettings || xfce4-settings-manager"] },
        { "id": "appstore", "name": "App Store", "iconSet": "launchpad", "icon": "appstore.png", "command": [] },
        { "id": "calendar", "name": "Calendar", "iconSet": "launchpad", "icon": "calendar.png", "command": [] },
        { "id": "calculator", "name": "Calculator", "iconSet": "launchpad", "icon": "calculator.png", "command": ["sh", "-c", "gnome-calculator || kcalc || galculator"] },
        { "id": "notes", "name": "Notes", "iconSet": "launchpad", "icon": "Notes - Light.png", "command": [] },
        { "id": "mail", "name": "Mail", "iconSet": "launchpad", "icon": "mail.png", "command": [] },
        { "id": "maps", "name": "Maps", "iconSet": "launchpad", "icon": "Maps - Light.png", "command": [] },
        { "id": "music", "name": "Music", "iconSet": "launchpad", "icon": "Music - Light.png", "command": [] },
        { "id": "photos", "name": "Photos", "iconSet": "launchpad", "icon": "Photos - Light.png", "command": [] },
        { "id": "reminders", "name": "Reminders", "iconSet": "launchpad", "icon": "Reminders - Light.png", "command": [] },
        { "id": "activity", "name": "Activity", "iconSet": "launchpad", "icon": "activitymonitor.png", "command": ["sh", "-c", "gnome-system-monitor || plasma-systemmonitor || htop"] },
        { "id": "shortcuts", "name": "Shortcuts", "iconSet": "launchpad", "icon": "Shortcuts - Light.png", "command": [] },
        { "id": "vscode", "name": "Code", "iconSet": "dock", "icon": "vscode.png", "command": ["sh", "-c", "code || codium"] }
    ]

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

        return iconPath(app.iconSet || "dock", app.icon || "");
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
        if (!app || !app.command || app.command.length === 0)
            return;

        Quickshell.execDetached(app.command);
    }
}
