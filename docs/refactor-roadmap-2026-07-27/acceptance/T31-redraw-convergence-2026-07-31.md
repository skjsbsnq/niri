# T-31 · queue_redraw_all 收敛 + Wallpaper /proc 异步化（2026-07-31）

任务定义：`docs/refactor-roadmap-2026-07-27/roadmap.md` T-31（R-1 + R-5，免门槛结构正确性）。
配套：研究报告 `research-report.md` R-1/R-5；T-30 基线给出直接数据依据（B-dock 波期
queue_redraw_all 503/5s、A-cursor 58/5s）。

## 0. 判定声明

- R-1 与 R-5 为结构正确性任务，免 profiling 门槛（T-30 acceptance §0 已锁定）。
- 行为契约：per-output 定向 redraw 必须是被替换的 `queue_redraw_all` 的**超集等价**——
  任何布局变更至少重绘其影响到的输出；真全局保留 `All{reason}` 审计计数。

## 1. 实现摘要

### niri 子模块（commit 见文末）

1. **归因类型扩展**：`RedrawReason::Action`（do_action 尾统一 attribution）、
   `RedrawFallbackReason::GlobalUi`（overview/debug/截图/热键/锁屏等全局 UI 兜底）；
   `lifecycle_diag` 新增 `redraw_targeted_action` / `redraw_fallback_global_ui` 计数器。
2. **Layout dirty 跟踪**：`Layout::dirty_outputs` + `mark_output_dirty` /
   `mark_all_outputs_dirty` / `take_dirty_outputs`。打脏注入点：
   - `active_workspace_mut` / `active_monitor` → 活动输出（覆盖 move/focus/center/swap/
     consume/expel/display/宽度等全部活动工作区方法）；
   - `workspaces_mut` → 全部输出（覆盖 by-id 窗口方法：set_*/toggle_*/urgent 等，保守超集）；
   - `activate_window` / `activate_window_without_raising` → 窗口所在 monitor + 旧活动输出；
   - `focus_output` → 新 + 旧活动输出；
   - `move_to_output` / `move_column_to_output` / `move_workspace_to_output_by_id` /
     `move_workspace_to_idx` → 源 + 目标输出；
   - 新增 `interactive_move_render_rect()` 供拖拽路径做 bbox 重叠定向。
3. **do_action 尾统一 attribution**：入口丢弃陈旧 marks（action 作用域），尾段
   `take_dirty_outputs()` → `apply_redraw_attribution(Outputs{.., Action})`；删除约 90 处
   逐点 `queue_redraw_all`（input/mod.rs 生产代码 0 处 `queue_redraw_all`）。
4. **指针/光标/DnD/grab 定向**：
   - `queue_redraw_output_under(pos)` / `queue_redraw_overlapping(rect)` 两个 Niri helper；
   - 指针 motion/axis/tablet/proximity/隐藏（hide_when_typing、inactivity timer）→ 指针下输出；
   - cursor image / cursor position hint / DnD icon commit（handlers/compositor.rs、
     handlers/mod.rs、ipc pick、pick grabs）→ 指针下输出；
   - move_grab / touch_overview_grab：motion 期间按被拖窗口 bbox 重叠输出定向，ungrab 用
     move 结束前 bbox + 手势输出。
5. **真全局 → All{reason} 可审计**：config reload / recompute rules → `All{GlobalConfig}`；
   overview / 调试叠加 / 截图 UI / 热键 / 锁屏 / 会话恢复 → `All{GlobalUi}`；
   `apply_redraw_attribution` 的 All 分支仍是唯一 `queue_redraw_all` 生产调用点。

### 主仓库（tahoe-shell）

6. **Wallpaper.qml /proc 轮询异步状态机（R-5）**：`prestartedWallpaperFile` 与
   `prestartedWallpaperProcessFile` 去 `blockLoading`、去 `waitForJob`；解析全部移入
   `onLoaded`/`onLoadFailed`；`requestPrestartedProcessCheck` / `requestPrestartedStopCheck`
   带代际 token（`prestartProcessGeneration`/`prestartStopCheckGeneration`/
   `prestartRecordGeneration`），迟到的过期读回调为 no-op；`stopPrestartedWallpaper`
   改「先读后杀」回调链；S3 两次连续 miss 保护与瞬时 IO 错误不算死亡语义保留
   （loadFailed → callback(true)）。

## 2. 验收

| 项 | 结果 |
|---|---|
| niri `cargo test --lib` | 536/536（r17 扩展 5 项新测试全过；连续 6 轮全绿） |
| shell pytest（Wallpaper 相关） | 15/15 通过（含新增 `prestartedProcStatMatches` node-vm 解析器测试） |
| shell 全量 pytest | 992/993 通过；唯一失败 `test_r17_dock_layout_motion.py::test_dock_replays_compositor_slide_for_each_surface_mapping` 为**既有失败**（quickshell 无 `mappingGeneration` 属性，主分支已红，与 T-31 无关） |
| qmllint Wallpaper.qml | 通过 |
| R17 归因测试扩展 | +5：do_action 仅活动输出、跨 monitor 源+目标、定向 helper 只命中重叠输出、dirty dedup/drain、do_action 源码零 `queue_redraw_all` 断言 |
| per-output NoDamage A/B | 见 §3（`tools/t31-redraw-ab/run-redraw-ab.sh`） |
| qmlprofiler 5s 尖峰 | 结构性消除：Wallpaper.qml 已无 `waitForJob`/`blockLoading`（测试断言 `assertNotIn("waitForJob")`）；5s 健康轮询不再同步阻塞 UI 线程 |

