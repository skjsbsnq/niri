# GOAL-1 验收：motion source of truth

日期：2026-07-06

范围：定义 Tahoe motion profile 的来源、映射表和不可表达能力。不修改运行时行为，不新增配置源。

## 完成了什么

- 定义了第一版 motion profile 表：`fast`, `balanced`, `liquid`, `reduced`。
- 明确 compositor layer animation 的 source of truth 是 `config/niri/tahoe-phase0.kdl` 中现有 `layer-rule animations`。
- 明确 QML 内部 motion vocabulary 继续复用 `Motion.js` 和 `DynamicIslandMotion.js`。
- 明确当前设置链路 `NiriSettings.qml` / `niri_settings_tool.py` 只能写四组 spring 参数；layer-rule profile 写入留到 GOAL-5 扩展同一链路。
- 列出 profile 到 KDL 字段、QML token、settings writer 的映射关系。
- 列出当前不可表达能力，作为 GOAL-2 到 GOAL-6 的输入。

## Source Of Truth 决策

| 领域 | Source of truth | 当前写入状态 | GOAL-1 决策 |
| --- | --- | --- | --- |
| compositor window/spring animation | `config/niri/tahoe-phase0.kdl` top-level `animations` | `NiriSettings.qml` -> `niri_settings_tool.py` 可写 `workspace-switch`, `window-movement`, `window-resize`, `overview-open-close` 的 spring params | 保持现有设置链路 |
| compositor layer open/close animation | `config/niri/tahoe-phase0.kdl` `layer-rule { animations { layer-open/layer-close } }` | Rust parser/runtime 已支持；settings writer 尚未暴露 | GOAL-5 只能扩展现有 writer，不新增 KDL writer |
| QML internal micro motion | `tahoe-shell/components/Motion.js` | 常量 token；部分组件已经使用，仍有硬编码 | GOAL-4 收敛到该文件，不新增 token 文件 |
| Dynamic Island motion | `tahoe-shell/components/DynamicIslandMotion.js` | 常量 token；Dynamic Island 专属 | 保持专属文件，不把通用 panel/popup token 塞进去 |
| profile 选择状态 | 尚无 runtime profile source | 不新增 profile JSON / daemon | GOAL-5 必须挂到现有 `NiriSettings.qml` / `niri_settings_tool.py` 和现有 shell settings 链路 |
| compatibility switch | `DesktopSettings.compositorLayerAnimations` | 已存在，只控制 QML 是否让出外层 motion | 不把它升级成 profile source |

## Motion Profile 表

这些 profile 是映射规范，不是新配置文件。实际应用时必须写入现有 KDL 字段和现有 QML token，不能引入第二套配置源。

| Profile | 目标体感 | Panel open/close | Small popup open/close | Spotlight open/close | Toast open/close | QML token target |
| --- | --- | --- | --- | --- | --- | --- |
| `fast` | 更短反馈、低等待 | edge reveal, open `170/80ms`, close transform `140ms`, close opacity `0ms` | edge reveal, open `140/70ms`, close transform `110ms`, close opacity `0ms` | popin `140/80ms`, popout `90/60ms` | slide `140/80ms`, close `90/60ms` | `fadeFast=90`, `menuEnter=120`, `menuExit=90`, `panelEnter=150`, `panelExit=110`, `elementMove=110`, `elementResize=140` |
| `balanced` | 当前默认候选 | current KDL: top panels open `210/100-110ms`, close transform `210ms`, close opacity `0ms` | current KDL: open `180/90ms`, close transform `180ms`, close opacity `0ms` | current KDL: popin `180/120ms`, popout `110/80ms` | current KDL: slide `180/100ms`, close `110/80ms` | current `Motion.js`: `120/150/120/180/140/130/180` |
| `liquid` | 更长空间运动、保留快速透明度 | edge reveal, open `240/130ms`, close transform `210ms`, close opacity `0ms` | edge reveal, open `210/110ms`, close transform `170ms`, close opacity `0ms` | popin `220/130ms`, popout `150/90ms` | slide `220/120ms`, close `150/90ms` | `fadeFast=140`, `menuEnter=170`, `menuExit=140`, `panelEnter=210`, `panelExit=160`, `elementMove=150`, `elementResize=210` |
| `reduced` | 最少空间位移，保留必要可见性 | prefer `fade`, transform `0ms`, opacity `80ms`; or current style with transform `0ms` when style swap is unsafe | prefer `fade`, transform `0ms`, opacity `70ms` | fade/pop with transform `0ms`, opacity `80/60ms` | fade/slide with transform `0ms`, opacity `80/60ms` | `fadeFast=70`, layout-affecting move/resize tokens `0` where safe; content opacity max `80` |

