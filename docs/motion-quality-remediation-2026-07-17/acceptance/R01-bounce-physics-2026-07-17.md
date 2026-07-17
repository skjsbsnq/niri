# R01 · 弹跳物理统一 · 2026-07-17

覆盖问题：#74（DockMinimizedWindow 死 bounce）、#75（点击 bounce 上行瞬跳）。

## 改动摘要

- **Motion.js**：新增单一 token 族 `dockClickBounceHeightPx=14 / dockClickBounceShelfHeightPx=8 / dockClickBounceUpMs=90 / dockClickBounceDownMs=220`，三处魔法数（14/8/16ms Timer/170ms/220ms）全部收敛。
- **DockMinimizedWindow.qml**（#74）：废除"16ms Timer 归零 + 170ms Behavior"结构（原 :101-104,248-259），改为显式上行 90ms InQuad NumberAnimation（`onFinished` 交给下行）+ 下行 springBouncy/eased 双分支（`useSpring` 门控，经 DockMinimizedShelf 从 Dock 转发）。弹跳肉眼可见完整。
- **Dock.qml 固定图标 / WindowButton.qml**（#75）：`bounceOffset = 14` 瞬跳改为 90ms InQuad 上行动画；下行维持 springBouncy/ease 双分支；16ms bounceTimer 删除，start/stopLaunchBounce 的 `bounceTimer.stop()` 同步改 `bounceUp.stop()`。
- 上行曲线 InQuad 与 T08 启动弹跳循环（InQuad 上/OutQuad 下）对齐，三处物理一致。
- **明确不做**（按计划）：三处代码结构未合并，仅统一物理与 token。

## 审查（/code-review，2 个独立审查 agent，逐 diff）

发现并已修复：
1. **reduced-motion 下行走 spring 分支**（三处）：reduced 分支原调 `animateBounceTo(0)`，在 `useSpring=true` 时会给 reduced 用户弹簧过冲。→ 改为 reduced 分支直接 `bounceEase` 归零（单跳：瞬时上 + eased 下）。
2. **`from: 0` 快速连点向下瞬跳**（三处）：下行进行中再点击会把 offset 瞬间拉回 0 再上行。→ 删除 `from: 0`，上行从当前值出发。
3. **新 token 缺收敛测试**：补 `test_motion_exports_dock_click_bounce_tokens` + `test_dock_click_bounce_sites_use_tokens`（断言 token 存在、三现场引用、魔法数归零）。

记录不修（评审结论）：
- reduced 下行仍 220ms eased —— 计划允许"降级为单跳"，单跳=瞬时上+eased settle，符合验收；未接 0 时长。
- `bounce()` 中 `launching` 早退后 `launchBounceLoop.stop()` 顺序为既有代码，行为正确（launching 期间点击不打断启动循环）。
- springBouncy 下行过冲可短暂 <0：bounceOffset 仅喂 `Translate y` 内容变换与 updateDockRectangle 补偿项（点击前采样），不喂玻璃 region —— 红线无涉。latent 耦合已在源码注释中有说明，不扩项。

## 审查清单过检

- 范围：仅 5 文件（3 现场 + Motion.js token + Shelf 转发 + 收敛测试），无越界。
- 红线：`bounceOffset` 只驱动 previewFrame/icon 的 Translate，不进 GlassPanel/region 路径；`check-tahoe-glass-guardrails.sh` passed。
- 无平行接口：token 只进 Motion.js；无新旧机制并存（`grep bounceTimer` 三文件=0，`bounceOffset = 14|8` =0）。
- 全状态：reduced（单跳）、`useSpring=false`（eased 下行）路径显式存在；深浅色无涉。
- 绑定安全：`Behavior on bounceOffset` 已删，bounceUp/bounceSpring/bounceEase 互斥（每次 bounce() 先 stop 全部），无双驱动。

## 验收

- `pytest tests/ -q` → **749 passed, 217 subtests**（新增 2 测试）。
- 嵌套会话冒烟：QML 零错误、glass region commit 正常（108 次）。日志 /tmp/r01-nested-smoke.log。
- 手测矩阵（嵌套会话环境限制，肉眼弹跳一致性留待宿主会话确认）：逻辑路径已由测试+冒烟覆盖；**待办：宿主会话点击 dock 图标/窗口按钮/最小化缩略图目测三处弹跳一致**。

## 范围外发现

无新增。
