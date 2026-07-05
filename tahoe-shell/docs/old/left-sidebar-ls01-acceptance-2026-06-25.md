# Left Sidebar LS01 验收记录

日期：2026-06-25

状态：完成

## 修改范围

- 新增 `tahoe-shell/services/SystemStats.qml`。
  - 使用长期运行的 `Process` 启动内联 shell 脚本。
  - 脚本按 JSON 行输出 `fast` / `medium` / `slow` 三类数据。
  - QML 侧按行解析、sanitize 数值、暴露属性并发出 `fastDataChanged` / `mediumDataChanged` / `slowDataChanged`。
  - 进程异常退出后 2 秒自动重启。
- 修改 `tahoe-shell/shell.qml`。
  - 在服务声明区新增 `SystemStats { id: systemStats }`。
  - 未接入任何视图或顶栏入口。

## 暴露数据

- fast，约 1 秒：`cpuUsage`、`ramUsage`、`ramUsedGB`、`ramTotalGB`、`netDownBps`、`netUpBps`。
- medium，约 2 秒：`load1`、`load5`、`load15`、`runningTasks`、`totalTasks`、`cpuTempC`、`cpuFrequencyGHz`、`gpuTempC`、`gpuUsage`、`processes`。
- slow，约 5 秒：`fanRpm`、`diskUsage`、`diskUsedGB`、`diskTotalGB`、`uptimeText`。

## 数据来源

- CPU：`/proc/stat`，非 idle 增量 / total 增量。
- 内存：`/proc/meminfo`，`(MemTotal - MemAvailable) / MemTotal`。
- 网络：`/proc/net/dev`，非 loopback 接口 rx/tx 字节增量。
- 负载：`/proc/loadavg`。
- CPU 温度：`/sys/class/hwmon/*/temp*_input`，优先 CPU 相关 hwmon。
- CPU 频率：`scaling_cur_freq`，回退 `/proc/cpuinfo`。
- GPU：启动时检测 `nvidia-smi`；否则回退 DRM `gpu_busy_percent` 和 GPU hwmon。
- 风扇：第一个可读 `fan*_input`。
- 进程：`ps -eo pid,user,uid,pcpu,rss,comm,args --sort=-pcpu`，限制 top 50。
- 磁盘：`df -P -B1 /`。
- uptime：`/proc/uptime`。

## 验证命令

```bash
/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I /home/wwt/niri/quickshell/build-tahoe/qml_modules services/SystemStats.qml shell.qml
timeout 12s /home/wwt/.local/bin/quickshell --no-color --path /home/wwt/niri/tahoe-shell
rg -n "LS01 SystemStats|console\\.log\\(|SpringAnimation" services/SystemStats.qml shell.qml
pgrep -af 'quickshell.*tahoe-shell|read_processes_json|SystemStats exited|gpu_busy_percent' || true
```

## 运行验收结果

- `qmllint` 退出 0。
  - 输出仍包含 `shell.qml` 既有 `modelData` unqualified warning；不是本次新增。
- 临时在 `shell.qml` 加 `Connections` 打印三类 signal，运行后已撤掉。
- `quickshell` smoke 到达 `Configuration Loaded`；`timeout` 退出 124 为预期。
- `fastDataChanged` 约每 1 秒触发。
  - 样例：`cpu=33.6 ram=45.2 netD=0 netU=0`。
  - 样例：`cpu=24.4 ram=45.5 netD=86 netU=81189`。
- `mediumDataChanged` 约每 2 秒触发。
  - 样例：`load=2.58 temp=100.1 procs=50`。
  - `processes.length` 为 50，满足 top50 进程列表要求。
- `slowDataChanged` 约每 5 秒触发。
  - 样例：`disk=16 fan=0 uptime=1h 8m`。
- CPU 在 0-100 范围内，网络速率非负，RAM 百分比合理。
- `rg` 未命中临时 `LS01 SystemStats` 日志、`console.log` 或 `SpringAnimation`。
- 验收结束后没有遗留 repo-path Quickshell/SystemStats 子进程。

## 运行时警告说明

本次 smoke 中仍出现既有运行时警告：

- Dock/WindowButton 的 `magnification`、`bounceOffset` interceptor warning。
- `shell.qml` 中 `Qt.application.font` 只读属性 warning。
- 第二个 repo-path shell 与当前会话并存时的 notification server 注册 warning。
- portal app id 注册 warning。

未出现 `SystemStats.qml` 加载失败、JSON 解析报错、进程退出重启报错或新增 import 错误。

## 偏离与理由

- 按行流式解析使用 `SplitParser`，不是 `StdioCollector`。
  - 原因：`StdioCollector.onStreamFinished` 只在进程退出时触发，长期循环进程不适合；`waitForEnd: false` 又会持续累积输出。`SplitParser` 是本仓库 `Windows.qml` / `Controls.qml` 已用的流式行解析方式，风险更低。
  - 行为仍满足 LS01：`Process` 输出 JSON 行，QML 按行解析并发出三类数据 signal。

## 遗留项

- LS01 只提供服务和 shell 声明，不提供 UI 展示。
- 进程右键菜单、系统页 Canvas、天气服务和侧边栏容器留给后续 LSxx。
