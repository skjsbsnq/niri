# P04 — 弹层进出场动画收尾（QML 侧删动画，交合成器）

> 状态：进行中（分批推进；每批独立对抗性审查后 commit+push）。

## 全面板盘点（2026-07-26）

判定标准：P04 目标是删除 QML 自有的 **map/unmap 进出场动画**（opacity/位移尾巴、延迟
unmap 技巧），surface 静态提交，动画由 niri layer-rule `layer-open`/`layer-close` 承担。
面板内部的交互/内容动画（morph、按压、列表增删、飞行编排）不属于 map/unmap 动画，保留。

| 面板（namespace） | 盘点结论 | 行动 |
|---|---|---|
| ControlCenter / NotificationCenter / LeftSidebar / Spotlight | 早期任务已迁移，`visible: open` 直接映射，profile 齐备 | 无 |
| Battery/Wifi/Fan/Clipboard popup、TrayMenu（small_popup 组） | 已迁移 | 无 |
| MenuPopup/AppMenuPopup/ProcessMenu/DockAppMenu/DockWindowMenu（menu 组） | 已迁移；MenuPopup `flashHold` 是行点击闪烁的交互反馈保持（避免 flash 被 unmap 截断），非退场动画 | 保留 flashHold |
| NotificationToast（toast 组） | 窗口级 `visible: shouldShowToast` 即时 unmap；per-entry 飞出/进入是多 toast 栈的内容动画（合成器无法按 entry 处理），最后一条退出后快照透明、close 动画不可见，无双重动画 | 无 |
| TaskSwitcher | T20 有意「瞬时显隐」（macOS cmd+tab 风格），无动画即设计 | 无（不加 profile） |
| NotificationCenter 行进场 | `claimHistoryEntryAnimation` 按 entry id 一次性认领，仅新到达通知播放，非面板开启尾巴 | 无 |
| PopupDismissLayer / TopBar / Dock / Wallpaper / DynamicIslandOverlay | 常驻或不可见 surface，无 map/unmap 动画诉求（灵动岛/Dock 形变属 P05） | 无 |
| **SettingsPanel（tahoe-settings）** | `visible: open \|\| panel.opacity > 0.01` 延迟 unmap；scrim fade（fadeFast) + panel fade（panelExit）+ scale 0.985→1（160ms 固定）双向 Behavior | **批次 1 迁移** |
| **Launchpad（tahoe-launchpad）** | `compositorLayerAnimations` 旗标硬编码 false 的休眠双路径（平行接口）；QML `layerProgress` 驱动整层 opacity+scale(0.988)+materialAlpha，OutQuint 340ms 进 / InOutCubic 240ms 出，延迟 unmap | **批次 2 迁移（收口双路径）** |
| **WindowOverview（tahoe-window-overview）** | 飞行编排（entering/leaving flight）= 内容动画保留；违规点是 leave 落地后 `visible: … \|\| backdrop.opacity > 0.01` 的 backdrop/panel fade 尾巴延迟 unmap | **批次 3 迁移（close fade 交合成器，open 保留 QML veil 内容淡入）** |

关键机制确认（合成器侧，均为已有实现）：

- 无 layer-rule 的 namespace **完全没有**合成器动画（`ResolvedLayerRules.layer_open/close: Option`）。
- open/close 动画的 alpha 会传入 `tahoe_glass::render_for_layer`（mapped.rs），玻璃 blur 跟随动画
  淡入淡出——Launchpad 迁移后 materialAlpha 钉 1 不会产生 blur 硬切。
- unmap 快照由 pre-commit hook 在「即将 unmap 且当前仍有 buffer」的提交上取**当前已呈现内容**
  （handlers/layer_shell.rs），QML 在 close 分支不做内容重置即可保证快照干净。
- `transform/opacity` 双通道 easing 0ms = disabled；close 两通道均 disabled 时不取快照、瞬时
  unmap（reduced 档 Launchpad 的瞬时行为由此实现）。

## 批次 1 — SettingsPanel → 受管组 `settings`

改动：

- `config/niri/tahoe-phase0.kdl`：新增 `tahoe-managed: layer-animation settings` 规则。
  balanced：popin/popout `scale 0.985`、`origin center`、transform 160ms `ease-out-cubic`、
  opacity 200ms `ease-out-cubic`（= 原 QML panel 双向 Behavior 的时长曲线；OutCubic 即
  Motion.emphasizedDecel）。
- `niri_settings_tool.py`：`LAYER_PROFILE_GROUPS` + 四档 `MOTION_PROFILE_LAYERS`
  （fast 160/160、balanced 160/200、liquid 160/230 —— opacity 跟 panelExit token，
  transform 恒 160 延续原「scale 时长不随 profile」注释；reduced 0/60 + style fade，
  与其他组 reduced 政策一致）。
