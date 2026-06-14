#!/usr/bin/env bash
# 一键诊断：托盘图标消失 + 启动器空白（VMware archlinux niri）
#
# 用法（在 VM 里）：
#   bash scripts/diagnose-tray-launcher.sh
#
# 它只读不写，不碰你的配置和进程。结果打到终端，同时存一份到：
#   /tmp/tray-launcher-diag.txt
# 你把那个文件传回来，或者直接把终端输出贴给我。

set -uo pipefail

REPORT=/tmp/tray-launcher-diag.txt
: > "$REPORT"

say() { printf '\n========== %s ==========\n' "$*" | tee -a "$REPORT"; }
line() { printf '%s\n' "$*" | tee -a "$REPORT"; }

say "1. 环境"
line "时间: $(date -Is)"
line "主机: $(hostname)  用户: $(whoami)"
line "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>}  XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-<unset>}"
line "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}  DISPLAY=${DISPLAY:-<unset>}"
line "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-<unset>}"

say "2. quickshell / niri 进程状态"
line "── pgrep quickshell ──"
pgrep -a quickshell 2>&1 | tee -a "$REPORT" || line "(没找到 quickshell 进程 — 可能已退出)"
line "── pgrep niri ──"
pgrep -a niri 2>&1 | tee -a "$REPORT" || line "(没找到 niri 进程)"

say "3. StatusNotifierWatcher（托盘核心，最关键）"
line "── RegisteredStatusNotifierItems（当前注册了哪些托盘项）──"
if command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems 2>&1 \
        | tee -a "$REPORT" || line "(qdbus 调用失败 — watcher 可能没注册)"
    line "── IsStatusNotifierHostRegistered ──"
    qdbus org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher.IsStatusNotifierHostRegistered 2>&1 \
        | tee -a "$REPORT"
    line "── ProtocolVersion ──"
    qdbus org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher.ProtocolVersion 2>&1 | tee -a "$REPORT"
elif command -v dbus-send >/dev/null 2>&1; then
    dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher \
        /StatusNotifierWatcher org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems \
        2>&1 | tee -a "$REPORT" || line "(dbus-send 调用失败)"
    dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher \
        /StatusNotifierWatcher org.kde.StatusNotifierWatcher.IsStatusNotifierHostRegistered \
        2>&1 | tee -a "$REPORT"
else
    line "(既无 qdbus 也无 dbus-send，装一个: sudo pacman -S qt6-tools 或 dbus)"
fi

say "4. D-Bus 会话是否健康"
line "── dbus 服务列表里和托盘相关的名字 ──"
if command -v dbus-send >/dev/null 2>&1; then
    dbus-send --session --print-reply --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>&1 \
        | grep -iE "StatusNotifier|NotifierItem|Ayatana|indicator" \
        | tee -a "$REPORT" || line "(没有任何 StatusNotifier* / indicator 名字活跃)"
else
    line "(无 dbus-send，跳过)"
fi

say "5. 常见托盘 applet 是否在跑（它们才提供图标）"
for proc in nm-applet blueman-applet pasystray volumeicon telegram vlc nextcloud fcitx5 ibus-daemon; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        line "  [运行中] $proc"
    else
        line "  [未运行] $proc"
    fi
done

say "6. quickshell 自己的日志（看 hover 那一刻有没有 warning）"
QS_DIR="/run/user/$(id -u)/quickshell/by-id"
if [[ -d "$QS_DIR" ]]; then
    # 取最新的实例
    LATEST=$(ls -t "$QS_DIR" 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        line "quickshell 最新实例: $QS_DIR/$LATEST"
        line "── log.log（纯文本）末尾 60 行 ──"
        tail -n 60 "$QS_DIR/$LATEST/log.log" 2>&1 | tee -a "$REPORT" \
            || line "(log.log 不存在)"
        line "── 关键词扫描（WARN/error/loop/crash/Tray/StatusNotifier/overflow）──"
        # log.qslog 是二进制，strings 提取后过滤
        if command -v strings >/dev/null 2>&1; then
            strings "$QS_DIR/$LATEST/log.qslog" 2>/dev/null \
                | grep -iE "WARN|error|loop|crash|tray|statusnotifier|overflow|region" \
                | tail -n 40 | tee -a "$REPORT" || line "(无匹配关键词)"
        else
            line "(无 strings 命令，跳过 qslog 扫描；可 pacman -S binutils)"
        fi
    else
        line "(by-id 目录为空)"
    fi
else
    line "(quickshell 运行时目录不存在: $QS_DIR)"
fi

say "7. niri session 日志末尾（看有没有 panic/overflow）"
NIRI_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/tahoe-niri/session.log"
if [[ -f "$NIRI_LOG" ]]; then
    line "── 末尾 40 行 ──"
    tail -n 40 "$NIRI_LOG" 2>&1 | tee -a "$REPORT"
    line "── 关键词扫描（panic/overflow/region/abort）──"
    grep -iE "panic|overflow|region_to_non|abort|SIGSEGV" "$NIRI_LOG" 2>/dev/null \
        | tail -n 20 | tee -a "$REPORT" || line "(niri 日志里无崩溃关键词 — niri 健康)"
else
    line "(session.log 不存在: $NIRI_LOG)"
fi

say "8. 当前 quickshell 部署的 QML 是否就是仓库 HEAD"
TAHOE_CFG="${TAHOE_CONFIG_DIR:-$HOME/.config/quickshell/tahoe}"
line "部署目录: $TAHOE_CFG"
if [[ -f "$TAHOE_CFG/shell.qml" ]]; then
    line "── shell.qml import 行 ──"
    grep -nE "^import|^//@ pragma" "$TAHOE_CFG/shell.qml" | tee -a "$REPORT"
else
    line "(shell.qml 不存在)"
fi

say "诊断完成"
line "报告已存: $REPORT"
line "把这个文件传回来，或直接贴终端输出。"

echo
echo ">>>>>>>>>> 把下面整段（从 '1. 环境' 到这行）贴给 AI 即可 <<<<<<<<<<"
