# Tahoe Motion Default Policy

日期：2026-07-16

本文记录 Tahoe motion 的当前默认策略。2026-07-16 的 R10 所有权治理取代了 GOAL-10 的临时 fallback 保留决策：每类 surface 的外层进出场只有一个 owner。

## Decisions

| Area | Decision | Source |
| --- | --- | --- |
| Default motion profile | `balanced` | `config/niri/tahoe-phase0.kdl`, `NiriSettings.qml`, `DesktopSettings.qml`, `Motion.js`, `niri_settings_tool.py` |
| Tahoe surface outer animation owner | niri layer animation / default-on | `NiriSettings.qml`, `niri_settings_tool.py`, Tahoe `layer-rule` |
| Conservative user profile | `reduced` | Existing `animations.profile` writer and settings page selector |
| Baseline rollback profile | `balanced` | GOAL-5 byte-for-byte rollback check |

2026-07-09 update (motion-visual-overhaul T01): `balanced` now carries the
Tahoe Motion 2.0 timings (menuEnter 180 / menuExit 160 / panelEnter 320 /
panelExit 200) and `Motion.js` additionally exports the spring vocabulary
(`springSnappy`/`springSmooth`/`springPanel`/`springBouncy`) plus the press
tokens (`pressDuration` 120 / `pressScale` 0.96). No new profile was added;
`fast`/`liquid` scale proportionally and `reduced` stays minimal. The
byte-for-byte rollback property is a round-trip guarantee of the profile
writer, not a freeze of `balanced` values; rollback for the retiming itself is
`git revert` of the T01 commit.

2026-07-09 update (motion-visual-overhaul T03): compositor layer-rule
animations now open on spring main channels (menus/popovers `popin origin
"anchor"` dr=0.88 st=500; CC/NC/left-sidebar edge-reveal dr=0.85 st=380; toast
slide dr=0.8 st=320; spotlight popin dr=0.88 st=500, scale-from 0.96). The
profile writer manages those spring lines per profile and keeps the layer-open
transform override channel absent so the transform inherits the spring.
`reduced` keeps its conservative shape — it zeroes the layer transform channel
(`transform-duration-ms 0`, opacity-only feedback) and leaves the inert spring
line untouched — and every profile round-trips back to `balanced`
byte-identically. Rollback is `git revert` of the T03 commit.

2026-07-16 update (R10): Toast、LeftSidebar、Spotlight 删除了 surface 级 QML
位移、缩放和淡出 fallback，niri 成为这些 surface 外层进出场的唯一 owner。
`animations.layer_animations_enabled` 通过既有 `NiriSettings` writer 在全部受管
`layer-open`/`layer-close` 中增删 `off`，关闭时外层显隐即时完成，而不是切换到
第二套 QML 动画。Launchpad 仍明确由 QML 拥有，因为它没有对应 compositor
layer animation rule。`reduced` 同时约束 niri layer channel 和 QML 内部微动画。

2026-07-26 update (P04 批次 1): SettingsPanel 加入 compositor owner 集合
（受管组 `settings`，popin/popout 0.985 + ease-out-cubic），是首个整面 scrim
面板。QML 侧删除了延迟 unmap（`visible: open || panel.opacity > 0.01`）与
scrim/panel 的 opacity/scale Behaviors；`materialAlpha` 恒 1、region 保持
enabled，供 niri close 快照按 live 路径渲染玻璃。两项已接受的观感取舍：
scrim 淡出从 `fadeFast`(120ms) 变为整面 opacity 通道（balanced 200ms，随
panelExit token 分档）；`reduced` 丢弃原固定 160ms scale settle，改纯 60ms
fade（与其他组 reduced 政策一致）。opacity 通道与 `panelExit` 的逐档一致性由
`test_niri_settings_tool.py` 收敛测试锁定。

2026-07-26 update (P04 批次 2): Launchpad 加入 compositor owner 集合（受管组
`launchpad`，popin/popout 0.988、340ms OutQuint 进 / 240ms InOutCubic 出），
**显式推翻** R10 段"Launchpad 仍明确由 QML 拥有"的旧决策：当年"compositor
缩放会软"的评估发生在 close 玻璃尚会被烘进快照、且参数为 0.98/180ms 的机制
状态下；现行机制（RescaleRenderElement 零上采样、close 玻璃 live 渲染、动画
alpha 作用于 material_alpha）已消除全部成因。QML 删除了休眠的
`compositorLayerAnimations` 双路径旗标与 `layerProgress` 外层驱动（含
exitCleanupTimer/延迟 unmap）；close 分支只停动画不重置内容（快照=最后呈现
帧，属承重设计）。内容动画（gridEnter、launch pop、paging、壁纸 zoom 联动）
保留在 QML。已接受取舍：blur region 随整面缩放（旧 QML 只缩绘制内容，region
静态），动画中期每侧 ~0.6% 未模糊边由同步 fade 掩蔽；额外 dim 由嵌套
opacity 二次方变单次线性；launch pop 240ms 窗口内用户主动关闭会把半程 pop
冻进快照。reduced 双通道 0ms = 瞬时 unmap 且不生成快照，与旧 QML reduced
snap 等价。

