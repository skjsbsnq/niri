# 任务：R15 / 性能基线复测与实施门槛

待审状态：Author verification complete
开始基线：外层 `cc39eb1e` / niri `3cb73217` / quickshell `8b71640`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/tests/r15_perf_baseline.rs` | 可复核 headless 测量 harness（`R15_SAMPLE` 输出 + 门槛相关断言） |
| `src/tests/mod.rs` | 注册 `r15_perf_baseline` 模块 |

### 外层

| 路径 | 作用 |
| --- | --- |
| `docs/.../acceptance/R15-baseline-2026-07-24.md` | 门槛锁定、原始样本、go/no-go |
| `docs/.../R15-execution-record.md` | 本记录 |

未改 quickshell；未改 production lifecycle/render ownership（观测门，非产品行为变更）。

Owner：性能门槛决策与可复测仪器样本；R16–R19 实施本身不在本任务。

## 目标设计落地

```text
R14 complete (ownership 收敛)
        │
        ▼  锁定门槛（acceptance §2）——先于结果
Headless r15_perf_baseline + 静态 rg + 嵌套 frame telemetry
        │
        ▼  原始 R15_SAMPLE / telemetry
对照门槛 → R16 GO / R17 GO / R18 NO-GO / R19 NO-GO
```

## 旧路径删除

不适用（R15 不替换 production owner，不删除 redraw/genie/snapshot 路径）。

检索确认无平行“假优化”API：

```text
rg -n 'beginBatch|endBatch|RedrawAttribution' niri/src
# 零命中（未提前实现 R17–R19 抽象）

rg -n 'r15_perf_baseline' niri/src/tests
# 仅 tests 模块注册与本 harness
```

## 行为契约

适用 1.4 节全部保持项：R15 不改变 scrolling/floating/lifecycle/glass/协议行为。
仅增加 test harness 与版本化测量记录。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all -- --check)` | 通过 |
| `(cd niri && cargo test -p niri --lib r15_perf_baseline -- --nocapture)` | **11 passed**；`R15_SAMPLE` 写入 acceptance |
| `(cd niri && cargo test -p niri --lib)` | **435 passed**（R15 要求整表自动化可覆盖部分；R14 为 424 + 本任务 11） |

未运行：

- 完整 `cargo test -p niri`（含 bin/doctest）：lib 为矩阵自动化主体；
- tracy GPU / allocation 会话：环境未配置 `profile-with-tracy-allocations`；
- 真双物理输出 + Tahoe Shell 工作负载；
- quickshell ctest：未改 C++/QML。

### 关键不变量（测量）

- foreign minimize/restore/maximize → `queue_redraw_all ≥ 1`；
- `queue_redraw_all` 双输出 Queued=2 → waste_ratio=0.5；
- glass mapped commit → targeted≥1、fallback=0；
- block-out vs single snapshot multiplier 可复现；
- 未引入 R17–R19 production 抽象。

## 性能

硬件/门槛/样本/判定真源：

`docs/.../acceptance/R15-baseline-2026-07-24.md`

摘要：

| 后续任务 | 判定 |
| --- | --- |
| R16 Genie 每帧分配 | **GO**（源码确定 + 前测对照） |
| R17 定向 redraw | **GO**（foreign/lifecycle；glass 已 R14 targeted） |
| R18 snapshot cache | **NO-GO**（默认单 variant；无 stall；绝对值不足） |
| R19 Tahoe batching | **NO-GO**（无 GPU 主瓶颈证据） |

## 独立审查专属问题（作者自查）

1. 前后场景、profile、硬件、采样长度是否一致？**Headless debug 一致；嵌套 release winit 单独标注限制，不与 headless 混结论。**
2. 门槛是否在结果之前固定？**是；acceptance §2 先锁定，§7 只对照。**
3. 是否混成单一“流畅度”？**否；R16–R19 分指标。**
4. R17–R19 go/no-go 是否有可复核原始数据？**是；`R15_SAMPLE` + 源码位点 + 嵌套 telemetry 限制表。**
