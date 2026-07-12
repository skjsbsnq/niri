.pragma library

// Tahoe symbol registry (T13). Hex codepoint keys (e.g. "e63e") + semantic names
// map to PNG filenames under assets/icons/symbols/.

var HexToName = {
    "e001": "error",
    "e002": "error-outline",
    "e029": "play",
    "e034": "skip-next",
    "e037": "skip-previous",
    "e042": "volume-down",
    "e044": "volume-mute-icon",
    "e045": "volume-off",
    "e04d": "volume-up",
    "e04f": "volume-mute",
    "e050": "volume",
    "e0c8": "place",
    "e145": "add",
    "e14b": "clear",
    "e14c": "cut",
    "e14d": "copy",
    "e14f": "clipboard",
    "e15b": "remove",
    "e161": "save",
    "e195": "storage",
    "e19c": "sd",
    "e1a3": "devices",
    "e1a4": "device-hub",
    "e1a5": "brightness-auto",
    "e1a7": "bluetooth",
    "e1ad": "bluetooth-searching",
    "e1b1": "thermostat",
    "e1bd": "ethernet",
    "e1db": "battery-full",
    "e256": "remove-circle",
    "e25f": "add-circle",
    "e268": "glyph-e268",
    "e2bd": "cloud",
    "e2c2": "folder",
    "e2c4": "folder-open",
    "e2c7": "folder-shared",
    "e307": "glyph-e307",
    "e30d": "phone",
    "e312": "keyboard",
    "e313": "laptop",
    "e322": "speaker",
    "e323": "tablet",
    "e332": "fan",
    "e333": "display",
    "e338": "watch",
    "e3a3": "sunny",
    "e3a4": "incandescent",
    "e3a9": "brightness-2",
    "e3aa": "brightness-3",
    "e3b0": "brightness-5",
    "e3b7": "brightness-7",
    "e3c9": "color-lens",
    "e3d3": "glyph-e3d3",
    "e3e4": "glyph-e3e4",
    "e3ea": "filter",
    "e3f4": "image",
    "e405": "camera",
    "e40a": "glyph-e40a",
    "e40b": "photo",
    "e425": "timelapse",
    "e429": "glyph-e429",
    "e42d": "timer",
    "e430": "tonality",
    "e518": "brightness",
    "e51c": "sleep",
    "e539": "flight",
    "e53b": "airport",
    "e55c": "my-location",
    "e55e": "explore",
    "e55f": "location",
    "e5c3": "apps",
    "e5c4": "arrow-back",
    "e5c9": "cancel",
    "e5ca": "check",
    "e5cb": "chevron-left",
    "e5cc": "chevron-right",
    "e5cd": "close",
    "e5ce": "expand-less",
    "e5cf": "expand-more",
    "e5d2": "menu",
    "e5d5": "refresh",
    "e5d8": "arrow-up",
    "e5db": "arrow-down",
    "e63c": "signal",
    "e63e": "wifi",
    "e65f": "glyph-e65f",
    "e798": "ac",
    "e7c9": "priority",
    "e7f1": "city",
    "e7f4": "notifications",
    "e7f6": "notifications-off",
    "e7fd": "person",
    "e7fe": "person-add",
    "e80b": "public",
    "e80d": "school",
    "e80f": "share",
    "e818": "stars",
    "e81a": "whatshot",
    "e835": "radio-off",
    "e84d": "glyph-e84d",
    "e84e": "bookmark",
    "e859": "schedule",
    "e863": "visibility",
    "e866": "check-circle",
    "e868": "delete-fill",
    "e869": "done",
    "e86a": "info",
    "e86c": "done-all",
    "e86f": "code",
    "e871": "dashboard",
    "e872": "delete",
    "e873": "description",
    "e876": "check-done",
    "e87d": "favorite",
    "e88a": "home",
    "e88e": "info-e88e",
    "e88f": "help-circle",
    "e892": "glyph-e892",
    "e897": "lock",
    "e89e": "open",
    "e8a0": "language",
    "e8a7": "windows",
    "e8ac": "power",
    "e8ad": "print",
    "e8b2": "battery",
    "e8b5": "search-off",
    "e8b6": "search",
    "e8b8": "settings",
    "e8c1": "cart",
    "e8c4": "notes",
    "e8d0": "windows-list",
    "e8d1": "view-module",
    "e8d2": "view-quilt",
    "e8d3": "view-stream",
    "e8d4": "workspace",
    "e8e5": "performance",
    "e8e8": "dns",
    "e8ef": "extension",
    "e8f4": "fingerprint",
    "e8f5": "flight-takeoff",
    "e8f9": "gavel",
    "e8ff": "help",
    "e915": "event",
    "e91f": "bug",
    "e97a": "memory",
    "e9ba": "logout",
    "e9e4": "bolt",
    "e9e9": "touch",
    "e9ef": "tag",
    "ea35": "eco",
    "ea46": "biotech",
    "ea5f": "science",
    "ea77": "psychology",
    "eb37": "dark-mode",
    "eb3b": "light-mode",
    "eb81": "sensors",
    "eb8e": "water",
    "ebdb": "air",
    "ef6b": "password",
    "efd8": "chart",
    "f090": "download",
    "f09b": "upload",
    "f1ad": "umbrella",
    "f20c": "leaderboard",
};

