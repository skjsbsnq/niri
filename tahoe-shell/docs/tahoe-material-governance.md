# Tahoe Material Governance

日期：2026-07-06

本文是 Tahoe glass/material 的 source-of-truth 治理文档。任何默认材质强度、surface recipe、fallback blur 或设置页 mirror 的变更，都必须同步本文和相关测试。

## Source Of Truth

必须保持同步的文件：

- `TahoeGlass.js`
- `config/niri/tahoe-phase0.kdl`
- `niri/niri-config/src/tahoe_glass.rs`
- `tahoe-shell/services/NiriSettings.qml`
- `tahoe-shell/services/niri_settings_tool.py`

禁止新增第二套材质 token、第二套 fallback blur profile、组件私有 shader 参数表。默认策略不做 GPU/渲染能力自适应；如果未来要按硬件能力分级，必须先开单独 goal，并给出测量、测试和回滚方式。

## Material Tokens

当前只允许这七个 material token：

| Material | 用途 | 默认风险级别 |
| --- | --- | --- |
| `panel` | 大面板、侧栏、设置页、普通 popup | 中；面积可能大，refraction 保守 |
| `pill` | Dynamic Island | 中；边缘高光较强但面积小 |
| `launcher` | 保留的启动器 profile，当前无生产 surface 绑定 | 中；大面积，lens/refraction 保守 |
| `dock` | Dock 胶囊 | 中；持续可见，不能高成本 |
| `menu` | MenuPopup、Dock menus、TaskSwitcher | 低到中；面积小，文字清晰优先 |
| `toast` | NotificationToast | 低；短时显示，避免完全透明闪烁 |
| `backdrop` | Launchpad 全屏 scrim/backdrop | 高面积；refraction/lens/chromatic 必须低 |

`chromatic` 默认保持 `0.0`。`refraction` 默认只允许在已测量预算内小幅调整，不允许为了“更玻璃”直接提高全局值。

## Sampling Strategy

采样策略仍由现有 material 的 `xray` 字段唯一决定，不新增协议或 QML 玻璃路径。所有液态玻璃 material 必须明确使用 `xray false`，采样其 region 后方已经合成的实时 framebuffer。`xray true` 不是透明的性能开关：它只采样 workspace backdrop 和 background layer，会跳过普通窗口，导致白色窗口上方的玻璃仍显示壁纸颜色。

| Material | Sampling | 原因 |
| --- | --- | --- |
| `panel` | live composed framebuffer | TopBar、面板和 popup 必须随后方窗口变化 |
| `pill` | live composed framebuffer | Dynamic Island 必须保持真实局部折射和模糊 |
| `launcher` | live composed framebuffer | 保留 profile 也必须采用安全的实时默认值 |
| `dock` | live composed framebuffer | Dock 必须随下方窗口和桌面内容变化 |
| `menu` | live composed framebuffer | 菜单必须反映其父窗口和邻近内容 |
| `toast` | live composed framebuffer | 通知必须反映其显示位置的实时内容 |
| `backdrop` | live composed framebuffer | Launchpad 全屏玻璃必须模糊当前桌面和窗口 |

当前 22 个生产 `GlassPanel` 调用点的覆盖如下：

| Material | 数量 | Surface |
| --- | ---: | --- |
| `panel` | 11 | TopBar、BatteryPopup、ClipboardPopup、ControlCenter、FanPopup、LeftSidebar、NotificationCenter、SettingsPanel、Spotlight、WifiPopup、WindowOverview |
| `pill` | 1 | DynamicIslandOverlay |
| `launcher` | 0 | 保留 token，当前无生产调用点 |
| `dock` | 1 | Dock |
| `menu` | 7 | AppMenuPopup、DockAppMenu、DockWindowMenu、MenuPopup、ProcessMenu、TaskSwitcher、TrayMenu |
| `toast` | 1 | NotificationToast |
| `backdrop` | 1 | Launchpad |

普通窗口的 `background-effect` 和 7 个 layer-rule fallback（ControlCenter、NotificationCenter、LeftSidebar、BatteryPopup、WifiPopup、FanPopup、ClipboardPopup）同样保持 live framebuffer。性能预算由 R05 的 FBO 复用、R06 的 shader feature 短路和 R07 的精确 damage/commit 控制，不得再用改变视觉语义的 `xray true` 规避实时采样。

## Surface Recipes

这些 recipes 是 shell 侧 glass region 的治理集合。新增或改动时，要记录 material、region 数量、最大面积和 fallback 行为。

