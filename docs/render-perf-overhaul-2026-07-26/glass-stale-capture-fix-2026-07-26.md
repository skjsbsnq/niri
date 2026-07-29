# 顶栏弹层玻璃陈旧捕捉修复（2026-07-26）

> 状态：代码完成，`cargo test --lib` 486/486 全绿，release 二进制已构建；双独立对抗性审查
> 见「审查结论」节；部署待用户重启窗口期（见「部署」节）。

## 用户报告的症状

1. **状态更新 → 整个面板透明度/颜色突变**：剪贴板点「清空历史」后整卡观感变化；
   所有顶栏弹层只要有状态更新都会这样。
2. **点图标收回 → 顶部突然变黑**：弹层 edge-reveal 收回过程中面板顶部区域突然变暗。

用户判断"这个设计不知道什么时候引入的"——实际不是设计，是渲染缺陷。

## 实证过程（截图证据 /tmp/tahoe-debug/）

- `01-open-baseline.png`：剪贴板弹层静止 1s 后，玻璃 blur 内容呈"上白下暗"，与真实
  背景（上暗下白的浏览器页）不符。
- 受控实验 `12-static-occluder-rest.png`（全宽静态图案窗口作背景，弹层静止 1.6s）：
  玻璃内容整体**上移 ≈40px 且顶部混入本属于顶栏后方的壁纸画面**——黄条纹在玻璃里
  出现在真实位置上方约 40px。
- `13-after-poke.png`：wl-copy 触发一次自身 damage 后，玻璃内容**瞬间下移对齐**真实
  背景——即症状 1 的"状态更新后整卡变化"。
- `14-close-2.png`：收回中采样带随 edge-reveal 位移上移扫过屏幕顶部内容。
- 对照实验（旁露动态壁纸时）玻璃始终正确 → 证明滞留条件是"背景静止且被不透明窗口
  完全遮挡（无下方 damage）"——最常见的日常场景（最大化窗口）。

## 根因（两个叠加缺陷 + 一个隐性缺陷）

1. **陈旧捕捉滞留**（症状 1 主因，`framebuffer_effect.rs` + P03 缓存）：
   edge-reveal 开场动画期间 fb-effect 逐帧在"移动位置"blit 背景；动画尾帧（弹簧亚像素
   尾）后的最后一次捕捉带 ≠ 静止位置带，而 P03 capture key 不含几何 → 静止后没有任何
   机制强制重捕，缓存纹理被拉伸映射到静止 dst 上常驻显示。任何 self/below damage
   （清空历史、刷新、新条目）才触发重捕 → 观感跳变。
2. **采样带随动画位移**（症状 2 主因）：close edge-reveal 玻璃 `location + offset` 逐帧
   上移，采样带扫过顶栏亮带与屏幕顶部内容；越过屏幕顶边后 capture clamp 把窄带拉伸到
   整个可见区 → 收回中面板明显变暗/发黑（背景上方内容偏暗时尤其明显）。
3. **region 静默丢弃 + 客户端缓存脱钩**（隐性，`protocols/tahoe_glass.rs`）：
   增高动画窗口期 region 先于 buffer 变大，`validate_regions` 静默丢弃越界 region 且消费
   `pending_dirty`；quickshell 侧 diff 缓存认为已设置、不再重发 → 面板永久掉到
   KDL layer-rule background-effect 回退渲染直到下一次 region 变化。

## 修复（niri 子仓，8 文件）

