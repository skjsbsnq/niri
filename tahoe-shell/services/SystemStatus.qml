pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property var commandRunner
    property var statusItems: []
    property var localStatusItems: []
    property var aboutItems: []
    property bool localRefreshing: false
    property string lastUpdatedText: "尚未检测"
    property string lastError: ""

    readonly property bool refreshing: localRefreshing || (!!commandRunner && commandRunner.refreshing)
    readonly property int okCount: countByState("ok")
    readonly property int staleCount: countByState("stale")
    readonly property int brokenCount: countByState("broken")
    readonly property int warnCount: countByState("warn") + staleCount
    readonly property int missingCount: countByState("missing") + brokenCount

    function countByState(state) {
        var count = 0;
        for (var i = 0; i < statusItems.length; i++) {
            if (statusItems[i] && statusItems[i].state === state)
                count += 1;
        }
        return count;
    }

    function refresh() {
        if (commandRunner && commandRunner.refreshDependencies)
            commandRunner.refreshDependencies();

        if (probe.running)
            return;

        localRefreshing = true;
        lastError = "";
        probe.running = true;
    }

    function mergeStatusItems(commandItems, localItems) {
        var out = [];
        var seen = {};
        var groups = [commandItems || [], localItems || []];
        for (var g = 0; g < groups.length; g++) {
            var values = Array.isArray(groups[g]) ? groups[g] : [];
            for (var i = 0; i < values.length; i++) {
                var item = values[i];
                if (!item)
                    continue;

                var id = String(item.id || "");
                if (id.length > 0 && seen[id])
                    continue;
                if (id.length > 0)
                    seen[id] = true;
                out.push(item);
            }
        }
        return out;
    }

    function rebuildStatusItems() {
        statusItems = mergeStatusItems(commandRunner ? commandRunner.statusItems : [], localStatusItems);
        if (commandRunner && commandRunner.lastUpdatedText && commandRunner.lastUpdatedText !== "尚未检测")
            lastUpdatedText = commandRunner.lastUpdatedText;
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

        localStatusItems = statuses;
        aboutItems = about;
        lastUpdatedText = Qt.formatDateTime(new Date(), "HH:mm:ss");
        rebuildStatusItems();
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
            "if system_bus_name org.freedesktop.UPower || (have upower && upower -e >/dev/null 2>&1); then",
            "  emit_status upower ok UPower 'UPower 在线' '电池、电源和健康状态可用' ''",
            "else",
            "  emit_status upower missing UPower '未检测到 UPower' '电池百分比、电源来源和电源页不可用' '安装并启动 upower'",
            "fi",
            "lock_ui=\"$shell_dir/components/LockScreen.qml\"",
            "lock_script=\"$shell_dir/scripts/tahoe-lock.sh\"",
            "shell_qml=\"$shell_dir/shell.qml\"",
            "lock_ui_ok=0",
            "[ -r \"$lock_ui\" ] && grep -q 'WlSessionLock' \"$lock_ui\" && lock_ui_ok=1",
            "lock_ipc_ok=0",
            "[ -r \"$shell_qml\" ] && grep -q 'function lock()' \"$shell_qml\" && grep -q 'function lockFrom' \"$shell_qml\" && lock_ipc_ok=1",
            "idle_lock_ok=0",
            "[ -r \"$shell_qml\" ] && grep -q 'IdleMonitor' \"$shell_qml\" && grep -q 'requestLock(\"idle\")' \"$shell_qml\" && idle_lock_ok=1",
            "lock_helper_ok=0",
            "[ -x \"$lock_script\" ] && lock_helper_ok=1",
            "fallback_detail='swaylock emergency fallback 不可用'",
            "have swaylock && fallback_detail='swaylock emergency fallback 可用'",
            "if [ \"$lock_ui_ok\" = 1 ] && [ \"$lock_ipc_ok\" = 1 ] && [ \"$idle_lock_ok\" = 1 ] && [ \"$lock_helper_ok\" = 1 ]; then",
            "  emit_status lockpath ok 'Tahoe 锁屏路径' \"LockScreen、IPC lock、idle monitor 与快捷键 helper 可用；$fallback_detail\" '快捷键、电源菜单和 idle 都进入 Tahoe lock path' ''",
            "elif [ \"$lock_ui_ok\" = 1 ] && [ \"$lock_ipc_ok\" = 1 ]; then",
            "  emit_status lockpath warn 'Tahoe 锁屏路径' \"Tahoe LockScreen 和 IPC 可用，但 idle/helper 不完整；$fallback_detail\" '电源菜单可用，快捷键或 idle 可能没有完全统一' '确认 shell.qml IdleMonitor 和 scripts/tahoe-lock.sh 已部署且可执行'",
            "else",
            "  emit_status lockpath missing 'Tahoe 锁屏路径' \"Tahoe LockScreen 或 IPC lock 不完整；$fallback_detail\" '快捷键、电源菜单和 idle 可能继续分裂或无法锁屏' '确认 LockScreen.qml 加载，并且 tahoe IPC 暴露 lock/lockFrom'",
            "fi",
            "repo=\"$shell_dir\"",
            "while [ \"$repo\" != / ] && [ ! -d \"$repo/.git\" ] && [ ! -f \"$repo/.git\" ]; do repo=\"$(dirname \"$repo\")\"; done",
            "[ -d \"$repo/.git\" ] || [ -f \"$repo/.git\" ] || repo=\"$shell_dir\"",
            "if user_bus_name org.kde.StatusNotifierWatcher; then",
            "  emit_status sni ok 'SNI 托盘' 'StatusNotifierWatcher 已注册' '现代托盘图标可显示菜单' ''",
            "else",
            "  emit_status sni warn 'SNI 托盘' '未在 session bus 上看到 StatusNotifierWatcher' '现代托盘图标可能不显示' '确认 Tahoe Shell 正在运行并拥有托盘服务'",
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
            "xwayland_check=\"$repo/scripts/check-xwayland-satellite-compat.sh\"",
            "[ -x \"$xwayland_check\" ] || xwayland_check=\"$shell_dir/scripts/check-xwayland-satellite-compat.sh\"",
            "if [ -x \"$xwayland_check\" ]; then",
            "  \"$xwayland_check\" --status 2>/dev/null || true",
            "elif pgrep -x xwayland-satellite >/dev/null 2>&1; then",
            "  emit_status xwayland ok 'XWayland patched path' 'xwayland-satellite 正在运行，但缺少 Tahoe 兼容诊断脚本' 'X11 应用兼容路径可用；patch/ref/wrapper 状态未知' '部署 scripts/check-xwayland-satellite-compat.sh'",
            "elif have xwayland-satellite; then",
            "  emit_status xwayland stale 'XWayland patched path' '已安装 xwayland-satellite 但未运行，且缺少 Tahoe 兼容诊断脚本' 'X11 应用可能无法显示；patch/ref/wrapper 状态未知' '部署 scripts/check-xwayland-satellite-compat.sh 并运行 arch-update.sh'",
            "else",
            "  emit_status xwayland missing 'XWayland patched path' '缺少 xwayland-satellite，且缺少 Tahoe 兼容诊断脚本' '依赖 XWayland 的应用可能无法使用' '运行 BUILD_XWAYLAND_SATELLITE=auto bash scripts/arch-update.sh'",
            "fi",
            "if have niri && niri msg --json outputs >/dev/null 2>&1; then",
            "  emit_status niri ok 'niri IPC' 'niri msg 可用' '窗口总览、Dock 窗口菜单和工作区状态可用' ''",
            "else",
            "  emit_status niri warn 'niri IPC' 'niri msg 当前不可用' '窗口模型可能只能使用 Quickshell toplevel 降级路径' '确认当前会话运行在 niri 下'",
            "fi",
            "repo_commit=\"$(git -C \"$repo\" rev-parse --short HEAD 2>/dev/null || echo unknown)\"",
            "dirty_count=\"$(git -C \"$repo\" status --short 2>/dev/null | wc -l | tr -d ' ')\"",
            "[ \"$dirty_count\" != 0 ] && repo_commit=\"$repo_commit (+$dirty_count)\"",
            "niri_sub=\"$(git -C \"$repo/niri\" rev-parse --short HEAD 2>/dev/null || echo missing)\"",
            "qs_sub=\"$(git -C \"$repo/quickshell\" rev-parse --short HEAD 2>/dev/null || echo missing)\"",
            "thumbnail_provider=\"$shell_dir/services/ThumbnailProvider.qml\"",
            "thumbnail_dir=\"${XDG_RUNTIME_DIR:-/tmp}/tahoe/window-thumbnails\"",
            "thumbnail_provider_ok=0",
            "[ -r \"$thumbnail_provider\" ] && grep -q 'requestThumbnail' \"$thumbnail_provider\" && grep -q 'maxQueueLength' \"$thumbnail_provider\" && thumbnail_provider_ok=1",
            "thumbnail_ipc_boundary_ok=0",
            "[ -r \"$repo/niri/src/ipc/server.rs\" ] && grep -q 'validate_tahoe_thumbnail_path' \"$repo/niri/src/ipc/server.rs\" && thumbnail_ipc_boundary_ok=1",
            "thumbnail_cli_ok=0",
            "have niri && niri msg window-thumbnail --help >/dev/null 2>&1 && thumbnail_cli_ok=1",
            "if [ \"$thumbnail_provider_ok\" = 1 ] && [ \"$thumbnail_ipc_boundary_ok\" = 1 ] && [ \"$thumbnail_cli_ok\" = 1 ]; then",
            "  emit_status thumbnails ok '窗口缩略图 provider' \"provider 队列、niri window-thumbnail CLI 和 runtime 路径边界可用；目录 $thumbnail_dir\" 'Dock、任务切换器和窗口总览共用同一缩略图路径' ''",
            "elif [ \"$thumbnail_provider_ok\" = 1 ] && [ \"$thumbnail_cli_ok\" = 1 ]; then",
            "  emit_status thumbnails warn '窗口缩略图 provider' \"provider 和 CLI 可用，但未确认 niri IPC 路径边界；目录 $thumbnail_dir\" '缩略图可用，但 compositor 写入边界需要确认' '确认 niri IPC 限制到 XDG_RUNTIME_DIR/tahoe/window-thumbnails'",
            "else",
            "  emit_status thumbnails missing '窗口缩略图 provider' \"provider、CLI 或路径边界不完整；目录 $thumbnail_dir\" 'Dock 最小化缩略栏、任务切换器或窗口总览会退回图标/几何 fallback' '确认 ThumbnailProvider.qml 和 niri msg window-thumbnail 已部署'",
            "fi",
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
            root.localRefreshing = false;
            if (code !== 0)
                root.lastError = "系统状态检测失败，退出码 " + String(code);
        }
    }

    Connections {
        target: root.commandRunner
        ignoreUnknownSignals: true

        function onRevisionChanged() {
            root.rebuildStatusItems();
        }
    }

    Component.onCompleted: root.refresh()
}
