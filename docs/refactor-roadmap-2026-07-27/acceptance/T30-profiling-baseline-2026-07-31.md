# T-30 · Profiling 基线采集（2026-07-31）

任务定义：`docs/refactor-roadmap-2026-07-27/roadmap.md` T-30。配套研究报告：同目录
`research-report.md` 第三部分「渲染性能」（R-1~R-8 与 Profiling 计划）。
原始产物归档：`~/.local/state/tahoe-profiling/t30-2026-07-31/`（tracy `.tracy` ×7、qmlprofiler `.qmlprof` ×2、会话/遥测日志、功耗 CSV、`analysis.json`）。

## 0. 门槛锁定声明

以下门槛在本任务采集任何样本之前按目标硬件与研究报告第三部分固定（research-report.md:177），
判定只对照本节，不回写门槛：

- 单项 ≥ **0.3 ms/帧**（60 Hz 帧预算 16.67 ms 的 1.8%）或 ≥ **3% GPU 帧时间** 才准入实现队列；
- R-1（queue_redraw_all 收敛）与 R-5（Wallpaper 异步化）为结构正确性任务，免门槛；
- 指标分离：CPU 帧时间、GPU 帧时间、功耗、协议流量不得混成单一「流畅度」结论。

## 1. 环境表

| 项 | 值 |
| --- | --- |
| 主机 | 笔记本，AMD Ryzen 7 7745HX（16 线程），NVIDIA RTX 4070 Laptop（dGPU），AMD Raphael iGPU |
| 线上会话 | niri 26.04 (866d73ea) + quickshell（Tahoe），输出 eDP-2 2560x1600@240Hz scale 1.25，逻辑 2048x1280；空闲功耗对照：CPU 3.9%、iGPU 22.1 W、dGPU 11.4 W（60s×1，见 §4.5） |
| 基线 commit | 外层 `089e7bc`（T-29 HEAD）、niri `866d73ea`、quickshell 部署二进制（`5a984c7` 构建） |
| 采集会话 | **嵌套 winit**（`NIRI_MODE=nested`，scripts/run-tahoe-session.sh），输出 winit 1600x1000@60Hz scale 1；niri 以 `--features profile-with-tracy` 构建（同一 commit，无源码改动）；`NIRI_FRAME_TELEMETRY=1`、`NIRI_LIFECYCLE_DIAG=1` |
| 渲染后端 | 嵌套 niri/quickshell 的 GL 上下文落在 **NVIDIA dGPU**（QSG_INFO：`OpenGL ES 3.2 NVIDIA 610.43.03`）；线上为 AMD iGPU DRM 路径（本任务未做 GPU 内帧测量，见 §7） |
| Tracy | niri 内嵌 tracy-client 0.13.1（tracy-client-sys 0.28.0）；捕获端 tracy-capture 0.13.1、分析端 tracy-csvexport 0.13.1（均按 v0.13.1 tag 构建） |
| QSG 计时 | Qt6 无 `QSG_RENDER_TIMER`（该变量止于 Qt 5.5 的 `QSG_RENDER_TIMING`）；等效机制 `QT_LOGGING_RULES='qt.scenegraph.time.renderloop=true'`，每帧输出 polish/sync/render/swap ms |
| 功耗工具 | turbostat/intel_gpu_top 未安装且不适用（Intel-only；RAPL `energy_uj` 本机 root-only）→ 替代：`tools/t30-profiling/power-sample.sh`（/proc CPU%、k10temp、amdgpu hwmon `power1_input`、nvidia-smi `power.draw`） |

## 2. 锁定门槛（T-32~T-35 各自准入条件）

| 任务 | 门槛（研究报告第三部分） | 判定依据来源 |
| --- | --- | --- |
| T-32 glass capture band 量化 + downsample tier2 | capture+blur 管线 ≥0.3ms/帧（动画期）或 ≥3% GPU 帧时间 | lifecycle-diag fb_capture/blur 计数（权威）+ tracy capture/blur zone 单次成本 |
| T-33 glass shader 法线场 LUT | glass draw（GPU span）≥3% GPU 帧时间；CPU 侧 draw 成本 ≥0.3ms/帧 | tracy GPU span（本环境不可用）→ CPU 侧 ShaderRenderElement::draw / TahoeGlass::render_region |
| T-34 xray 短路 + per-region 脏标记 | xray 更新 ≥0.3ms/帧 或 region rebuild ≥0.3ms/帧 | tracy `Niri::fill_xray_elements`、QSG polish |
| T-35 Island Loader 预热 + Dock 波节流 | 展开首帧/波场景 JS 总量证实热 | QSG 帧时间、qmlprofiler 原始数据 |

