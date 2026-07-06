# GOAL-3 验收：曲线与 spring 预览

日期：2026-07-06

范围：在现有 niri 动画设置页中增加只读曲线和 spring preview。保留现有 spring slider 写入路径，不新增独立调参应用，不新增第二套 runtime 配置源。

## 完成了什么

- 在 `tahoe-shell/components/settings/pages/NiriAnimationsPage.qml` 增加只读 `曲线预览` section。
- 曲线预览包含 Canvas 曲线图、25% / 50% / 75% 采样值、起段/中段/尾段速度估算、named curve 列表、cubic-bezier 参数展示和风险提示。
- named curve 表显式镜像 `niri/niri-config/src/animations.rs::parse_animation_curve_node` 支持的命名曲线：`linear`, `ease-out-quad`, `ease-out-cubic`, `ease-out-expo`, `emphasized-decel`, `emphasized-accel`, `standard-decel`, `expressive-effects`, `menu-decel-safe`, `menu-decel`, `menu-accel`, `stall`。
- cubic-bezier 采样语义镜像 `niri/src/animation/bezier.rs`：先对 `x(t)` 做 0..1 二分反解，再用同一 `t` 采样 `y(t)`。
- 在同一页增加只读 `Spring response` section，复用现有 `NiriSettings.animSprings` 四组 action，显示 response 曲线、reach time、settle time、overshoot 和风险提示。
- spring 响应计算镜像 `niri/src/animation/spring.rs` 的 mass=1、damping-ratio 到 damping 转换、critical/under/over damped 分支、duration 和 clamped duration 近似逻辑。
- 新增 `tahoe-shell/tests/test_motion_preview.py`，校验 QML mirrored curve table 与 niri parser table 不漂移，并校验 preview sections 不调用 `setAnimParam` / `writeField`。

## 推荐曲线使用场景

| Curve | 推荐用途 | 风险说明 |
| --- | --- | --- |
| `linear` | 常速调试或极短非空间变化 | 视觉上机械，默认不推荐 |
| `ease-out-quad` | 短 opacity / content fade | 安全 |
| `ease-out-cubic` | 兼容旧 QML decel 语义 | 安全 |
| `ease-out-expo` | 快速进入、柔和尾段 | 尾段长，避免过长 duration |
| `standard-decel` | opacity channel | 安全 |
| `emphasized-decel` | panel / surface enter transform | 当前 Tahoe 主进入曲线 |
| `emphasized-accel` | panel / surface close transform | 当前 Tahoe 主退出曲线 |
| `expressive-effects` | QML 内部 richer effects 的参考曲线 | 安全 |
| `menu-decel-safe` | small menu enter | 替代 `menu-decel` 的安全版本 |
| `menu-decel` | 兼容 end-4 旧配置 | `x2 < x1`，标记 non-monotonic x |
| `menu-accel` | menu close | 安全 |
| `stall` | 兼容/对比用 | 有 overshoot control 和 non-monotonic 风险，不做默认 |

## 没有做什么

- 没有写 KDL。
- 没有新增 curve writer、profile writer、daemon、IPC target 或独立调参 App。
- 没有改 `Motion.js` 或 `DynamicIslandMotion.js` token。
- 没有修改现有 spring slider 的 `setAnimParam` 写入行为。
- 没有 deploy/reload 当前运行中的 Quickshell；本 gate 只修改 source tree。
- 没有为任意手输 cubic-bezier 增加持久配置；当前是只读 sampler 和 named curve display。

## 复用了哪些现有接口

- `NiriAnimationsPage.qml`：继续作为 niri animation settings 的唯一 UI surface。
- `NiriSettings.qml`：继续提供 `animSprings` 当前值和现有 `setAnimParam` slider 写入接口。
- `TahoeSection` / `TahoeSegmented`：复用现有 settings controls。
- `niri/niri-config/src/animations.rs`：作为 named curve 名称和值的来源。
- `niri/src/animation/bezier.rs` 和 `niri/src/animation/spring.rs`：作为 preview 采样语义来源。

## 是否新增接口

没有新增 runtime 接口。

新增了一个 source-level test 文件 `tahoe-shell/tests/test_motion_preview.py`。原因：GOAL-3 需要在 QML 中显式镜像 niri named curve 表；测试负责防止该镜像与 niri parser table 漂移。

## 运行命令

```text
python3 tahoe-shell/tests/test_motion_preview.py
git diff --check
/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl
which qmllint qmlformat qml6 qml quickshell
timeout 5s env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 --software -f tahoe-shell/components/settings/pages/NiriAnimationsPage.qml
```

结果：

- `python3 tahoe-shell/tests/test_motion_preview.py`：2 tests passed。
- `git diff --check`：passed。
- `/home/wwt/.local/bin/niri validate --config /home/wwt/niri/config/niri/tahoe-phase0.kdl`：config is valid。
- `which ...`：`qml6` found at `/usr/bin/qml6`; `qmllint`, `qmlformat`, `qml`, and `quickshell` not found on this PATH。
- `qml6` offscreen smoke：no stderr before the expected `timeout` exit `124`; this is only a bounded load smoke, not live-shell validation。

## 剩余风险

- No live Quickshell reload/deploy was performed, so screenshots and interactive visual acceptance still belong to a later visual gate.
- `qml6` smoke does not replace `qmllint`; lint tooling was unavailable.
- The curve selector previews niri-supported curve semantics, but it does not read every current `layer-rule` curve assignment from KDL.
- The spring preview assumes the same normalized from=0 to=1, initial_velocity=0 sampling shape used for explanatory comparison; real compositor animations may start from different values.

## 回滚方式

Rollback is removing the added preview helpers/sections from `tahoe-shell/components/settings/pages/NiriAnimationsPage.qml`, deleting `tahoe-shell/tests/test_motion_preview.py`, deleting this acceptance document, and reverting the GOAL-3 status row. Existing spring sliders and KDL state do not need rollback because the preview path does not write config.