| 机制 | 实现 |
|---|---|
| 采样锚定 | `RenderParams.sample_offset` → `FramebufferEffectElement.sample_offset`：capture blit 带 = dst − offset。仅 edge-reveal（crop_rect 存在）时 = 动画位移（`edge_reveal_glass_sample_offset`，mapped.rs 开/关两路共用），其余为零。玻璃随面板移动绘制，但 blur 内容锚定静止位置：不再扫顶、不再越界拉伸，整个动画期缓存有效。 |
| 捕捉带入 key | `ResolvedEffectCaptureKey.capture_geometry`（= round(params.geometry) − sample_offset）：捕捉带变化 → commit bump → damage tracker 强制重捕；带不变复用缓存。彻底消灭"缓存带与绘制带错位"类滞留（含 slide/popin 等其它样式与面板 resize）。 |
| P06 档位收窄 | edge-reveal（纯平移+锚定采样）不再计入 `geometry_animating`（开/关两路注释同步更新）；scale/pop 类与 P05 变换动画不变。 |
| region 自愈 | `validate_regions_for_surface_geo` 返回 `(committed, complete)`；几何越界丢弃或面积超限时 `complete=false`，post-commit hook 保持 `pending_dirty` → 补上新尺寸 buffer 的那次 commit 自动重校验，region 恢复无需客户端重发。退化 region（空/溢出）不标记 incomplete，避免永久重试。 |

新增测试：`edge_reveal_anchors_glass_sample_band_at_rest`（mapped.rs）、
`capture_band_change_forces_recapture`（background_effect.rs）、
`oversized_region_revalidates_once_surface_geometry_catches_up` +
`degenerate_regions_do_not_mark_validation_incomplete`（protocols/tahoe_glass.rs）；
既有 P03/P06 语义测试全部保持通过。

## 审查结论

双独立对抗性审查（渲染路径专审 + 协议/回归面专审），第一轮共报 1 BLOCKER（两审
交叉命中）+ 3 MAJOR + 若干 MINOR，全部按建议修复后送复核：

- **BLOCKER（已修）**：初版在 capture 端"先平移后裁剪"，与 draw 端"整纹理→
  裁剪后矩形"的 1:1 契约破裂——移动带越出屏幕后内容被竖直压缩错位（恰是收回
  场景主体）。改为"先裁剪后平移"（`capture_blit_band` 纯函数 + 行对应测试），
  draw 端零改动。
- **MAJOR-渲染①（已修）**：被打断的 popin→edge-reveal 交接继承非 1.0 缩放时，
  capture 收到 post-scale 几何，减未缩放偏移会锚到错误位置 → `wrapped` 参数
  归零回退随动采样（该场景 geometry_animating 恒真，逐帧重捕保证正确）。
- **MAJOR-渲染②（已修）**：edge-reveal 从 P06 档位排除的收益描述不成立（元素
  每帧移动，tracker 逐帧重捕不受 key 影响），排除只会把动画期金字塔推回全分
  辨率 → 回退为原判定式，注释改为如实描述。
- **MAJOR-协议①（已修）**：incomplete 提交曾把被拒 region 从 committed 中抹
  掉——增高窗口期玻璃闪回退、RegionMorph 的 old_rect 锚点被毁 → 几何可自愈
  拒绝时携带旧 committed 条目（仍适配且面积预算允许），窗口期玻璃保持旧尺寸、
  morph 锚点保留、committed 不变则零 damage。
- **MAJOR-协议②（已修）**：面积超限/负 origin 等结构性拒绝曾同样标 incomplete
  → 永久 dirty + morph 饥饿 → 仅"origin 在内、extent 超出"（可增长自愈类）标
  incomplete，结构性拒绝维持旧的一次性丢弃语义。
- MINOR：capture key 在包裹元素下为保守近似（文档已注明，由逐帧 instance
  damage 兜底）；分数缩放下锚定带 ±1px 抖动（仅多余重捕，无错误内容）；多输
  出同 surface 的 key 乒乓（理论场景，niri 中 layer surface 单输出）；行宽已修。

复核轮结论回填于下：

