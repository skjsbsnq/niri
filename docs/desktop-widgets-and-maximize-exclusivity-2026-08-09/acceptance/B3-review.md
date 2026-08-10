# B3 审查记录

日期：2026-08-10
子代理数：4（轮1 ×2、轮2 ×1、复核 ×1）

## 各子代理结论

### 子代理 1（对抗审查 B3 生产零改动结论）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1（测试强度）：恢复动画期间无断言（B1 审查 P3 遗留项，roadmap 定义终态缺陷故不阻塞）
  - P2（快照路径覆盖）：测试只走 model-only 路径，未覆盖带 Genie 的 `restore_with_snapshot` + `start_restore` Suppress lease 路径（lease 仅 Suppress 目标，已代码确认）
- 关键结论：「生产零改动」成立——B2 已消除 B3 缺陷实质；恢复路径三处状态变更（lease 只抑制目标自身、activate_workspace 同 workspace no-op、floating_is_active=No 被 `!covers` 兜底）在普通平铺窗口下均不隐藏其它窗口。

### 子代理 2（对抗审查 B3 真实因果链）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1：场景3 不再验证历史缺陷本身（普通版 B2 前就绿）
  - P2：交叉窗口残留路径（最大化 A 动画中恢复 B）无覆盖——窄窗口瞬态
  - P3：场景3 可空过（restore 返回值未断言）
- 关键确认：用户现象 3 真实因果链 = B2 前 minimize 不清独占 → restore 时 `suppress_floating_live_tiles=true` 抑制浮窗 + `maximize_exclusive` 过滤其它 tile = 「两个应用同时隐藏」，B2 已根治。

### 子代理 3（对抗审查 B3 测试改动质量，第 2 轮）
- 结论：REJECT
- CONFIRMED：
  - C-1：普通平铺版场景3 在 B2 前就绿（/tmp/b2pre 实测）——作为 B3 守护空洞化，B3 完成判据被恒绿测试空洞满足
  - C-2：B2 后 Maximized 版仍红（合理语义），但「restore 普通窗口 + Maximized 列并存」的浮层行为失去覆盖
- PLAUSIBLE：P-1 lease 传输悬挂（restore 动画中传输 tile，`remove_tile_by_idx:1237` 丢弃 Reveal 不重置 lease 位 → 隐形窗口直到下次 minimize）——作用于目标自身，独立于 B3 范围

### 子代理 4（场景3 重构复核，第 3 轮）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1（范围收窄）：新场景3 用 policy 标志断言（!maximize_exclusive / !suppress_floating_live_tiles）替代浮窗可见性断言——B2 后 Maximized restore 盖浮窗是既有设计语义（`active_maximized_window_covers_floating_layer` 测试背书）；P1 留待人工验证对照
  - P2（文档过时）：模块头「expected to FAIL」与现状矛盾
- 关键实证：B2 前（be621b18 生产）新场景3 红于 :304（obs=CommittedSettling + suppress=true）；B2 后（f61ebda6）绿。判别力成立。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| 场景3 空洞化（审查3 C-1） | CONFIRMED | 已修（第 3 轮）：重构为「Maximized setup + 不推进动画」版——setup 无 CompleteAnimations（保持 transition CommittedSettling），minimize 后无动画推进（防 settle 清除），restore 后无动画推进（看 restore 瞬间）；断言改为「restore 后 !maximize_exclusive && !suppress_floating_live_tiles + 无 transition + 窗口 1 可见 + 命中窗口 2」 | `b1_maximize_exclusivity.rs` 场景3；B2 前红 :304、B2 后绿（复核代理实证） |
| Maximized restore 浮层行为失覆盖（审查3 C-2） | CONFIRMED | 已修：新场景3 保留 Maximized setup（窗口 2 Maximized 列在视口），命中断言验证窗口 2 可命中；浮窗被 Maximized 列覆盖是既有设计语义（不断言），已在注释与审查记录说明 | 同上；`active_maximized_window_covers_floating_layer`（tests.rs:3887）背书 |
| 模块头注释过时（审查4 P2） | PLAUSIBLE | 已修：改为「regression tests」描述，注明 B2/B3 修复后转绿 | `b1_maximize_exclusivity.rs:1-19` |
| lease 传输悬挂（审查3 P-1） | PLAUSIBLE | 不修：作用于目标自身（非「其它窗口被隐藏」），独立于 B3 范围；记录为已知遗留（后续任务处理：remove 时若 Reveal 被丢弃应将 lease 位一并清除） | scrolling.rs:1237 |
| 恢复动画期间无断言（审查1 P1、审查2 P3） | PLAUSIBLE | 不修：roadmap 定义 B3 为终态缺陷；restore 返回值已断言（:292）防空过 | — |
| 快照路径无测试覆盖（审查1 P2） | PLAUSIBLE | 不修：属既有测试架构局限（headless 无 GPU）；lease 仅 Suppress 目标已代码确认 | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| B1 全部三个场景转绿 | 是 | `cargo test --lib layout::tests::b1_maximize_exclusivity`：3 passed; 0 failed |
| niri 既有测试全绿 | 是 | `cargo test --lib`：666 passed; 0 failed |
| 人工验证三个原始现象均消失（部署后） | 否（待部署） | 需部署后人工验证；P1（浮窗可见性）留作人工对照项 |

## 约束核对

| 约束 | 满足 | 证据 |
|---|---|---|
| B-C1 无并行状态机 | 是 | 生产零改动；无新状态机（git diff 仅测试文件） |
| B-C3 BI-1 | 是 | 场景3 断言 restore 后独占残留已消除（suppress=false）；场景 1/2 断言 minimize 后其它 tile 可见 |

## 最终结论

四轮审查：轮1/2 APPROVE（生产零改动成立，B2 已消除 B3 缺陷实质）；轮3 REJECT（场景3 空洞化——已重构为有效判别测试）；轮4 APPROVE（判别力实证：B2 前红 :304、B2 后绿）。全部 CONFIRMED 已修；P1（浮窗可见性范围收窄）留作部署后人工验证对照项，其余 PLAUSIBLE 记录为不修（理由见上）。

全部 CONFIRMED 已修 → 允许 commit。