var NameToFile = {
    "ac": "ac.png",
    "add": "add.png",
    "add-circle": "add-circle.png",
    "air": "air.png",
    "airport": "airport.png",
    "apps": "apps.png",
    "arrow-back": "arrow-back.png",
    "arrow-down": "arrow-down.png",
    "arrow-up": "arrow-up.png",
    "battery": "battery.png",
    "battery-full": "battery-full.png",
    "biotech": "biotech.png",
    "bluetooth": "bluetooth.png",
    "bluetooth-searching": "bluetooth-searching.png",
    "bolt": "bolt.png",
    "bookmark": "bookmark.png",
    "brightness": "brightness.png",
    "brightness-2": "brightness-2.png",
    "brightness-3": "brightness-3.png",
    "brightness-5": "brightness-5.png",
    "brightness-7": "brightness-7.png",
    "brightness-auto": "brightness-auto.png",
    "bug": "bug.png",
    "camera": "camera.png",
    "cancel": "cancel.png",
    "cart": "cart.png",
    "chart": "chart.png",
    "check": "check.png",
    "check-circle": "check-circle.png",
    "check-done": "check-done.png",
    "chevron-left": "chevron-left.png",
    "chevron-right": "chevron-right.png",
    "city": "city.png",
    "clear": "clear.png",
    "clipboard": "clipboard.png",
    "close": "close.png",
    "cloud": "cloud.png",
    "code": "code.png",
    "color-lens": "color-lens.png",
    "copy": "copy.png",
    "cut": "cut.png",
    "dark-mode": "dark-mode.png",
    "dashboard": "dashboard.png",
    "delete": "delete.png",
    "delete-fill": "delete-fill.png",
    "description": "description.png",
    "device-hub": "device-hub.png",
    "devices": "devices.png",
    "display": "display.png",
    "dns": "dns.png",
    "done": "done.png",
    "done-all": "done-all.png",
    "download": "download.png",
    "eco": "eco.png",
    "error": "error.png",
    "error-outline": "error-outline.png",
    "ethernet": "ethernet.png",
    "event": "event.png",
    "expand-less": "expand-less.png",
    "expand-more": "expand-more.png",
    "explore": "explore.png",
    "extension": "extension.png",
    "fan": "fan.png",
    "favorite": "favorite.png",
    "filter": "filter.png",
    "fingerprint": "fingerprint.png",
    "flight": "flight.png",
    "flight-takeoff": "flight-takeoff.png",
    "folder": "folder.png",
    "folder-open": "folder-open.png",
    "folder-shared": "folder-shared.png",
    "gavel": "gavel.png",
    "glyph-e268": "glyph-e268.png",
    "glyph-e307": "glyph-e307.png",
    "glyph-e3d3": "glyph-e3d3.png",
    "glyph-e3e4": "glyph-e3e4.png",
    "glyph-e40a": "glyph-e40a.png",
    "glyph-e429": "glyph-e429.png",
    "glyph-e65f": "glyph-e65f.png",
    "glyph-e84d": "glyph-e84d.png",
    "glyph-e892": "glyph-e892.png",
    "help": "help.png",
    "help-circle": "help-circle.png",
    "home": "home.png",
    "image": "image.png",
    "incandescent": "incandescent.png",
    "info": "info.png",
    "info-e88e": "info-e88e.png",
    "keyboard": "keyboard.png",
    "language": "language.png",
    "laptop": "laptop.png",
    "leaderboard": "leaderboard.png",
    "light-mode": "light-mode.png",
    "location": "location.png",
    "lock": "lock.png",
    "logout": "logout.png",
    "memory": "memory.png",
    "menu": "menu.png",
    "my-location": "my-location.png",
    "notes": "notes.png",
    "notifications": "notifications.png",
    "notifications-off": "notifications-off.png",
    "open": "open.png",
    "password": "password.png",
    "performance": "performance.png",
    "person": "person.png",
    "person-add": "person-add.png",
    "phone": "phone.png",
    "photo": "photo.png",
    "place": "place.png",
    "play": "play.png",
    "power": "power.png",
    "print": "print.png",
    "priority": "priority.png",
    "psychology": "psychology.png",
    "public": "public.png",
    "radio-off": "radio-off.png",
    "refresh": "refresh.png",
    "remove": "remove.png",
    "remove-circle": "remove-circle.png",
    "save": "save.png",
    "schedule": "schedule.png",
    "school": "school.png",
    "science": "science.png",
    "sd": "sd.png",
    "search": "search.png",
    "search-off": "search-off.png",
    "sensors": "sensors.png",
    "settings": "settings.png",
    "share": "share.png",
    "signal": "signal.png",
    "skip-next": "skip-next.png",
    "skip-previous": "skip-previous.png",
    "sleep": "sleep.png",
    "speaker": "speaker.png",
    "stars": "stars.png",
    "storage": "storage.png",
    "sunny": "sunny.png",
    "tablet": "tablet.png",
    "tag": "tag.png",
    "thermostat": "thermostat.png",
    "timelapse": "timelapse.png",
    "timer": "timer.png",
    "tonality": "tonality.png",
    "touch": "touch.png",
    "umbrella": "umbrella.png",
    "upload": "upload.png",
    "view-module": "view-module.png",
    "view-quilt": "view-quilt.png",
    "view-stream": "view-stream.png",
    "visibility": "visibility.png",
    "volume": "volume.png",
    "volume-down": "volume-down.png",
    "volume-mute": "volume-mute.png",
    "volume-mute-icon": "volume-mute-icon.png",
    "volume-off": "volume-off.png",
    "volume-up": "volume-up.png",
    "watch": "watch.png",
    "water": "water.png",
    "whatshot": "whatshot.png",
    "wifi": "wifi.png",
    "windows": "windows.png",
    "windows-list": "windows-list.png",
    "workspace": "workspace.png",
    "AppStore-Symbol": "AppStore-Symbol.png",
    "Back-Symbol": "Back-Symbol.png",
    "Copy-Symbol": "Copy-Symbol.png",
    "Folder-Symbol": "Folder-Symbol.png",
    "Forward-Symbol": "Forward-Symbol.png",
    "Shortcuts-Symbol": "Shortcuts-Symbol.png",
    "appstore": "AppStore-Symbol.png",
    "back": "Back-Symbol.png",
    "copy-symbol": "Copy-Symbol.png",
    "folder-symbol": "Folder-Symbol.png",
    "forward": "Forward-Symbol.png",
    "shortcuts": "Shortcuts-Symbol.png",
};

