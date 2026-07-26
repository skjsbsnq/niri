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

本修复只动 niri 合成器二进制（shell/KDL 无改动）：

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
