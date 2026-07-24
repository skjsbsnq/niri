# R17 验收：lifecycle/foreign/glass 定向 redraw

日期：2026-07-24  
前置：R15 GO（foreign/lifecycle）；glass mapped 已 R14 targeted

## 1. 前后对照

| 场景 | R15 | R17 |
| --- | --- | --- |
| dual-output foreign minimize（attribution 路径） | queue_redraw_all≥1，Queued 2/2，waste=0.50 | Queued **1/2** home，other Idle，waste=**0** |
| foreign maximize adapter | queue_redraw_all≥1 | `RedrawReason::Maximize` targeted |
| foreign activate | queue_redraw_all | `RedrawReason::Activate` targeted |
| glass mapped commit | targeted（R14） | 经 `apply_redraw_attribution`，行为不变 |
| glass unlocatable | queue_redraw_all | `RedrawFallbackReason::Unlocatable` + counter |
| set_rectangle | 无 redraw（缓存） | 仍无 cluster attribution |

## 2. 删除证明

| 检查 | 结果 |
| --- | --- |
| `ForeignToplevelHandler` 块内 `queue_redraw_all` | **0**（自动化源码测试） |
| xdg `minimize_request` / IPC Minimize\|Restore | 仅 `apply_redraw_attribution` |
| 平行 redraw API / 改名伪装 | **无** |
| glass 第二 handler | **无**（R14 单一 handler） |

## 3. 样本摘录（headless）

```text
R17_SAMPLE kind=foreign_minimize_targeted queued=1 total=2
  queue_redraw_all=0 queue_redraw=1 targeted_lifecycle=1
  home_queued=true other_queued=false

R17_SAMPLE kind=restore_cross_focus outputs=2
  names=["headless-1", "headless-2"]

R17_SAMPLE kind=foreign_maximize_targeted
  targeted_maximize=1
```

## 4. 残余全局重绘（cluster 外，已审查列出）

| 路径 | reason 性质 |
| --- | --- |
| `refresh_pointer_contents` | pointer 内容变化；FIXME granular；非 lifecycle adapter |
| glass unlocatable | `RedrawFallbackReason::Unlocatable`（cluster 内合法 fallback） |
| ext_workspace activate / cursor / dnd 等 | 非本任务 cluster |

## 5. 测试矩阵覆盖

- 双输出 minimize/restore/maximize/activate
- 跨 focus restore 双输出 attribution
- set_rectangle 无 cluster redraw
- unlocatable fallback counter
- 既有 lifecycle / foreign_toplevel / tahoe_glass / 全 lib（455）