- **渲染侧复核：通过**（零阻断）。裁剪顺序方案被确认在数学上成立且优于原建议
  （draw 端零改动，两端重新锁回同一矩形）；双向行对应、防御性再裁剪退化行为、
  wrap/平移 presentation/P06 降采样/旋转输出交互逐项排查未构造出错位。追加
  2 MINOR 均已落实：wrapped 判据扩展到"合成 wrap 含缩放"（带缩放 presentation
  transform 也归零回退，纯平移仍保持锚定精确）；`capture_blit_band` 文档措辞修
  正（终端残条为整块跳过而非缺行）。
- **协议侧复核：通过**（零阻断）。指定推演项全部验证：morph 场景（commit 1 增
  高+morph → commit N 自愈）正确解析 old→new；增高窗口期 committed 恒等、零
  damage 零重绘；shrink+grow 交错时携带条目逐次重验、绝不保留越界陈旧玻璃。
  追加 3 MINOR：MIN-1（面积预算 break 短路其后条目的可自愈分类）已修——改为
  标志位继续扫描 + `healable_overflow_behind_budget_point_still_revalidates`
  锁定；MIN-2（客户端病态永不匹配 buffer 时的有界重验）为设计固有边界，接受；
  MIN-3（B 增高窗口内 A 的 morph 顺延后按无几何变化丢弃）为有界角落场景，留观。

最终状态：`cargo test --lib` 490 全绿；触及文件 rustfmt 干净（仓库既有漂移未
扩大）；niri 子仓提交 `0be01c18` 已推送。

## 部署后回归与二次修复（2026-07-26 深夜，`5c47e260`）

`0be01c18` 部署当晚用户报告两个新回归（截图证实，背景为黑色终端）：

**回归 A：开/收动画期间玻璃出现"黑块"，面板卡片尚未接触黑终端区域就已变黑。**
根因是上一轮的"采样锚定"机制本身：把采样带锚在静止位意味着移动中的面板显示
的是它**将要停靠/曾经停靠**位置的背景模糊——静止位下方有黑终端时，面板刚从
顶栏滑出就带着终端的黑色模糊（收回时黑色又跟着面板上移）。锚定采样在光学上
就是错的：玻璃必须折射**当前实际身后**的内容。

**回归 B：剪贴板增高后扩张带完全透明，直到再复制一条/截图引发重绘才恢复。**
根因是 region 校验的取数时序差一帧：校验挂在 smithay post-commit 钩子上，而
smithay `Transaction::apply` 的顺序是 apply_state → post-commit hooks →
`CompositorHandler::commit`，surface 的 view（`RendererSurfaceState`）要到最
后一步里的 `on_commit_buffer_handler` 才更新——钩子里 `surface_geo()` 读到的
永远是**上一条 commit** 的几何。增高动画最后一帧（buffer 已到位、region 实际
已适配）因此仍被判"可自愈拒绝"，之后再无 commit 来复验，扩张带就永久卡在无
玻璃状态；任何下一次 commit（再复制、截图触发重绘）都会瞬间愈合——与用户观
察完全吻合。上一轮的 region 自愈机制把旧的"永久掉 KDL 回退"变成了这个更显眼
的"扩张带透明"，才暴露出这个一直存在的差一帧。

**二次修复（`5c47e260`，9 文件 +85/−297）**：

| 机制 | 实现 |
|---|---|
| 回退锚定采样 | 整体移除 `sample_offset`（RenderParams/FramebufferEffectElement 字段、`capture_blit_band()`、`edge_reveal_glass_sample_offset()`、`glass_xray_pos` 静止位分支及配套测试），capture blit 恢复 `dst ∩ output`，xray 恢复随动。原症状①（停稳陈旧带）②（收回缓存拉伸变黑）的防护完全由保留的 `capture_geometry` 键承担：带一动 → key 变 → 同帧强制重捕，缓存纹理结构上不可能再被拉伸到错误位置（审查已在 smithay damage tracker 逐环证实，含 crop/rescale 包裹场景的 instance-damage 兜底）。 |
| 校验挪到 buffer 更新后 | 删除 post-commit 钩子注册机制（`hook_registered`/`with_inner_and_commit_hook`），钩子函数改为 `tahoe_glass::on_surface_commit`，由 `CompositorHandler::commit` 在 `on_commit_buffer_handler`/`early_import` 之后、`layer_shell_handle_commit` 之前直调——校验读到的就是本次 commit 附加的几何，误拒窗口从根上消失。时序不变量保持：mapping commit 携带的 transform directive 仍先于 `MappedLayer::new` 发布；触发集合与旧钩子 1:1（对照 `Transaction::apply` 核实，sync 子表面递延行为持平并已注释）。自愈携带逻辑保留，作为真实 region-先行-一帧 commit 的安全网。 |

