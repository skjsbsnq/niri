# T08 · Dock 启动弹跳 + autohide 手感 · 验收记录

日期：2026-07-11

## 实现范围

### 1. Launching 状态机（`Dock.qml` pinned 图标）

- `property bool launching`：冷启动后为真，直到窗口出现或超时。
- **抛物线循环弹跳**（`SequentialAnimation` 无限循环）：
  - 高度 = `Motion.dockLaunchBounceHeight(iconSize)` ≈ `0.7 × 56 = 39.2px`
  - 周期 = `Motion.dockLaunchBouncePeriodMs = 550`（上 275ms InQuad / 下 275ms OutQuad）
  - 驱动 `bounceOffset`（与单击弹跳共用，避免双属性冲突）
- **终止条件**：
  - `onRunningChanged` → `appHasRunningWindow` 为真时 `stopLaunchBounce()`
  - `launchBounceTimeout` 10s（`Motion.dockLaunchBounceTimeoutMs`）
  - `Component.onDestruction` 清理
- **连点不叠加**：`startLaunchBounce()` 在 `launching` 时直接 return；`onClicked` 分支：
  - 未运行且未 launching → startLaunchBounce + launch
  - 已 launching → 只 launch，不叠动画
  - 已运行 → 单次 `bounce()` + launch（激活既有窗口路径）
- **reduced profile**：不进循环，退化为一次 `bounce()`
- 单击 bounce 改用 `Motion.springBouncy`（去掉硬编码 spring:380）

### 2. Autohide 弹簧化 + reveal 消抖

- `dockSlideOffset` 不再用 `Behavior + NumberAnimation 190ms`
- 改为 **显式 dual-branch**（`useSpring` 门控 + reduced 走 ease）：
  - spring：`Motion.springSmooth`（spring 3.0 / damping 0.40，近临界，无过冲）
  - ease：190ms `emphasizedDecel`
- 目标：`dockSlideTarget = dockVisualHidden ? Motion.dockAutohideSlidePx(88) : 0`
- **reveal 消抖 150ms**（`Motion.dockRevealDebounceMs`）：
  - 仅在「autohide 开 + 当前完全收起 + 首次 edge enter」路径 debounce
  - 已 hover / 指针已在 surface 上（`updateDockHover`）立即 reveal，不抖
  - `scheduleDockHoverReset` / `resetDockHover` 会 cancel debounce timer
- 玻璃 region 几何仍只跟 `dockVisibleHeight` 裁剪，弹簧只驱动 content `Translate.y`（红线 §2.1 合规）

### 3. 运行指示点 2px 辉光

- pinned `runningDot` + `WindowButton` 指示点：中心对齐 sibling `width+4 / height+4` 半透明 halo（**不引入 GraphicalEffects**）
- launching 期间指示点也显示（稍淡），窗口出现后切 running 色

### 4. Motion.js token 出口

| token | 值 |
| --- | --- |
| `dockLaunchBounceHeightFactor` | 0.7 |
| `dockLaunchBouncePeriodMs` | 550 |
| `dockLaunchBounceTimeoutMs` | 10000 |
| `dockRevealDebounceMs` | 150 |
| `dockAutohideSlidePx` | 88 |
| `dockLaunchBounceHeight(iconSizePx)` | helper |

### 5. 治理测试

`test_motion_token_convergence.py` 新增：
- `test_motion_exports_dock_launch_and_autohide_tokens`
- `test_dock_launch_bounce_and_autohide_spring`

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，90 passed**（+2 相对 T07 的 88） |
| quickshell 冒烟（`timeout 12s qs -p tahoe-shell`） | PASS，`Configuration Loaded`；**interceptor=0**；**Binding loop=0**；无 Dock/WindowButton QML 错误 |
| `git diff --check` | 提交前再跑 |

### 机械验证

```
rg -n 'function startLaunchBounce|launchBounceLoop|dockRevealDebounceMs|Motion.springSmooth' tahoe-shell/components/Dock.qml
→ 命中

rg -n 'Behavior on dockSlideOffset' tahoe-shell/components/Dock.qml
→ 无匹配

rg -n 'dockLaunchBounce|dockRevealDebounce|dockAutohideSlide' tahoe-shell/components/Motion.js
→ 命中

rg -n 'parent.width \+ 4' tahoe-shell/components/{Dock,WindowButton}.qml
→ 两处辉光命中
```

## 手测 / 行为说明

- 冷启慢应用：图标抛物线循环跳，首窗出现即停；10s 无窗也停。
- 连点：不叠加第二套动画；已 launching 再点只 re-launch。
- 已运行应用：单击仍是单次 bounce（springBouncy settle）。
- reduced：启动无循环，一次 hop。
- autohide：收起/展开 springSmooth；快速扫过 reveal 区 150ms 内不抖开；指针进表面立即展开。
- 运行点：running / launching 可见 + 2px 晕。

## 性能

| 进程 | T00 RSS | 当前 RSS | 备注 |
| --- | --- | --- | --- |
| niri | 211,844 KB ≈ 206.9 MB | 210,256 KB ≈ 205.3 MB | 与 T07 同级，略降 |
| quickshell（部署副本） | 584,292 KB ≈ 570.6 MB | 583,252 KB ≈ 569.6 MB | 部署副本未加载 T08 源；冒烟第二实例已退出 |

动画仍走 Animation 框架（SequentialAnimation / SpringAnimation），无 per-frame JS Timer 驱动弹跳帧。

## 红线自查

- 玻璃 region 几何未弹簧（仅 content Translate.y + dockVisibleHeight 裁剪）✓
- `useSpring` 双分支保留（slide / bounce settle）✓
- 未新建 token 文件 / 未直写 KDL / 未动 quickshell C++ ✓
- reduced + useSpring=false 路径同提交完成 ✓

## 基线警告（非 T08 引入）

- `shell.qml:479` font 只读 TypeError
- `StartupPage.qml:358` `addCandidateRow` ReferenceError
- 第二实例 portal 注册失败

## 发现待办

- 部署副本 `~/.config/quickshell/tahoe` 需用户侧同步/重启 shell 才能看到 T08。
- WindowButton 单击 bounce 仍是单次 hop（非 launching 循环）——正确，窗口半区不冷启应用。
- 若后续要 Launchpad 格子也有启动弹跳，归 Launchpad 任务（T18）而非本任务。

## 结论

T08 清单 100% 落地，验收通过，可 commit + push。
