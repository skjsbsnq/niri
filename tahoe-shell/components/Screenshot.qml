pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root
    visible: false

    property var settingsService
    property string lastFile: ""
    readonly property var keywords: ["截图", "截屏", "screenshot", "screen", "capture", "shot"]
    readonly property string configuredDirectory: settingsService ? settingsService.effectiveScreenshotDirectory : ""
    readonly property bool copyToClipboard: !settingsService || settingsService.screenshotCopyToClipboard
    readonly property bool offerActions: !settingsService || settingsService.screenshotOfferActions

    function matchesQuery(query) {
        var text = String(query || "").trim().toLowerCase();
        if (text.length === 0)
            return false;

        for (var i = 0; i < keywords.length; i++) {
            if (String(keywords[i]).toLowerCase().indexOf(text) !== -1
                    || text.indexOf(String(keywords[i]).toLowerCase()) !== -1)
                return true;
        }
        return false;
    }

    function spotlightResult() {
        return {
            "id": "tahoe-screenshot-selection",
            "resultType": "screenshot",
            "kind": "screenshot",
            "name": "截图选区",
            "title": "截图选区",
            "genericName": "保存、复制并可标注",
            "subtitle": "保存、复制并可标注",
            "icon": "photos.png",
            "score": 860
        };
    }

    function activateResult(result) {
        if (result && (result.resultType === "screenshot" || result.kind === "screenshot"))
            captureSelection();
    }

    function captureSelection() {
        Quickshell.execDetached({
            command: [
                "sh",
                "-lc",
                [
                    "set -u",
                    "configured_dir=\"$1\"",
                    "copy_to_clipboard=\"$2\"",
                    "offer_actions=\"$3\"",
                    "if ! command -v grim >/dev/null 2>&1 || ! command -v slurp >/dev/null 2>&1; then",
                    "  command -v notify-send >/dev/null 2>&1 && notify-send -a niri '截图不可用' '请安装 grim slurp swappy'",
                    "  exit 1",
                    "fi",
                    "if [ -n \"$configured_dir\" ]; then",
                    "  dir=\"$configured_dir\"",
                    "else",
                    "  pictures=\"$HOME/Pictures\"",
                    "  if command -v xdg-user-dir >/dev/null 2>&1; then",
                    "    found=\"$(xdg-user-dir PICTURES 2>/dev/null || true)\"",
                    "    [ -n \"$found\" ] && pictures=\"$found\"",
                    "  fi",
                    "  dir=\"$pictures/Screenshots\"",
                    "fi",
                    "mkdir -p \"$dir\"",
                    "file=\"$dir/$(date +'%Y-%m-%d_%H-%M-%S').png\"",
                    "geom=\"$(slurp 2>/dev/null)\" || exit 0",
                    "[ -n \"$geom\" ] || exit 0",
                    "grim -g \"$geom\" \"$file\" || exit 1",
                    "if [ \"$copy_to_clipboard\" = 1 ]; then",
                    "  command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < \"$file\" || true",
                    "fi",
                    "if command -v notify-send >/dev/null 2>&1; then",
                    "  if [ \"$offer_actions\" = 1 ] && notify-send --help 2>&1 | grep -q -- '--action'; then",
                    "    action=\"$(notify-send -a niri --icon=\"$file\" --action=annotate=标注 --action=open=打开 --action=copy=复制 --wait '截图已保存' \"$file\" 2>/dev/null || true)\"",
                    "    case \"$action\" in",
                    "      annotate) command -v swappy >/dev/null 2>&1 && swappy -f \"$file\" ;;",
                    "      open) command -v xdg-open >/dev/null 2>&1 && xdg-open \"$file\" ;;",
                    "      copy) command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < \"$file\" ;;",
                    "    esac",
                    "  else",
                    "    notify-send -a niri '截图已保存' \"$file\"",
                    "  fi",
                    "fi"
                ].join("\n"),
                "sh",
                root.configuredDirectory,
                root.copyToClipboard ? "1" : "0",
                root.offerActions ? "1" : "0"
            ],
            workingDirectory: ""
        });
    }
}