**二次审查**：双独立对抗审查（渲染路径专审 + 协议/commit 时序专审），零
BLOCKER/MAJOR；全部发现为注释债（`MappedLayer::new` epoch 理由引用已删机制、
"post-commit hook"/"minus sample offset"措辞残留、sync 子表面限定缺失），已
全部清偿。`cargo test --lib` 488 全绿（随机制删除其 2 个专属测试）。

## 三次修复（2026-07-27，`0faa78bd`：动画途中扩张带无玻璃）

`5c47e260` 部署后用户反馈：停稳后不再卡死，但**扩张动画途中**新增带仍无玻璃
（不透明），扩张完成后立即恢复模糊。根因是二次修复保留的"携带旧 committed
条目"自愈策略：region 超 surface 时 complete=false 保持 dirty，但玻璃 rect 冻
在上一帧的小尺寸，surface 已变大 → 新增带无玻璃，直到 buffer 追上那一帧完整
rect 才落地。shell 侧（ClipboardPopup `Behavior on height` + quickshell polish
显式 commit）会让 region 比 buffer 早一帧，正好打中这条路径。

**修复（niri `0faa78bd`）**：几何可自愈溢出改为**把 pending region clamp 到当
前 surface 后提交**（仍 complete=false，buffer 追上后同一 pending 复验完整
rect）。动画每帧玻璃贴着 buffer 边长大，不再冻在旧尺寸。删除 previous 参数。
RegionMorph（仅 DynamicIsland）在 pending_dirty 期间继续 hold，不会锚到半成
品 clamp 尺寸；剪贴板等面板不走 morph，只靠 clamp 跟踪。

对抗审查零阻断（RegionMorph hold、radius fit_to、pending 不改、缩小路径、
budget×clamp 多 region 仅 MINOR 且壳层单 region 打不中）。测试改写
`oversized_region_clamps_and_revalidates_once_surface_geometry_catches_up`
覆盖 small→mid→caught-up；`cargo test --lib` 488 全绿。

## 四次修复（2026-07-29，T-18：撤除 clamp 兜底）

`0faa78bd` 的 clamp 是上游根因的合成器侧兜底：shell 在 polish/`sendTransform*`
阶段立即 `wl_surface.commit()`，把新 region/transform 贴到**上一帧 buffer** 上，
合成器因此锁住一帧"region 新、内容旧"。`0faa78bd` 用"把 pending region clamp 到
当前 surface 后提交"绕开它，代价是 grow 途中玻璃贴 buffer 边而非目标布局，并可能
在 grow 动画产生超前带。

**T-17（quickshell `063a65b`，主仓 `3bca257`）根治了上游根因**：`commitGlassIfIdle()`
在 `QEvent::UpdateRequest` 置位 `mRepaintInFlight`、`QQuickWindow::frameSwapped`
清位；有重绘在途时不显式 commit，让 region/transform 由 render 线程的 buffer commit
在**同一个原子 `wl_surface.commit`** 里携带，region 不再领先 buffer。`sendTransform*`
三处立即 commit 并入同一框架（S-M6）。

