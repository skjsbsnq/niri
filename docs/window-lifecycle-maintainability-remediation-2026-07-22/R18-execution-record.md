# 任务：R18 / snapshot variant cache 与显存预算（条件任务 · NO-GO）

待审状态：No-go proposed
开始基线：外层 `4c2ae827` / niri `3aa34057` / quickshell `8b71640`（未改）

## 范围

### 外层

| 路径 | 作用 |
| --- | --- |
| `docs/.../R18-execution-record.md` | 本记录：对照 R15 锁定门槛 + R17 后复测 → NO-GO |

### niri / quickshell

**未修改。** 不引入 `SnapshotVariantCache`、不迁移 `render_to_texture` closure、不改 minimize/closing/closing-layer 纹理所有权。

Owner（本任务决策 owner）：条件实施门槛判定与可复核 no-go 证据；**无** production cache owner。

## Go 条件（路线图 §22 / R15 acceptance §2.3，测量前锁定）

**Go 当且仅当同时满足：**

1. block-out 路径 `multi_peak / single_peak ≥ 1.5`；
2. 实测 multi-variant peak ≥ **8 MiB**（1080p-class）**或** 观测到 allocation stall / OOM fallback；
3. 默认生产 minimize 路径（无特设 window-rule）也出现多 variant，**或** 证明 Shell/screencast 常态走 multi-variant。

**No-go：** 仅理论表很大但默认单 variant、绝对值小、无 stall/OOM——不引入 cache 抽象。

本任务**不移动**上述门槛；只在 R17 完成后的 HEAD 复测对照。

## 复测命令与原始样本

### 命令（R17 后 HEAD）

```text
(cd niri && cargo test -p niri --lib r15_snapshot -- --nocapture)
→ 1 passed
```

### 原始 `R15_SAMPLE`（与 R15 acceptance §5.3 一致）

| sample | 字段 |
| --- | --- |
| `r18_snapshot_single_variant` | peak_bytes=**231120**；默认 640×360 窗口，无 block-out rule |
| `r18_snapshot_block_out_variant` | peak_bytes=**462240**；同几何 + `block-out-from "screencast"` |
| `r18_snapshot_multiplier` | multiplier=**2.000**；理论 1080p=8_294_400 / 1440p=14_745_600 / 4K=33_177_600 / 4K@2=132_710_400 |
| stall / OOM | **未观测**（headless 路径完成 create，无 fallback 日志/失败） |

### 静态源码事实（本基线）

```text
# 无 cache 抽象（确认未提前实现）
rg -n 'SnapshotVariantCache|VariantCache|snapshot_variant_cache' niri/src --glob '*.rs'
# 零命中

# 各动画类仍自持 render_to_texture（创建时一次性转纹理，非每帧）
rg -n 'render_to_texture' niri/src/layout/minimize_window_animation.rs \
                         niri/src/layout/closing_window.rs \
                         niri/src/layer/closing_layer.rs
# 各文件内本地 closure；仅在 new/create 路径调用

# 默认仅在 block_out_from.is_some() 时初始化 blocked_out 纹理
# minimize_window_animation.rs:
#   let blocked_out = if snapshot.block_out_from.is_some() { Some(...) } else { None };
```

`RenderSnapshot` 上的 `OnceCell` 槽位（`texture` / `texture_with_blocked_out_bg` / `blocked_out_texture`）是**按需懒求值字段**，不是跨动画共享的 variant cache owner；本任务不将其重命名为 cache 以规避 no-go。

## 对照门槛 → 判定

| # | 门槛 | 复测结果 | 满足？ |
| --- | --- | --- | --- |
| 1 | multi/single ≥ 1.5 | 462240/231120 = **2.000** | **是** |
| 2 | multi peak ≥ 8 MiB 或 stall/OOM | multi=**462240 B ≈ 451 KiB** ≪ 8 MiB；无 stall/OOM | **否** |
| 3 | 默认生产路径多 variant 或常态 multi | 默认无 block-out rule → **单 variant**；未证 Shell 常态 multi | **否** |

**判定：NO-GO。** 三条必须同时满足；仅 #1 成立。不引入 snapshot variant cache 抽象；不迁移 closure；不改资源释放策略。

真源交叉引用：

- 锁定门槛：`acceptance/R15-baseline-2026-07-24.md` §2.3
- R15 同结论：同文件 §7 行 R18
- 本任务复测：上表（R17 后 niri `3aa34057`，样本数值与 R15 完全一致）

## 目标设计（若 Go 才会实施；本任务不落地）

路线图 §22 目标（cache key / 字节预算 / LRU / 动画 lifetime / 统一降级）**全部不实施**。原因：门槛未满足时增加 owner 只会制造无收益抽象，违反约束 11 与 §28 停止条件。

## 旧路径删除

**不适用（no-go）。** 不替换 production owner，故无“删除旧平行 cache/closure”义务。

检索确认未偷偷引入 cache：

```text
rg -n 'SnapshotVariantCache|beginBatch|VariantCache' niri/src --glob '*.rs'
# 零命中
```

## 行为契约

适用 1.4 节全部保持项：本任务零 production diff，scrolling/floating/lifecycle/xray/blocked-out/screencast/动画路径不变。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo test -p niri --lib r15_snapshot -- --nocapture)` | **1 passed**；样本写入本记录 |
| 静态 `rg`（cache 抽象零命中） | 通过 |

未运行（不得记为通过）：

- 完整 `cargo test -p niri --lib`：本任务无代码变更，不重复整表；
- tracy allocation / 4K@2 真实纹理峰值：环境与 R15 §9 相同限制；理论表已足够否定“绝对值显著”门槛；
- 真机 screencast + Shell 常态 multi-variant 会话：R15 已记未运行；即使未来证明常态 multi，仍需 #2 绝对峰值或 stall 才可翻案；
- quickshell ctest：未改。

### 关键不变量（no-go）

- 门槛在结果前固定（R15 §2.3）；
- 复测样本可复核且与 R15 一致；
- 工作树无 production 抽象提前实现；
- 未借 no-go 修改 minimize/closing 纹理布局。

## 性能

| 项 | 值 |
| --- | --- |
| 硬件 | 同 R15：Linux WWT / Ryzen 7 7745HX / Radeon / 14 GiB |
| 场景 | headless debug；640×360 客户端；foreign minimize；single vs block-out rule |
| 前测（R15） | single 231120 / multi 462240 / mult 2.0 |
| 后测（本任务复测） | **相同** |
| 阈值 | multi ≥ 8 MiB 或 stall；默认 multi-variant；mult ≥ 1.5（三者 AND） |
| 结论 | 未过门槛 → 不实施 |

若未来产品在 4K@2 / 三 variant 并发 / OOM 路径上出现新证据，应**新开测量任务**重锁门槛后评估，不得静默改写 R15 或本记录门槛。

## 独立审查专属问题（作者自查）

1. cache key 是否包含所有 renderer/scale/transform/variant 语义？**N/A（no-go，未建 cache）。**
2. 预算和释放是否真实减少强引用，而非只多一层 map？**N/A（未实施）。**
3. fallback 是否仍保持动画可见和资源一致？**N/A（未改路径）。**
4. 若 no-go，数据是否足以证明不值得增加抽象？**是。#2 实测 multi peak 451 KiB ≪ 8 MiB 且无 stall/OOM；#3 默认单 variant。仅 #1 multiplier=2.0 不足以证明 cache owner 收益。可复核命令与样本已写入本记录与 R15 acceptance。**