## 3. 四场景采集矩阵

| 场景 | 内容 | 驱动 | 样本 |
| --- | --- | --- | --- |
| A-idle ×3 | 静置（无输入） | 无 | tracy 68s×3（A-idle-1/2 客户端提前断连，实际 33.6s/29.4s）+ 功耗 60s×3；遥测/计数器全程 |
| A-cursor | 光标画圈 R=400 逻辑 px，3 圈 ×10s | `tools/t30-profiling/vpointer`（zwlr_virtual_pointer_v1，相对步进 128 步/圈 = 12.8 event/s） | tracy 45s |
| B-dock | Dock 波 10s（底边横向扫两遍，130 步/5s），指针停在 dock 行 | vpointer | tracy 45s（**波输入落在 winit swap 停顿期，compositor 侧波数据无效，见 §5**） |
| C-island | Island 展开 ×10（quickshell IPC `dynamicIslandShowNotification`，间隔 1.5s） | quickshell ipc | tracy 45s |
| D-overview | Overview 进出 ×10（quickshell IPC `toggleWindowOverview`，间隔 1.2s） | quickshell ipc | tracy 45s |
| QML 侧 | B/C 场景在 `--debug 3768` + renderloop 计时的嵌套 quickshell 上重放 | 同上 | qmlprofiler ×2（binding/creating/js/compiling；scenegraph/animations/painting）+ QSG 计时日志 |

每个 compositor 场景使用**独立重启的嵌套会话**（tracy 客户端每进程只接受一个服务端；计数器按场景清零）。
速率类指标以进程内遥测/计数器为权威；tracy 提供单次成本结构（低负载场景计数与计数器一致，见 §4.3 注）。

## 4. 原始样本

### 4.1 帧遥测（进程内，权威）

| 场景 | 活动期 fps | render_p95（ms） | 说明 |
| --- | --- | --- | --- |
| A-idle-1/2/3 | 0（稳态无 redraw） | — | 启动突发后合成器静默（日志在无 redraw 时无输出，非会话死亡；trace 时间跨度 39.2s/35.0s/73.7s 证明会话存活） |
| A-cursor | 12.8–26.8 | 2.77–5.09 | fps=圆圈步进率 12.8/s 的 1–2 倍 |
| B-dock | 波期 ~1（swap 停顿伪影）；QML 接管期 34–97 | 1.75–5.35（接管期） | 见 §5 |
| C-island | 45.4（峰值窗口，227 redraw/5s） | 4.97 | |
| D-overview | 7.0–26.7（10 次进出） | 3.22–5.56 | |

### 4.2 生命周期计数器（lifecycle-diag 5s 增量，进程内权威）

| 场景 | 会话长度 | fb_capture 总量 | 峰值 5s 窗口（/s） | 会话均值（/s） | queue_redraw_all 峰值/5s |
| --- | --- | --- | --- | --- | --- |
| A-idle-1 | ~10s（trace 39.2s） | 0（窗口未覆盖启动突发；tracy 显示启动 0.6s 内 129 次 ≈215/s） | — | 0 | 0 |
| A-idle-2 | ~15s | 130 | 130（26/s，启动突发） | 8.7 | 5 |
| A-idle-3 | ~20s | 127 | 125（25/s，启动突发） | 6.4（稳态 2/5s=0.4/s） | 1 |
| A-cursor | ~45s | 125 | 123（24.6/s，启动突发；圆圈期 0） | 2.8 | 65 |
| B-dock | ~185s | 3525 | 180（36/s，QML 接管期 dock 波/hover，持续 ~85s） | 19.1 | 503 |
| C-island | ~10s | 308 | 308（61.6/s） | 30.8 | 16 |
| D-overview | ~30s | 863 | 310（62/s） | 28.8 | 22 |

注：A-idle-1/2 的 tracy 捕获提前断连（33.6s/29.4s，原因未确认），其功耗样本可能含少量会话结束后时段，见 §7。

### 4.3 tracy 单次成本结构（嵌套 NVIDIA）

| zone | A-idle-1 | A-cursor | B-dock* | C-island | D-overview |
| --- | --- | --- | --- | --- | --- |
| `FramebufferEffectElement::capture_framebuffer` mean / max（ms） | 0.469 / 10.9 | 0.614 / 10.1 | 0.364 / 8.8 | 0.307 / 11.5 | 0.209 / 7.9 |
| `Blur::render` mean / max（ms） | 0.288 / 3.7 | 0.292 / 6.6 | 0.198 / 6.1 | 0.197 / 8.4 | 0.131 / 5.1 |
| `TahoeGlass::render_region` mean（µs） | 2.2 | 3.7 | 2.9 | 2.1 | 2.2 |
| `ShaderRenderElement::draw` mean（µs） | 4.1 | 6.1 | 4.8 | 3.5 | 5.1 |
| `Niri::fill_xray_elements` mean（µs）/ 覆盖帧数 | 9.7 / 141 | 14.7 / 524 | 10.1 / 201 | 6.8 / 187 | 6.8 / 346 |
| `Niri::redraw` mean（ms） | 2.49 | 1.68 | 225† | 2.34 | 2.36 |