function normalizeKey(value) {
    if (value === undefined || value === null)
        return "";
    // Avoid boolean/number coercion artifacts (e.g. false -> "false").
    if (typeof value !== "string")
        return "";
    return String(value).trim();
}

function hexFromValue(value) {
    var key = normalizeKey(value);
    if (key.length === 0)
        return "";
    // Already a 4-digit hex private-use codepoint
    var lower = key.toLowerCase();
    if (/^[ef][0-9a-f]{3}$/.test(lower))
        return lower;
    if (/^u[ef][0-9a-f]{3}$/.test(lower))
        return lower.substring(1);
    if (/^\\u[ef][0-9a-f]{3}$/.test(lower))
        return lower.substring(2);
    // Single private-use character
    if (key.length === 1) {
        var cp = key.charCodeAt(0);
        if (cp >= 0xe000 && cp <= 0xf8ff) {
            var h = cp.toString(16);
            while (h.length < 4)
                h = "0" + h;
            return h;
        }
    }
    return "";
}

function resolveName(value) {
    var key = normalizeKey(value);
    if (key.length === 0)
        return "";
    if (Object.prototype.hasOwnProperty.call(NameToFile, key))
        return key;
    if (key.indexOf(".png") > 0) {
        var bare = key.replace(/\.png$/, "");
        if (Object.prototype.hasOwnProperty.call(NameToFile, bare))
            return bare;
        return bare;
    }
    var hex = hexFromValue(key);
    if (hex.length > 0 && Object.prototype.hasOwnProperty.call(HexToName, hex))
        return HexToName[hex];
    var alt = key.replace(/_/g, "-");
    if (Object.prototype.hasOwnProperty.call(NameToFile, alt))
        return alt;
    // Unknown: do not invent a filename from raw codepoint text
    return "";
}

function fileName(value) {
    var name = resolveName(value);
    if (name.length === 0)
        return "";
    if (Object.prototype.hasOwnProperty.call(NameToFile, name))
        return NameToFile[name];
    if (name.indexOf(".png") > 0)
        return name;
    return name + ".png";
}

function isKnown(value) {
    return resolveName(value).length > 0;
}

function glyph(value) {
    var key = normalizeKey(value);
    if (key.length === 0)
        return "";

    var hex = hexFromValue(key);
    if (hex.length === 0) {
        var name = resolveName(key);
        for (var candidate in HexToName) {
            if (Object.prototype.hasOwnProperty.call(HexToName, candidate)
                    && HexToName[candidate] === name) {
                hex = candidate;
                break;
            }
        }
    }

    if (hex.length === 0)
        return "";
    return String.fromCharCode(parseInt(hex, 16));
}

// Backward-compatible aliases used by older call sites / tests.
var CodepointToName = HexToName;
function nameFromCodepoint(code) {
    var hex = hexFromValue(code);
    if (hex.length === 0)
        return "";
    return Object.prototype.hasOwnProperty.call(HexToName, hex) ? HexToName[hex] : "";
}
