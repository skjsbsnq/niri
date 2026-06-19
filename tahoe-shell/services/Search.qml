pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root
    visible: false

    property var appsService
    property var screenshotService
    readonly property int defaultLimit: 6
    readonly property var settingsItems: [
        {
            "id": "tahoe-settings",
            "title": "Tahoe 设置",
            "subtitle": "外观、通知、输入法、截图、Dock 和启动项",
            "keywords": ["设置", "tahoe", "settings", "preferences", "desktop", "dock", "截图", "通知", "输入法"],
            "internalPage": "settings"
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

    signal openSettingsRequested(string page)

    function normalizedText(value) {
        return String(value || "").trim().toLowerCase();
    }

    function iconPath(iconSet, fileName) {
        return root.appsService ? root.appsService.iconPath(iconSet, fileName) : "";
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
                "title": "运行命令",
                "subtitle": command,
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

    function resultsForQuery(query, limit) {
        var normalized = String(query || "").trim();
        if (normalized.length === 0)
            return [];

        var max = Math.max(1, limit || root.defaultLimit);
        var results = [];
        results = results.concat(commandResults(normalized));
        results = results.concat(calculatorResults(normalized));
        results = results.concat(screenshotResults(normalized));
        results = results.concat(settingsResults(normalized));
        results = results.concat(appResults(normalized, max));
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
            command: ["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", value],
            workingDirectory: ""
        });
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
}