\* B-dock 的 capture/blur/redraw 采样来自启动突发与 swap 停顿期（波输入期间 compositor 几乎无帧），**不代表波期成本**；波/hover 期的 36/s 证据来自计数器（§5）。
† winit 嵌套 1s swap 停顿伪影；动画期真实渲染 p95 见 4.1。
计数一致性：A-idle-2/3、A-cursor、C-island、D-overview 的 tracy capture zone 数与 lifecycle 计数器一致（130/127/125/313/863 vs 130/127/125/308/863，±启动缓冲）；B-dock 的 205 vs 3525 由 capture 窗口（45s）早于活动期（12:45:00+）结束解释，**无环形缓冲丢 zone 证据**。
GPU zone（`-g`）在嵌套 NVIDIA 上下文为空：GL 扩展 `GL_EXT_disjoint_timer_query` 缺失，smithay GpuProfiler 静默降级为 no-op。

### 4.4 QSG 渲染循环（嵌套 quickshell，B+C 重放，924 帧）

| 指标 | min | 中位 | p90 | p95 | max |
| --- | --- | --- | --- | --- | --- |
| 帧总时长 ms | 0 | 1 | 4 | 5 | 12 |
| polish ms | 0 | 0 | 0 | 0 | 1 |
| render ms | 0 | 0 | 0 | 0 | 1 |
| swap ms | 0 | 0 | 2 | 3 | 10 |

924/924 帧 < 17 ms（60 Hz 预算）。首次启动含一次性 EGL 初始化停顿（~992 ms，见 §7）。

### 4.5 功耗/负载（60s×3 中位）

| 样本 | CPU 忙 % | CPU 温度 °C | iGPU W | dGPU W |
| --- | --- | --- | --- | --- |
| A-idle-1 | 4.3 | 78.7 | 25.1 | 12.9 |
| A-idle-2 | 4.3 | 77.3 | 23.2 | 12.8 |
| A-idle-3 | 4.1 | 69.7 | 22.1 | 15.2 |
| 线上空闲（对照） | 3.9 | 71.9 | 22.1 | 11.4 |

## 5. B-dock 会话时间线（计数器 × 遥测对齐；本场景波数据归属修正）

| 时段（会话 t） | redraws/5s | fb_capture/5s | queue_redraw_all/5s | 事件与判定 |
| --- | --- | --- | --- | --- |
| t+0–5s | 151 | 131 | 12 | 启动突发（blur 纹理重建、glass 区域映射） |
| t+5–70s | 5–9 | 10–12 | 0–1 | **波输入（t≈6–16s）落在此段**：winit 嵌套 swap 停顿（p95≈1000ms，~1fps，host 帧回调节流/遮挡伪影）→ **compositor 侧波成本未测得，本场景 trace 不作为波数据** |
| t+65–150s | 170–488 | **180（36/s）** | 0–503 | QML 阶段接管该会话（嵌套 quickshell 换为 `--debug 3768` 版并重放 B/C；指针仍停在 dock 行）→ dock 波/hover 状态的**计数器级**证据：34fps、36 captures/s 持续 ~65–85s |
| t+155s+ | 120 | 0 | 0 | 波静止后 shell 仍以 24fps 提交（无 capture） |

说明：B-dock 场景的 vpointer 波输入（t≈6–16s）恰好落入 ~60s 的 swap 停顿期，遥测显示该段仅 ~1fps；
因此「36/s 持续」与「queue_redraw_all 503/5s」虽为真实计数器读数，但来自 QML 接管会话（shell 重启 + dock 波/hover），
不是 B-dock 场景自己的 trace。Dock 波/hover 的 compositor 侧成本（36 captures/s）由计数器成立，
波期单次 capture 成本借用 C/D 场景的 tracy mean（0.21–0.36ms）。

## 6. 判定表（对照 §2 锁定门槛）

