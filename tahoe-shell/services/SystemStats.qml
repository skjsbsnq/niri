pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// 左侧边栏系统页的数据泵。
//
// 这里保持无界面职责：一个长期运行的 shell 进程按行输出 JSON，QML 只做
// 轻量解析和属性暴露。指标来源与公式写在脚本注释里，方便以后维护。
Item {
    id: root
    visible: false

    property bool available: false
    property string lastError: ""
    property int parseErrorCount: 0

    property real cpuUsage: 0
    property real cpuTempC: 0
    property real cpuFrequencyGHz: 0
    property real gpuUsage: 0
    property real gpuTempC: 0
    property real ramUsage: 0
    property real ramUsedGB: 0
    property real ramTotalGB: 0
    property real netDownBps: 0
    property real netUpBps: 0
    property real load1: 0
    property real load5: 0
    property real load15: 0
    property int runningTasks: 0
    property int totalTasks: 0
    property int fanRpm: 0
    property real diskUsage: 0
    property real diskUsedGB: 0
    property real diskTotalGB: 0
    property string uptimeText: ""
    property var processes: []

    signal fastDataChanged()
    signal mediumDataChanged()
    signal slowDataChanged()

    function setValue(name, value) {
        if (root[name] !== value)
            root[name] = value;
    }

    function finiteNumber(value, fallback, minimum, maximum) {
        var n = Number(value);
        if (!isFinite(n))
            n = fallback;
        if (minimum !== undefined)
            n = Math.max(minimum, n);
        if (maximum !== undefined)
            n = Math.min(maximum, n);
        return n;
    }

    function finiteInt(value, fallback, minimum, maximum) {
        return Math.round(finiteNumber(value, fallback, minimum, maximum));
    }

    function textValue(value, fallback) {
        var text = String(value === undefined || value === null ? "" : value).trim();
        return text.length > 0 ? text : fallback;
    }

    function sanitizeProcesses(value) {
        if (!Array.isArray(value))
            return [];

        var result = [];
        for (var i = 0; i < value.length && result.length < 60; i++) {
            var item = value[i] || {};
            var pid = finiteInt(item.pid, 0, 1);
            if (pid <= 0)
                continue;

            result.push({
                "pid": pid,
                "user": textValue(item.user, ""),
                "uid": finiteInt(item.uid, -1, -1),
                "name": textValue(item.name, "process"),
                "cpuPercent": finiteNumber(item.cpuPercent, 0, 0),
                "memKB": finiteInt(item.memKB, 0, 0),
                "cmdline": textValue(item.cmdline, textValue(item.name, "process"))
            });
        }
        return result;
    }

    function parseStatsLine(line) {
        var text = String(line || "").trim();
        if (text.length === 0)
            return;

        var packet = null;
        try {
            packet = JSON.parse(text);
        } catch (e) {
            parseErrorCount += 1;
            return;
        }

        if (!packet || !packet.c)
            return;

        if (packet.c === "fast") {
            setValue("cpuUsage", finiteNumber(packet.cpuUsage, root.cpuUsage, 0, 100));
            setValue("ramUsage", finiteNumber(packet.ramUsage, root.ramUsage, 0, 100));
            setValue("ramUsedGB", finiteNumber(packet.ramUsedGB, root.ramUsedGB, 0));
            setValue("ramTotalGB", finiteNumber(packet.ramTotalGB, root.ramTotalGB, 0));
            setValue("netDownBps", finiteNumber(packet.netDownBps, 0, 0));
            setValue("netUpBps", finiteNumber(packet.netUpBps, 0, 0));
            root.fastDataChanged();
            return;
        }

        if (packet.c === "medium") {
            setValue("load1", finiteNumber(packet.load1, root.load1, 0));
            setValue("load5", finiteNumber(packet.load5, root.load5, 0));
            setValue("load15", finiteNumber(packet.load15, root.load15, 0));
            setValue("runningTasks", finiteInt(packet.runningTasks, root.runningTasks, 0));
            setValue("totalTasks", finiteInt(packet.totalTasks, root.totalTasks, 0));
            setValue("cpuTempC", finiteNumber(packet.cpuTempC, 0, 0));
            setValue("cpuFrequencyGHz", finiteNumber(packet.cpuFrequencyGHz, 0, 0));
            setValue("gpuTempC", finiteNumber(packet.gpuTempC, 0, 0));
            setValue("gpuUsage", finiteNumber(packet.gpuUsage, 0, 0, 100));
            setValue("processes", sanitizeProcesses(packet.processes));
            root.mediumDataChanged();
            return;
        }

        if (packet.c === "slow") {
            setValue("fanRpm", finiteInt(packet.fanRpm, 0, 0));
            setValue("diskUsage", finiteNumber(packet.diskUsage, 0, 0, 100));
            setValue("diskUsedGB", finiteNumber(packet.diskUsedGB, 0, 0));
            setValue("diskTotalGB", finiteNumber(packet.diskTotalGB, 0, 0));
            setValue("uptimeText", textValue(packet.uptimeText, ""));
            root.slowDataChanged();
        }
    }

    function monitorScript() {
        return [
            "set +e",
            "LC_ALL=C",
            "export LC_ALL",
            "have() { command -v \"$1\" >/dev/null 2>&1; }",
            "",
            "# CPU: /proc/stat, usage = non-idle delta / total delta * 100.",
            "read_cpu() {",
            "  awk '/^cpu / { idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; printf \"%.0f %.0f\\n\", total, idle; exit }' /proc/stat 2>/dev/null || printf '0 0\\n'",
            "}",
            "",
            "# Memory: /proc/meminfo, usage = (MemTotal - MemAvailable) / MemTotal.",
            "read_mem() {",
            "  awk '/^MemTotal:/ { total=$2 } /^MemAvailable:/ { avail=$2 } END { if (total > 0 && avail >= 0) { used=total-avail; printf \"%.1f %.3f %.3f\\n\", used*100/total, used/1048576, total/1048576 } else { printf \"0 0 0\\n\" } }' /proc/meminfo 2>/dev/null || printf '0 0 0\\n'",
            "}",
            "",
            "# Network: /proc/net/dev, sum non-loopback rx/tx bytes.",
            "read_net_bytes() {",
            "  awk 'NR>2 { iface=$1; sub(/:/, \"\", iface); if (iface != \"lo\") { rx+=$2; tx+=$10 } } END { printf \"%.0f %.0f\\n\", rx, tx }' /proc/net/dev 2>/dev/null || printf '0 0\\n'",
            "}",
            "",
            "# Load: /proc/loadavg, plus running/total task counts from field 4.",
            "read_load() {",
            "  awk '{ split($4, tasks, \"/\"); printf \"%.2f %.2f %.2f %d %d\\n\", $1, $2, $3, tasks[1], tasks[2] }' /proc/loadavg 2>/dev/null || printf '0 0 0 0 0\\n'",
            "}",
            "",
            "# CPU temperature: prefer CPU-related hwmon chips, then fall back to labels.",
            "read_cpu_temp() {",
            "  for hw in /sys/class/hwmon/hwmon*; do",
            "    [ -d \"$hw\" ] || continue",
            "    name=$(cat \"$hw/name\" 2>/dev/null)",
            "    case \"$name\" in",
            "      coretemp|k10temp|zenpower|x86_pkg_temp|cpu_thermal|acpitz)",
            "        for f in \"$hw\"/temp*_input; do",
            "          [ -r \"$f\" ] || continue",
            "          v=$(cat \"$f\" 2>/dev/null)",
            "          awk -v v=\"$v\" 'BEGIN { if (v > 0) printf \"%.1f\\n\", v/1000; else printf \"0\\n\" }'",
            "          return",
            "        done",
            "        ;;",
            "    esac",
            "  done",
            "  for hw in /sys/class/hwmon/hwmon*; do",
            "    [ -d \"$hw\" ] || continue",
            "    for f in \"$hw\"/temp*_input; do",
            "      [ -r \"$f\" ] || continue",
            "      label=$(cat \"${f%_input}_label\" 2>/dev/null)",
            "      case \"$label\" in",
            "        *CPU*|*Core*|*Package*|*Tctl*|*Tdie*)",
            "          v=$(cat \"$f\" 2>/dev/null)",
            "          awk -v v=\"$v\" 'BEGIN { if (v > 0) printf \"%.1f\\n\", v/1000; else printf \"0\\n\" }'",
            "          return",
            "          ;;",
            "      esac",
            "    done",
            "  done",
            "  printf '0\\n'",
            "}",
            "",
            "# CPU frequency: scaling_cur_freq kHz -> GHz; /proc/cpuinfo fallback.",
            "read_cpu_freq() {",
            "  f=/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq",
            "  if [ -r \"$f\" ]; then",
            "    v=$(cat \"$f\" 2>/dev/null)",
            "    awk -v v=\"$v\" 'BEGIN { if (v > 0) printf \"%.2f\\n\", v/1000000; else printf \"0\\n\" }'",
            "    return",
            "  fi",
            "  awk -F: '/cpu MHz/ { gsub(/^[ \\t]+/, \"\", $2); printf \"%.2f\\n\", $2/1000; found=1; exit } END { if (!found) printf \"0\\n\" }' /proc/cpuinfo 2>/dev/null || printf '0\\n'",
            "}",
            "",
            "# GPU: detect nvidia-smi once; otherwise use drm busy percent + hwmon temp.",
            "detect_gpu_backend() {",
            "  if have nvidia-smi && nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits >/dev/null 2>&1; then",
            "    GPU_BACKEND=nvidia",
            "  else",
            "    GPU_BACKEND=sysfs",
            "  fi",
            "}",
            "",
            "read_gpu() {",
            "  if [ \"$GPU_BACKEND\" = nvidia ]; then",
            "    line=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' ')",
            "    if [ -n \"$line\" ] && [ \"${line#*,}\" != \"$line\" ]; then",
            "      temp=${line%%,*}",
            "      usage=${line#*,}",
            "      awk -v t=\"$temp\" -v u=\"$usage\" 'BEGIN { if (t < 0) t=0; if (u < 0) u=0; printf \"%.1f %.1f\\n\", t+0, u+0 }'",
            "      return",
            "    fi",
            "  fi",
            "  usage=0",
            "  for f in /sys/class/drm/card*/device/gpu_busy_percent; do",
            "    [ -r \"$f\" ] || continue",
            "    usage=$(cat \"$f\" 2>/dev/null)",
            "    break",
            "  done",
            "  temp=0",
            "  for f in /sys/class/drm/card*/device/hwmon/hwmon*/temp*_input; do",
            "    [ -r \"$f\" ] || continue",
            "    v=$(cat \"$f\" 2>/dev/null)",
            "    if [ -n \"$v\" ] && [ \"$v\" -gt 0 ] 2>/dev/null; then",
            "      temp=$(awk -v v=\"$v\" 'BEGIN { printf \"%.1f\", v/1000 }')",
            "      break",
            "    fi",
            "  done",
            "  if [ \"$temp\" = 0 ]; then",
            "    for hw in /sys/class/hwmon/hwmon*; do",
            "      [ -d \"$hw\" ] || continue",
            "      name=$(cat \"$hw/name\" 2>/dev/null)",
            "      case \"$name\" in",
            "        amdgpu|i915|nouveau|radeon)",
            "          for f in \"$hw\"/temp*_input; do",
            "            [ -r \"$f\" ] || continue",
            "            v=$(cat \"$f\" 2>/dev/null)",
            "            if [ -n \"$v\" ] && [ \"$v\" -gt 0 ] 2>/dev/null; then",
            "              temp=$(awk -v v=\"$v\" 'BEGIN { printf \"%.1f\", v/1000 }')",
            "              break 2",
            "            fi",
            "          done",
            "          ;;",
            "      esac",
            "    done",
            "  fi",
            "  awk -v t=\"$temp\" -v u=\"$usage\" 'BEGIN { if (t < 0) t=0; if (u < 0) u=0; if (u > 100) u=100; printf \"%.1f %.1f\\n\", t+0, u+0 }'",
            "}",
            "",
            "# Fan: first readable hwmon fan*_input RPM.",
            "read_fan() {",
            "  for f in /sys/class/hwmon/hwmon*/fan*_input; do",
            "    [ -r \"$f\" ] || continue",
            "    v=$(cat \"$f\" 2>/dev/null)",
            "    awk -v v=\"$v\" 'BEGIN { if (v > 0) printf \"%d\\n\", v; else printf \"0\\n\" }'",
            "    return",
            "  done",
            "  printf '0\\n'",
            "}",
            "",
            "# Processes: procps ps does sorting; awk escapes the final JSON.",
            "read_processes_json() {",
            "  if ! have ps; then",
            "    printf '[]'",
            "    return",
            "  fi",
            "  ps -eo pid=,user=,uid=,pcpu=,rss=,comm=,args= --sort=-pcpu 2>/dev/null | awk '",
            "function esc(s) { gsub(/\\\\/, \"\\\\\\\\\", s); gsub(/\\\"/, \"\\\\\\\"\", s); gsub(/[[:cntrl:]]/, \"?\", s); return s }",
            "BEGIN { printf \"[\"; count=0 }",
            "NR <= 50 {",
            "  pid=$1+0; user=$2; uid=$3+0; cpu=$4+0; rss=$5+0; comm=$6; cmd=\"\";",
            "  for (i=7; i<=NF; i++) cmd=cmd (i>7 ? \" \" : \"\") $i;",
            "  if (cmd == \"\") cmd=comm;",
            "  if (comm == \"\") comm=cmd;",
            "  if (pid <= 0) next;",
            "  if (count > 0) printf \",\";",
            "  printf \"{\\\"pid\\\":%d,\\\"user\\\":\\\"%s\\\",\\\"uid\\\":%d,\\\"name\\\":\\\"%s\\\",\\\"cpuPercent\\\":%.1f,\\\"memKB\\\":%d,\\\"cmdline\\\":\\\"%s\\\"}\", pid, esc(user), uid, esc(comm), cpu, rss, esc(cmd);",
            "  count++;",
            "}",
            "END { printf \"]\" }'",
            "}",
            "",
            "# Disk: df /, used and total bytes -> GiB, usage percent from df.",
            "read_disk() {",
            "  df -P -B1 / 2>/dev/null | awk 'NR==2 { pct=$5; gsub(/%/, \"\", pct); printf \"%.1f %.3f %.3f\\n\", pct+0, $3/1073741824, $2/1073741824; found=1 } END { if (!found) printf \"0 0 0\\n\" }' || printf '0 0 0\\n'",
            "}",
            "",
            "# Uptime: /proc/uptime seconds -> compact display token.",
            "read_uptime() {",
            "  awk '{ s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if (d > 0) printf \"%dd %dh\\n\", d, h; else if (h > 0) printf \"%dh %dm\\n\", h, m; else printf \"%dm\\n\", m }' /proc/uptime 2>/dev/null || printf '\\n'",
            "}",
            "",
            "detect_gpu_backend",
            "set -- $(read_cpu)",
            "prev_cpu_total=${1:-0}",
            "prev_cpu_idle=${2:-0}",
            "set -- $(read_net_bytes)",
            "prev_rx=${1:-0}",
            "prev_tx=${2:-0}",
            "prev_time=$(date +%s 2>/dev/null || printf '0')",
            "tick=0",
            "",
            "while :; do",
            "  sleep 1",
            "  tick=$((tick + 1))",
            "  now=$(date +%s 2>/dev/null || printf '0')",
            "  elapsed=$((now - prev_time))",
            "  [ \"$elapsed\" -gt 0 ] 2>/dev/null || elapsed=1",
            "",
            "  set -- $(read_cpu)",
            "  cpu_total=${1:-0}",
            "  cpu_idle=${2:-0}",
            "  cpu_delta=$((cpu_total - prev_cpu_total))",
            "  cpu_idle_delta=$((cpu_idle - prev_cpu_idle))",
            "  cpu_usage=$(awk -v d=\"$cpu_delta\" -v i=\"$cpu_idle_delta\" 'BEGIN { if (d > 0) { v=(d-i)*100/d; if (v < 0) v=0; if (v > 100) v=100; printf \"%.1f\", v } else printf \"0\" }')",
            "",
            "  set -- $(read_mem)",
            "  ram_usage=${1:-0}",
            "  ram_used=${2:-0}",
            "  ram_total=${3:-0}",
            "",
            "  set -- $(read_net_bytes)",
            "  rx=${1:-0}",
            "  tx=${2:-0}",
            "  rx_delta=$((rx - prev_rx))",
            "  tx_delta=$((tx - prev_tx))",
            "  [ \"$rx_delta\" -ge 0 ] 2>/dev/null || rx_delta=0",
            "  [ \"$tx_delta\" -ge 0 ] 2>/dev/null || tx_delta=0",
            "  net_down=$(awk -v d=\"$rx_delta\" -v s=\"$elapsed\" 'BEGIN { if (s > 0) printf \"%.0f\", d/s; else printf \"0\" }')",
            "  net_up=$(awk -v d=\"$tx_delta\" -v s=\"$elapsed\" 'BEGIN { if (s > 0) printf \"%.0f\", d/s; else printf \"0\" }')",
            "  printf '{\"c\":\"fast\",\"cpuUsage\":%s,\"ramUsage\":%s,\"ramUsedGB\":%s,\"ramTotalGB\":%s,\"netDownBps\":%s,\"netUpBps\":%s}\\n' \"$cpu_usage\" \"$ram_usage\" \"$ram_used\" \"$ram_total\" \"$net_down\" \"$net_up\"",
            "",
            "  if [ $((tick % 2)) -eq 0 ]; then",
            "    set -- $(read_load)",
            "    load1=${1:-0}; load5=${2:-0}; load15=${3:-0}; running_tasks=${4:-0}; total_tasks=${5:-0}",
            "    cpu_temp=$(read_cpu_temp)",
            "    cpu_freq=$(read_cpu_freq)",
            "    set -- $(read_gpu)",
            "    gpu_temp=${1:-0}",
            "    gpu_usage=${2:-0}",
            "    processes=$(read_processes_json)",
            "    printf '{\"c\":\"medium\",\"load1\":%s,\"load5\":%s,\"load15\":%s,\"runningTasks\":%s,\"totalTasks\":%s,\"cpuTempC\":%s,\"cpuFrequencyGHz\":%s,\"gpuTempC\":%s,\"gpuUsage\":%s,\"processes\":%s}\\n' \"$load1\" \"$load5\" \"$load15\" \"$running_tasks\" \"$total_tasks\" \"$cpu_temp\" \"$cpu_freq\" \"$gpu_temp\" \"$gpu_usage\" \"$processes\"",
            "  fi",
            "",
            "  if [ $((tick % 5)) -eq 0 ]; then",
            "    fan_rpm=$(read_fan)",
            "    set -- $(read_disk)",
            "    disk_usage=${1:-0}",
            "    disk_used=${2:-0}",
            "    disk_total=${3:-0}",
            "    uptime_text=$(read_uptime)",
            "    printf '{\"c\":\"slow\",\"fanRpm\":%s,\"diskUsage\":%s,\"diskUsedGB\":%s,\"diskTotalGB\":%s,\"uptimeText\":\"%s\"}\\n' \"$fan_rpm\" \"$disk_usage\" \"$disk_used\" \"$disk_total\" \"$uptime_text\"",
            "  fi",
            "",
            "  prev_cpu_total=$cpu_total",
            "  prev_cpu_idle=$cpu_idle",
            "  prev_rx=$rx",
            "  prev_tx=$tx",
            "  prev_time=$now",
            "done"
        ].join("\n");
    }

    Process {
        id: statsProcess
        running: true
        command: ["sh", "-lc", root.monitorScript()]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                root.parseStatsLine(line);
            }
        }
        onStarted: {
            root.setValue("available", true);
            root.setValue("lastError", "");
        }
        onRunningChanged: {
            if (!running && !restartTimer.running)
                restartTimer.restart();
        }
        onExited: function(code, exitStatus) {
            root.setValue("available", false);
            if (code !== 0)
                root.setValue("lastError", "SystemStats exited with code " + String(code));
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!statsProcess.running)
                statsProcess.running = true;
        }
    }
}
