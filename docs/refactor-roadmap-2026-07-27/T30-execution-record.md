# 任务：T-30 / Profiling 基线采集

待审状态：Author verification complete → 待对抗性审查
基线：外层 `089e7bc` / niri `866d73ea` / quickshell 部署二进制（未改子模块源码）

## 范围

### 外层新增

| 路径 | 作用 |
| --- | --- |
| `tools/t30-profiling/vpointer.c` + Makefile + `wlr-virtual-pointer-unstable-v1.xml` | zwlr_virtual_pointer_v1 驱动（niri fork 已实现该协议），场景 B/A 的指针输入；wayland-scanner 生成，源码+协议 XML 入库，产物不入库 |
| `tools/t30-profiling/power-sample.sh` | 功耗/负载采样（turbostat/intel_gpu_top 替代：CPU%、k10temp、amdgpu hwmon、nvidia-smi） |
| `tools/t30-profiling/scenario-driver.sh` | 单场景驱动（idle/cursor/dock/island/overview） |
| `tools/t30-profiling/run-compositor-baseline.sh` | 嵌套会话编排：每场景重启嵌套 niri（tracy 构建 + 遥测 env）、处理 tracy 监听 fd 泄漏、capture+功耗并行、失败重试 |
| `tools/t30-profiling/analyze-baseline.py` | tracy csvexport + 遥测日志汇总 |
| `docs/refactor-roadmap-2026-07-27/acceptance/T30-profiling-baseline-2026-07-31.md` | 门槛锁定、原始样本、go/no-go 判定（验收真源） |
| 本执行记录 | |

未改 niri/quickshell 源码（构建时临时启用 `profile-with-tracy` feature，任务后已恢复无 feature 的 release 构建并校验二进制体积一致）；未改线上会话（线上 niri/quickshell 全程未重启；线上 quickshell 曾误杀后按原配置恢复，见 §意外与恢复）。

## 目标设计落地

```text
研究报告第三部分 Profiling 计划（research-report.md:175-177）
        │
        ▼ 锁定门槛（acceptance §2）——先于结果
嵌套 winit 会话 × 7 场景（tracy + 帧遥测 + lifecycle 计数 + 功耗）
        + QML 侧（qmlprofiler + QSG renderloop 计时）重放 B/C
        │
        ▼ 原始样本
对照门槛 → T-32 GO / T-33 NO-GO / T-34 NO-GO / T-35 NO-GO
```

## 旧路径删除

不适用（测量任务，无生产代码改动；未引入平行接口）。

## 行为契约

线上会话零改动：niri（1295）/quickshell（1392→恢复实例）保持原二进制与配置运行；
未触碰 `~/.local/bin/niri`、`~/.local/bin/quickshell` 部署文件。
嵌套会话仅用于测量，退出后清理（端口 8086 释放、泄漏 holder 终止、嵌套进程退出）。

## 工具链与环境事实（记录）

- tracy-client 0.13.1（crate 内嵌）与 tracy-capture/csvexport 0.13.1（v0.13.1 tag 构建）协议匹配；master(0.13.6) 不兼容。
- Qt6 无 `QSG_RENDER_TIMER`；等效 `QT_LOGGING_RULES='qt.scenegraph.time.renderloop=true'`。
- 嵌套 quickshell GL 上下文落在 NVIDIA dGPU（QSG_INFO）；线上为 AMD iGPU DRM。
- GPU span（smithay GpuProfiler）在嵌套 NVIDIA 上下文因缺 `GL_EXT_disjoint_timer_query` 为空。
- 发现：niri tracy 监听 fd 未 CLOEXEC，泄漏至 quickshell→`udevadm monitor` 子进程；旧会话死后该 fd 占住 8086 导致后续会话 tracy 绑定失败（驱动脚本已清理；修复建议随 T-36）。

## 测试 / 验证