- `SettingsPanel.qml`：`visible: open`；scrim/panel 静态化（删 3 个 Behavior 与 opacity/scale
  绑定）；GlassPanel `materialAlpha: 1`、`regionEnabled` 回落默认恒 true（LeftSidebar 模式，
  unmap 快照保留玻璃材质）。
- `test_layer_animation_ownership.py`：settings 纳入已迁移面板契约。

已声明的观感取舍（均记录并接受）：

1. scrim 淡入从 120ms（fadeFast）变为整面统一 200ms。
2. popin/popout 会把全屏 surface（含 scrim）整体缩放 0.985，动画期屏幕边缘有 ≤0.75% 宽度的
   scrim 露边（伴随 opacity 渐变，主观不可见；Launchpad 现状 QML 即整层缩放先例）。
3. reduced 档由「60ms fade + 160ms scale」变纯 60ms fade（无障碍语义更正确）。

验证：`niri validate` 通过；tahoe-shell 907 测试全绿。

### 批次 1 对抗性审查

**审查 A（正确性/回归/边界）：无阻断、无应修，3 项建议级观察。**
方向性实证：① 工具 roundtrip——balanced→reduced→balanced、→fast、→liquid 及混合序列
全部**字节还原**，每步 `detect_motion_profile` 回报正确，表外键（scale-from/origin/双
curve）不写不比、不破坏检测；② close 快照必为全不透明末帧（opacity 静态 1 + pre-commit
hook 在 null-buffer 提交生效前截取）；③ 全屏 popin 无更糟渲染问题——玻璃 region 与内容同被
`RescaleRenderElement` 包裹（同 pivot 同 scale），相比旧 QML「region 不随 QML scale 动」
的 7px 错位，一致性反而更好；popin/popout 无 crop 路径；④ 守护规则：纯 easing 无 spring，
glass region 几何静态绑定；⑤ Rust 玻璃路径：open alpha 作用于 material_alpha
（tahoe_glass.rs:279），close 走 `should_render_close_effects_live`（`^tahoe-` allowlist）
每帧以 close alpha×scale 活渲玻璃，打断态继承 alpha/scale。五种档位状态 `niri validate`
全部通过。

建议级观察（记录，不修）：
1. close 残影期（~100ms，alpha 0.4-0.8）点击直达下方窗口——旧方案 mapped 期间全屏 scrim
   吞点击。此为 spotlight/menu 迁移取舍的延续（响应性更好），保持 200ms 观感对齐优先。
2. close 进行中快速重开出现 ≤200ms 双影（quickshell 重建 layer surface，`reopen_start`
   连续性仅同句柄生效）——spotlight 等既有迁移面板同样存在，非本批引入。
3. 工具与 KDL 存在部署耦合：工具新/配置旧的半部署态下 profile 功能整体 fail-safe 不可用
   （不损坏配置）——与 toast/menu 组加入时模式一致，KDL 与 shell 同批部署即可。

**审查 B（行为语义/系统一致性）：无阻断；2 项应修（均文档级）+ 5 项建议，已按下述处置。**
实证亮点：① KDL/工具表/Motion.js 三方数值逐档一致（含 fast/reduced 往返逐字节还原复跑）；
② 开关文案一致性——迁移后 SettingsPanel 硬切（toggle off 时）**恰好从旧行为的未记录例外
变为符合 NiriAnimationsPage 文案**；③ shell.qml 集成无耦合（SettingsPanel 不用
PopupDismissLayer，自带 scrim MouseArea；focusable/servicePollingActive 均键在状态变量）；
④ close 快照玻璃材质：`materialAlpha: 1` + region 恒 enabled 正是
`should_render_close_effects_live` live 渲染路径的必要条件，改法正确；⑤ P02 冻结门控无旧页
闪现路径（snapTo 在渲染前复位 progressAnim）。

处置：
- 应修 #1（部署顺序耦合）→ 记入本文档与 commit message：**KDL 与 shell 必须同批部署**；
  半部署态 fail-safe（profile 功能整体拒写、显示 custom/off，不损坏配置）。
- 应修 #2（tahoe-motion-default-policy.md R10 枚举过期）→ 已补 2026-07-26 P04 批次 1 段落。
- 建议（KDL 注释缺取舍记录）→ 已补两行 Accepted deltas 注释。
- 建议（panelExit 收敛无测试锁定）→ 已在 test_niri_settings_tool.py 新增
  `test_settings_layer_opacity_follows_panel_exit_token`（四档 × 双相位）。
