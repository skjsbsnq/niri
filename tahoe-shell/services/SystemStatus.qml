pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var statusItems: []
    property var aboutItems: []
    property bool refreshing: false
    property string lastUpdatedText: "尚未检测"
    property string lastError: ""

    readonly property int okCount: countByState("ok")
    readonly property int warnCount: countByState("warn")
    readonly property int missingCount: countByState("missing")

    function countByState(state) {
        var count = 0;
        for (var i = 0; i < statusItems.length; i++) {
            if (statusItems[i] && statusItems[i].state === state)
                count += 1;
        }
        return count;
    }

    function refresh() {
        if (probe.running)
            return;

        refreshing = true;
        lastError = "";
        probe.running = true;
    }

    function parseProbe(text) {
        var statuses = [];
        var about = [];
        var lines = String(text || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (!line || line.length === 0)
                continue;

            var fields = line.split("|");
            if (fields[0] === "STATUS" && fields.length >= 6) {
                statuses.push({
                    "id": fields[1],
                    "state": fields[2],
                    "title": fields[3],
                    "detail": fields[4],
                    "impact": fields[5],
                    "action": fields.length > 6 ? fields.slice(6).join("|") : ""
                });
            } else if (fields[0] === "ABOUT" && fields.length >= 4) {
                about.push({
                    "id": fields[1],
                    "label": fields[2],
                    "value": fields[3],
                    "detail": fields.length > 4 ? fields.slice(4).join("|") : ""
                });
            }
        }

        statusItems = statuses;
        aboutItems = about;
        lastUpdatedText = Qt.formatDateTime(new Date(), "HH:mm:ss");
    }

    function probeScript() {
        return [
            "set +e",
            "shell_dir=\"$1\"",
            "state_dir=\"$2\"",
            "have() { command -v \"$1\" >/dev/null 2>&1; }",
            "user_bus_name() { have busctl && busctl --user list 2>/dev/null | awk '{print $1}' | grep -qx \"$1\"; }",
            "system_bus_name() { have busctl && busctl --system list 2>/dev/null | awk '{print $1}' | grep -qx \"$1\"; }",
            "is_user_active() { have systemctl && systemctl --user is-active --quiet \"$1\" 2>/dev/null; }",
            "is_user_enabled() { have systemctl && systemctl --user is-enabled --quiet \"$1\" 2>/dev/null; }",
            "is_system_active() { have systemctl && systemctl is-active --quiet \"$1\" 2>/dev/null; }",
            "emit_status() { printf 'STATUS|%s|%s|%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\"; }",
            "emit_about() { printf 'ABOUT|%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$4\"; }",
            "missing_commands() { out=''; for c in \"$@\"; do have \"$c\" || out=\"$out ${c}\"; done; printf '%s' \"${out# }\"; }",
            "if user_bus_name org.freedesktop.portal.Desktop || pgrep -x xdg-desktop-portal >/dev/null 2>&1; then",
            "  emit_status portal ok 'Desktop Portal' 'xdg-desktop-portal 在线' '文件选择、屏幕共享、应用权限可用' ''",
            "else",
            "  emit_status portal missing 'Desktop Portal' '未检测到 xdg-desktop-portal' '门户文件选择、屏幕共享和部分应用权限会不可用' '安装并启动 xdg-desktop-portal 与对应后端'",
            "fi",
            "if (have pw-cli && pw-cli info 0 >/dev/null 2>&1) || is_user_active pipewire.service || pgrep -x pipewire >/dev/null 2>&1; then",
            "  emit_status pipewire ok PipeWire 'PipeWire 服务在线' '音频、录屏和屏幕共享后端可用' ''",
            "else",
            "  emit_status pipewire missing PipeWire '未检测到 PipeWire' '音频控制、录屏和 portal screencast 会受影响' '安装并启动 pipewire 与 pipewire-pulse'",
            "fi",
            "if (have nmcli && [ \"$(nmcli -t -f RUNNING general 2>/dev/null)\" = running ]) || system_bus_name org.freedesktop.NetworkManager || is_system_active NetworkManager.service; then",
            "  emit_status network ok NetworkManager 'NetworkManager 在线' 'Wi-Fi 和网络状态可用' ''",
            "else",
            "  emit_status network missing NetworkManager '未检测到 NetworkManager' 'Wi-Fi 列表、连接和网络状态不可用' '安装并启动 NetworkManager'",
            "fi",
            "if have bluetoothctl && bluetoothctl show >/dev/null 2>&1; then",
            "  emit_status bluetooth ok Bluetooth '蓝牙控制器可用' '蓝牙开关和设备状态可用' ''",
            "elif have bluetoothctl; then",
            "  emit_status bluetooth warn Bluetooth '未检测到蓝牙控制器或 bluetoothd 未就绪' '蓝牙开关会显示不可用' '确认蓝牙硬件、rfkill 和 bluetooth.service'",
            "else",
            "  emit_status bluetooth missing Bluetooth '缺少 bluetoothctl' '蓝牙诊断和控制不可用' '安装 bluez'",
            "fi",
            "if system_bus_name org.freedesktop.UPower || (have upower && upower -e >/dev/null 2>&1); then",
            "  emit_status upower ok UPower 'UPower 在线' '电池、电源和健康状态可用' ''",
            "else",
            "  emit_status upower missing UPower '未检测到 UPower' '电池百分比、电源来源和电源页不可用' '安装并启动 upower'",
            "fi",
            "if have fcitx5-remote; then",
            "  fcitx_state=\"$(fcitx5-remote 2>/dev/null || echo 0)\"",
            "  if [ \"$fcitx_state\" = 1 ] || [ \"$fcitx_state\" = 2 ]; then",
            "    emit_status fcitx ok fcitx5 \"fcitx5-remote 状态 $fcitx_state\" '输入法状态和切换可用' ''",
            "  else",
            "    emit_status fcitx warn fcitx5 'fcitx5-remote 存在但 daemon 未响应' '输入法状态可能不可用' '启动 fcitx5 或检查 DBus 环境'",
            "  fi",
            "else",
            "  emit_status fcitx missing fcitx5 '缺少 fcitx5-remote' '顶栏输入法状态和切换不可用' '安装 fcitx5'",
            "fi",
            "shot_missing=\"$(missing_commands grim slurp)\"",
            "if [ -z \"$shot_missing\" ]; then",
            "  if have swappy; then",
            "    emit_status screenshot ok '截图工具' 'grim、slurp、swappy 均可用' '选区截图、复制和标注可用' ''",
            "  else",
            "    emit_status screenshot warn '截图工具' 'grim 和 slurp 可用，缺少 swappy' '截图可保存和复制，但标注动作不可用' '安装 swappy 以启用标注'",
            "  fi",
            "else",
            "  emit_status screenshot missing '截图工具' \"缺少 $shot_missing\" '截图入口不可用' '安装 grim 和 slurp'",
            "fi",
            "clip_missing=\"$(missing_commands cliphist wl-copy wl-paste)\"",
            "if [ -z \"$clip_missing\" ]; then",
            "  emit_status clipboard ok '剪贴板工具' 'cliphist 与 wl-clipboard 可用' '剪贴板历史可用' ''",
            "else",
            "  emit_status clipboard missing '剪贴板工具' \"缺少 $clip_missing\" '剪贴板历史不可用或只能部分工作' '安装 cliphist 与 wl-clipboard'",
            "fi",
            "if user_bus_name org.kde.StatusNotifierWatcher; then",
            "  emit_status sni ok 'SNI 托盘' 'StatusNotifierWatcher 已注册' '现代托盘图标可显示菜单' ''",
            "else",
            "  emit_status sni warn 'SNI 托盘' '未在 session bus 上看到 StatusNotifierWatcher' '现代托盘图标可能不显示' '确认 Tahoe Shell 正在运行并拥有托盘服务'",
            "fi",
            "if user_bus_name com.canonical.AppMenu.Registrar; then",
            "  emit_status appmenu ok 'AppMenu registrar' 'com.canonical.AppMenu.Registrar 在线' '支持 appmenu 的应用可把原生菜单发布给 Tahoe 顶栏' ''",
            "else",
            "  emit_status appmenu warn 'AppMenu registrar' '未检测到 com.canonical.AppMenu.Registrar' '支持全局菜单的应用不会通过 registrar 暴露菜单；Tahoe 会尝试 focused app /MenuBar 降级探测' '安装或启动 appmenu registrar/bridge'",
            "fi",
            "legacy_autostart=0",
            "[ -n \"${HOME:-}\" ] && [ -f \"$HOME/.config/autostart/xembedsniproxy.desktop\" ] && legacy_autostart=1",
            "is_user_enabled xembedsniproxy.service && legacy_autostart=1",
            "legacy_startup='未配置自启动'",
            "[ \"$legacy_autostart\" = 1 ] && legacy_startup='已配置自启动'",
            "if have xembedsniproxy && pgrep -x xembedsniproxy >/dev/null 2>&1; then",
            "  emit_status legacytray ok 'legacy tray bridge' \"xembedsniproxy 正在运行；$legacy_startup\" 'Steam、输入法面板、同步盘等 XEmbed 托盘可桥接到 SNI' ''",
            "elif have xembedsniproxy; then",
            "  emit_status legacytray warn 'legacy tray bridge' \"xembedsniproxy 已安装但未运行；$legacy_startup\" 'Steam、输入法面板、同步盘等旧托盘可能消失；SNI 原生应用不受影响' '启动 xembedsniproxy，并加入 XDG autostart 或 systemd user service'",
            "else",
            "  emit_status legacytray missing 'legacy tray bridge' '缺少 xembedsniproxy' '旧 XEmbed 托盘应用不会出现在顶栏；Steam、同步盘等可能看起来消失' '安装 xembedsniproxy，并配置会话自启动'",
            "fi",
            "if pgrep -x xwayland-satellite >/dev/null 2>&1; then",
            "  emit_status xwayland ok xwayland-satellite 'xwayland-satellite 正在运行' 'X11 应用兼容路径可用' ''",
            "elif have xwayland-satellite; then",
            "  emit_status xwayland warn xwayland-satellite '已安装但未运行' 'X11 应用可能无法显示' '按需启动 xwayland-satellite'",
            "else",
            "  emit_status xwayland missing xwayland-satellite '缺少 xwayland-satellite' '依赖 XWayland 的应用可能无法使用' '安装 xwayland-satellite'",
            "fi",
            "if have niri && niri msg --json outputs >/dev/null 2>&1; then",
            "  emit_status niri ok 'niri IPC' 'niri msg 可用' '窗口总览、Dock 窗口菜单和工作区状态可用' ''",
            "else",
            "  emit_status niri warn 'niri IPC' 'niri msg 当前不可用' '窗口模型可能只能使用 Quickshell toplevel 降级路径' '确认当前会话运行在 niri 下'",
            "fi",
            "repo=\"$shell_dir\"",
            "while [ \"$repo\" != / ] && [ ! -d \"$repo/.git\" ] && [ ! -f \"$repo/.git\" ]; do repo=\"$(dirname \"$repo\")\"; done",
            "[ -d \"$repo/.git\" ] || [ -f \"$repo/.git\" ] || repo=\"$shell_dir\"",
            "repo_commit=\"$(git -C \"$repo\" rev-parse --short HEAD 2>/dev/null || echo unknown)\"",
            "dirty_count=\"$(git -C \"$repo\" status --short 2>/dev/null | wc -l | tr -d ' ')\"",
            "[ \"$dirty_count\" != 0 ] && repo_commit=\"$repo_commit (+$dirty_count)\"",
            "niri_sub=\"$(git -C \"$repo/niri\" rev-parse --short HEAD 2>/dev/null || echo missing)\"",
            "qs_sub=\"$(git -C \"$repo/quickshell\" rev-parse --short HEAD 2>/dev/null || echo missing)\"",
            "niri_runtime=\"$(niri --version 2>/dev/null | head -n 1 || echo unavailable)\"",
            "qs_runtime=\"$(quickshell --version 2>/dev/null | head -n 1 || echo unavailable)\"",
            "gpu=\"$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | sed -E 's/^[^:]+: //' | head -n 2 | paste -sd '; ' -)\"",
            "[ -z \"$gpu\" ] && gpu=unavailable",
            "session=\"type=${XDG_SESSION_TYPE:-unknown}; desktop=${XDG_CURRENT_DESKTOP:-unknown}; wayland=${WAYLAND_DISPLAY:-unset}\"",
            "backend=\"qt=${QT_QUICK_BACKEND:-auto}; software=${LIBGL_ALWAYS_SOFTWARE:-0}; niri_socket=${NIRI_SOCKET:+set}\"",
            "emit_about tahoe 'Tahoe Shell' \"$repo_commit\" \"$repo\"",
            "emit_about niri_submodule 'niri submodule' \"$niri_sub\" \"$repo/niri\"",
            "emit_about quickshell_submodule 'Quickshell submodule' \"$qs_sub\" \"$repo/quickshell\"",
            "emit_about niri_runtime 'niri runtime' \"$niri_runtime\" ''",
            "emit_about quickshell_runtime 'Quickshell runtime' \"$qs_runtime\" ''",
            "emit_about gpu GPU \"$gpu\" ''",
            "emit_about session Session \"$session\" ''",
            "emit_about backend Backend \"$backend\" ''",
            "emit_about state 'Quickshell state' \"$state_dir\" ''",
            "exit 0"
        ].join("\n");
    }

    Process {
        id: probe
        running: false
        command: ["sh", "-lc", root.probeScript(), "sh", Quickshell.shellPath(""), Quickshell.stateDir]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.parseProbe(probeOut.text)
        }
        onExited: function(code, exitStatus) {
            root.refreshing = false;
            if (code !== 0)
                root.lastError = "系统状态检测失败，退出码 " + String(code);
        }
    }

    Component.onCompleted: root.refresh()
}
