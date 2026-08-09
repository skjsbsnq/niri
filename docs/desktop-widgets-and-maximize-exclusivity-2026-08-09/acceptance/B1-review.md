# B1 审查记录

日期：2026-08-10
子代理数：3（轮1 ×2，轮2/3 复核 ×1）

## 各子代理结论

### 子代理 1（对抗审查 B1 测试基线，第 1 轮）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1：测试2 缺命中测试断言，BI-3 双路径覆盖不完整（套件级已覆盖，按测试粒度缺）
  - P2：测试2 的 `!contains(&1)` 断言要求 `tiles_with_render_positions` 代理过滤 minimized（scrolling.rs:2852-2883 无该过滤，仅 render 循环 :3653 有），任何正确修复下永远红
  - P3：测试3 只钉终态、不钉动画期间（set_complete_instantly 后断言）

### 子代理 2（对抗审查 B1 时序语义，第 1 轮）
- 结论：REJECT
- CONFIRMED：
  - C1：测试1 列构造错误——`ConsumeOrExpelWindowLeft{id:None}` 在「多 tile 列」时是**驱逐**语义（scrolling.rs:2262-2305），导致实际是三单列 `[1],[3],[2]` 而非注释声称的 `[1,2,3]`；命中测试断言 `(10,500)` 基于错误几何，正确修复后永远红
  - C2：测试2 的 `!visible.contains(&1)` 断言要求代理过滤 minimized——代理无该过滤，任何正确修复下永远红
- PLAUSIBLE：
  - P1：测试2 只断言成员资格，无法区分「per-window 释放」与「minimize 时整列齐翻」；且文档不变量与断言自相矛盾

### 子代理 3（修复后复核：列构造 + 动态命中，第 2/3 轮）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1（轮2 遗留）：测试2 无法区分 per-window 与整列齐翻——B1 只要求红基线，不阻塞
  - P2：命中断言绿与否依赖 B2 在 minimize 时结束 maximize transition（`columns_in_display_order` scrolling.rs:2828-2833 / `tiles_in_display_order` :6130-6136 的 take(1) 门在 transition 激活时使 window_under 跳过 window 3）；这与 B-C2 渲染/命中一致性约束一致，属修复形态敏感点而非测试缺陷，B2 阶段须知

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| 测试1 列构造错误（C1，轮2） | CONFIRMED | 已修（第 2 轮）：改用「每次 AddWindow 后立即 consume 单 tile 列」逐步建列（AddWindow(1)→AddWindow(2)→Consume(None)→AddWindow(3)→Consume(None)），最大化时目标被抽成独立 Maximized 列、后方 [2,3] 留邻列（与用户场景一致） | `b1_maximize_exclusivity.rs:44-62`；探针确认 `col0:[2,3] + col1:[1]` |
| 测试2 `!contains(&1)` 永远红（C2，轮2） | CONFIRMED | 已修（第 2 轮）：删除该断言，改为断言 `contains(&3)` 与 `contains(&2)`（非目标窗口在按窗口解除后必然可见），并补动态命中断言 | `b1_maximize_exclusivity.rs:181-191` |
| 硬编码命中坐标在修复后永远红（轮2 C1/C2 后续） | CONFIRMED | 已修（第 2 轮）：命中点改为**动态**——从 `tiles_with_render_positions` 找 window 3 的 tile，取其 pos + tile_size/2 为中心；与 `window_under` 坐标公式逐项一致（scrolling.rs:2875-2878 vs :3733-3736），缺陷下必红、修复下必绿 | `b1_maximize_exclusivity.rs:109-116、201-208`；复核代理逐项验证 None 路径（minimized 跳过/visible 跳过/tab 分支/floating 分支/take(1) 门） |
| 测试2 判别力不足（P1，轮2） | PLAUSIBLE | 不修：B1 只要求红基线（当前树满足），判别修复形态是 B2 验收时的关注点；错误修复（齐翻）在 B2 阶段会被命中测试部分拦截（若同时清理 transition 则骗过绿灯，需 B2 实施时补充判定） | — |
| 测试3 只钉终态（P3，轮1） | PLAUSIBLE | 不修：用户报告与 roadmap B-3 描述的缺陷即终态持久隐藏（workspace.rs:808-810 同步置位），终态断言是正确靶点；动画期间行为是否需钉住取决于 B3 修复形态 | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| 三个测试存在、可运行 | 是 | `cargo test --lib layout::tests::b1_maximize_exclusivity` 三个测试均运行 |
| 三个测试当前全红 | 是 | 0 passed; 3 failed；失败点全部在缺陷断言（:95 `got [1]`、:182 `got [1]`、:279 floating 被隐藏），前置断言全部通过 |
| 红因是真实缺陷而非测试自身 bug | 是 | 三轮审查逐条溯源：测试1 = `.take(1)` 独占持续（scrolling.rs:6126-6137，minimize 不清理 transition，scrolling.rs:1666-1730）；测试2 = 独占未按窗口解除；测试3 = workspace.rs:808-810 无条件清 floating_is_active + active_window_covers_floating（scrolling.rs:3430-3441） |
| 测试须同时覆盖渲染路径与命中测试路径（B-C2） | 是 | 三个测试均含 `tiles_with_render_positions`（渲染）与 `window_under`（命中）断言；动态取点与 window_under 坐标逐项一致 |
| 不得做任何生产代码改动 | 是 | `git diff --stat` 仅 `src/layout/tests.rs` +1 行（mod 声明）+ 新文件 `src/layout/tests/b1_maximize_exclusivity.rs`；无生产文件改动 |
| 全量回归 663 绿 + 3 红 | 是 | `cargo test --lib`：663 passed; 3 failed（仅新增三测试） |
| 无假通过路径 | 是 | 复核代理确认：缺陷下三测试必红（渲染断言在命中断言之前执行）；动态命中在缺陷下必红（visible=false → window_under 跳过 → None） |

## 最终结论

三轮审查：轮1 双代理 APPROVE（P1 已修——补测试2 命中断言）；轮2 REJECT（C1 列构造错误 + C2 代理过滤断言，均已修：逐步建列 + 删 `!contains(&1)` + 动态命中点）；轮3 APPROVE（0 CONFIRMED）。两条 PLAUSIBLE（P1 判别力、P2 修复形态敏感点）记录为 B2 阶段须知，不阻塞 B1。

全部 CONFIRMED 已修、三测试真红、全量回归 663 绿 → 允许 commit。
