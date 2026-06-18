pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property bool darkMode: appearanceAdapter.darkMode
    readonly property bool nightMode: appearanceAdapter.nightMode
    readonly property int colorTemperature: appearanceAdapter.colorTemperature

    function setDarkMode(enabled) {
        var next = !!enabled;
        if (appearanceAdapter.darkMode === next)
            return;

        appearanceAdapter.darkMode = next;
        appearanceFile.writeAdapter();
        applyDarkMode();
    }

    function toggleDarkMode() {
        setDarkMode(!darkMode);
    }

    function setNightMode(enabled) {
        var next = !!enabled;
        if (appearanceAdapter.nightMode === next)
            return;

        appearanceAdapter.nightMode = next;
        appearanceFile.writeAdapter();
        applyNightMode();
    }

    function toggleNightMode() {
        setNightMode(!nightMode);
    }

    function setColorTemperature(value) {
        var next = Math.max(2500, Math.min(6500, Math.round(Number(value) || 4500)));
        if (appearanceAdapter.colorTemperature === next)
            return;

        appearanceAdapter.colorTemperature = next;
        appearanceFile.writeAdapter();
        applyNightMode();
    }

    function applyDarkMode() {
        var scheme = darkMode ? "prefer-dark" : "prefer-light";
        var gtkTheme = darkMode ? "Adwaita-dark" : "Adwaita";
        var plasmaScheme = darkMode ? "BreezeDark" : "BreezeLight";
        var kvTheme = darkMode ? "KvArcDark" : "KvArc";

        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                [
                    "scheme=\"$1\"",
                    "gtk_theme=\"$2\"",
                    "plasma_scheme=\"$3\"",
                    "kv_theme=\"$4\"",
                    "command -v gsettings >/dev/null 2>&1 && gsettings set org.gnome.desktop.interface color-scheme \"$scheme\" || true",
                    "command -v gsettings >/dev/null 2>&1 && gsettings set org.gnome.desktop.interface gtk-theme \"$gtk_theme\" || true",
                    "command -v plasma-apply-colorscheme >/dev/null 2>&1 && plasma-apply-colorscheme \"$plasma_scheme\" >/dev/null 2>&1 || true",
                    "command -v kvantummanager >/dev/null 2>&1 && kvantummanager --set \"$kv_theme\" >/dev/null 2>&1 || true"
                ].join("\n"),
                "sh",
                scheme,
                gtkTheme,
                plasmaScheme,
                kvTheme
            ],
            workingDirectory: ""
        });
    }

    function applyNightMode() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                [
                    "enabled=\"$1\"",
                    "temperature=\"$2\"",
                    "if ! command -v gammastep >/dev/null 2>&1; then exit 0; fi",
                    "if [ \"$enabled\" = \"1\" ]; then",
                    "  gammastep -x >/dev/null 2>&1 || true",
                    "  gammastep -O \"$temperature\" >/dev/null 2>&1 || true",
                    "else",
                    "  gammastep -x >/dev/null 2>&1 || true",
                    "fi"
                ].join("\n"),
                "sh",
                nightMode ? "1" : "0",
                String(colorTemperature)
            ],
            workingDirectory: ""
        });
    }

    FileView {
        id: appearanceFile
        path: Quickshell.stateDir + "/appearance.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.applyDarkMode();
            root.applyNightMode();
        }
        onLoadFailed: writeAdapter()

        JsonAdapter {
            id: appearanceAdapter
            property bool darkMode: false
            property bool nightMode: false
            property int colorTemperature: 4500
        }
    }
}
