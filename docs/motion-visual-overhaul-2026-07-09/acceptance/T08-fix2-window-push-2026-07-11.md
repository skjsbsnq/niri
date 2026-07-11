# T08-fix2 · 窗口半区推挤（图标叠影）· 验收记录

日期：2026-07-11

## 背景

T08-fix 后用户截图仍见：光标在 **运行窗口半区** 时，放大图标互相重叠（如 M / 花瓣 / 文件管理器叠在一起）。

## 根因

T07 只给 **pinned** 做了解析式推挤（显式 x/width）；窗口半区仍是 `Row` + 定宽槽，只做 `scale`/`lift`。放大后图标视觉宽度超过槽宽，于是叠影。T07 验收「发现待办」已记录此项，此前未做。

## 改动

### `Dock.qml`

- 新增 `windowItemWidthAt` / `windowItemXAt` / `windowWaveContentWidth` / `windowWaveLeftExtra` / `syncWindowViewportToCursor`（镜像 pinned）。
- `windowDisplayedWidth`：icon-only + wave 时按解析宽度扩展 viewport（预算内）。
- `dockWaveSurfaceBias` 并入窗口半区 leftExtra。
- 窗口半区容器：`Row` → `Item` + 显式 `slotXTarget`/`slotWidthTarget`。
- title 模式仍走定宽槽、不 scale/不推挤（避免文字 reflow）。
- hover 时同步 window Flickable contentX；reset 归零。

### `WindowButton.qml`

- 新增 `slotWidthTarget` / `slotXTarget`，x/width 经 `useSpring` 双分支 spring/ease 动画。
- bounce 改用 `Motion.springBouncy`（去掉硬编码 380）。
- lift 因子 16→14（对齐 Dock）。

### 治理测试

`test_dock_uses_analytical_cosine_wave_and_unified_label` 增加 window push helpers 与 `slotWidthTarget`/`slotXTarget` 断言。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，90 passed** |
| quickshell 冒烟 | PASS，`Configuration Loaded`；Binding loop=0；interceptor=0；无 Dock/WindowButton 错误 |
| 基线警告 | 既有 `shell.qml:479` / `StartupPage.qml:358` |

## 红线自查

- 玻璃 region 几何未弹簧 ✓
- useSpring 双分支 ✓
- 无 dual Behavior interceptor ✓
- 未直写 KDL / 未动 quickshell C++ ✓

## 手测

1. 光标扫过运行窗口半区：邻图标被推开，无叠影。
2. pinned 半区波形不回归。
3. 标题模式（宽屏）仍定宽、不放大。

## 部署

`~/.config/quickshell/tahoe` 需 `arch-update` 或手动 rsync 仓库 `tahoe-shell/` 后重启 shell。

## 结论

窗口半区 icon-only 与 pinned 同级解析式推挤；可 `git revert` 单独回滚。
