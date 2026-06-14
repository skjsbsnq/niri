#!/usr/bin/env bash
# 一键诊断 v3：dock/launchpad 图标 hover 后消失（spring 化后回归）
#
# 做法：用全量 QML 日志级别重启 quickshell，stderr 进文件，然后留出
# 时间让你重现症状（hover dock 图标、点开 launchpad），时间到自动抓取
# hover 那一刻 quickshell 吐出的 QML warning（TypeError / ReferenceError /
# binding loop / Unable to assign undefined 之类——那才是根因）。
#
# 用法（VM 里）：
#   bash scripts/diagnose-tray-launcher.sh          # 重启 + 等你重现 45s
#   bash scripts/diagnose-tray-launcher.sh 90        # 等你重现 90s
#
# 跑起来后：桌面会闪一下（quickshell 重启），然后立刻去 hover dock 图标、
# 点 launchpad，把"图标消失"重现出来。倒计时结束自动出结果。
# 报告存到 /tmp/qs-hover-diag.txt，贴回来。

set -uo pipefail

WAIT="${1:-45}"
REPORT=/tmp/qs-hover-diag.txt
QSLOG=/tmp/qs-hover.log
: > "$REPORT"

say()  { printf '\n========== %s ==========\n' "$*" | tee -a "$REPORT"; }
line() { printf '%s\n' "$*" | tee -a "$REPORT"; }
ts()   { printf '[%s] ' "$(date '+%H:%M:%S')"; }

say "0. 时间 $(date -Is)"
line "重启后留 ${WAIT}s 给你重现症状。"

# ── 1. 杀掉当前 quickshell ──
say "1. 杀掉当前 quickshell"
if pgrep -x quickshell >/dev/null 2>&1; then
    pgrep -a quickshell | tee -a "$REPORT"
    pkill -x quickshell
    sleep 1
    line "已杀掉。"
else
    line "(没有 quickshell 进程在跑)"
fi

# ── 2. 用全量 QML 日志级别重启，stderr 进文件 ──
say "2. 重启 quickshell（QT_LOGGING_RULES=qml=true，stderr -> $QSLOG）"
: > "$QSLOG"
TAHOE_CFG="${TAHOE_CONFIG_DIR:-$HOME/.config/quickshell/tahoe}"
line "config: $TAHOE_CFG"

# 启动。用 nohup + setsid 保证脱离脚本也能活，日志进文件。
QT_LOGGING_RULES="qml=true" \
    nohup quickshell -p "$TAHOE_CFG" >"$QSLOG" 2>&1 &
QSPID=$!
setsid true 2>/dev/null || true
disown 2>/dev/null || true

# 等它起来
sleep 2
if pgrep -x quickshell >/dev/null 2>&1; then
    line "quickshell 已重启 (pid: $(pgrep -x quickshell | tr '\n' ' '))"
else
    line "!!! quickshell 没起来，看 $QSLOG。"
    line "── 启动日志前 30 行 ──"
    head -n 30 "$QSLOG" 2>/dev/null | tee -a "$REPORT"
    exit 1
fi

# ── 3. 留时间重现症状 ──
say "3. ★ 现在去重现症状（${WAIT}s）★"
line "  - 鼠标放 dock 上的 pinned 图标（Launchpad/Finder/Terminal/...）"
line "  - 点开启动器看空白"
line "  - 把'图标消失'重现出来"
line "倒计时："
BEFORE=$(wc -l < "$QSLOG" 2>/dev/null || echo 0)
line "（日志起始行数: $BEFORE，重现后行数会增加）"

for i in $(seq "$WAIT" -1 1); do
    printf '\r  剩余 %2ds   ' "$i" >&2
    sleep 1
done
printf '\r              \n' >&2

AFTER=$(wc -l < "$QSLOG" 2>/dev/null || echo 0)
line "（日志现在行数: $AFTER，新增 $((AFTER - BEFORE)) 行）"

# ── 4. 抓 hover 期间的 QML warning ──
say "4. ★ hover 期间的输出（关键）★"
line "── 全量日志中匹配 QML/错误的行（最后 80 行）──"
grep -inE "qml|error|warn|type|binding|image|source|null|undefined|cannot|failed|assign|icon" \
    "$QSLOG" 2>/dev/null | tail -n 80 | tee -a "$REPORT" \
    || line "(没有任何匹配行 — 见第 5 段)"

line
line "── 如果上面空，看原始日志最后 40 行 ──"
tail -n 40 "$QSLOG" 2>/dev/null | tee -a "$REPORT"

# ── 5. 判定 ──
say "5. 判定"
if [[ "$AFTER" -le "$BEFORE" ]]; then
    line "!!! hover 期间日志一行都没增加。"
    line "这说明 hover 根本没经过 quickshell 的 QML 引擎 ——"
    line "input 事件可能被 niri 的 input region 直接吞掉了。"
    line "方向转向：niri layer-shell input region / PanelWindow 的 WLayer。"
else
    MATCHED=$(grep -icE "qml|error|warn|type|binding|null|undefined|cannot|failed|assign" "$QSLOG" 2>/dev/null || echo 0)
    line "hover 期间新增 $((AFTER - BEFORE)) 行日志，其中 $MATCHED 行疑似 QML 错误。"
    line "把上面第 4 段贴给 AI 即可定位。"
fi

say "完成"
line "报告: $REPORT"
line "原始日志: $QSLOG"
