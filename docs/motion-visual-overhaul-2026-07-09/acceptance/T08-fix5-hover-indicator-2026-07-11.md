# T08-fix5 · 波形消失 / 误隐藏 / 指示点 · 验收记录

日期：2026-07-11

## 背景

用户反馈 T08-fix4 后问题变多：
1. **图标动效没了**（鼠标滑过完全不放大跳动）；
2. **自动隐藏过快**（鼠标还在 Dock 上就收起）；
3. **指示点/条很丑**（辉光 + 粗条）。

## 根因

### 1–2 同源：子 MouseArea `onExited` 误调度 hide

图标之间移动时，当前图标 `onExited` 会 `scheduleDockHoverReset()` → 很快 `dockHovered=false` → `dockWaveActive()` 为假 → **波形归 1**；autohide 也跟着收。

表面虽有 hover 区，但子项 exit 抢先关了 hover 状态，且 hide 计时不复查「指针是否仍在玻璃上」。

### 3 指示点

T08 给 runningDot / 窗口指示加了 `parent.width+4` 半透明 halo，窗口半区还是 **16×4 粗条**，观感脏。

## 改动

| 项 | 处理 |
| --- | --- |
| 指针跟踪 | 玻璃上 `HoverHandler`（`dockSurfaceHover`）覆盖子项；`_hoverLocalX/Y` 绑定驱动波形 |
| hide 所有权 | **仅** surface HoverHandler 离开时 schedule hide；子 icon/window/tool/minimized 的 `onExited` **只清标签** |
| reset 守卫 | `resetDockHover` 若 `dockSurfaceHover.hovered` 仍为真则直接 return |
| hide 宽限 | autohide 至少 320ms（`max(320, dockHideDelay)`） |
| 指示点 | 去掉 glow；pinned 4px 圆点；窗口 3–5px 圆点（active 略大），去掉 16×4 条 |

波形解析式推挤 / 底部放大 / rest 宽 surface（fix2–4）保留。

## 验收

| 命令 | 结果 |
| --- | --- |
| pytest | **90 passed** |
| quickshell 冒烟 | Configuration Loaded；Binding loop=0；interceptor=0 |

## 手测

1. 慢/快横扫 pinned + 窗口半区：波形连续，不突然归 1。
2. 指针停在图标间距上：Dock 不收起。
3. 真正离开玻璃后：宽限到期再收（≥320ms）。
4. 运行点：小圆点、无光晕、无粗条。

## 部署

必须同步 `tahoe-shell` → `~/.config/quickshell/tahoe` 并重启 shell。

## 结论

可 `git revert` 单独回滚。