Spring profile mapping, using existing top-level `animations` spring fields:

| Profile | `workspace-switch` | `window-movement` | `window-resize` | `overview-open-close` |
| --- | --- | --- | --- | --- |
| `fast` | damping `1.0`, stiffness `860`, epsilon `0.0001` | damping `0.9`, stiffness `700`, epsilon `0.001` | damping `1.0`, stiffness `760`, epsilon `0.0005` | damping `0.98`, stiffness `820`, epsilon `0.0005` |
| `balanced` | current `1.0 / 780 / 0.0001` | current `0.86 / 620 / 0.001` | current `0.96 / 700 / 0.0005` | current `0.95 / 760 / 0.0005` |
| `liquid` | damping `0.92`, stiffness `680`, epsilon `0.0001` | damping `0.82`, stiffness `560`, epsilon `0.001` | damping `0.92`, stiffness `620`, epsilon `0.0005` | damping `0.9`, stiffness `680`, epsilon `0.0005` |
| `reduced` | prefer `animations off` if whole-profile reduce is selected; otherwise damping `1.0`, stiffness `1000`, epsilon `0.001` | same | same | same |

## KDL Layer Animation 字段映射

| KDL field | Applies to | Existing parser/runtime | Profile owner |
| --- | --- | --- | --- |
| `layer-rule match namespace="^tahoe-...$"` | surface selection | `niri-config/src/layer_rule.rs` -> `LayerRule.animations` | KDL |
| `animations { layer-open {} layer-close {} }` | per-rule layer motion | existing parser/runtime | KDL |
| `style` | open: `fade`, `popin`, `slide`, `edge-reveal`; close: `fade`, `popout`, `slide`, `edge-reveal` | existing parser/runtime | profile table -> KDL |
| `duration-ms` / `curve` | compatibility baseline for both channels | existing parser/runtime | only when split channel fields are absent |
| `transform-duration-ms` / `transform-curve` | spatial channel | existing parser/runtime | profile table -> KDL |
| `opacity-duration-ms` / `opacity-curve` | alpha channel | existing parser/runtime | profile table -> KDL |
| `opacity-delay-ms` | alpha delay | existing parser/runtime | optional; not used in current Tahoe KDL |
| `scale-from` / `scale-to` | popin/popout scale | existing parser/runtime | profile table -> KDL |
| `opacity-from` / `opacity-to` | open/close alpha endpoints | existing parser/runtime | profile table -> KDL |
| `origin` | `center` or layer-shell `anchor` origin | existing parser/runtime | profile table -> KDL |
| `edge` | edge for slide/edge-reveal | existing parser/runtime | profile table -> KDL |
| `distance` | slide distance; parsed for edge-reveal but not used by current edge-reveal offset | parser exists; runtime gap for edge-reveal | GOAL-6 input |

Current namespace groups:

| Group | Namespaces | Current profile family |
| --- | --- | --- |
| Top panels | `tahoe-control-center`, `tahoe-notification-center` | panel edge reveal |
| Left Sidebar | `tahoe-left-sidebar` | left edge reveal, no opacity fade |
| Spotlight | `tahoe-spotlight` | center popin/popout |
| Small top popups | `tahoe-battery-popup`, `tahoe-wifi-popup`, `tahoe-fan-popup`, `tahoe-clipboard-popup`, `tahoe-menu-popup`, `tahoe-application-menu`, `tahoe-tray-menu` | small edge reveal |
| Dock menus | `tahoe-dock-app-menu`, `tahoe-dock-window-menu` | bottom edge reveal |
| Process menu | `tahoe-process-menu` | tight popin/popout |
| Toast | `tahoe-notification-toast` | right slide |
| Not compositor-driven | `tahoe-dock`, `tahoe-task-switcher`, `tahoe-window-overview`, `tahoe-launchpad` | QML path |

## QML Token 映射

| QML token | Current value | Target use | Closest KDL concept |
| --- | ---: | --- | --- |
| `Motion.fadeFastDuration` | `120` | material/content opacity fades | opacity duration |
| `Motion.menuEnterDuration` | `150` | small menu internal enter | small popup transform duration |
| `Motion.menuExitDuration` | `120` | small menu internal exit | small popup close transform duration |
| `Motion.panelEnterDuration` | `180` | panel/toast/spotlight material or x enter | panel transform duration |
| `Motion.panelExitDuration` | `140` | panel content exit | panel close transform duration |
| `Motion.elementMoveDuration` | `130` | list/row x movement | internal micro move |
| `Motion.elementResizeDuration` | `180` | expandable height/size changes | internal resize |
| `Motion.emphasizedDecel` | `QtQuick.Easing.OutCubic` | enter/move | approximates KDL `emphasized-decel`; not exact |
| `Motion.emphasizedAccel` | `QtQuick.Easing.InCubic` | exit | approximates KDL `emphasized-accel`; not exact |
| `Motion.standardDecel` | `QtQuick.Easing.OutQuad` | opacity/content decel | approximates KDL `standard-decel`; not exact |
| `Motion.expressiveEffects` | `QtQuick.Easing.OutQuart` | richer QML-only effects | approximates KDL `expressive-effects`; not exact |
| `DynamicIslandMotion.*` | multiple | Dynamic Island chip/overlay only | separate vocabulary; do not merge into panel profile yet |

