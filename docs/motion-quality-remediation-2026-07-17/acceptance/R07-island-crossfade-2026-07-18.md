# R07 · 灵动岛换场重构（点名④a）验收记录

日期：2026-07-18
覆盖问题：#20 #24 #25 #26 #27 #28 #29（#30 属范围外 shell 衔接，未动）

## 实施摘要

**架构**："全隐-换-全现"staged swap（Overlay contentSwap SequentialAnimation + contentState/pending* 双状态机）→ **场景就地 crossfade**：

1. **#20 空胶囊帧**：Overlay 删除 contentSwap/contentRestore/contentLayerOpacity/pendingContentState/renderedNotificationExpanded/contentTransitionsReady/syncContentTransition 全套机制；`islandState` 直通 `effectiveContentState`。每个场景在 Content 内自持 `opacity: active ? 1 : 0` + Behavior（exit 110ms / enter 170ms，v2ContentEasing）+ ≤6px 方向位移（顶部锚定：exit 上移、enter 自上落位；workspace 保留方向性 x 位移）。outgoing 场景保持渲染淡出，incoming 同时淡入，几何与内容同一时刻起步。
2. **场景持有/释放**：重场景（notification、expanded media）Loader 增加 hold/release——`notificationLoaderActive`/`mediaLoaderActive` + `expandedUnloadHoldMs`（exitMs+40）Timer，退场淡出完成后卸载。
3. **#27 输入死区**：contentHost 的 `enabled: !contentTransitionRunning && opacity>0.99` 整层死区**移除**（二选一决策：移除而非 0.5 门槛——incoming 即时可交互）；改为 outgoing 场景级 `enabled: opacity > 0.5`（notification/media/timer delegate），防止淡出中的场景抢点击。
4. **#24 通知 compact↔expanded**：NotificationView 两布局由 `visible` 硬切改 opacity crossfade（enter 170/exit 110）+ expanded 布局 ≤6px settle-down Translate；`enabled` 跟随布局所属态。Overlay 的 forceSwap 路径（onContentNotificationExpandedChanged→整层眨眼）删除，`notificationExpanded` 直通绑定，几何高度 morph 由既有 Behavior 承担。
5. **#25 滑动关闭跟手**：bodyClick MouseArea 改为 armed 后 `swipeOffsetX` 跟手（Translate x 施加于 compactRow）；释放时 |offset| ≥ notificationDismissThresholdPx(72) → 飞出动画（notificationFlyOutMs 160）后 dismissRequested；未过阈值 → useSpring 门控回弹（springSnappy SpringAnimation / swipeSettle eased 双分支）。
6. **#26 媒体收起硬切**：MediaView `opacity` Behavior 始终启用（enter/exit 双时长），`visible: mediaExpandedContentVisible || opacity>0.01`，Loader hold 保障淡出完整；"Hard-cut" 注释路径清零。
7. **#28**：CompactMediaView 封面 Image 加载完成后 opacity 淡入（contentEnterMs），fallback 音符 glyph 反向 crossfade（`1 - artImage.opacity`）；播放/暂停字形切换改"半程淡出→换字形→半程淡入"（contentExitMs/2 ×2，shownPlaying 延迟镜像）。
8. **#29 补丁 Timer 删除清单**（Content.qml）：
   - `compactLayerWanted` / `compactLayerHeld` / `compactLayerShown` / `compactLayerOpacity` / `compactLayerY` + `onCompactLayerWantedChanged` 全套整层 hold 状态机；
   - `compactExitHold` Timer；
   - `compactMediaExitLatch` Timer（latch 释放改为 `onVisibleChanged` 淡出结束时清零——数据冻结语义保留，时序补丁删除）;
   - Overlay 侧 contentSwap/contentRestore 动画对象与 pending 双状态机（见 1）。
   保留（非补丁、仍必要）：`mediaUnloadHold`/`notificationUnloadHold`（hold/release 机制本体）、OSD retained exit（osdExitOpacity/osdExitTravel）、`latchedCompactMediaTitle/Width` 数据冻结。
9. **OSD 语义保持**：OSD 进场仍即时（compactContentMotionMs 在 osdActive 下取 v2OsdEnterMs，旧场景瞬时让位，硬件反馈拥有首帧）；OSD 退场 retained exit 不变。
10. **Token**：新增 `notificationDismissThresholdPx=72`、`notificationFlyOutMs=160`（仅 DynamicIslandMotion.js）。

**玻璃 region 路径零变化**：mask/region*/quantize/protocol* 与全部几何 Behavior 未触碰（R08 范围）。

## 测试更新

- `test_dynamic_island_v2_motion.py`：`test_overlay_coordinates_scene_swap_with_geometry` → `test_scene_crossfade_replaces_staged_swap`（断言旧机制不存在 + crossfade/hold 标记存在）。
- `test_dynamic_island_compact_media.py`：compactLayer* 断言改为双场景各自 crossfade 断言；latch 断言保留。
- `tst_dynamic_island_media_hit_testing.qml`：`test_scene_swap_exits_before_replacing_content` → `test_scene_crossfade_holds_outgoing_then_settles`。
- `tst_dynamic_island_runtime_hardening.qml`：notification loader 卸载改为等待 hold 窗口。

## 审查

- 主会话人工逐段自查：Overlay 无残留 swap 标识符（grep contentState/contentLayerOpacity/... 为零）；glass region 路径零 diff；场景 enabled 门（opacity>0.5）覆盖 notification/media/timer；useSpring 仅用于通知回弹 SpringAnimation（内容 transform，非 region）。
- 独立 /code-review 因基础设施故障（权限分类器长时间不可用）未能在 commit 前运行，用户明令直接 commit push。**待补：R08 开始前补跑一次针对本 diff 的独立审查。**

## 验收

- `pytest tests/ -q` → **764 passed, 217 subtests passed in 29.27s**（全绿）。
- 测试修复过程记录：
  - `tst_dynamic_island_media_interaction_lifecycle.qml` content-gate 测试改为淡出语义（tryCompare enabled→false、visible→false），并补 mouseRelease 清理（原失败会遗留全局鼠标 grab 级联炸掉同文件其余 7 个测试）。
  - `test_dynamic_island_v2_surface.py` / `test_dynamic_island_runtime_hardening.py`：notification Loader 断言改 `notificationLoaderActive`。
- 宿主/嵌套会话手测矩阵：**待补**（时钟↔媒体↔OSD↔通知↔展开两两切换、换场中可点击、滑动关闭跟手、reduced/useSpring=false 退化）。

## 范围外发现

- #30（岛→控制中心 surface 衔接）仍在范围外清单。
- Overlay 胶囊层兜底的通知横滑 dismiss（MouseArea released 分支）保留为非跟手 fallback（仅覆盖空白区按压），主路径已在视图内跟手。
