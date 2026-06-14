#!/usr/bin/env bash
# 一键诊断 v2：托盘图标消失（hover 后永久不回）+ 启动器空白
#
# v2 修正：RegisteredStatusNotifierItems 是 D-Bus *property* 不是 method，
# 旧版脚本用方法调用去查 → 制造了假的 qt.dbus.integration warning，已纠正。
#
# 真正怀疑链路：有 app 注册了 SNI（图标出现）→ 那个 app 的 D-Bus 服务消失
# （item 被 watcher.onServiceUnregistered 移除，图标永久消失）。本脚本会
# *实时*监听 watcher 的 Registered/Unregistered 信号 + D-Bus 总线的服务
# NameOwnerChanged，抓到掉线那一瞬间是哪个服务、为什么走。
#
# 用法（VM 里）：
#   bash scripts/diagnose-tray-launcher.sh          # 实时监听 60 秒
#   bash scripts/diagnose-tray-launcher.sh 300      # 监听 300 秒
#
# 跑起来后立刻重现症状：鼠标放托盘图标、点开启动器，等它抓到掉线事件。
# 报告存到 /tmp/tray-launcher-diag.txt，贴回来。

set -uo pipefail

DURATION="${1:-60}"
REPORT=/tmp/tray-launcher-diag.txt
: > "$REPORT"

say() { printf '\n========== %s ==========\n' "$*" | tee -a "$REPORT"; }
line() { printf '%s\n' "$*" | tee -a "$REPORT"; }
ts()  { printf '[%s] ' "$(date '+%H:%M:%S.%3N')"; }

say "0. 说明 / 当前时间: $(date -Is)"
line "本次监听时长: ${DURATION}s。跑起来后请立刻去 hover 托盘、点启动器。"

say "1. 环境与进程"
line "user=$(whoami) host=$(hostname)"
line "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>} DESKTOP=${XDG_CURRENT_DESKTOP:-<unset>}"
line "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>} DBUS=${DBUS_SESSION_BUS_ADDRESS:-<unset>}"
line "── pgrep quickshell ──"; pgrep -a quickshell 2>&1 | tee -a "$REPORT" || line "(无)"
line "── pgrep niri ──";       pgrep -a niri 2>&1      | tee -a "$REPORT" || line "(无)"

# ── 用 dbus-send 以 *属性* 方式查询（这是正确语法）──
prop_get() {
    # $1 = property name
    dbus-send --session --print-reply --reply-timeout=3000 \
        --dest=org.kde.StatusNotifierWatcher \
        /StatusNotifierWatcher \
        org.freedesktop.DBus.Properties.Get \
        string:org.kde.StatusNotifierWatcher string:"$1" 2>&1
}

say "2. StatusNotifierWatcher 当前状态（属性方式，正确）"
if ! dbus-send --session --print-reply --reply-timeout=3000 \
        --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
        string:org.kde.StatusNotifierWatcher 2>&1 | grep -q 'boolean true'; then
    line "!!! org.kde.StatusNotifierWatcher 没有所有者 — watcher 没起来。"
else
    line "watcher 在 D-Bus 上有所有者 ✓"
    line "── RegisteredStatusNotifierItems（property Get）──"
    prop_get RegisteredStatusNotifierItems | tee -a "$REPORT"
    line "── IsStatusNotifierHostRegistered（property Get）──"
    prop_get IsStatusNotifierHostRegistered | tee -a "$REPORT"
    line "── ProtocolVersion（property Get）──"
    prop_get ProtocolVersion | tee -a "$REPORT"
fi

say "3. 所有托盘 applet 进程（没在跑 = 没人提供图标）"
for proc in nm-applet blueman-applet pasystray volumeicon telegram vlc \
            nextcloud fcitx5 ibus-daemon steam discord slack spotify; do
    if pgrep -fx "$proc" >/dev/null 2>&1 || pgrep -f "$proc" >/dev/null 2>&1; then
        line "  [运行中] $proc  (pid: $(pgrep -f "$proc" | tr '\n' ' '))"
    fi
done
line "  (上面若一片空白 = 没有任何 SNI 客户端在跑，托盘本来就该是空的)"

say "4. ★ 实时监听 ${DURATION}s ★"
line "现在去重现症状。下面会按时间打印："
line "  [SNI+]  StatusNotifierItem 注册（图标应该出现）"
line "  [SNI-]  StatusNotifierItem 注销（图标应该消失）"
line "  [BUS-]  D-Bus 服务消失（看是哪个 app 的服务掉了）"
line "  [BUS+]  D-Bus 服务出现"
line "────────────────────────────────────────────────"

# 监听 1：watcher 的 Registered/Unregistered 信号
dbus-monitor --session \
    "type='signal',sender='org.kde.StatusNotifierWatcher',interface='org.kde.StatusNotifierWatcher'" \
    2>&1 | while read -r l; do printf '%s[SNI] %s\n' "$(ts)" "$l"; done \
    >> "$REPORT" &
SNI_PID=$!

# 监听 2：会话总线上所有 NameOwnerChanged（服务增删），过滤掉无关噪音
dbus-monitor --session \
    "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'" \
    2>&1 | while read -r l; do
        # 只打印看起来像应用服务名（含点）且不是 quickshell/dbus 自身的
        case "$l" in
            *org.kde.StatusNotifier*|*:*) printf '%s[BUS] %s\n' "$(ts)" "$l" ;;
        esac
    done >> "$REPORT" &
BUS_PID=$!

# 倒计时，让用户知道还剩多久
for i in $(seq "$DURATION" -1 1); do
    printf '\r监听中... %3ds 剩余   ' "$i" >&2
    sleep 1
done
printf '\r                      \n' >&2

kill "$SNI_PID" "$BUS_PID" 2>/dev/null || true
wait "$SNI_PID" "$BUS_PID" 2>/dev/null || true

say "5. 监听期间 quickshell 有没有打 warning（再扫一次 log.log）"
QS_DIR="/run/user/$(id -u)/quickshell/by-id"
if [[ -d "$QS_DIR" ]]; then
    LATEST=$(ls -t "$QS_DIR" 2>/dev/null | head -1)
    line "实例: $QS_DIR/$LATEST"
    # 只看最近 DURATION+30 秒内的、非 brightnessctl 的 warning
    tail -n 400 "$QS_DIR/$LATEST/log.log" 2>/dev/null \
        | grep -ivE "brightnessctl" \
        | grep -iE "WARN|error|StatusNotifier|sni|tray|unregister|removed" \
        | tail -n 30 | tee -a "$REPORT" || line "(监听期间无非 brightnessctl 的 warning)"
else
    line "(quickshell 运行时目录不存在)"
fi

say "诊断完成"
line "报告: $REPORT"
line "重点看第 4 段：SNI+/SNI- 出现的顺序和对应的服务名。"