- 建议（快速连点双影 + 双 scrim 叠加脉冲、close 残影期点击穿透）→ 记录为走查项（与
  spotlight/menu 迁移行为同构，既有先例）；契约测试子串匹配弱点已知（组合断言成立）。

**批次 1 commit：`943c969`（已推送）。**

## 批次 2 — Launchpad → 受管组 `launchpad`（双路径收口）

改动：

- `tahoe-phase0.kdl`：新增 `tahoe-managed: layer-animation launchpad` 规则（popin/popout
  `scale 0.988`、open 340ms `cubic-bezier 0.22 1.0 0.36 1.0`≈OutQuint、close 240ms
  `cubic-bezier 0.65 0.0 0.35 1.0`≈InOutCubic，与旧 QML layerProgress 单驱动完全同参）；
  顺带删除 spotlight 规则上"Launchpad stays on the QML path"的过期矛盾注释。
- `niri_settings_tool.py`：`launchpad` 组入 `LAYER_PROFILE_GROUPS` + 四档模板
  （fast/balanced/liquid 相同 340/240——QML 从不按档缩放；reduced 双通道 0ms + fade =
  **瞬时 unmap 且不生成快照**，等价旧 QML reduced snap）。
- `Launchpad.qml`：删 `compositorLayerAnimations` 旗标、`layerProgress` 属性、
  playLayerEnter/playLayerExit、layerProgressAnim、exitCleanupTimer、延迟 unmap；
  launcher/dim/backdrop 静态化；close 分支只停动画**不重置内容**（niri 快照=最后呈现帧，
  承重设计）；死属性 `closingForLaunch` 一并移除；文件头注释同步。
- `Motion.js`：删 launchpadLayerEnterMs/ExitMs/ScaleFrom 与两个 duration 函数
  （wallpaper/icon/pop/paging 内容 token 保留）。
- 测试：test_launchpad_refactor.py 断言翻转（含 §2.11 原契约保留）；ownership 测试
  launchpad 改写为已迁移断言 + Motion.js token 缺席断言；新增
  `test_launchpad_reduced_profile_disables_both_channels`（锁 reduced 0/0 跳快照语义 +
  三档 340/240）。
- `tahoe-motion-default-policy.md`：Ownership 表 Launchpad 行改 Removed；新增批次 2 段落，
  显式推翻 R10 段旧决策并记录成因分析。

### 批次 2 对抗性审查

**审查 A（生命周期/快照/曲线）：无阻断。** 实证：① launch-then-close——launchPopAnim 200ms
OutBack 在 timer 240ms 时已稳定于 1.0，快照=峰值冻结帧（图标 1.14×、其余 0.45），与旧
"hold final pop + fade"逐值一致；② 快照 blur 是 **live 采样**（"frozen"仅指 region 几何），
240ms 快照淡出期间 blur 实时跟随 400ms 壁纸 zoom-out，无新撕裂；③ 中途重开由 niri
`reopen_start` 以 ClosingLayer 当前 alpha/scale 续走 OpenAnimation——正是旧 QML "continue
from current progress" 的合成器版；④ 曲线保真：bezier vs OutQuint 最大偏差 1.13%、vs
InOutCubic 0.95%，不可感知；⑤ 工具往返（含 reduced KDL 独立 validate）字节还原、三档
detect 正确；⑥ reduced 0/0 → `layer_close_animation_config_is_disabled` → 不生成快照。

**审查 B（一致性/渲染路径/文档治理）：无阻断。** 实证性推翻旧"软"决策：①
RescaleRenderElement 只缩 dst 几何、src 不变，open 直接 wrap surface 元素无离屏中转，
close 以输出 fractional scale 1:1 烘焙后向 0.988 缩小——**两方向零上采样**，popin 终帧
`should_wrap()=false` 完全不包装（像素级 1:1）；② 玻璃 alpha 乘法位置与旧 materialAlpha
绑定相同（`material_alpha × layer_alpha`）；③ 当年"软"评估发生在 close 玻璃还会被烘进
快照的机制状态（cde9f181/f5b9b67e 次日才落地）且参数为 0.98/180ms 短促曲线——成因均已
消除。发现的注释/文档残留（Launchpad.qml:13、KDL spotlight 注释、policy 文档表格/段落）
已全部修复；KDL "unchanged/exact" 过强措辞已改 Accepted deltas 三条（blur region 随缩放
~0.6%/侧由 fade 掩蔽、dim 二次方→线性、Esc-during-pop 冻结半程 pop 属固有）。

走查项（沿批次 1 清单累计）：快速连点开关的合成器接力观感、launch pop 快照 fade、
动画期 blur 边缘。

