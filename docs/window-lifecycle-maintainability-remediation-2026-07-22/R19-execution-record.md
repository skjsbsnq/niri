# 任务：R19 / Tahoe render batching（条件任务 · NO-GO）

待审状态：No-go proposed
开始基线：外层 `b8a5156a`（R18 完成） / niri `3aa34057` / quickshell `8b71640`（未改）

## 范围

### 外层

| 路径 | 作用 |
| --- | --- |
| `docs/.../R19-execution-record.md` | 本记录：对照 R15 锁定门槛 + R18 后复测 → NO-GO |

### niri / quickshell

**未修改。** 不引入 batch owner、不合并 region capture、不改 wire protocol、不保留 batched/legacy 双路径开关。

Owner（本任务决策 owner）：条件实施门槛判定与可复核 no-go 证据；**无** production batch owner。

## Go 条件（路线图 §23 / R15 acceptance §2.4，测量前锁定）

**Go 当且仅当同时满足：**

1. 结构上 N region → N capture（`note_tahoe_region_capture` 每 `render_region` 一次）且 N≥7 时 capture/region ≥ 0.9；
2. **GPU 主瓶颈：** tracy 或等价 GPU 计时证明 capture/blur 占 glass GPU 主成本（非仅 CPU request 计数）；
3. 可安全合并候选：≥2 region 共享 sample plane / kernel / xray / stacking epoch，且 union 面积增长 ≤ 1.2× 各 area 之和。

**No-go：** 无 GPU 计时、或 capture/blur 非主瓶颈、或无可安全合批几何——不引入 batch abstraction。

本任务**不移动**上述门槛；只在 R18 完成后的 HEAD 复测对照。

## 复测命令与原始样本

### 命令（R18 后 HEAD）

```text
(cd niri && cargo test -p niri --lib r15_tahoe -- --nocapture)
→ 1 passed
```

### 原始 `R15_SAMPLE`（与 R15 acceptance §5.4 一致）

| sample | 字段 |
| --- | --- |
| `r19_structural_capture_counters` | request=1, commit=1, capture=**7**（人工 note 验证计数器；capture/region=1.0≥0.9） |
| GPU blur/capture p95 | **未采集**（无 tracy GPU 会话；headless 无 glass 工作负载计时） |
| 安全合批几何证据 | **无**（未采样相邻/重叠 region 的 sample plane / kernel / xray / stacking / union 面积） |

### 静态源码事实（本基线）

```text
# 无 batch 抽象（确认未提前实现）
rg -n 'RenderBatch|beginBatch|endBatch|TahoeBatch|batch_identity|region_batch' niri/src --glob '*.rs'
# 零命中

# 生产路径仍为逐 region 调度：
# niri/src/render_helpers/tahoe_glass.rs
#   render_regions_for_layer:
#     for region in regions.iter() { render_region(...); }
#   render_region:
#     note_tahoe_region_capture();  // 每 region 一次
```

`tracy_client::span!("TahoeGlass::render_region")` 仅为可选 instrumentation hook；本环境未跑 `profile-with-tracy` / GPU 时长采集，**不能**当作 GPU 主瓶颈证据。

## 对照门槛 → 判定

| # | 门槛 | 复测结果 | 满足？ |
| --- | --- | --- | --- |
| 1 | N→N capture 且 N≥7 时 ratio≥0.9 | 源码 `for region → render_region → note_capture`；计数器 capture=7 / region=7 = **1.0** | **是**（结构） |
| 2 | GPU 计时证明 capture/blur 为主瓶颈 | **无** tracy/等价 GPU p95；仅有 CPU 侧 counter | **否** |
| 3 | ≥2 region 可安全合批且 union ≤1.2× | **无** 几何样本 / union 面积数据 | **否** |

**判定：NO-GO。** 三条必须同时满足；仅 #1 结构成立。不引入 Tahoe render batch owner；不改 region 调度；不新增协议接口；不制造 batched/legacy 双路径。

真源交叉引用：

- 锁定门槛：`acceptance/R15-baseline-2026-07-24.md` §2.4
- R15 同结论：同文件 §7 行 R19
- 本任务复测：上表（R18 后外层 `b8a5156a`，niri `3aa34057`）

## 目标设计（若 Go 才会实施；本任务不落地）

路线图 §23 原则（完整 batch identity、sample union 硬门、stacking epoch、独立 clip/shadow/damage、替换逐 region 调度、不改 wire protocol）**全部不实施**。原因：无 GPU 主瓶颈与安全合批证据时增加 batch owner 违反约束 11 与 §28 停止条件。

## 旧路径删除

**不适用（no-go）。** 不替换 production capture 调度，故无“删除 legacy 逐 region 路径”义务。

检索确认未偷偷引入 batch：

```text
rg -n 'RenderBatch|beginBatch|endBatch|TahoeBatch|batch_identity' niri/src --glob '*.rs'
# 零命中
```

## 行为契约

适用 1.4 节全部保持项：本任务零 production diff，glass region/clip/shadow/xray/damage/stacking、协议 available 与 Shell fallback 不变。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo test -p niri --lib r15_tahoe -- --nocapture)` | **1 passed**；样本写入本记录 |
| 静态 `rg`（batch 抽象零命中） | 通过 |
| 源码阅读 `tahoe_glass.rs` `render_regions_for_layer` / `render_region` | 确认 N→N 结构仍在 |

未运行（不得记为通过）：

- tracy GPU spans / blur passes 1/3/10/31 p95（环境与 R15 §9 相同；无 GPU 计时则无法翻过 #2）；
- 真 7/32 region Shell 会话 capture 面积与 union 几何；
- 像素 golden（halo/clip/refract/stacking）——仅 Go 实施后才需要；
- 完整 `cargo test -p niri --lib`：本任务无代码变更；
- quickshell ctest：未改。

### 关键不变量（no-go）

- 门槛在结果前固定（R15 §2.4）；
- 结构证据可复核，且**单独不构成 Go**；
- 工作树无 batch production 抽象；
- 未借 no-go 修改 glass render 路径或协议。

## 性能

| 项 | 值 |
| --- | --- |
| 硬件 | 同 R15：Linux WWT / Ryzen 7 7745HX / Radeon / 14 GiB |
| 场景 | headless 结构计数器 + 源码 N→N；无 glass GPU 负载会话 |
| 前测（R15） | capture=7 结构；无 GPU p95；无合批几何 |
| 后测（本任务复测） | **相同** |
| 阈值 | 结构 ratio≥0.9 **且** GPU 主瓶颈 **且** 安全 union≤1.2× |
| 结论 | 未过门槛 → 不实施 |

若未来 tracy/KMS 会话证明 capture/blur 为主瓶颈且存在可安全合批几何，应**新开测量任务**重锁门槛后评估，不得静默改写 R15 或本记录门槛，也不得为完成路线图强行合批。

## 独立审查专属问题（作者自查）

1. batch identity 是否完整覆盖 renderer/target/namespace/scale/transform/kernel/xray，并将 sample compatibility 与 stacking 约束作为硬门？**N/A（no-go，未建 batch）。**
2. union capture 是否在真实场景减少总成本？**N/A（未实施）；亦无证明应实施的 GPU/几何数据。**
3. shadow、clip、halo 和 damage 是否像素正确？**N/A（未改路径）。**
4. 是否存在长期 legacy fallback 或新协议接口？**否；零 production diff，无双路径、无新 wire。**

补充（对应 no-go 充分性）：仅结构 N→N 不能证明 capture/blur 是主瓶颈，也无 union 收益样本；数据足以证明**此刻不值得**增加 batch abstraction。
