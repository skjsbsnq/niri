pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var appsService
    property var screenshotService
    property var windowsService
    property var clipboardService
    property var commandRunner
    readonly property int defaultLimit: 6
    readonly property int slowProviderDebounceMs: 90
    property int providerRevision: 0
    property string pendingTaskQuery: ""
    property string activeTaskQuery: ""
    property string taskIndexOutputQuery: ""
    property string cachedTaskQuery: ""
    property var cachedTaskEntries: []
    readonly property var settingsItems: [
        {
            "id": "tahoe-settings",
            "title": "Tahoe 设置",
            "subtitle": "外观、壁纸、通知、输入法、截图、Dock 和启动项",
            "keywords": ["设置", "tahoe", "settings", "preferences", "desktop", "dock", "壁纸", "wallpaper", "截图", "通知", "输入法"],
            "internalPage": "settings"
        },
        {
            "id": "tahoe-wallpaper",
            "title": "壁纸设置",
            "subtitle": "静态图片、动态命令和 Linux Wallpaper Engine UX",
            "keywords": ["壁纸", "动态壁纸", "wallpaper", "live wallpaper", "linux-wallpaper-engine", "wallpaperengine", "ux"],
            "internalPage": "wallpaper"
        },
        {
            "id": "tahoe-dock",
            "title": "Dock 设置",
            "subtitle": "自动隐藏、触发热区和窗口按钮",
            "keywords": ["dock", "自动隐藏", "隐藏", "热区", "窗口标题", "autohide", "auto hide"],
            "internalPage": "dock"
        },
        {
            "id": "tahoe-dynamic-island",
            "title": "灵动岛设置",
            "subtitle": "顶栏胶囊、点击行为和 hover 展开",
            "keywords": ["灵动岛", "dynamic island", "island", "胶囊", "顶栏", "时间", "hover", "媒体"],
            "internalPage": "dynamic-island"
        },
        {
            "id": "tahoe-health",
            "title": "系统健康",
            "subtitle": "检查 portal、PipeWire、截图、剪贴板、托盘和兼容性",
            "keywords": ["健康", "诊断", "依赖", "状态", "health", "diagnostics", "status", "pipewire", "portal", "tray"],
            "internalPage": "health"
        },
        {
            "id": "tahoe-about",
            "title": "关于 niri",
            "subtitle": "版本、提交、子模块、GPU 和会话信息",
            "keywords": ["关于", "版本", "提交", "about", "version", "commit", "gpu", "session", "niri", "quickshell"],
            "internalPage": "about"
        },
        {
            "id": "tahoe-niri",
            "title": "niri 设置",
            "subtitle": "布局、玻璃材质、输入、动画与快捷键",
            "keywords": ["niri", "布局", "窗口", "间距", "玻璃", "动画", "快捷键", "compositor", "wayland", "合成器"],
            "internalPage": "niri"
        },
        {
            "id": "tahoe-niri-glass",
            "title": "玻璃材质",
            "subtitle": "tahoe-glass 折射、边缘光与全局模糊",
            "keywords": ["玻璃", "材质", "模糊", "blur", "折射", "refraction", "glass", "边缘光", "色散", "透镜", "niri"],
            "internalPage": "niri-glass"
        },
        {
            "id": "tahoe-niri-input",
            "title": "输入与显示",
            "subtitle": "键盘、触摸板与显示器缩放（输出只读）",
            "keywords": ["输入", "键盘", "触摸板", "触控板", "重复", "自然滚动", "numlock", "显示", "缩放", "input", "keyboard", "touchpad", "display", "niri"],
            "internalPage": "niri-input"
        },
        {
            "id": "tahoe-niri-animations",
            "title": "动画",
            "subtitle": "工作区、窗口与概览的弹簧动画",
            "keywords": ["动画", "弹簧", "阻尼", "刚度", "弹性", "animation", "spring", "damping", "stiffness", "niri"],
            "internalPage": "niri-animations"
        },
        {
            "id": "tahoe-niri-keyboard",
            "title": "键盘快捷键",
            "subtitle": "niri binds 只读查看",
            "keywords": ["快捷键", "键位", "binds", "shortcut", "keybind", "热键", "niri"],
            "internalPage": "niri-keyboard"
        },
        {
            "id": "system",
            "title": "系统设置",
            "subtitle": "打开桌面系统设置",
            "keywords": ["设置", "系统", "system", "settings", "preferences", "control center"],
            "appCandidates": ["org.gnome.Settings", "gnome-control-center", "systemsettings", "xfce4-settings-manager", "settings"],
            "commands": [["gnome-control-center"], ["systemsettings"], ["xfce4-settings-manager"]]
        },
        {
            "id": "appearance",
            "title": "外观设置",
            "subtitle": "主题、深浅色和显示外观",
            "keywords": ["外观", "主题", "深色", "浅色", "appearance", "theme", "dark", "light"],
            "commands": [["gnome-control-center", "appearance"], ["systemsettings", "kcm_colors"], ["xfce4-appearance-settings"]]
        },
        {
            "id": "display",
            "title": "显示设置",
            "subtitle": "分辨率、缩放和显示器布局",
            "keywords": ["显示", "屏幕", "分辨率", "缩放", "display", "monitor", "screen", "resolution", "scale"],
            "commands": [["gnome-control-center", "display"], ["systemsettings", "kcm_kscreen"], ["xfce4-display-settings"]]
        },
        {
            "id": "network",
            "title": "网络设置",
            "subtitle": "Wi-Fi、以太网和 VPN",
            "keywords": ["网络", "wifi", "wi-fi", "无线", "以太网", "vpn", "network"],
            "commands": [["gnome-control-center", "network"], ["nm-connection-editor"], ["systemsettings", "kcm_networkmanagement"]]
        },
        {
            "id": "sound",
            "title": "声音设置",
            "subtitle": "输入、输出和音量",
            "keywords": ["声音", "音频", "麦克风", "音量", "sound", "audio", "volume", "microphone"],
            "commands": [["gnome-control-center", "sound"], ["pavucontrol"], ["systemsettings", "kcm_pulseaudio"]]
        },
        {
            "id": "power",
            "title": "电源设置",
            "subtitle": "电池、节能和电源模式",
            "keywords": ["电源", "电池", "省电", "性能", "power", "battery", "energy", "profile"],
            "commands": [["gnome-control-center", "power"], ["systemsettings", "powerdevilprofilesconfig"]]
        },
        {
            "id": "bluetooth",
            "title": "蓝牙设置",
            "subtitle": "蓝牙设备和连接",
            "keywords": ["蓝牙", "bluetooth", "bt"],
            "commands": [["gnome-control-center", "bluetooth"], ["blueman-manager"], ["systemsettings", "kcm_bluetooth"]]
        },
        {
            "id": "notifications",
            "title": "通知设置",
            "subtitle": "通知权限和勿扰",
            "keywords": ["通知", "勿扰", "notification", "notifications", "dnd", "do not disturb"],
            "commands": [["gnome-control-center", "notifications"], ["systemsettings", "kcm_notifications"]]
        },
        {
            "id": "keyboard",
            "title": "键盘与快捷键",
            "subtitle": "键盘、快捷键和输入设置",
            "keywords": ["键盘", "快捷键", "输入", "keyboard", "shortcut", "shortcuts", "input"],
            "commands": [["gnome-control-center", "keyboard"], ["systemsettings", "kcm_keys"], ["fcitx5-configtool"]]
        },
        {
            "id": "input-method",
            "title": "输入法设置",
            "subtitle": "配置 fcitx5 输入法",
            "keywords": ["输入法", "中文", "拼音", "fcitx", "fcitx5", "ime", "input method"],
            "commands": [["fcitx5-configtool"], ["gnome-control-center", "keyboard"], ["systemsettings", "kcm_fcitx5"]]
        }
    ]
    readonly property var systemActionItems: [
        {
            "id": "lock",
            "title": "锁定屏幕",
            "subtitle": "使用 Tahoe 锁屏",
            "keywords": ["锁屏", "锁定", "lock", "screen", "安全", "session"],
            "action": "lock",
            "icon": "preferences.png"
        },
        {
            "id": "overview",
            "title": "窗口总览",
            "subtitle": "查看并切换当前打开的窗口",
            "keywords": ["窗口", "总览", "overview", "expose", "mission control", "任务"],
            "action": "overview",
            "icon": "finder.png"
        },
        {
            "id": "task-switcher",
            "title": "任务切换器",
            "subtitle": "打开最近窗口切换器",
            "keywords": ["任务", "切换", "窗口", "alt tab", "switcher", "recent"],
            "action": "task-switcher",
            "icon": "finder.png"
        },
        {
            "id": "launchpad",
            "title": "Launchpad",
            "subtitle": "打开应用网格",
            "keywords": ["launchpad", "启动台", "应用", "app grid", "程序"],
            "action": "launchpad",
            "icon": "launchpad.png"
        },
        {
            "id": "control-center",
            "title": "控制中心",
            "subtitle": "打开 Wi-Fi、蓝牙、亮度和电源控制",
            "keywords": ["控制中心", "control center", "wifi", "蓝牙", "亮度", "电源"],
            "action": "control-center",
            "icon": "preferences.png"
        },
        {
            "id": "notification-center",
            "title": "通知中心",
            "subtitle": "查看通知历史和勿扰状态",
            "keywords": ["通知", "通知中心", "notification", "notifications", "dnd", "勿扰"],
            "action": "notification-center",
            "icon": "preferences.png"
        },
        {
            "id": "clipboard",
            "title": "剪贴板历史",
            "subtitle": "打开剪贴板历史与固定项",
            "keywords": ["剪贴板", "clipboard", "复制", "copy", "固定项", "pins"],
            "action": "clipboard",
            "icon": "notes.png"
        },
        {
            "id": "sleep",
            "title": "睡眠",
            "subtitle": "打开确认框后让电脑进入睡眠",
            "keywords": ["睡眠", "sleep", "suspend", "挂起"],
            "action": "sleep",
            "icon": "preferences.png"
        },
        {
            "id": "logout",
            "title": "退出登录",
            "subtitle": "打开确认框后退出当前 niri 会话",
            "keywords": ["退出", "注销", "logout", "log out", "session", "quit"],
            "action": "logout",
            "icon": "preferences.png"
        },
        {
            "id": "restart",
            "title": "重新启动",
            "subtitle": "打开确认框后重启电脑",
            "keywords": ["重启", "重新启动", "restart", "reboot"],
            "action": "restart",
            "icon": "preferences.png"
        },
        {
            "id": "shutdown",
            "title": "关机",
            "subtitle": "打开确认框后关闭电脑",
            "keywords": ["关机", "关闭", "shutdown", "poweroff", "power off"],
            "action": "shutdown",
            "icon": "preferences.png"
        }
    ]

    signal openSettingsRequested(string page)
    signal systemActionRequested(string action)

    function normalizedText(value) {
        return String(value || "").trim().toLowerCase();
    }

    function iconPath(iconSet, fileName) {
        return root.appsService ? root.appsService.iconPath(iconSet, fileName) : "";
    }

    function bumpProviderRevision() {
        root.providerRevision += 1;
    }

    function pathBasename(path) {
        var text = String(path || "").replace(/\\/g, "/");
        var slash = text.lastIndexOf("/");
        return slash >= 0 ? text.substring(slash + 1) : text;
    }

    function compactPath(path) {
        var text = String(path || "").trim();
        var home = String(Quickshell.env("HOME") || "").trim();
        if (home.length > 0 && text.indexOf(home + "/") === 0)
            return "~" + text.substring(home.length);
        return text;
    }

    function windowTitle(window) {
        var title = String(window && window.title || "").trim();
        if (title.length > 0)
            return title;
        if (root.appsService)
            return root.appsService.windowAppLabel(window);
        var appId = String(window && window.appId || "").trim();
        return appId.length > 0 ? appId : "窗口";
    }

    function windowSubtitle(window) {
        var parts = [];
        var app = root.appsService ? root.appsService.windowAppLabel(window) : String(window && window.appId || "").trim();
        if (app.length > 0)
            parts.push(app);
        var workspace = window && window.workspace ? String(window.workspace.name || window.workspace.id || "").trim() : "";
        if (workspace.length > 0)
            parts.push("工作区 " + workspace);
        if (window && window.isMinimized)
            parts.push("已最小化");
        return parts.length > 0 ? parts.join(" · ") : "打开窗口";
    }

    function windowIcon(window) {
        if (!root.appsService)
            return iconPath("dock", "finder.png");
        var app = root.appsService.appForWindow(window);
        if (app)
            return root.appsService.iconForApp(app);
        return root.appsService.iconForAppId(window && window.appId ? window.appId : "");
    }

    function makeResult(fields) {
        var result = fields || {};
        result.title = String(result.title || result.name || "");
        result.subtitle = String(result.subtitle || result.genericName || "");
        result.kind = String(result.kind || "action");
        result.id = String(result.id || result.kind + ":" + result.title);
        result.provider = String(result.provider || result.kind);
        result.score = Number(result.score || 0);
        result.activate = function() {
            root.activateResult(result);
        };
        return result;
    }

    function scoreText(title, subtitle, keywords, query, baseScore) {
        var normalized = normalizedText(query);
        if (normalized.length === 0)
            return 0;

        var titleText = normalizedText(title);
        var subtitleText = normalizedText(subtitle);
        var haystack = titleText + " " + subtitleText + " " + normalizedText((keywords || []).join(" "));
        var terms = normalized.split(/\s+/);
        for (var i = 0; i < terms.length; i++) {
            if (terms[i].length > 0 && haystack.indexOf(terms[i]) === -1)
                return 0;
        }

        var score = baseScore;
        if (titleText === normalized)
            score += 120;
        else if (titleText.indexOf(normalized) === 0)
            score += 80;
        else if (haystack.indexOf(" " + normalized) !== -1)
            score += 48;
        else if (titleText.indexOf(normalized) !== -1)
            score += 36;
        else if (subtitleText.indexOf(normalized) !== -1)
            score += 24;
        else
            score += 12;

        return score;
    }

    function appResults(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0 || !root.appsService)
            return [];

        var max = Math.max(1, limit || root.defaultLimit);
        var apps = root.appsService.spotlightResults(normalized, Math.max(max * 2, 12));
        var results = [];
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var title = root.appsService.appLabel(app);
            var subtitle = String(app.genericName || app.id || "应用");
            var score = scoreText(title, subtitle, [app.id || "", app.startupClass || "", app.execString || ""], normalized, 430);
            if (score <= 0)
                continue;

            results.push(makeResult({
                "id": "app:" + root.appsService.appStableId(app),
                "title": title,
                "subtitle": subtitle,
                "icon": root.appsService.iconForApp(app),
                "kind": "application",
                "provider": "apps",
                "score": score,
                "app": app
            }));
        }
        return results;
    }

    function screenshotResults(query) {
        if (!root.screenshotService || !root.screenshotService.matchesQuery(query))
            return [];

        var raw = root.screenshotService.spotlightResult();
        return [
            makeResult({
                "id": "screenshot:" + String(raw.id || "selection"),
                "title": String(raw.title || raw.name || "截图选区"),
                "subtitle": String(raw.subtitle || raw.genericName || "保存、复制并可标注"),
                "icon": iconPath("dock", raw.icon || "photos.png"),
                "kind": "screenshot",
                "provider": "screenshot",
                "score": Number(raw.score || 860),
                "resultType": "screenshot"
            })
        ];
    }

    function commandText(query) {
        var text = String(query || "").trim();
        if (text.length < 2)
            return "";

        var prefix = text.charAt(0);
        if (prefix !== ">" && prefix !== "!")
            return "";

        return text.substring(1).trim();
    }

    function commandResults(query) {
        var command = commandText(query);
        if (command.length === 0)
            return [];

        return [
            makeResult({
                "id": "command:" + command,
                "title": "运行 Shell 命令",
                "subtitle": "危险：回车将在 shell 中执行 · " + command,
                "icon": iconPath("dock", "terminal.png"),
                "kind": "command",
                "provider": "command",
                "score": 950,
                "command": command
            })
        ];
    }

    function calculatorResults(query) {
        var parsed = parseCalculatorQuery(query);
        if (!parsed)
            return [];

        var valueText = formatNumber(parsed.value);
        return [
            makeResult({
                "id": "calculator:" + parsed.expression,
                "title": valueText,
                "subtitle": parsed.expression + " = " + valueText + " · 回车复制",
                "icon": iconPath("dock", "calculator.png"),
                "kind": "calculator",
                "provider": "calculator",
                "score": 920,
                "copyText": valueText
            })
        ];
    }

    function settingsResults(query) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0)
            return [];

        var results = [];
        for (var i = 0; i < settingsItems.length; i++) {
            var item = settingsItems[i];
            var score = scoreText(item.title, item.subtitle, item.keywords || [], normalized, item.internalPage ? 760 : 620);
            if (score <= 0)
                continue;

            results.push(makeResult({
                "id": "settings:" + item.id,
                "title": item.title,
                "subtitle": item.subtitle,
                "icon": iconPath("dock", "preferences.png"),
                "kind": "settings",
                "provider": "settings",
                "score": score,
                "settingsItem": item
            }));
        }
        return results;
    }

    function systemActionResults(query) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0)
            return [];

        var results = [];
        for (var i = 0; i < systemActionItems.length; i++) {
            var item = systemActionItems[i];
            var score = scoreText(item.title, item.subtitle, item.keywords || [], normalized, 740);
            if (score <= 0)
                continue;

            results.push(makeResult({
                "id": "system-action:" + item.id,
                "title": item.title,
                "subtitle": item.subtitle,
                "icon": iconPath("dock", item.icon || "preferences.png"),
                "kind": "system-action",
                "provider": "system-actions",
                "score": score,
                "systemAction": item.action
            }));
        }
        return results;
    }

    function windowResults(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0 || !root.windowsService)
            return [];

        var windows = root.windowsService.recentWindowList || root.windowsService.windowList || [];
        var max = Math.max(1, limit || root.defaultLimit);
        var results = [];
        for (var i = 0; i < windows.length && results.length < max; i++) {
            var window = windows[i];
            if (!window)
                continue;

            var title = windowTitle(window);
            var subtitle = windowSubtitle(window);
            var score = scoreText(title, subtitle, [window.appId || "", window.output || ""], normalized, 820);
            if (score <= 0)
                continue;

            if (window.isFocused)
                score += 16;
            if (window.isMinimized)
                score += 12;

            results.push(makeResult({
                "id": "window:" + String(window.modelKey || window.id || i),
                "title": title,
                "subtitle": subtitle,
                "icon": windowIcon(window),
                "kind": "window",
                "provider": "windows",
                "score": score,
                "window": window
            }));
        }
        return results;
    }

    function pinnedClipboardResults(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0 || !root.clipboardService || !root.clipboardService.pinnedEntries)
            return [];

        var pins = root.clipboardService.pinnedEntries || [];
        var max = Math.max(1, limit || root.defaultLimit);
        var results = [];
        for (var i = 0; i < pins.length && results.length < max; i++) {
            var pin = pins[i];
            if (!pin)
                continue;

            var preview = String(pin.preview || "").trim();
            var text = String(pin.text || "");
            var title = preview.length > 0 ? preview : root.clipboardService.previewForText(text);
            var score = scoreText(title, "固定剪贴板 · 回车复制", [text], normalized, 700);
            if (score <= 0)
                continue;

            results.push(makeResult({
                "id": "clipboard-pin:" + String(i) + ":" + title,
                "title": title,
                "subtitle": "固定剪贴板 · 回车复制",
                "icon": iconPath("dock", "notes.png"),
                "kind": "clipboard-pin",
                "provider": "clipboard-pins",
                "score": score,
                "pin": pin
            }));
        }
        return results;
    }

    function taskIndexResults(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0 || root.cachedTaskQuery !== normalized)
            return [];

        var entries = root.cachedTaskEntries || [];
        var max = Math.max(1, limit || root.defaultLimit);
        var results = [];
        for (var i = 0; i < entries.length && results.length < max; i++) {
            var entry = entries[i] || {};
            var path = String(entry.path || "").trim();
            if (path.length === 0)
                continue;

            var kind = String(entry.kind || "recent-file");
            var title = String(entry.title || pathBasename(path) || path);
            var subtitle = String(entry.subtitle || (kind === "folder" ? "文件夹" : "最近文件"));
            var score = scoreText(title, subtitle, [path], normalized, kind === "folder" ? 540 : 560);
            if (score <= 0)
                continue;

            results.push(makeResult({
                "id": kind + ":" + path,
                "title": title,
                "subtitle": subtitle,
                "icon": iconPath("dock", kind === "folder" ? "finder.png" : "notes.png"),
                "kind": kind,
                "provider": kind === "folder" ? "folders" : "recent-files",
                "score": score,
                "path": path
            }));
        }
        return results;
    }

    function dedupeAndSort(results, limit) {
        var seen = {};
        var unique = [];
        for (var i = 0; i < results.length; i++) {
            var result = results[i];
            var key = String(result.id || result.kind + ":" + result.title);
            if (key.length === 0 || seen[key])
                continue;

            seen[key] = true;
            result._order = i;
            unique.push(result);
        }

        unique.sort(function(left, right) {
            if (right.score !== left.score)
                return right.score - left.score;

            var leftTitle = normalizedText(left.title);
            var rightTitle = normalizedText(right.title);
            if (leftTitle < rightTitle)
                return -1;
            if (leftTitle > rightTitle)
                return 1;
            return left._order - right._order;
        });

        return unique.slice(0, Math.max(1, limit || root.defaultLimit));
    }

    function shouldRunTaskIndex(query) {
        var normalized = String(query || "").trim();
        if (normalized.length < 2)
            return false;

        var prefix = normalized.charAt(0);
        return prefix !== ">" && prefix !== "!" && prefix !== "=";
    }

    function scheduleTaskIndex(query) {
        var normalized = String(query || "").trim();
        if (!shouldRunTaskIndex(normalized)) {
            root.pendingTaskQuery = "";
            return;
        }

        if (root.cachedTaskQuery === normalized || root.activeTaskQuery === normalized || root.pendingTaskQuery === normalized)
            return;

        root.pendingTaskQuery = normalized;
        taskIndexDebounceTimer.restart();
    }

    function startTaskIndex() {
        if (taskIndexProcess.running)
            return;
        if (root.pendingTaskQuery.length === 0)
            return;

        root.activeTaskQuery = root.pendingTaskQuery;
        root.taskIndexOutputQuery = root.activeTaskQuery;
        root.pendingTaskQuery = "";
        taskIndexProcess.running = true;
    }

    function taskIndexCommand(query) {
        if (root.commandRunner && root.commandRunner.revision > 0 && !root.commandRunner.commandAvailable("python3"))
            return ["sh", "-c", "exit 0"];

        return [
            "sh",
            "-lc",
            "if command -v python3 >/dev/null 2>&1; then " +
                "if command -v timeout >/dev/null 2>&1; then " +
                    "exec timeout 1s python3 -c \"$1\" \"$2\"; " +
                "else " +
                    "exec python3 -c \"$1\" \"$2\"; " +
                "fi; " +
            "fi",
            "sh",
            taskIndexPython(),
            String(query || "")
        ];
    }

    function taskIndexPython() {
        return [
            "import datetime, json, os, sys, time, urllib.parse, xml.etree.ElementTree as ET",
            "query = sys.argv[1].strip().lower() if len(sys.argv) > 1 else ''",
            "terms = [term for term in query.split() if term]",
            "deadline = time.monotonic() + 0.82",
            "home = os.path.expanduser('~')",
            "results = []",
            "seen = set()",
            "def expired():",
            "    return time.monotonic() > deadline",
            "def compact(path):",
            "    if home and path.startswith(home + os.sep):",
            "        return '~' + path[len(home):]",
            "    return path",
            "def matches(*values):",
            "    haystack = ' '.join(str(value or '').lower() for value in values)",
            "    return all(term in haystack for term in terms)",
            "def basename(path):",
            "    name = os.path.basename(path.rstrip(os.sep))",
            "    return name or path",
            "def stamp(value):",
            "    if not value:",
            "        return 0.0",
            "    try:",
            "        return datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()",
            "    except Exception:",
            "        return 0.0",
            "def add(kind, path, title, subtitle, mtime=0.0):",
            "    if expired():",
            "        return",
            "    path = os.path.abspath(os.path.expanduser(path))",
            "    if path in seen or not os.path.exists(path):",
            "        return",
            "    if kind == 'folder':",
            "        if not os.path.isdir(path):",
            "            return",
            "    elif not os.path.isfile(path):",
            "        return",
            "    title = str(title or basename(path)).strip()",
            "    subtitle = str(subtitle or compact(path)).strip()",
            "    if terms and not matches(title, subtitle, path):",
            "        return",
            "    seen.add(path)",
            "    results.append({'kind': kind, 'path': path, 'title': title, 'subtitle': subtitle, 'mtime': float(mtime or 0)})",
            "def bookmark_title(bookmark, fallback):",
            "    for child in list(bookmark):",
            "        if child.tag.rsplit('}', 1)[-1] == 'title' and child.text:",
            "            text = child.text.strip()",
            "            if text:",
            "                return text",
            "    return fallback",
            "def local_href_path(href):",
            "    parsed = urllib.parse.urlparse(href or '')",
            "    if parsed.scheme != 'file':",
            "        return ''",
            "    return urllib.parse.unquote(parsed.path or '')",
            "def add_recent_files():",
            "    xbel = os.path.join(home, '.local', 'share', 'recently-used.xbel')",
            "    try:",
            "        bookmarks = ET.parse(xbel).getroot().findall('.//{*}bookmark')",
            "    except Exception:",
            "        return",
            "    for bookmark in bookmarks[:450]:",
            "        if expired() or len(results) >= 80:",
            "            return",
            "        path = local_href_path(bookmark.attrib.get('href', ''))",
            "        if not path:",
            "            continue",
            "        title = bookmark_title(bookmark, basename(path))",
            "        mtime = stamp(bookmark.attrib.get('modified') or bookmark.attrib.get('visited') or bookmark.attrib.get('added'))",
            "        add('recent-file', path, title, '最近文件 · ' + compact(path), mtime)",
            "def configured_user_dirs():",
            "    paths = [home]",
            "    config = os.path.join(home, '.config', 'user-dirs.dirs')",
            "    try:",
            "        with open(config, 'r', encoding='utf-8', errors='ignore') as handle:",
            "            for line in handle:",
            "                line = line.strip()",
            "                if not line.startswith('XDG_') or '=' not in line:",
            "                    continue",
            "                value = line.split('=', 1)[1].strip().strip(chr(34))",
            "                value = value.replace('$HOME', home)",
            "                paths.append(os.path.expandvars(value))",
            "    except Exception:",
            "        pass",
            "    for name in ('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos', 'Templates', 'Public', 'Projects'):",
            "        paths.append(os.path.join(home, name))",
            "    unique = []",
            "    used = set()",
            "    for path in paths:",
            "        path = os.path.abspath(os.path.expanduser(path))",
            "        if path not in used and os.path.isdir(path):",
            "            used.add(path)",
            "            unique.append(path)",
            "    return unique",
            "def add_folders():",
            "    roots = configured_user_dirs()",
            "    for path in roots:",
            "        if expired() or len(results) >= 80:",
            "            return",
            "        add('folder', path, basename(path), '文件夹 · ' + compact(path), os.path.getmtime(path) if os.path.exists(path) else 0)",
            "    for base in roots[:7]:",
            "        if expired() or len(results) >= 80:",
            "            return",
            "        try:",
            "            with os.scandir(base) as entries:",
            "                for entry in entries:",
            "                    if expired() or len(results) >= 80:",
            "                        return",
            "                    try:",
            "                        if entry.is_dir(follow_symlinks=False):",
            "                            stat = entry.stat(follow_symlinks=False)",
            "                            add('folder', entry.path, entry.name, '文件夹 · ' + compact(entry.path), stat.st_mtime)",
            "                    except Exception:",
            "                        pass",
            "        except Exception:",
            "            pass",
            "add_recent_files()",
            "add_folders()",
            "results.sort(key=lambda item: (float(item.get('mtime') or 0), 1 if item.get('kind') == 'folder' else 0), reverse=True)",
            "print(json.dumps(results[:80], ensure_ascii=False))"
        ].join("\n");
    }

    function parseTaskIndexOutput(text) {
        var entries = [];
        try {
            var parsed = JSON.parse(String(text || "[]"));
            var list = Array.isArray(parsed) ? parsed : [];
            for (var i = 0; i < list.length && entries.length < 80; i++) {
                var item = list[i] || {};
                var kind = String(item.kind || "");
                var path = String(item.path || "").trim();
                if ((kind === "recent-file" || kind === "folder") && path.length > 0) {
                    entries.push({
                        "kind": kind,
                        "path": path,
                        "title": String(item.title || pathBasename(path)),
                        "subtitle": String(item.subtitle || compactPath(path)),
                        "mtime": Number(item.mtime || 0)
                    });
                }
            }
        } catch (e) {
            entries = [];
        }

        root.cachedTaskQuery = root.taskIndexOutputQuery;
        root.cachedTaskEntries = entries;
        bumpProviderRevision();
    }

    function resultsForQuery(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0)
            return [];

        var revision = root.providerRevision;
        var max = Math.max(1, limit || root.defaultLimit);
        var results = [];
        scheduleTaskIndex(normalized);
        results = results.concat(commandResults(normalized));
        results = results.concat(calculatorResults(normalized));
        results = results.concat(screenshotResults(normalized));
        results = results.concat(settingsResults(normalized));
        results = results.concat(systemActionResults(normalized));
        results = results.concat(windowResults(normalized, max));
        results = results.concat(pinnedClipboardResults(normalized, max));
        results = results.concat(appResults(normalized, max));
        results = results.concat(taskIndexResults(normalized, max));
        return dedupeAndSort(results, max);
    }

    function resultTitle(result) {
        return String(result && result.title || result && result.name || "");
    }

    function resultSubtitle(result) {
        return String(result && result.subtitle || result && result.genericName || "");
    }

    function resultIcon(result) {
        return String(result && result.icon || "");
    }

    function activateResult(result) {
        if (!result)
            return false;

        if (result.kind === "application" && root.appsService) {
            root.appsService.launchApp(result.app);
            return true;
        }

        if (result.kind === "screenshot" && root.screenshotService) {
            root.screenshotService.activateResult(result);
            return true;
        }

        if (result.kind === "calculator")
            return copyText(result.copyText);

        if (result.kind === "command") {
            runShellCommand(result.command);
            return true;
        }

        if (result.kind === "settings")
            return activateSettingsItem(result.settingsItem);

        if (result.kind === "window")
            return activateWindowResult(result.window);

        if (result.kind === "recent-file" || result.kind === "folder")
            return openPath(result.path);

        if (result.kind === "clipboard-pin")
            return copyPinnedClipboardResult(result.pin);

        if (result.kind === "system-action") {
            root.systemActionRequested(String(result.systemAction || ""));
            return true;
        }

        return false;
    }

    function activateShortcut(kind, query) {
        if (kind === "copy")
            return copyText(query);

        var candidates = [];
        if (kind === "store") {
            candidates = [
                "org.gnome.Software",
                "gnome-software",
                "org.kde.discover",
                "plasma-discover",
                "software"
            ];
        } else if (kind === "files") {
            candidates = [
                "org.gnome.Nautilus",
                "nautilus",
                "org.kde.dolphin",
                "dolphin",
                "thunar",
                "files"
            ];
        } else if (kind === "shortcuts") {
            candidates = [
                "shortcuts",
                "org.gnome.Settings",
                "gnome-control-center",
                "systemsettings",
                "settings"
            ];
        }

        return launchCandidateApp(candidates);
    }

    function launchCandidateApp(candidates) {
        if (!root.appsService || !candidates || candidates.length === 0)
            return false;

        var app = root.appsService.findApplication(candidates);
        if (!app)
            return false;

        root.appsService.launchApp(app);
        return true;
    }

    function copyText(text) {
        var value = String(text || "");
        if (value.trim().length === 0)
            return false;

        Quickshell.execDetached({
            command: ["sh", "-c", "printf %s \"$1\" | wl-copy --type 'text/plain;charset=utf-8'", "sh", value],
            workingDirectory: ""
        });
        return true;
    }

    function activateWindowResult(window) {
        if (!window || !root.windowsService)
            return false;

        if (window.isMinimized && root.windowsService.restore)
            root.windowsService.restore(window);
        else if (root.windowsService.activate)
            root.windowsService.activate(window);
        else
            return false;
        return true;
    }

    function openPath(path) {
        var value = String(path || "").trim();
        if (value.length === 0)
            return false;

        Quickshell.execDetached({
            command: ["xdg-open", value],
            workingDirectory: ""
        });
        return true;
    }

    function copyPinnedClipboardResult(pin) {
        if (!pin || !root.clipboardService || !root.clipboardService.copyPinnedEntry)
            return false;

        root.clipboardService.copyPinnedEntry(pin);
        return true;
    }

    function runShellCommand(command) {
        var text = String(command || "").trim();
        if (text.length === 0)
            return;

        Quickshell.execDetached({
            command: ["sh", "-lc", text],
            workingDirectory: ""
        });
    }

    function activateSettingsItem(item) {
        if (!item)
            return false;

        if (item.internalPage) {
            root.openSettingsRequested(String(item.internalPage || "settings"));
            return true;
        }

        if (item.appCandidates && launchCandidateApp(item.appCandidates))
            return true;

        if (item.commands && item.commands.length > 0) {
            runFirstAvailableCommand(item.commands);
            return true;
        }

        return false;
    }

    function shellQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\\''") + "'";
    }

    function runFirstAvailableCommand(commands) {
        var script = [];
        for (var i = 0; i < commands.length; i++) {
            var command = commands[i] || [];
            if (command.length === 0)
                continue;

            var binary = shellQuote(command[0]);
            var argv = [];
            for (var j = 0; j < command.length; j++)
                argv.push(shellQuote(command[j]));

            script.push("if command -v " + binary + " >/dev/null 2>&1; then exec " + argv.join(" ") + "; fi");
        }
        script.push("exit 1");

        Quickshell.execDetached({
            command: ["sh", "-lc", script.join("\n")],
            workingDirectory: ""
        });
    }

    function parseCalculatorQuery(query) {
        var raw = String(query || "").trim();
        if (raw.length === 0)
            return null;

        var explicit = raw.charAt(0) === "=";
        var expression = explicit ? raw.substring(1).trim() : raw;
        expression = expression.replace(/×/g, "*").replace(/÷/g, "/").replace(/，/g, ".");
        if (expression.length === 0 || !/[0-9]/.test(expression))
            return null;
        if (!/^[0-9+\-*/%^().\s]+$/.test(expression))
            return null;
        if (!explicit && !/[+\-*/%^()]/.test(expression))
            return null;
        if (/^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$/.test(expression))
            return null;

        try {
            var state = { "text": expression, "pos": 0 };
            var value = parseExpression(state);
            skipSpaces(state);
            if (state.pos !== state.text.length || !isFinite(value))
                return null;
            return { "expression": expression, "value": value };
        } catch (e) {
            return null;
        }
    }

    function skipSpaces(state) {
        while (state.pos < state.text.length && /\s/.test(state.text.charAt(state.pos)))
            state.pos += 1;
    }

    function parseExpression(state) {
        var value = parseTerm(state);
        while (true) {
            skipSpaces(state);
            var op = state.text.charAt(state.pos);
            if (op !== "+" && op !== "-")
                break;

            state.pos += 1;
            var right = parseTerm(state);
            value = op === "+" ? value + right : value - right;
        }
        return value;
    }

    function parseTerm(state) {
        var value = parsePower(state);
        while (true) {
            skipSpaces(state);
            var op = state.text.charAt(state.pos);
            if (op !== "*" && op !== "/" && op !== "%")
                break;

            state.pos += 1;
            var right = parsePower(state);
            if (op === "*")
                value *= right;
            else if (op === "/")
                value /= right;
            else
                value %= right;
        }
        return value;
    }

    function parsePower(state) {
        var value = parseUnary(state);
        skipSpaces(state);
        if (state.text.charAt(state.pos) === "^") {
            state.pos += 1;
            value = Math.pow(value, parsePower(state));
        }
        return value;
    }

    function parseUnary(state) {
        skipSpaces(state);
        var op = state.text.charAt(state.pos);
        if (op === "+" || op === "-") {
            state.pos += 1;
            var value = parseUnary(state);
            return op === "-" ? -value : value;
        }
        return parsePrimary(state);
    }

    function parsePrimary(state) {
        skipSpaces(state);
        var ch = state.text.charAt(state.pos);
        if (ch === "(") {
            state.pos += 1;
            var value = parseExpression(state);
            skipSpaces(state);
            if (state.text.charAt(state.pos) !== ")")
                throw "missing closing parenthesis";
            state.pos += 1;
            return value;
        }
        return parseNumber(state);
    }

    function parseNumber(state) {
        skipSpaces(state);
        var start = state.pos;
        var dotSeen = false;
        var digitSeen = false;
        while (state.pos < state.text.length) {
            var ch = state.text.charAt(state.pos);
            if (ch >= "0" && ch <= "9") {
                digitSeen = true;
                state.pos += 1;
            } else if (ch === "." && !dotSeen) {
                dotSeen = true;
                state.pos += 1;
            } else {
                break;
            }
        }

        if (!digitSeen)
            throw "number expected";

        return Number(state.text.substring(start, state.pos));
    }

    function formatNumber(value) {
        if (Math.abs(value) < 1e-12)
            return "0";
        if (Math.abs(value - Math.round(value)) < 1e-10)
            return String(Math.round(value));

        var text = Math.abs(value) >= 1000000000000 || Math.abs(value) < 0.000001
            ? value.toPrecision(12)
            : value.toFixed(10);
        text = text.replace(/(\.\d*?)0+($|e)/, "$1$2");
        text = text.replace(/\.($|e)/, "$1");
        return text;
    }

    Timer {
        id: taskIndexDebounceTimer
        interval: root.slowProviderDebounceMs
        repeat: false
        onTriggered: root.startTaskIndex()
    }

    Process {
        id: taskIndexProcess
        running: false
        command: root.taskIndexCommand(root.activeTaskQuery)

        stdout: StdioCollector {
            id: taskIndexOut
            onStreamFinished: root.parseTaskIndexOutput(taskIndexOut.text)
        }

        onExited: function(code, exitStatus) {
            Qt.callLater(function() {
                root.activeTaskQuery = "";
                if (root.pendingTaskQuery.length > 0)
                    root.startTaskIndex();
            });
        }
    }
}