**批次 2 commit：`49ddac0`（已推送）。**

## 批次 3 — WindowOverview → 受管组 `window_overview`（close 尾巴收尾）

设计要点：飞行编排（entering/leaving flight）与 veil 淡入是**内容动画，保留**；P04 移除的
是 leave 落地后靠 `visible: … || backdrop.opacity > 0.01` 延迟 unmap 的 QML 淡出尾巴。
layer-open 是刻意 no-op（双通道 0ms、opacity-from 1.0）：入场必须 map 即时 + 静态提交，
卡片才能从真实窗口矩形起飞；veil 与 flight 同帧起步，与今日 Behavior 起步时机相同，不存
在双重动画。

改动：

- `WindowOverview.qml`：`visible: surfaceVisible`；新增 `veil` 属性 + veilAnim +
  playVeilEnter（fadeFast/OutCubic，与被删 Behavior 同参）；onFlightPhaseChanged 在 idle
  时复位 veil（此时已 unmap、永不渲染，快照保留全 veil 帧）；backdrop/overview opacity
  改绑 veil、删两个 Behavior；regionEnabled 门控删除（快照保玻璃，LeftSidebar 模式）。
- `tahoe-phase0.kdl`：`window_overview` 受管规则（open no-op；close fade 120ms
  ease-out-cubic = 被删尾巴的 fadeFast/emphasizedDecel 同参）。
- `niri_settings_tool.py`：组表 + 四档 layer-close（90/120/140/70 跟 fadeFast token；
  layer-open 常量 no-op 留 KDL 编著、不入 profile 表）。
- 测试：test_thumbnail_async_budget.py 断言改块形式（延迟捕获契约不变）；ownership 新增
  overview close 尾巴归属测试。
- policy 文档：表格行拆分（WindowOverview 尾巴 Removed；Dock=P05 域、TaskSwitcher=T20
  瞬时设计）+ 批次 3 段落。

（批次 3 审查结论与 commit 号见下。）

### 批次 3 对抗性审查

**审查 A（veil 时序/快照/合成器 no-op）：无阻断，2 应修已修。** 实证：① veil 时序五场景
穷举（entering 中关、leaving 中重开、空列表强制关、leaveWatchdog 路径、初值）全部无洞——
含"不存在 open=true 时 phase 变 idle 的路径"的反证；② no-op open 合成器行为：duration 0
→ is_done 即真 → `open_animation_state()` 返回 None → 零包装零 damage 零重绘循环；
`opacity-from 1.0` 双保险 alpha≡1；③ 删 regionEnabled 门控**顺带修掉**旧版 tail 期间
region 先于 unmap 被禁用导致淡出丢玻璃的竞态（实质改进）；④ 工具往返四档字节还原 +
off/on 还原 + `.items()` 天然跳过缺失 layer-open 无 KeyError 路径。
应修落实：缩略图断言改邻接正则（变异实验曾证旧改写可被绕过）；KDL no-op open 加锁定
测试（profile 表刻意不管理它，此前无任何守护，漂移会造成无声双重入场动画）。

**审查 B（任务级完整性/全局收尾）：无阻断，1 实质应修 → 批次 4。** 实证：① 全仓 25 个
namespace 独立复核，19 个开合面板 `visible: open` 全部干净，豁免定性逐项挑战成立——
**除 `tahoe-wallpaper-launchpad-overlay` 被盘点漏掉**（Wallpaper.qml 内嵌第二个
PanelWindow，live 壁纸模式的 launchpad 调光层，`|| opacity > 0.01` 延迟 unmap +双向
Behavior，用户真实配置 wallpaperMode=external 下每次开关 launchpad 都活跃）→ 立项
**批次 4 迁移**；② 10 受管组 KDL/marker/registry 全绑定、detect=balanced、
enabled=True、四档往返字节还原；③ no-op open 论证收紧（合成器 open fade 不被"静态提交"
论据排除，真正理由是 CPU 零差异+逐位观感一致+单相位单归属——已补进 policy 文档）；
④ CPU 验收：仓库只有空闲基线，动画期无既有数据——采集方案（IPC toggle 循环 + pidstat
0.2s 采样 + close 后 300ms 窗口专项）记录于下文"验收数据"节，部署后执行。

已接受差异（审查 A 补充量化）：close 快照卡片冻结 opacity 1（旧为并行 fade ≈OutCubic²）、
reduced 路径快照为完整网格淡出（观感更好）、≤120ms 重开接力不连续（同批次 2 类）。

**批次 3 commit：待填。**

## 批次 4 — Wallpaper live 壁纸 launchpad 调光层 → 受管组 `wallpaper_overlay`

（实施与审查记录待补。）