Current QML profile application boundary:

- Components must import and use `Motion.js` or `DynamicIslandMotion.js`.
- Components must not define local motion token files.
- Components must not write niri KDL directly.
- GOAL-4 should migrate hardcoded component values to these existing token files.
- GOAL-5 can only make profile write/apply real by extending existing settings services and helper script.

## 不可表达能力清单

| Gap | Evidence | Future gate |
| --- | --- | --- |
| Settings writer cannot write `layer-rule animations` yet | `niri_settings_tool.py` only whitelists four spring actions under `animations.*` | GOAL-5 |
| QML token values are constants, not runtime profile state | `Motion.js` and `DynamicIslandMotion.js` are `.pragma library` constants | GOAL-4/GOAL-5 |
| QML easing tokens are approximations, not exact KDL cubic-bezier names | `Motion.js` uses Qt enum easing; KDL named curves parse to explicit cubic-bezier values | GOAL-3/GOAL-4 |
| `edge-reveal distance` is misleading | runtime edge reveal uses full surface width/height, not configured short `distance` | GOAL-6 |
| Dynamic button origin for topbar popup is not expressible in niri | compositor only has `origin center/anchor`; QML knows exact button rect | GOAL-2/GOAL-7 |
| Current IPC cannot trigger Control Center, Notification Center, Small Popup, Spotlight repeatably | GOAL-0 trigger matrix | GOAL-2 |
| No live IPC exposes committed TahoeGlass region count/area | `niri msg --json layers` only returns namespace/layer/interactivity | GOAL-8 |
| No curve/spring preview UI exists | settings page exposes raw spring sliders only | GOAL-3 |

## 没有做什么

- 没有改 KDL profile values.
- 没有改 `Motion.js` or `DynamicIslandMotion.js`.
- 没有扩展 `NiriSettings.qml` or `niri_settings_tool.py`.
- 没有新增 profile JSON, daemon, protocol, KDL writer, or QML token file.
- 没有开始 GOAL-2 trigger implementation.

## 复用了哪些现有接口

- `niri/niri-config/src/animations.rs`
- `niri/niri-config/src/layer_rule.rs`
- `config/niri/tahoe-phase0.kdl`
- `tahoe-shell/components/Motion.js`
- `tahoe-shell/components/DynamicIslandMotion.js`
- `tahoe-shell/services/NiriSettings.qml`
- `tahoe-shell/services/niri_settings_tool.py`
- `tahoe-shell/services/DesktopSettings.qml`

## 是否新增接口

没有新增接口。Profile 表是设计映射，不是 runtime 配置源。

## 运行命令

```text
sed -n '1,260p' niri/niri-config/src/animations.rs
sed -n '540,790p' niri/niri-config/src/animations.rs
sed -n '1,120p' niri/niri-config/src/layer_rule.rs
sed -n '760,1090p' tahoe-shell/services/niri_settings_tool.py
sed -n '320,360p' tahoe-shell/services/NiriSettings.qml
rg -n "LayerOpenAnim|LayerCloseAnim|transform-duration-ms|opacity-duration-ms|style|edge-reveal" niri/niri-config/src niri/src/layer niri/src/tests
rg -n "emphasized-decel|emphasized-accel|standard-decel|menu-accel|curve" niri/niri-config/src config/niri/tahoe-phase0.kdl docs/layer-animation-motion-v2-roadmap.md
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
git diff --check
```

## 剩余风险

- The numeric profile values are a first mapping spec, not visual validation. GOAL-5/GOAL-7/GOAL-8 must validate before any default decision.
- `reduced` needs careful implementation because global `animations off` and per-layer zero-duration fields have different scope.
- QML exact cubic-bezier parity may require using Qt bezier easing or accepting documented approximation.
- Profile persistence must not become a second source of truth; GOAL-5 must choose one existing settings path.

## 回滚方式

This gate adds only this acceptance document and updates the GOAL-1 status row in the goal document. Rollback is deleting this file and reverting that status row.

