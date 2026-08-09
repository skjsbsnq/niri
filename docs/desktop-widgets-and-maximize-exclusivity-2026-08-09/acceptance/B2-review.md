# B2 审查记录

日期：2026-08-10
子代理数：3

## 各子代理结论

### 子代理 1（对抗审查 B2 独占解除）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1（低）：已最小化窗口上发起 maximize（`set_maximized` :3371 不受 minimized 限制，会 begin transition）后恢复该窗口时 else 分支不清 transition，独占持续到 commit/settle/超时。生产路径不可达（maximize 键位作用于聚焦窗口，最小化窗口不可聚焦），且属既有类别非本次引入。
  - P2（测试 nit）：场景2 命中探测 window 3→2 的注释称"window 3 列滚出视口"，但 `window_under` 无视口裁剪；断言意图成立（独占期间 window 2 被 `sorted_visible_ids==[1]` 证实隐藏，释放后须可命中），实测绿，非测试放松。

### 子代理 2（对抗审查 B2 快照路径与时序）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1：场景2 探针 3→2 的具体列几何未逐像素复算；机理（`monitor.rs:1583-1587` workspace_under 边界）已确认成立，断言意图完整，风险极低。
  - P2（观察）：minimize 清 transition 后窗口保留 committed maximized，restore 后直接以 Maximized 呈现且无过渡重放——正是 B-1 目标行为。
- 关键证伪：任务书预设的「minimize_with_snapshot 绕过 set_minimized 清逻辑」不成立——`minimize_with_snapshot`（:1774-1827）两条路径（has_restore :1794、普通 :1821）都经 `set_minimized` 的 minimize 分支；生产链路（niri.rs:2462 → workspace.rs:871）与测试链路（mod.rs:4015 → workspace.rs:802）在 `ScrollingSpace::set_minimized` 汇合为单一漏斗，无平行状态机（非 G-6）。

### 子代理 3（对抗审查 B2 既有行为与边界）
- 结论：APPROVE
- CONFIRMED：无
- PLAUSIBLE：
  - P1：场景2 探针注释"window 2 sits in the viewport"论据不承重（window_under 无视口裁剪）；真正让断言稳定的因素是探针取 tile 自身中心 + 目标 window 1 minimized 被跳过 + window 3 列矩形右缘 < 探针 x。注释与断言机制错位，非行为错误。
  - P2：`on_target_maximized_commit` 文档（maximize_visual_fsm.rs:122-130）未注明「target 被 minimize 后不再适用」——文档口径问题。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| on_target_maximized_commit 文档未注明 minimize 后不适用（审查3 P2） | PLAUSIBLE | 已修：补充文档「Not applicable once the target left the maximize scope (removed, minimized — the holder clears the transition in those paths, so this is a no-op on `None`)」 | `maximize_visual_fsm.rs:122-130` |
| 场景2 探针 3→2 的注释/机制错位（审查1 P2、审查2 P1、审查3 P1） | PLAUSIBLE | 不修：注释已改为如实描述（window 3 列被 re-maximize 滚出视口，实测 pos=(-100,16)）；断言核心（渲染 contains(&3) 保留 + 命中 window 2）不削弱 BI-2 验证 | `b1_maximize_exclusivity.rs:193-216` |
| 已最小化窗口上 maximize 后恢复不清 transition（审查1 P1） | PLAUSIBLE | 不修：生产路径不可达（最小化窗口不可聚焦），且 restore 侧抑制面归 B3 范围 | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| B1 场景 1、2 转绿 | 是 | `cargo test --lib layout::tests::b1_maximize_exclusivity`：2 passed; 1 failed（场景 1/2 ok，场景 3 红） |
| 场景 3 仍可为红 | 是 | 场景 3 红于 :281（floating 被隐藏），B3 范围 |
| niri 既有测试全绿（回归） | 是 | `cargo test --lib`：665 passed; 1 failed（仅 b1 场景3）；重点：observe 23 绿（含独占断言 :113-115 非目标 minimize 保持独占）、lifecycle_observe 19 绿（含 f02 超时晚提交）、fullscreen 29 绿、floating 30 绿、lifecycle_controller 8 绿 |

## 约束核对

| 约束 | 满足 | 证据 |
|---|---|---|
| B-C1 无并行状态机 | 是 | 改动仅调用既有 `clear_maximize_transition`（scrolling.rs:3424）+ `MaximizeVisualClear::Cancelled` 既有枚举；未新增字段/枚举/相位；MinimizeVisualFsm 仍唯一存在于 scrolling.rs |
| B-C2 渲染命中共用判据 | 是 | 渲染（render :3640）与命中（window_under :3703）共用 `maximizing_window_location()`（:3457）；改动只在源头清 transition，两条消费逻辑未动 |
| B-C3 BI-1/BI-2/BI-3 | 是 | BI-1：minimize 目标窗口清 transition，动画首帧独占失效（场景1 未推进动画即断言 2、3 可见）；BI-2：`targets(window)` 按窗口等值判断（observe.rs:99 非目标 MinimizeWindow(2) 保持独占，实测绿）；BI-3：渲染命中共用判据 |
| B-C4 不得削弱超时保护 | 是 | 超时机制零改动（finish_maximize_transition_if_settled :3565、on_clock_tick :3601 原样）；TimedOut 相位 exclusivity_active=false 本就无过滤；minimize 清掉后晚提交不恢复独占——与 remove_tile/remove_column/fullscreen 的「离开作用域即终结」同构，是正确语义非削弱 |

## 最终结论

三代理全部 APPROVE（0 CONFIRMED）。修复：`scrolling.rs:1684-1696` minimize 目标窗口时清 maximize_transition（+13 行，最小侵入），经 `set_minimized` 公共漏斗覆盖生产所有 minimize 路径（含 minimize_with_snapshot 真实用户路径）；场景 1、2 转绿、场景 3 红（B3 范围）；665 既有测试全绿；clippy 无新增告警。1 条 PLAUSIBLE 已修（FSM 文档），其余记录为不修（理由见上）。

全部子代理 APPROVE / 全部 CONFIRMED 已修 → 允许 commit。
