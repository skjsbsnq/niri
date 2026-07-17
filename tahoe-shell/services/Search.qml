pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "search/AppProvider.js" as AppProvider
import "search/CalculatorProvider.js" as CalculatorProvider
import "search/ClipboardProvider.js" as ClipboardProvider
import "search/CommandProvider.js" as CommandProvider
import "search/ScreenshotProvider.js" as ScreenshotProvider
import "search/SettingsProvider.js" as SettingsProvider
import "search/SystemActionProvider.js" as SystemActionProvider
import "search/TaskIndexProvider.js" as TaskIndexProvider
import "search/WindowProvider.js" as WindowProvider

Item {
    id: root
    visible: false

    property var appsService
    property var screenshotService
    property var windowsService
    property var clipboardService
    property var commandRunner
    property bool active: true
    readonly property int defaultLimit: 6
    readonly property int slowProviderDebounceMs: 90
    property int providerRevision: 0
    property int taskIndexGeneration: 0
    property int activeTaskGeneration: 0
    property string latestTaskQuery: ""
    property string pendingTaskQuery: ""
    property string activeTaskQuery: ""
    property string taskIndexStdoutText: ""
    property int taskIndexStdoutGeneration: 0
    property string cachedTaskQuery: ""
    property var cachedTaskEntries: []
    readonly property var settingsItems: [
        {
            "id": "tahoe-settings",
            "title": "设置",
            "subtitle": "Wi-Fi、网络、蓝牙、显示、电源、应用和系统",
            "keywords": ["设置", "tahoe", "settings", "preferences", "desktop", "wifi", "network", "bluetooth", "display", "power", "应用", "系统"],
            "internalPage": "settings"
        },
        {
            "id": "tahoe-wallpaper",
            "title": "壁纸设置",
            "subtitle": "静态图片、动态命令和 Linux Wallpaper Engine UX",
            "keywords": ["壁纸", "动态壁纸", "wallpaper", "live wallpaper", "linux-wallpaper-engine", "wallpaperengine", "ux"],
            "internalPage": "appearance"
        },
        {
            "id": "tahoe-apps",
            "title": "应用设置",
            "subtitle": "默认应用、应用列表和权限状态",
            "keywords": ["应用", "默认应用", "权限", "apps", "applications", "default apps", "permissions"],
            "internalPage": "apps"
        },
        {
            "id": "tahoe-displays",
            "title": "显示器设置",
            "subtitle": "显示输出、夜览和色温",
            "keywords": ["显示", "显示器", "缩放", "夜览", "色温", "display", "monitor", "scale", "night light"],
            "internalPage": "displays"
        },
        {
            "id": "tahoe-power",
            "title": "电源设置",
            "subtitle": "电池、亮度、电源模式和空闲锁定",
            "keywords": ["电源", "电池", "亮度", "省电", "性能", "锁屏", "power", "battery", "brightness", "profile", "idle"],
            "internalPage": "power"
        },
        {
            "id": "tahoe-notifications",
            "title": "通知设置",
            "subtitle": "勿扰和通知历史",
            "keywords": ["通知", "勿扰", "历史", "notification", "notifications", "dnd"],
            "internalPage": "notifications"
        },
        {
            "id": "tahoe-keyboard",
            "title": "键盘设置",
            "subtitle": "按键重复、输入法、快捷键和截图",
            "keywords": ["键盘", "输入法", "快捷键", "截图", "repeat", "keyboard", "input method", "shortcut", "screenshot"],
            "internalPage": "keyboard"
        },
        {
            "id": "tahoe-mouse-touchpad",
            "title": "鼠标与触摸板",
            "subtitle": "触摸板点按、自然滚动和指针速度",
            "keywords": ["鼠标", "触摸板", "触控板", "滚动", "指针", "mouse", "touchpad", "scroll", "pointer"],
            "internalPage": "mouse-touchpad"
        },
        {
            "id": "tahoe-dock",
            "title": "Dock 设置",
            "subtitle": "自动隐藏、触发热区和窗口按钮",
            "keywords": ["dock", "自动隐藏", "隐藏", "热区", "窗口标题", "autohide", "auto hide"],
            "internalPage": "multitasking"
        },
        {
            "id": "tahoe-dynamic-island",
            "title": "灵动岛设置",
            "subtitle": "顶栏胶囊、点击行为和 hover 展开",
            "keywords": ["灵动岛", "dynamic island", "island", "胶囊", "顶栏", "时间", "hover", "媒体"],
            "internalPage": "multitasking"
        },
        {
            "id": "tahoe-health",
            "title": "系统健康",
            "subtitle": "检查 portal、PipeWire、截图、剪贴板、托盘和兼容性",
            "keywords": ["健康", "诊断", "依赖", "状态", "health", "diagnostics", "status", "pipewire", "portal", "tray"],
            "internalPage": "system"
        },
        {
            "id": "tahoe-about",
            "title": "关于 niri",
            "subtitle": "版本、提交、子模块、GPU 和会话信息",
            "keywords": ["关于", "版本", "提交", "about", "version", "commit", "gpu", "session", "niri", "quickshell"],
            "internalPage": "system"
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
            "title": "旧输入与显示入口",
            "subtitle": "已归档到键盘、鼠标与触摸板、显示器",
            "keywords": ["输入", "键盘", "触摸板", "触控板", "重复", "自然滚动", "numlock", "显示", "缩放", "input", "keyboard", "touchpad", "display", "niri"],
            "internalPage": "keyboard"
        },
        {
            "id": "tahoe-niri-animations",
            "title": "动画",
            "subtitle": "工作区、窗口与概览的弹簧动画",
            "keywords": ["动画", "弹簧", "阻尼", "刚度", "弹性", "animation", "spring", "damping", "stiffness", "niri"],
            "internalPage": "multitasking"
        },
        {
            "id": "tahoe-niri-keyboard",
            "title": "键盘快捷键",
            "subtitle": "niri binds 只读查看",
            "keywords": ["快捷键", "键位", "binds", "shortcut", "keybind", "热键", "niri"],
            "internalPage": "keyboard"
        },
        {
            "id": "tahoe-weather",
            "title": "天气设置",
            "subtitle": "定位、手动覆盖和温度单位",
            "keywords": ["天气", "定位", "温度", "weather", "forecast", "temperature", "location"],
            "internalPage": "system"
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

    function providerContext() {
        return {
            "appsService": root.appsService,
            "screenshotService": root.screenshotService,
            "windowsService": root.windowsService,
            "clipboardService": root.clipboardService,
            "commandRunner": root.commandRunner,
            "defaultLimit": root.defaultLimit,
            "settingsItems": root.settingsItems,
            "systemActionItems": root.systemActionItems,
            "cachedTaskQuery": root.cachedTaskQuery,
            "cachedTaskEntries": root.cachedTaskEntries,
            "normalizedText": root.normalizedText,
            "iconPath": root.iconPath,
            "pathBasename": root.pathBasename,
            "compactPath": root.compactPath,
            "scoreText": root.scoreText,
            "makeResult": root.makeResult
        };
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
        return WindowProvider.title(window, providerContext());
    }

    function windowSubtitle(window) {
        return WindowProvider.subtitle(window, providerContext());
    }

    function windowIcon(window) {
        return WindowProvider.icon(window, providerContext());
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
        return AppProvider.results(query, limit, providerContext());
    }

    function screenshotResults(query) {
        return ScreenshotProvider.results(query, providerContext());
    }

    function commandText(query) {
        return CommandProvider.commandText(query);
    }

    function commandResults(query) {
        return CommandProvider.results(query, providerContext());
    }

    function calculatorResults(query) {
        return CalculatorProvider.results(query, providerContext());
    }

    function settingsResults(query) {
        return SettingsProvider.results(query, providerContext());
    }

    function systemActionResults(query) {
        return SystemActionProvider.results(query, providerContext());
    }

    function windowResults(query, limit) {
        return WindowProvider.results(query, limit, providerContext());
    }

    function pinnedClipboardResults(query, limit) {
        return ClipboardProvider.results(query, limit, providerContext());
    }

    function taskIndexResults(query, limit) {
        return TaskIndexProvider.results(query, limit, providerContext());
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
        return TaskIndexProvider.shouldRun(query);
    }

    function scheduleTaskIndex(query) {
        var normalized = String(query || "").trim();
        if (root.latestTaskQuery === normalized && root.active)
            return;

        root.taskIndexGeneration += 1;
        root.latestTaskQuery = normalized;
        root.pendingTaskQuery = "";
        taskIndexDebounceTimer.stop();

        if (taskIndexProcess.running)
            taskIndexProcess.running = false;

        if (!root.active || !shouldRunTaskIndex(normalized))
            return;
        if (root.cachedTaskQuery === normalized)
            return;

        root.pendingTaskQuery = normalized;
        taskIndexDebounceTimer.restart();
    }

    function startTaskIndex() {
        if (!root.active || taskIndexProcess.running)
            return;
        if (root.pendingTaskQuery.length === 0)
            return;
        if (root.pendingTaskQuery !== root.latestTaskQuery)
            return;

        root.activeTaskQuery = root.pendingTaskQuery;
        root.activeTaskGeneration = root.taskIndexGeneration;
        root.taskIndexStdoutText = "";
        root.taskIndexStdoutGeneration = 0;
        root.pendingTaskQuery = "";
        taskIndexProcess.running = true;
    }

    function cancelTaskIndex() {
        root.taskIndexGeneration += 1;
        root.latestTaskQuery = "";
        root.pendingTaskQuery = "";
        taskIndexDebounceTimer.stop();
        if (taskIndexProcess.running)
            taskIndexProcess.running = false;
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
        return TaskIndexProvider.pythonSource();
    }

    function parseTaskIndexOutput(text, query) {
        var entries = TaskIndexProvider.parseOutput(text, providerContext());

        root.cachedTaskQuery = String(query || "");
        root.cachedTaskEntries = entries;
        bumpProviderRevision();
    }

    function finishTaskIndex(code, generation, query, text) {
        var gen = Number(generation);
        if (gen <= 0 || gen !== Number(root.activeTaskGeneration))
            return;

        root.activeTaskGeneration = 0;
        root.activeTaskQuery = "";
        if (code === 0
                && root.active
                && gen === Number(root.taskIndexGeneration)
                && String(query || "") === root.latestTaskQuery)
            root.parseTaskIndexOutput(text, query);

        Qt.callLater(function() {
            if (root.active
                    && root.pendingTaskQuery.length > 0
                    && !taskIndexDebounceTimer.running
                    && !taskIndexProcess.running)
                root.startTaskIndex();
        });
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
        return CalculatorProvider.parseQuery(query);
    }

    function formatNumber(value) {
        return CalculatorProvider.formatNumber(value);
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
            onStreamFinished: {
                root.taskIndexStdoutText = taskIndexOut.text;
                root.taskIndexStdoutGeneration = root.activeTaskGeneration;
            }
        }

        onExited: function(code, exitStatus) {
            var generation = root.activeTaskGeneration;
            var query = root.activeTaskQuery;
            var text = root.taskIndexStdoutGeneration === generation
                ? root.taskIndexStdoutText
                : taskIndexOut.text;
            root.finishTaskIndex(code, generation, query, text);
        }
        onRunningChanged: {
            if (!taskIndexProcess.running && root.activeTaskGeneration > 0)
                root.finishTaskIndex(-1, root.activeTaskGeneration, root.activeTaskQuery, "");
        }
    }

    onActiveChanged: {
        if (!root.active)
            root.cancelTaskIndex();
    }
}
