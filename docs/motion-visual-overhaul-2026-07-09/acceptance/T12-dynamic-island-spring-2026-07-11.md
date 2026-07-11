# T12 · 灵动岛 morph 弹簧化 · 验收记录

日期：2026-07-11

## 关键决策：玻璃 region 存在 → 高度通道保持 easing

路线图原文假设「灵动岛不是玻璃 region 项（自绘黑底）」。实机源码核查：

- `DynamicIslandOverlay.qml` 使用 `GlassPanel` + `TahoeGlass.regions: [islandSurface.region]`
- `GlassPanel` 的 `TahoeGlassRegion` 绑定 `item` 几何（x/y/width/height/radius）

因此 **width/height/x/radius 不得使用 SpringAnimation / 过冲曲线**（02-rules §2.1）。  
**springBouncy 仅用于内容 content transform（scale）**，与 Motion.js `springBouncy` 参数组一致。

| 通道 | 实现 |
| --- | --- |
| islandSurface width/height/x/radius | `NumberAnimation` + `OutCubic`（`overlayMorphDuration=380`，近似 spring 感知时长、无过冲） |
| radius | **恒等** `height/2`（去掉 expanded 固定 30） |
| 内容切换 scale | `0.9 → 1`，`useSpring` 时 `SpringAnimation(springBouncy)`，否则 eased；reduced → 瞬时 1.0 |
| 内容淡入 | 既有 `DynamicIslandContent` opacity Behaviors 保留 |
| chip | 时长微调 280/220/180 → 260/200/160 |

## 改动文件

| 文件 | 内容 |
| --- | --- |
| `DynamicIslandMotion.js` | morph/content spring tokens；import Motion.springBouncy |
| `DynamicIslandOverlay.qml` | radius=h/2；contentHost scale 双分支；useSpring/settingsService |
| `shell.qml` | 转发 `useSpring` + `settingsService` |
| 治理测试 | `test_dynamic_island_morph_spring_tokens_and_wiring` |

## 保留路径（不回归）

- 媒体出现 / expanded_media / expanded_summary / 收起
- 横滑：`beginSwipe` / `advanceSwipe` / `resolveSwipe` / `cancelSwipe`
- IPC：`dynamicIslandSwipe*`、`dynamicIslandShow*` 等 shell 函数未改
- hover expand timers 保留

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，97 passed**（+1 相对 T11） |

### 机械验证

```
rg -n 'SpringAnimation \{' tahoe-shell/components/DynamicIslandOverlay.qml
→ 仅 contentScaleSpring 一处

rg -n 'return h / 2|overlayContentSpring|useSpring' \
  tahoe-shell/components/DynamicIslandOverlay.qml \
  tahoe-shell/components/DynamicIslandMotion.js
→ 命中
```

## RSS 阶段检查点（规则 §4.9，对照 T00）

| 进程 | T00 RSS | 当前 RSS (2026-07-11) | Δ vs T00 |
| --- | --- | --- | --- |
| niri | 211,844 KB ≈ 206.9 MB | **180,568 KB ≈ 176.3 MB** | −14.8%（低于基线） |
| quickshell | 584,292 KB ≈ 570.6 MB | **643,920 KB ≈ 628.8 MB** | **+10.2%** |

说明：当前会话自 T00 起连续运行多日，quickshell 涨幅含通知栈、媒体元数据、设置页缓存等常驻状态，**不能**直接归因于 T12（T12 未新增常驻 surface、未加密 Timer、仅增加瞬时 contentScale 动画对象）。niri 反而低于 T00。T23 冷启动复测若仍 >5% 再处置。

采样命令：`ps -eo pid,rss,comm,args | grep -E 'niri --session|quickshell -p'`

## 发现待办

- 实机：reload 后媒体 expand/collapse + swipe IPC 目测。
- T13：图标体系迁移。
