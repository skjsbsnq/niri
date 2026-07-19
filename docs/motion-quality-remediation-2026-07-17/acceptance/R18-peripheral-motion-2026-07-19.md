# R18 - Peripheral motion - 2026-07-19

覆盖问题：#51 #52 #60 #61 #62 #63 #64 #65 #70 #71 #87 #88 #91 #92 #93 #94。

## 实施摘要

- TopBar 角标改为守卫式生命周期，补入场/退场 opacity+scale；按钮底色、workspace/niri hover 和电池填充统一接入 eased `Behavior`/`ColorAnimation`。
- SettingsPanel 标题、副标题与正文共用 `pageHost` 的双层 progress；返回/刷新按钮保留退场实例并淡出。快速重定向保存两层当前 opacity，避免目标页回跳到 1。
- LeftSidebar 子页互补 crossfade，标签颜色平滑过渡；天气刷新图标使用共享 IconButton 的可选旋转，温度条、内容/空态、状态横幅均有生命周期过渡。
- WeatherBackground 的天空 palette 使用 ColorAnimation；MeteoIcon 使用两层 glyph crossfade，并在连续状态变化时保存当前可见权重。
- Tray 改为稳定 `modelKey` 的 ListView，补 add/remove/move/displaced、hover、根容器收放和 press/lifecycle 输出分离。
- Spotlight 保持 R15 的 compositor close ownership（`visible: open`），只补结果行 hover/move 过渡，避免 QML/KDL 双重关闭动画。
- Wallpaper 静态层保留 zoom+dim；动态 wallpaperengine 是独立 background layer，新增短生命周期 Bottom overlay 提供同样的 dim，不重启/暂停动态进程。

## 审查

- 首轮独立审查发现并修复：
  - `SettingsPanel.qml` 快速重定向时 outgoing/incoming opacity 会瞬时回到 1；改为保存 `layerOpacity()` 的当前权重后再 retarget。
  - `MeteoIcon.qml` 连续 glyph 切换时 outgoing 层会瞬时变亮；改为保存两层当前 opacity 并从主可见层继续。
  - Wallpaper 合同测试曾以全文匹配误把静态 zoom 当成动态 zoom；测试已拆分 staticLayer 与 live overlay 的断言。
- 第二轮独立逐 diff 复审结论：**CLEAN**。未发现新的 P0-P2 bug、QML 双驱动、列表 identity 回归或 Spotlight ownership 回归。

## 自动验收

- `python3 -m unittest tahoe-shell/tests/test_r18_peripheral_motion.py` -> **8 tests OK**。
- `/usr/lib/qt6/bin/qmllint --signal-handler-parameters disable -I quickshell/build-tahoe/qml_modules` 对 10 个变更 QML 文件 -> **退出码 0**；输出仅为现有 Quickshell/TahoeGlass qmltypes 与 unqualified/import warning，无新增语法错误。
- `git diff --check` -> 通过。
- `pytest -q` -> **811 passed, 234 subtests passed in 41.84s**。

## 运行期/手测矩阵

本环境没有可复用的完整 Wayland 人工输入会话；以下由生产源码生命周期、offscreen QML 测试和既有 Motion profile 合同覆盖，未把截图/指针手感伪记为实机结果。

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 开/关与最后一项退出 | [x] | guard-visible + opacity/height contracts；全量测试 |
| 快速连续切换/重入 | [x] | SettingsPanel/MeteoIcon continuity contracts；独立复审 |
| Esc/点外关闭 | [x] | Spotlight 保持 compositor ownership；R15 edge/ownership tests |
| 深色/浅色 palette | [x] | TopBar/WeatherBackground ColorAnimation contracts |
| reduced profile | [x] | Motion.reducedMotion 分支与共享控件合同 |
| `useSpring=false` 回退 | [x] | eased-only region/width path；全量治理测试 |

## 二选一决策与边界

- **#87：维持 R15 合成器方案。** Spotlight 继续 `visible: open`，由 KDL 对称 `scale-from/scale-to` 负责 map/unmap；不引入 QML 外层 opacity/scale 双驱动。
- **#94：在现有独立 layer 架构下采用“静态 zoom+dim、动态 dim”方案。** `linux-wallpaperengine` surface 不属于 Wallpaper.qml 的 Item 树，QML 或现有 layer-rule 无法在 launchpad 状态变化时对其做运行时几何 transform；新增 overlay 只承担可证明安全的 dim，并保持 direct-scanout 恢复和进程不重启。动态画面真实 zoom 若仍需实现，必须先提供 compositor surface transform 或把 renderer 嵌入可变换的 Item。

## 范围外发现/待办

- 动态 wallpaperengine 的几何 zoom 需要独立的 compositor/renderer 能力，不在本任务中伪造；当前已将限制、测试边界和生命周期行为落盘。
- Qt6 qmllint 的既有 unresolved PanelWindow/TahoeGlass 警告仍来自本地 qmltypes，不是 R18 新增；真实 Wayland 视觉截图与 direct-scanout 瞬时恢复留给有完整会话的视觉基线流程。