**T-18（本提交）撤除合成器侧 clamp 兜底**：`git revert 0faa78bd`，恢复 `5c47e260`
的"携带旧 committed 条目"自愈策略。T-17 之后该 region-ahead-of-buffer 窗口在正常
操作中不再打开，携带策略降级为**休眠安全网**——万一仍有客户端把 region 落到上一帧
buffer，携带策略继续显示上一帧（较小尺寸）的玻璃而非掉回 fallback，残留窗口仍会
在新增长行上留一帧无玻璃带（比 clamp 的超前带轻，但非完全无瑕疵），不会出现 clamp
的持续性超前带。
`validate_regions_for_surface_geo` 文档注释补记此休眠语义与 T-17/T-18 因果。测试
恢复 `oversized_region_revalidates_once_surface_geometry_catches_up`（carry-previous
版）与 `healable_overflow_behind_budget_point_still_revalidates`；`cargo test --lib`
524 全绿；`scripts/check-tahoe-glass-guardrails.sh` 通过（VERSION 4 / MAX_REGIONS 32
/ XML 同步 / Phase 5 popup 几何静态均不变）。

**运行时验证（须部署后活会话）**：`WAYLAND_DEBUG=1` 抓 dock/剪贴板 grow，每帧只见一次
`wl_surface.commit`、且 `set_region` 与 buffer `attach` 在同一 commit；grow 动画途中
无超前带、无玻璃断带。复用下文「部署」节走查清单第 5、6 条。

## 遗留观察项

- 一次未复现的偶发：剪贴板弹层开着时 wl-copy 新条目，弹层自行关闭（仅出现一
  次，后续两次同操作均正常入列）。与本修复无关，留观。
- `glass_surface_detail()`（postprocess.frag）使大面板材质随尺寸滑变（长边
  620–980 / 面积 180k–420k 渐变带），面板 resize 跨带时整体观感有设计内的连续
  变化——与本次修的"跳变"不同类；若部署后用户仍觉大面板 resize 前后观感差异
  过大，这是下一个调参点。
- P06 收尾帧强制重捕在旧部署上未生效的精确断点未单独定位（本修复用"捕捉带入
  key"从机制上覆盖了它）；P08 A/B 时若见静止面板驻留半档模糊可再追。

## 部署

本修复只动 niri 合成器二进制（shell/KDL 无改动）；四次修复（T-18）后二进制版本串
应为 T-18 的 niri 提交 `f9bed7e5`（`niri msg version` 核对）：

```bash
cp /home/wwt/niri/niri/target/release/niri ~/.local/bin/niri
# 然后重启 niri 会话（重新登录或 niri msg action quit 后自动重启）
```

部署后走查清单：
1. 剪贴板/电池/WiFi/风扇/控制中心/通知中心在**静态最大化窗口前**打开，静置 2s 观察玻璃
   是否与背景对齐（修复前会整体偏移出现"白雾"）。
2. 打开后点「清空历史」/触发任意状态更新，整卡观感不应再突变。
3. 点图标收回，面板顶部不应再突然变黑；开/收全程玻璃内容稳定。
4. 弹层打开时向剪贴板连续塞入新条目使面板增高，玻璃不应闪断（region 自愈）。
5. **（二次修复）**在屏幕下方摆一个黑色终端，打开/收回剪贴板与控制中心：
   动画全程玻璃只应显示其当前实际覆盖区域的模糊——黑色只在面板真正盖到终端
   时出现、离开即消失，不得提前/滞后出现黑块。
6. **（二次+三次+T-18 修复）**复制一条新内容 / 点固定使剪贴板增高：扩张途中及
   结束玻璃都应稳定模糊——无超前带、无途中不透明、无需再复制/截图才恢复。T-17
   使 region 与 buffer 在同一 `wl_surface.commit` 原子落地，T-18 撤除了为旧根因
   兜底的合成器 clamp（不再"贴 buffer 边长大"，而是 region/buffer 同帧到位）。