| 任务 | 判定 | 依据 |
| --- | --- | --- |
| **T-32** glass capture band 量化 + 快速运动 downsample tier2 | **通过（GO）** | capture+blur 每事件 0.4–0.9 ms（4.3）；动画期每帧折算：C-island 峰值窗口 308 captures/227 redraws × 0.307ms = **0.42 ms/帧**；D-overview 峰值窗口 310/103 × 0.209ms 与 139/39 × 0.209ms = **0.61–0.75 ms/帧**；B-dock 波/hover（计数器）36/s × 0.36ms ÷ 34fps = **0.38 ms/帧**。全部 ≥0.3 ms/帧。band 量化（4–8× 重捕获降幅）与 tier2 降采样命中该热路径；实施须保持严格超集捕获（61138be 教训） |
| **T-33** glass shader 法线场 LUT | **不通过（NO-GO）** | GPU span 本环境不可测（无 timer query 扩展）；CPU 侧 glass draw（ShaderRenderElement::draw + render_region）约 **10–60 µs/帧**，远低于 0.3 ms/帧。无法证明 ≥3% GPU 帧时间；需在 AMD 实机/可用 GPU 计时的环境复测后才可准入 |
| **T-34** xray 短路 + per-region 脏标记 | **不通过（NO-GO）** | `Niri::fill_xray_elements` 每帧 6.8–14.7 µs（4.3），远低于 0.3 ms/帧；嵌套 QSG polish ≤1 ms。region 请求 wire 量大（D-overview 峰值 343–399/5s）但门槛是 ms/帧 而非流量。xray 部分按源码结构仍可作免门槛的整洁性改动，但不满足性能准入 |
| **T-35** Island Loader 预热 + Dock 波节流 | **不通过（NO-GO）** | QSG 帧 924/924 <17 ms（含 island/wave 重放期），无帧超预算证据；波场景的 JS 总量需 Qt Creator 解析 qmlprofiler（未运行，§7）。波的热点实测在 compositor 侧 capture 管线（归入 T-32），FrameAnimation 节流无帧时间证据 |
| 佐证（免门槛项） | — | B-dock QML 接管期 queue_redraw_all 峰值 503/5s、A-cursor 光标移动期 58/5s——光标/dock 路径仍在打全局 redraw，为 **T-31（R-1）定向 redraw 收敛** 提供直接数据依据 |

## 7. 未运行项 / 限制（不得记为通过）

1. **GPU 帧时间**：嵌套 NVIDIA 上下文缺 `GL_EXT_disjoint_timer_query`，smithay GPU span 为空；线上 AMD iGPU DRM 路径未测（需 tracy 版二进制重启线上会话，会中断本任务运行环境）。T-33 的 GPU 侧证据因此缺失。
2. **qmlprofiler 定量解析**：`qml-binding.qmlprof`（165 MB）/`qml-scenegraph.qmlprof`（296 MB）已归档，binding/JS/create 分布需 Qt Creator 可视化，本次未提取定量分布（Wallpaper 5s 尖峰、Island create 逐项统计留待 T-34/T-35 实施前）。
3. **B-dock compositor 侧波成本未测得**：波输入落入 ~60s winit swap 停顿（host 帧回调节流/遮挡伪影）；波/hover 的 36/s 证据来自 QML 接管会话的计数器。T-32 判定由 C-island/D-overview 干净数据独立支撑。
4. **A-idle-1/2 tracy 提前断连**：捕获 33.6s/29.4s 而非 68s（A-idle-3 完整 68s），原因未确认；对应功耗样本可能含少量会话结束后时段（数值与线上空闲对照接近，影响有限）。
5. **QSG 首次启动停顿**：首轮 EGL 初始化 ~992 ms 为一次性，不计入基线。
6. **winit 嵌套限制**：无 KMS presentation（frame_time 分位为 0）、swap 停顿伪影，沿用 R15 限制记录；场景 A 计划为「静置双屏」，当前硬件仅一块屏，按单屏执行。
7. **turbostat/intel_gpu_top**：未安装且与本机硬件不符（Intel 专用）；RAPL 需 root。以 CPU%+k10temp+amdgpu hwmon+nvidia-smi 替代并记录单位。
8. **Dock 波 24fps 余波**：波静止后 shell 仍以 ~24fps 提交（无 capture），成因（shell 侧动画 cadence）未在本任务深挖，列为 T-24/T-25 走查时可复查的现象。
9. 环境发现：niri tracy 客户端监听 fd 未设 CLOEXEC，泄漏进 quickshell→`udevadm monitor` 子进程链，导致后续嵌套会话绑定 8086 失败（本任务在驱动脚本中做了 holder 清理，未改 niri 源码；建议随 T-36 fork 收敛时一并修复）。QML 接管脚本（/tmp 工具，未入库）曾缺 `TAHOE_NESTED_SESSION=1`，已修正并记入执行记录。