| 命令 | 结果 |
| --- | --- |
| `make -C tools/t30-profiling`（vpointer 构建） | 通过 |
| `power-sample.sh 5 1000` 冒烟 | 输出 5 行 CSV |
| 7 场景采集（run-compositor-baseline.sh） | 7/7 `.tracy` 保存成功（含 1 次 B-dock 失败重试，重试逻辑 3 次内成功） |
| tracy 链路 5s 短测试 | 握手/保存通过（22.6 MB，34k zones） |
| qmlprofiler 两遍（binding/creating/js/compiling；scenegraph/animations/painting） | 165 MB / 296 MB 归档 |
| `analyze-baseline.py` 全量汇总 | analysis.json 生成（含全部遥测/计数器/tracy zone 统计） |
| 恢复验证 | `cargo build --release --locked` 后 target/release/niri 与基线字节数一致（138,566,984）；线上 niri/quickshell 运行、IPC 可调 |

未运行：真实 AMD DRM 路径的 GPU 帧时间（需重启线上会话）；qmlprofiler 定量解析（需 Qt Creator）。

## 意外与恢复

1. tracy 客户端「另一个 server 已连接」→ 定位为监听 fd 泄漏（tracy 监听 fd 未 CLOEXEC，经 quickshell 泄漏到 `udevadm monitor` 子进程，旧会话死后仍占 8086）+ 每进程单服务端语义，改为每场景重启嵌套会话，驱动脚本清理全部泄漏 holder 并校验新会话拥有 8086 监听。
2. 误杀线上 quickshell（ps 匹配过宽）→ 立即按原配置恢复（start-quickshell.sh），确认 IPC 正常后继续（执行记录如实披露）。
3. csvexport 对含逗号的 Rust 泛型 zone 名不转义 → 分析脚本跳过错位行（关键 zone 均为干净名字）。
4. **B-dock 波数据归属修正（对抗性审查发现）**：波输入（t≈6–16s）落入 ~60s winit swap 停顿期（~1fps），compositor 侧波成本未测得；文档原「tracy 丢 zone」解释错误（205 vs 3525 由 capture 窗口早于活动期结束解释）。36/s 与 queue_redraw_all 503/5s 为 QML 接管会话（shell 重启 + 指针停 dock 行）的真实计数器读数，已在验收文档 §5 修正归属。
5. **A-idle-1/2 tracy 提前断连**（33.6s/29.4s vs 68s，原因未确认）：会话存活（trace 时间跨度证明），日志止于最后一条 redraw 行（无 redraw 则无日志输出，非会话死亡）；对应功耗样本可能含少量会话结束后时段，已在验收文档 §7 披露。
6. **QML 接管脚本曾缺 `TAHOE_NESTED_SESSION=1`**：/tmp 工具（未入库）启动被剖 quickshell 时未设置嵌套隔离 env，已修正；验收文档 §7 披露。

## 性能摘要（判定真源：acceptance 文档）

| 后续任务 | 判定 |
| --- | --- |
| T-32 glass capture 量化 | **GO**（0.4–0.9 ms/事件；动画期每帧：C-island 峰值窗口 0.42 ms、D-overview 峰值窗口 0.61–0.75 ms、B-dock 波/hover 计数器折算 0.38 ms） |
| T-33 glass shader LUT | **NO-GO**（GPU span 不可测；CPU 侧 ~10–60 µs/帧） |
| T-34 xray/region 短路 | **NO-GO**（xray ~10 µs/帧；polish ≤1 ms） |
| T-35 Island 预热 / 波节流 | **NO-GO**（QSG 全帧 <17 ms；JS 分布未解析） |
| 佐证 | B-dock 波期 queue_redraw_all 503/5s、A-cursor 58/5s → T-31 定向 redraw 数据依据 |

## 独立审查专属问题（作者自查）

1. 门槛是否在结果前固定、判定只对照门槛？**是（acceptance §0/§2/§6）。**
2. 前后环境/采样是否一致？**嵌套会话同二进制同配置逐场景重启；线上空闲对照单独标注。**
3. 是否混成单一「流畅度」？**否：CPU 帧时间（遥测/tracy）、功耗、流量（region 计数）分列。**
4. 速率类结论是否有可复核原始数据？**是：进程内遥测/计数器为权威源，tracy 计数下界已标注（B-dock 205 vs 3525）。**
5. tracy 客户端丢 zone 是否影响判定？**不适用：经审查，B-dock 的 tracy 计数差由 capture 窗口覆盖差异解释，无丢 zone 证据；判定基于进程内计数器与 telemetry，tracy 提供单次成本结构。**