| Surface | Region baseline | Material | 备注 |
| --- | --- | --- | --- |
| TopBar | 1 | `panel` | 持续显示；region 跟随 inner floating bar，不覆盖整屏宽度以外区域 |
| Dock | 1 | `dock` | 持续显示；region height 限制为 visible dock 高度 |
| ControlCenter | 1 | `panel` | 大 popup；compositor layer motion 时 region geometry 固定 |
| NotificationToast | 1 | `toast` | 短时 toast；materialAlpha 跟随 toast 生命期 |
| Launchpad | 1 | `backdrop` | 全屏 backdrop；不提高 chromatic/refraction |
| Spotlight | 1 | `panel` | 输入与结果共用一个紧凑 panel region |
| MenuPopup | 1 | `menu` | 小面积 menu；清晰度优先 |
| SettingsPanel | 1 | `panel` | 大面板；region 绑定 panel surface safe area |
| DynamicIsland | 1 | `pill` | 每输出一个 Overlay PanelWindow；单一 `islandSurface` GlassPanel region；`exclusiveZone: 0`；fill/stroke 由 SettingsTheme island tokens 提供，不新增第八 material；region geometry 仅 NumberAnimation（禁止 Spring）；scene host 用 Loader，隐藏输出不实例化 expanded media/summary |

`GlassPanel` 保留每个 surface 提供的 baseline `interaction`，并用被动
`PointHandler` 把面板内左键按压合成为 `max(baseline, 1)`。该反馈只改变材质
强度，不改变 region 几何，也不会抢占子 `MouseArea` 的点击或拖拽；baseline
已经为 `1` 的 surface 不再额外叠加强度。

当前 protocol 硬上限：

- 每个 Wayland surface 最多 32 个 TahoeGlass region。
- 单 surface committed region 总面积不能超过 surface area。
- 超出 surface 几何的 region 会被拒绝，不做自动裁剪后提交。

治理预算：

- 常驻 surface：目标 1 region。
- 普通 popup/menu/toast：目标 1 region。
- 复杂 surface：最多 2 regions，必须说明为什么不能合并。
- 禁止用大量小 regions 模拟复杂 shape；优先一个 rounded rect + clip。

## Measurement Hooks

GOAL-8 起，测量必须复用现有 render path：

- `TahoeGlass::render_regions_for_layer` Tracy span：每个 layer 的 region render 聚合入口。
- `TahoeGlass::render_region` Tracy span：单个 region 的 material render 入口。
- `trace` fields：namespace、region_count、total_area、material、region area、sample_padding、blur、clip、material_alpha。
- `FramebufferEffectElement::capture_framebuffer` Tracy/GPU span：framebuffer capture 成本。
- `Blur::prepare_textures` Tracy span：blur texture 准备和重建成本。
- `Blur::render` Tracy/GPU span：blur pass 成本。
- `EffectBuffer::prepare_offscreen` 和 `creating effect offscreen texture` span：offscreen allocation/reuse 观察点。

`sample_padding` 预算来源：

- baseline lower bound: 2 logical px。
- blur enabled: `blur.offset * blur.passes`。
- refractive/lens effect: `(abs(refraction) + abs(lens-depth)) * short_edge * 2 + 4`。
- runtime clamp: `[2, 64]`。

## Change Rules

材质变更流程：

1. 记录 baseline：surface、region_count、total_area、max sample_padding、capture span、blur render span。
2. 只改一个 material 或一个 surface recipe。
3. 不默认提高 `chromatic`。
4. 不默认提高 `refraction`，除非 baseline 和调整后 capture/blur span 都在预算内。
5. 同步 `TahoeGlass.js`、`config/niri/tahoe-phase0.kdl`、`niri/niri-config/src/tahoe_glass.rs`、`NiriSettings.qml`、`niri_settings_tool.py`。
6. 运行 `test_tahoe_material_governance.py` 和 niri config validation。

Fallback rule：`background-effect` fallback block 只服务没有 TahoeGlass region 的路径，必须保持与对应 material profile 同步。

## GOAL-8 Baseline

本 gate 没有提高默认材质强度。当前 baseline 是 source-level + instrumentation baseline：

- Material token set unchanged: `panel`, `pill`, `launcher`, `dock`, `menu`, `toast`, `backdrop`。
- Default `chromatic` remains `0.0` for every material。
- Default `refraction` remains unchanged。
- Existing TahoeGlass region recipes stay at 1 region for every production surface。
- Runtime measurement hooks now expose region count, area, sample padding, framebuffer capture, and blur render spans for live DRM/TTY capture。

调整建议：先采集 TopBar、ControlCenter、Launchpad、Spotlight、Dock 的 DRM/TTY Tracy capture，再考虑只调整 `edge-highlight` 或 `inner-shadow`。在没有 capture 前，不调整 `refraction`、`chromatic` 或 global blur。