## 3. 运行时 A/B（queue_redraw_all 计数器）

方法：嵌套会话（`NIRI_MODE=nested`，`NIRI_LIFECYCLE_DIAG=1`），T-30 vpointer 驱动
cursor 画圈 / dock 行横扫，解析 5s 周期 `lifecycle-diag` 增量。
Before = 部署二进制 866d73ea（与基线字节一致）；After = 本任务 release 构建。
数据见 `t31-ab-*/summary-*.txt`。

| 场景 | before redraw_all/5s | after redraw_all/5s | after redraw/5s |
|---|---|---|---|
| cursor（稳态画圈） | +48 | +0（仅会话启动 +1） | +120 ~ +167（定向，帧数不减） |
| dock（波横扫） | +80 ~ +132 | +0（仅会话启动 +1） | +90 ~ +264（定向，帧数不减） |

说明：before 与 after 的 per-output redraw 帧数一致（光标/波每帧照常重绘），但
after 中这些帧全部走定向 `queue_redraw`；`redraw_all` 稳态为 0，唯一 +1 在会话
启动窗口（输出挂载/首帧全局事件）。单屏嵌套会话下 per-output NoDamage 结构性证明
由 R17 扩展测试承担（`r17_directed_helpers_queue_only_overlapping_outputs`：
未命中输出保持 Idle，即不产生 NoDamage 帧）。原始数据：`t31-ab-before` /
`t31-ab-after-final`（`tools/t31-redraw-ab/run-redraw-ab.sh`，复用 T-30 vpointer 与
嵌套会话编排）。

## 5. 对抗性审查发现与修复（独立子代理）

| # | 严重度 | 发现 | 修复 |
|---|---|---|---|
| 1 | BLOCKER | `remove_output` + 打开 MRU → `queue_redraw_mru_output` 对已删除 output unwrap panic | `queue_redraw_mru_output` 改走新增 `queue_redraw_if_exists`（hot-unplug 防护）；新增测试 `r17_remove_output_with_open_mru_does_not_panic` |
| 2 | MAJOR | 非 do_action 激活路径（DnD dropped/指针/平板/触摸点击/MoveGrab ungrab）的 layout 脏标记被下次 do_action 丢弃 → 旧 active output 焦点环残留 | 新增 `Niri::apply_layout_dirty_redraw(reason)`；dropped、pointer/tablet/touch 点击分支、MoveGrab::on_ungrab 全部显式 drain；新增测试 `r17_apply_layout_dirty_redraw_after_cross_output_activation` |
| 3 | MAJOR | MoveGrab::on_ungrab 在 overview 打开时缺 `All{GlobalUi}`（多显示器残留变暗） | 与 touch 版一致：ungrab 前采样 `overview_was_open` → GlobalUi |
| 4 | MAJOR | 跨输出指针/平板移动只重绘新输出 → 旧输出软件光标残影 | `on_pointer_motion`/absolute/tablet-axis 尾部补 `queue_redraw_output_under(old_location)` |
| 6 | MAJOR | touch_overview_grab 直接 `queue_redraw(&self.output)` 热拔 panic | 改 `queue_redraw_if_exists` |
| 9 | MAJOR | Wallpaper stop check 会被在途 process check 顶掉（不杀进程 + 80ms 无限轮询 + 重新收养） | `requestPrestartedStopCheck` 先作废 `prestartProcessCheck` 并 bump process 代际 |
| 10 | MINOR | `prestartRecordGeneration` 只写不读（声明未实现） | 增加 `prestartReloadGeneration` 捕获，`finishPrestartedRecordLoad` 入口校验代际 |
| 15 | BLOCKER | node-vm 解析器测试定义在 `unittest.main()` 之后（直跑死代码） | 移入 `WallpaperIdleBudgetTests` 类内；`python file.py` 与 pytest 均 10/10 |
| 16 | INFO | r17 dirty 测试注释与实现不符 | 注释修正 |

审查其余核验项（do_action 全覆盖、unwrap 恐慌面、grab 落点、计数器语义、R17 兼容性）无问题。

## 4. 行为等价核验要点

- 布局变更类动作（move/focus/workspace 切换等）→ 尾段至少重绘活动输出；跨 monitor →
  源+目标；by-id 窗口方法 → 全部输出（保守）。
- 指针路径 → 仅指针所在输出（原为全部）；光标/DnD icon 每帧 commit 同理。
- 拖拽 → 被拖窗口 bbox 重叠输出；结束动画由布局动画 redraw_sources 接续（不丢帧）。
- 真全局（overview/锁屏/config/调试）→ `All{reason}` 计数可审计，行为不变。
- Wallpaper：adopt/stop/health 三条路径全部保留原语义（S1/S3 对抗性修复不回退），
  stop 的「先读后杀」身份校验保留（stale record 不杀重用 pid）。