2026-07-26 update (P04 批次 3): WindowOverview 的 close 收尾交给合成器（受管
组 `window_overview`）。飞行编排（entering/leaving flight）与 veil 淡入是
**内容动画，保留在 QML**；被移除的是 leave 落地后靠
`visible: … || backdrop.opacity > 0.01` 延迟 unmap 的 backdrop/panel 淡出
尾巴。现在 `visible: surfaceVisible`：leave flight 落地即 unmap，niri
layer-close 以同样的 fadeFast 时长（balanced 120ms）+ OutCubic 对最终快照
淡出。layer-open 是刻意的 no-op（双通道 0ms、opacity-from 1.0）——不用合成器
open fade 的理由：入场期客户端本就逐帧渲染飞行（CPU 零差异）、veil 与被删
Behavior 起步帧与曲线逐位一致（合成器 fade 会把逐 item alpha 换成整面合成后
统一 alpha、玻璃 ramp 换通道，两处微差收益为零）、open=QML 内容/close=合成器
的单相位单归属。该 no-op 形状由 `test_niri_settings_tool.py` 锁定（profile
表刻意不管理它）。已接受差异：① close 快照中卡片冻结在 opacity 1（旧尾巴里
卡片自身 fade 与面板淡出并行 ≈ OutCubic²），悬于真实窗口上的幽灵卡片在
≤120ms 内略更醒目；② reduced/无飞行路径的快照是完整网格淡出（旧版卡片先瞬
跳到窗口位再淡出）——观感反而更好；③ 合成器淡出 ≤120ms 窗口内再次打开存在
与 launchpad（批次 2，240ms 窗口）同类的接力不连续，属快照架构既定取舍。
veil 在 flightPhase 回到 idle（已 unmap、永不渲染）时复位为 0，保证快照是全
veil 帧、下次打开从 0 淡入。

## Why Balanced Stays Default

`balanced` remains the default because it is the only profile with all of the following evidence:

- GOAL-0 recorded it as the current KDL/QML timing baseline.
- GOAL-5 proved `fast -> balanced` returns `config/niri/tahoe-phase0.kdl` to a byte-for-byte match.
- GOAL-7 added snapshot lifecycle tests for fast toggle and one-frame close snapshot release.
- GOAL-8 kept material strength unchanged because live DRM/TTY render timing was not captured.
- GOAL-9 reduced allocation churn but did not deploy/restart the running compositor, so no live after-RSS win is claimed.

`fast`, `liquid`, and `reduced` remain selectable profiles. They are not the default because they have less live visual and performance evidence than `balanced`.

## Layer Animation Default

`layerAnimationsEnabled` 从当前 KDL layer rules 读取，默认配置中为 `true`。用户可在 Niri animations 页面关闭。

Reasons:

- The compositor layer animation path has automated lifecycle coverage after GOAL-7, including fast toggle, interrupt, and snapshot release tests.
- The KDL layer animation rules remain present and validated, and `balanced` remains the rollback profile.
- 开关由唯一 KDL writer 写入所有受管 layer phase，并在写入后热加载 niri。
- 关闭时 surface 即时 map/unmap；不会恢复 QML 外层 fallback。

## Ownership And Fallback Plan

| Fallback | Keep/Remove | Reason |
| --- | --- | --- |
| QML outer fallback for migrated Tahoe surfaces | Remove | niri is the sole outer owner; disabling means instant outer visibility |
| Launchpad QML outer animation | Removed (P04 批次 2) | Migrated to compositor layer animation; content animations (grid enter, launch pop, paging) stay QML |
| WindowOverview QML unmap fade tail | Removed (P04 批次 3) | Close fade is compositor-owned; the flight choreography and veil fade-in stay QML content animations |
| Dock, TaskSwitcher QML path | Keep | Dock is a persistent surface (P05 scope); TaskSwitcher is deliberately instant (T20) |
| TahoeGlass client fallback to BackgroundEffect | Keep | Protocol/fallback lifecycle is separate from motion defaults |
| Thumbnail `WindowPreviewFallback` | Keep | Required when niri thumbnail IPC or image decode fails |
| `reduced` motion profile | Keep | Conservative profile for low-motion preference |

不得为 Toast、LeftSidebar、Spotlight 或其它已迁移 surface 重新增加条件式 QML 外层路径。

## User Rollback Paths

Settings UI:

- Open Niri animations.
- Set `Motion profile` to `Balanced` for the baseline profile.
- Set `Motion profile` to `Reduced` for conservative low-spatial-motion behavior.
- Turn off `使用 compositor layer 动画` for instant outer surface visibility.

KDL/profile rollback through the existing writer:

```text
python3 tahoe-shell/services/niri_settings_tool.py write --config "$HOME/.config/niri/tahoe/config.kdl" --field animations.profile --value balanced --niri-bin /home/wwt/.local/bin/niri
python3 tahoe-shell/services/niri_settings_tool.py write --config "$HOME/.config/niri/tahoe/config.kdl" --field animations.layer_animations_enabled --value false --niri-bin /home/wwt/.local/bin/niri
/home/wwt/.local/bin/niri validate --config "$HOME/.config/niri/tahoe/config.kdl"
```

## Maintenance Rules

- Do not introduce a profile JSON file or component-private motion token file.
- Do not let QML components write niri KDL directly.
- Keep `Motion.js` profile names synchronized with `niri_settings_tool.py`.
- Keep `NiriSettings.qml` and `niri_settings_tool.py` layer animation state aligned with this document.
- `DesktopSettings.qml` must not regain a compositor layer animation mirror.
- Migrated components may keep internal content motion, but must not retain a surface-level fallback owner.
