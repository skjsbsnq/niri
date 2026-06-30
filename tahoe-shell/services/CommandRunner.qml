pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Central command/dependency policy for Tahoe shell services.
Item {
    id: root
    visible: false

    property var dependencies: ({})
    property var commandMap: ({})
    property var statusItems: []
    property bool refreshing: false
    property int revision: 0
    property string lastUpdatedText: "尚未检测"
    property string lastError: ""
    property var lastActionResult: null

    signal actionFinished(var result)

    function refreshDependencies() {
        if (dependencyProbe.running)
            return;

        refreshing = true;
        lastError = "";
        dependencyProbe.running = true;
    }

    function dependency(id) {
        return root.dependencies[String(id || "")] || null;
    }

    function dependencyState(id) {
        var item = dependency(id);
        return item ? String(item.state || "") : "missing";
    }

    function dependencyDetail(id) {
        var item = dependency(id);
        return item ? String(item.detail || "") : "";
    }

    function dependencyReady(id) {
        var state = dependencyState(id);
        return state === "ok" || state === "warn";
    }

    function commandAvailable(name) {
        return !!root.commandMap[String(name || "")];
    }

    function missingCommands(commands) {
        var missing = [];
        var values = Array.isArray(commands) ? commands : [];
        for (var i = 0; i < values.length; i++) {
            var command = String(values[i] || "").trim();
            if (command.length > 0 && !commandAvailable(command))
                missing.push(command);
        }
        return missing;
    }

    function makeResult(action, status, message, detail, missing, exitCode) {
        return {
            "action": String(action || ""),
            "status": String(status || "failure"),
            "success": status === "success",
            "message": String(message || ""),
            "detail": String(detail || ""),
            "missing": Array.isArray(missing) ? missing : [],
            "exitCode": exitCode === undefined || exitCode === null ? -1 : Number(exitCode),
            "timestamp": new Date().toISOString()
        };
    }

    function emitResult(result) {
        root.lastActionResult = result;
        root.actionFinished(result);
        return result;
    }

    function successResult(action, message, detail) {
        return emitResult(makeResult(action, "success", message || "已启动", detail || "", [], 0));
    }

    function failureResult(action, message, detail, exitCode) {
        return emitResult(makeResult(action, "failure", message || "执行失败", detail || "", [], exitCode));
    }

    function missingResult(action, missing, message, detail) {
        return emitResult(makeResult(action, "missing", message || "缺少依赖", detail || "", missing || [], 127));
    }

    function timeoutResult(action, message, detail) {
        return emitResult(makeResult(action, "timeout", message || "执行超时", detail || "", [], 124));
    }

    function cancelledResult(action, message, detail) {
        return emitResult(makeResult(action, "cancelled", message || "用户取消", detail || "", [], 0));
    }

    function notify(title, body) {
        if (!commandAvailable("notify-send"))
            return false;

        try {
            Quickshell.execDetached({
                command: ["notify-send", "-a", "niri", String(title || ""), String(body || "")],
                workingDirectory: ""
            });
            return true;
        } catch (error) {
            return false;
        }
    }

    function runDetached(action, command, requiredCommands, options) {
        var opts = options || {};
        if (root.revision === 0)
            refreshDependencies();
        var missing = root.revision > 0 ? missingCommands(requiredCommands || []) : [];
        if (missing.length > 0) {
            var detail = String(opts.missingDetail || ("缺少 " + missing.join(" ")));
            if (opts.notifyOnMissing)
                notify(String(opts.missingTitle || "操作不可用"), detail);
            return missingResult(action, missing, String(opts.missingMessage || "缺少依赖"), detail);
        }

        if (!command || command.length === 0)
            return failureResult(action, "命令为空", "");

        try {
            Quickshell.execDetached({
                command: command,
                workingDirectory: String(opts.workingDirectory || "")
            });
            return successResult(action, String(opts.successMessage || "已启动"), String(opts.successDetail || ""));
        } catch (error) {
            return failureResult(action, String(opts.failureMessage || "执行失败"), String(error));
        }
    }

    function shellCommand(script, args) {
        var command = ["sh", "-lc", String(script || ""), "sh"];
        var values = Array.isArray(args) ? args : [];
        for (var i = 0; i < values.length; i++)
            command.push(String(values[i] === undefined || values[i] === null ? "" : values[i]));
        return command;
    }

    function screenshotSelectionCommand(configuredDirectory, copyToClipboard, offerActions) {
        return shellCommand([
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
        ].join("\n"), [
            configuredDirectory,
            copyToClipboard ? "1" : "0",
            offerActions ? "1" : "0"
        ]);
    }

    function runScreenshotSelection(configuredDirectory, copyToClipboard, offerActions) {
        return runDetached("screenshot.selection", screenshotSelectionCommand(configuredDirectory, copyToClipboard, offerActions), ["grim", "slurp"], {
            "notifyOnMissing": true,
            "missingTitle": "截图不可用",
            "missingMessage": "截图依赖缺失",
            "missingDetail": "请安装 grim 和 slurp",
            "successMessage": "截图工具已启动"
        });
    }

    function clipboardCopyEntryCommand(raw, mimeType) {
        return shellCommand("printf %s \"$1\" | cliphist decode | wl-copy --type \"$2\"", [raw, mimeType]);
    }

    function clipboardCopyTextCommand(text, mimeType) {
        return shellCommand("printf %s \"$1\" | wl-copy --type \"$2\"", [text, mimeType]);
    }

    function clipboardDeleteEntryCommand(raw) {
        return shellCommand("printf %s \"$1\" | cliphist delete", [raw]);
    }

    function clipboardDecodeCommand(raw) {
        return shellCommand("printf %s \"$1\" | cliphist decode", [raw]);
    }

    function clipboardListCommand() {
        return ["cliphist", "list"];
    }

    function clipboardClearHistoryCommand() {
        return ["cliphist", "wipe"];
    }

    function clipboardWatchCommand() {
        return ["wl-paste", "--watch", "cliphist", "store"];
    }

    function runClipboardCopyEntry(raw, mimeType) {
        return runDetached("clipboard.copy-entry", clipboardCopyEntryCommand(raw, mimeType), ["cliphist", "wl-copy"], {
            "missingMessage": "剪贴板复制不可用",
            "missingDetail": "需要 cliphist 和 wl-copy",
            "successMessage": "已复制"
        });
    }

    function runClipboardCopyText(text, mimeType) {
        return runDetached("clipboard.copy-text", clipboardCopyTextCommand(text, mimeType), ["wl-copy"], {
            "missingMessage": "剪贴板复制不可用",
            "missingDetail": "需要 wl-copy",
            "successMessage": "已复制"
        });
    }

    function runClipboardDeleteEntry(raw) {
        return runDetached("clipboard.delete-entry", clipboardDeleteEntryCommand(raw), ["cliphist"], {
            "missingMessage": "剪贴板删除不可用",
            "missingDetail": "需要 cliphist",
            "successMessage": "已删除"
        });
    }

    function runClipboardClearHistory() {
        return runDetached("clipboard.clear-history", clipboardClearHistoryCommand(), ["cliphist"], {
            "missingMessage": "剪贴板清空不可用",
            "missingDetail": "需要 cliphist",
            "successMessage": "已清空历史"
        });
    }

    function appMenuProbeCommand(windowId, pid, appId, title) {
        return [
            "python3",
            Quickshell.shellPath("services/appmenu_probe.py"),
            String(windowId || ""),
            String(pid || ""),
            String(appId || ""),
            String(title || "")
        ];
    }

    function appMenuTriggerCommand(service, path, itemId) {
        return [
            "busctl",
            "--user",
            "call",
            String(service || ""),
            String(path || ""),
            "com.canonical.dbusmenu",
            "Event",
            "isvu",
            String(itemId),
            "clicked",
            "i",
            "0",
            "0"
        ];
    }

    function inputMethodProbeCommand() {
        return shellCommand([
            "if ! command -v fcitx5-remote >/dev/null 2>&1; then echo '0|'; exit 0; fi",
            "state=\"$(fcitx5-remote 2>/dev/null || echo 0)\"",
            "name=\"$(fcitx5-remote -n 2>/dev/null || true)\"",
            "printf '%s|%s\\n' \"$state\" \"$name\""
        ].join("; "), []);
    }

    function inputMethodToggleCommand() {
        return ["fcitx5-remote", "-t"];
    }

    function wifiRestorePreferredCommand(ssid) {
        return shellCommand([
            "ssid=\"$1\"",
            "[ -n \"$ssid\" ] || exit 0",
            "command -v nmcli >/dev/null 2>&1 || exit 0",
            "nmcli radio wifi on >/dev/null 2>&1 || true",
            "nmcli connection modify \"$ssid\" connection.autoconnect yes >/dev/null 2>&1 || true",
            "nmcli --wait 20 connection up id \"$ssid\" >/dev/null 2>&1",
            "  || nmcli --wait 20 device wifi connect \"$ssid\" >/dev/null 2>&1",
            "  || true"
        ].join("\n"), [ssid]);
    }

    function wifiAutoconnectCommand(ssid) {
        return shellCommand([
            "ssid=\"$1\"",
            "[ -n \"$ssid\" ] || exit 0",
            "command -v nmcli >/dev/null 2>&1 || exit 0",
            "nmcli connection modify \"$ssid\" connection.autoconnect yes >/dev/null 2>&1 || true"
        ].join("\n"), [ssid]);
    }

    function wifiConnectCommand(ssid, psk) {
        var command = ["nmcli", "device", "wifi", "connect", String(ssid || "")];
        if (psk && String(psk).length > 0)
            command.push("password", String(psk));
        return command;
    }

    function runWifiRestorePreferred(ssid) {
        return runDetached("network.restore-wifi", wifiRestorePreferredCommand(ssid), ["nmcli"], {
            "missingMessage": "Wi-Fi 恢复不可用",
            "missingDetail": "需要 nmcli",
            "successMessage": "已请求恢复 Wi-Fi"
        });
    }

    function runWifiAutoconnect(ssid) {
        return runDetached("network.autoconnect", wifiAutoconnectCommand(ssid), ["nmcli"], {
            "missingMessage": "Wi-Fi 自动连接不可用",
            "missingDetail": "需要 nmcli",
            "successMessage": "已更新 Wi-Fi 自动连接"
        });
    }

    function runWifiConnect(ssid, psk) {
        return runDetached("network.connect-wifi", wifiConnectCommand(ssid, psk), ["nmcli"], {
            "missingMessage": "Wi-Fi 连接不可用",
            "missingDetail": "需要 nmcli",
            "successMessage": "已请求连接 Wi-Fi"
        });
    }

    function powerCommandForAction(action) {
        if (action === "lock")
            return ["loginctl", "lock-session"];
        if (action === "sleep")
            return ["systemctl", "suspend"];
        if (action === "logout") {
            return shellCommand(
                "if command -v niri >/dev/null 2>&1; then niri msg action quit --skip-confirmation && exit 0; fi; " +
                "if [ -n \"$XDG_SESSION_ID\" ]; then exec loginctl terminate-session \"$XDG_SESSION_ID\"; fi; " +
                "exit 1",
                []
            );
        }
        if (action === "restart")
            return ["systemctl", "reboot"];
        if (action === "shutdown")
            return ["systemctl", "poweroff"];
        return [];
    }

    function runPowerAction(action) {
        var required = [];
        if (action === "sleep" || action === "restart" || action === "shutdown")
            required = ["systemctl"];
        if (action === "logout" && root.revision > 0 && !commandAvailable("niri") && !commandAvailable("loginctl"))
            return missingResult("power." + String(action || ""), ["niri", "loginctl"], "退出登录不可用", "需要 niri IPC 或 loginctl");

        return runDetached("power." + String(action || ""), powerCommandForAction(action), required, {
            "missingMessage": "电源操作不可用",
            "missingDetail": "缺少系统电源命令",
            "successMessage": "已请求电源操作"
        });
    }

    function powerProfileBusGetCommand(propertyName) {
        return [
            "busctl",
            "get-property",
            "net.hadess.PowerProfiles",
            "/net/hadess/PowerProfiles",
            "net.hadess.PowerProfiles",
            String(propertyName || "")
        ];
    }

    function powerProfileBusSetCommand(id) {
        return [
            "busctl",
            "set-property",
            "net.hadess.PowerProfiles",
            "/net/hadess/PowerProfiles",
            "net.hadess.PowerProfiles",
            "ActiveProfile",
            "s",
            String(id || "")
        ];
    }

    function powerProfileCliGetCommand() {
        return ["powerprofilesctl", "get"];
    }

    function powerProfileCliListCommand() {
        return ["powerprofilesctl", "list"];
    }

    function powerProfileCliSetCommand(id) {
        return ["powerprofilesctl", "set", String(id || "")];
    }

    function parseProbe(text) {
        var commands = {};
        var deps = {};
        var statuses = [];
        var lines = String(text || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (!line || line.length === 0)
                continue;

            var fields = line.split("|");
            if (fields[0] === "COMMAND" && fields.length >= 3) {
                commands[fields[1]] = fields[2] === "1";
            } else if (fields[0] === "STATUS" && fields.length >= 7) {
                var missing = fields.length > 7 && fields[7].length > 0 ? fields[7].split(/\s+/).filter(function(value) { return value.length > 0; }) : [];
                var item = {
                    "id": fields[1],
                    "state": fields[2],
                    "title": fields[3],
                    "detail": fields[4],
                    "impact": fields[5],
                    "action": fields[6],
                    "missing": missing
                };
                statuses.push(item);
                deps[item.id] = item;
            }
        }

        root.commandMap = commands;
        root.dependencies = deps;
        root.statusItems = statuses;
        root.lastUpdatedText = Qt.formatDateTime(new Date(), "HH:mm:ss");
        root.revision += 1;
    }

    function dependencyProbeScript() {
        return [
            "set +e",
            "have() { command -v \"$1\" >/dev/null 2>&1; }",
            "user_bus_name() { have busctl && busctl --user list 2>/dev/null | awk '{print $1}' | grep -qx \"$1\"; }",
            "system_bus_name() { have busctl && busctl --system list 2>/dev/null | awk '{print $1}' | grep -qx \"$1\"; }",
            "is_system_active() { have systemctl && systemctl is-active --quiet \"$1\" 2>/dev/null; }",
            "emit_command() { if have \"$1\"; then printf 'COMMAND|%s|1\\n' \"$1\"; else printf 'COMMAND|%s|0\\n' \"$1\"; fi; }",
            "emit_status() { printf 'STATUS|%s|%s|%s|%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\"; }",
            "missing_commands() { out=''; for c in \"$@\"; do have \"$c\" || out=\"$out ${c}\"; done; printf '%s' \"${out# }\"; }",
            "for c in grim slurp swappy wl-copy wl-paste cliphist notify-send xdg-open xdg-user-dir nmcli bluetoothctl busctl python3 fcitx5-remote loginctl systemctl niri powerprofilesctl brightnessctl; do emit_command \"$c\"; done",
            "if (have nmcli && [ \"$(nmcli -t -f RUNNING general 2>/dev/null)\" = running ]) || system_bus_name org.freedesktop.NetworkManager || is_system_active NetworkManager.service; then",
            "  emit_status network ok NetworkManager 'NetworkManager 在线' 'Wi-Fi 和网络状态可用' '' ''",
            "elif have nmcli; then",
            "  emit_status network missing NetworkManager 'nmcli 存在但 NetworkManager 未运行' 'Wi-Fi 列表、连接和网络状态不可用' '启动 NetworkManager' ''",
            "else",
            "  emit_status network missing NetworkManager '缺少 nmcli' 'Wi-Fi 列表、连接和网络状态不可用' '安装 NetworkManager' 'nmcli'",
            "fi",
            "if have bluetoothctl && bluetoothctl show >/dev/null 2>&1; then",
            "  emit_status bluetooth ok Bluetooth '蓝牙控制器可用' '蓝牙开关和设备状态可用' '' ''",
            "elif have bluetoothctl; then",
            "  emit_status bluetooth warn Bluetooth '未检测到蓝牙控制器或 bluetoothd 未就绪' '蓝牙开关会显示不可用' '确认蓝牙硬件、rfkill 和 bluetooth.service' ''",
            "else",
            "  emit_status bluetooth missing Bluetooth '缺少 bluetoothctl' '蓝牙诊断和控制不可用' '安装 bluez' 'bluetoothctl'",
            "fi",
            "if have fcitx5-remote; then",
            "  fcitx_state=\"$(fcitx5-remote 2>/dev/null || echo 0)\"",
            "  if [ \"$fcitx_state\" = 1 ] || [ \"$fcitx_state\" = 2 ]; then",
            "    emit_status fcitx ok fcitx5 \"fcitx5-remote 状态 $fcitx_state\" '输入法状态和切换可用' '' ''",
            "  else",
            "    emit_status fcitx warn fcitx5 'fcitx5-remote 存在但 daemon 未响应' '输入法状态可能不可用' '启动 fcitx5 或检查 DBus 环境' ''",
            "  fi",
            "else",
            "  emit_status fcitx missing fcitx5 '缺少 fcitx5-remote' '顶栏输入法状态和切换不可用' '安装 fcitx5' 'fcitx5-remote'",
            "fi",
            "shot_missing=\"$(missing_commands grim slurp)\"",
            "shot_optional=\"$(missing_commands swappy wl-copy notify-send)\"",
            "if [ -z \"$shot_missing\" ]; then",
            "  if [ -z \"$shot_optional\" ]; then",
            "    emit_status screenshot ok '截图工具' 'grim、slurp、swappy、wl-copy、notify-send 均可用' '选区截图、复制、通知和标注可用' '' ''",
            "  else",
            "    emit_status screenshot warn '截图工具' \"grim 和 slurp 可用；缺少 $shot_optional\" '截图可保存，复制、通知或标注可能降级' '按需安装缺少的截图辅助工具' \"$shot_optional\"",
            "  fi",
            "else",
            "  emit_status screenshot missing '截图工具' \"缺少 $shot_missing\" '截图入口不可用' '安装 grim 和 slurp' \"$shot_missing\"",
            "fi",
            "clip_missing=\"$(missing_commands cliphist wl-copy wl-paste)\"",
            "if [ -z \"$clip_missing\" ]; then",
            "  emit_status clipboard ok '剪贴板工具' 'cliphist 与 wl-clipboard 可用' '剪贴板历史可用' '' ''",
            "else",
            "  emit_status clipboard missing '剪贴板工具' \"缺少 $clip_missing\" '剪贴板历史不可用或只能部分工作' '安装 cliphist 与 wl-clipboard' \"$clip_missing\"",
            "fi",
            "appmenu_helper=" + JSON.stringify(Quickshell.shellPath("services/appmenu_probe.py")),
            "appmenu_missing=\"$(missing_commands python3 busctl)\"",
            "if [ ! -r \"$appmenu_helper\" ]; then",
            "  emit_status appmenu missing 'AppMenu bridge' \"helper 不可读：$appmenu_helper\" '应用原生菜单探测不可用' '确认 tahoe-shell/services/appmenu_probe.py 已部署' ''",
            "elif [ -n \"$appmenu_missing\" ]; then",
            "  emit_status appmenu missing 'AppMenu bridge' \"缺少 $appmenu_missing\" '应用原生菜单探测不可用' '安装 python3 和 systemd busctl' \"$appmenu_missing\"",
            "elif ! python3 \"$appmenu_helper\" '' '' '' '' >/dev/null 2>&1; then",
            "  emit_status appmenu broken 'AppMenu bridge' \"helper 无法运行：$appmenu_helper\" '应用原生菜单探测不可用' '运行 python3 tahoe-shell/services/appmenu_probe.py 检查语法和 busctl 输出' ''",
            "elif user_bus_name com.canonical.AppMenu.Registrar; then",
            "  emit_status appmenu ok 'AppMenu bridge' \"helper、busctl 和 registrar 可用；$appmenu_helper\" '支持 appmenu 的应用可把原生菜单发布给 Tahoe 顶栏' '' ''",
            "else",
            "  emit_status appmenu warn 'AppMenu bridge' \"helper 和 busctl 可用，未检测到 registrar；$appmenu_helper\" 'Tahoe 会继续尝试 focused app /MenuBar 降级探测' '需要全局菜单时，安装或启动 appmenu registrar/bridge' ''",
            "fi",
            "power_missing=\"$(missing_commands systemctl loginctl)\"",
            "if [ -z \"$power_missing\" ]; then",
            "  emit_status power ok '电源命令' 'systemctl 与 loginctl 可用' '睡眠、重启、关机、退出登录 fallback 可用' '' ''",
            "elif have systemctl || have loginctl || have niri; then",
            "  emit_status power warn '电源命令' \"缺少 $power_missing\" '部分电源或会话动作可能降级' '安装 systemd 用户态命令并确认 niri IPC' \"$power_missing\"",
            "else",
            "  emit_status power missing '电源命令' '缺少 systemctl、loginctl 和 niri IPC' '电源菜单 fallback 不可用' '确认 systemd 和 niri IPC 可用' 'systemctl loginctl niri'",
            "fi",
            "if have busctl && busctl get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile >/dev/null 2>&1; then",
            "  emit_status powerprofiles ok '电源模式' 'power-profiles-daemon busctl 后端可用' '省电、均衡、性能模式可切换' '' ''",
            "elif have powerprofilesctl && powerprofilesctl get >/dev/null 2>&1; then",
            "  emit_status powerprofiles ok '电源模式' 'powerprofilesctl 后端可用' '省电、均衡、性能模式可切换' '' ''",
            "elif have busctl || have powerprofilesctl; then",
            "  emit_status powerprofiles warn '电源模式' '命令存在但 daemon 未响应' '电源模式切换可能不可用' '启动 power-profiles-daemon' ''",
            "else",
            "  emit_status powerprofiles missing '电源模式' '缺少 busctl 和 powerprofilesctl' '电源模式切换不可用' '安装 power-profiles-daemon' 'busctl powerprofilesctl'",
            "fi",
            "if have brightnessctl && brightnessctl -m info >/dev/null 2>&1; then",
            "  emit_status brightness ok '亮度命令' 'brightnessctl 可读取背光' '控制中心亮度滑块可用' '' ''",
            "elif have brightnessctl; then",
            "  emit_status brightness warn '亮度命令' 'brightnessctl 存在但未检测到可用背光' '亮度滑块会显示不可用' '确认背光设备和权限' ''",
            "else",
            "  emit_status brightness missing '亮度命令' '缺少 brightnessctl' '控制中心亮度滑块不可写入' '安装 brightnessctl' 'brightnessctl'",
            "fi",
            "exit 0"
        ].join("\n");
    }

    Process {
        id: dependencyProbe
        running: false
        command: ["sh", "-lc", root.dependencyProbeScript()]
        stdout: StdioCollector {
            id: dependencyProbeOut
            onStreamFinished: root.parseProbe(dependencyProbeOut.text)
        }
        onExited: function(code, exitStatus) {
            root.refreshing = false;
            if (code !== 0)
                root.lastError = "命令依赖检测失败，退出码 " + String(code);
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refreshDependencies()
    }

    Component.onCompleted: root.refreshDependencies()
}
