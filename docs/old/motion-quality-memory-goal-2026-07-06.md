# Tahoe 动画质感与内存治理 Goal 文档

日期：2026-07-06

状态：执行目标文档。本文配套 `docs/motion-quality-memory-roadmap-2026-07-06.md` 使用；roadmap 负责研究与路线，本文负责目标、闸门、完成定义和串行执行顺序。

## 总目标

把 Tahoe / niri 的动画手感、曲线调参、玻璃质感、渲染性能和内存占用治理到一个可维护、可测量、可回滚的状态。

最终状态必须满足：

1. 动画手感由统一 motion profile 管理，而不是散落在 KDL、QML 和组件硬编码里。
2. 曲线和 spring 可以预览、比较、解释，调参不再靠盲试。
3. panel、popup、toast、overview 等 surface 的 open/close 行为有连续性，不闪透明、不 double fade、不残留 snapshot。
4. Glass 质感提升必须有性能预算，不靠盲目提高 blur/refraction/chromatic。
5. 内存和高频分配优化必须基于测量，优先修复明确热点。
6. 所有改动优先复用现有接口，不重复创造平行能力。

## 串行闸门

本 goal 的执行规则是强制串行：

1. `GOAL-0` 完成并通过验收后，才能开始 `GOAL-1`。
2. `GOAL-1` 完成并通过验收后，才能开始 `GOAL-2`。
3. 依此类推，直到 `GOAL-10`。
4. 当前任务未验收通过时，不允许写后续任务代码。
5. 当前任务发现路线错误时，只能先更新本文档和对应 roadmap，再继续当前任务。
6. 不允许把后续任务作为“顺手修复”塞进当前任务。

每个 goal 完成后必须新增验收文档：

```text
docs/motion-quality-memory-goalXX-acceptance-YYYY-MM-DD.md
```

验收文档必须说明：

- 完成了什么。
- 没有做什么。
- 复用了哪些现有接口。
- 是否新增接口；如果新增，为什么不能复用旧接口。
- 运行了哪些命令或做了哪些人工验收。
- 剩余风险。
- 回滚方式。

## 反腐化契约

所有 goal 必须遵守以下契约：

1. 优先复用 `NiriSettings.qml`、`niri_settings_tool.py`、`DesktopSettings.qml`、`Motion.js`、`DynamicIslandMotion.js`、`TahoeGlass.js`、`ThumbnailProvider.qml` 和现有 niri IPC。
2. 不新增第二套动画配置系统。
3. 不新增第二套 KDL 编辑工具。
4. 不新增第二套 thumbnail provider。
5. 不新增组件私有 motion token 文件。
6. 不让 QML 组件直接写 niri 配置。
7. 不把 Tahoe 专用 namespace 写进 niri Rust 逻辑。
8. 不把 read-only 状态包装成可写开关。
9. 不在没有测量基线时改变默认材质强度。
10. 不删除 fallback，除非已有单独 goal 验收。

## 完成定义

整个 goal 完成时，必须同时满足：

- `docs/motion-quality-memory-roadmap-2026-07-06.md` 中任务 0 到任务 10 均有验收记录。
- 本文 `GOAL-0` 到 `GOAL-10` 均标记为完成。
- 默认 motion profile 有数据和视觉验收支持。
- 设置页能解释和调试动画，而不是只暴露底层物理参数。
- 常用 surface 快速 toggle 不出现明显闪烁、残影或长期 repaint。
- Glass 变更通过 governance 检查。
- 内存优化有优化前后对比。
- 没有引入功能平行接口。

## GOAL-0：建立现状基线

目标：先知道当前真实状态，不做任何行为修改。

交付物：

- 当前动画触发矩阵。
- 当前 QML 硬编码动画清单。
- 当前 glass region、blur、frame time、RSS 和 thumbnail 行为记录。
- nested winit 与 DRM/TTY 差异说明。

通过标准：

- 生成 `goal00` 验收文档。
- 明确记录哪些场景无法自动触发。
- 没有修改代码和参数。

解锁：`GOAL-1`。

## GOAL-1：定义 motion source of truth

目标：先把 motion 参数归口，明确哪些参数由谁负责。

交付物：

- Motion profile 表。
- KDL layer animation 字段映射表。
- QML token 映射表。
- 不可表达能力清单。

通过标准：

- 每个 profile 都能落到现有接口。
- 没有新增配置源。
- 生成 `goal01` 验收文档。

解锁：`GOAL-2`。

## GOAL-2：补齐可重复触发入口

目标：让动画验收可以重复执行，而不是靠随机手动点击。

交付物：

- 常用 surface open/close/toggle 触发命令。
- layers 采样脚本或命令清单。
- 截图采样时间点说明。

通过标准：

- Control Center、Notification Center、Small Popup、Spotlight、Toast 至少有可重复触发路径或明确不可触发原因。
- 复用现有 shell IPC 或 shell 函数。
- 没有新增 Wayland protocol 或平行控制服务。
- 生成 `goal02` 验收文档。

解锁：`GOAL-3`。

## GOAL-3：曲线与 spring 预览

目标：让曲线可理解、可比较、可解释。

交付物：

- cubic-bezier 预览。
- spring response 预览。
- named curve 展示。
- overshoot、settle time、non-monotonic 风险提示。

通过标准：

- 预览阶段不写 KDL。
- 预览语义与 niri 实现一致。
- 没有新增独立调参应用。
- 生成 `goal03` 验收文档。

解锁：`GOAL-4`。

## GOAL-4：QML motion token 收敛

目标：减少硬编码动画，让 shell 内部微动效进入统一 vocabulary。

交付物：

- 常见硬编码 `NumberAnimation` / `ColorAnimation` 迁移到现有 token。
- 剩余例外清单。
- 视觉行为保持记录。

通过标准：

- 不新增 motion token 文件。
- 不改变组件结构。
- `rg` 结果显示硬编码动画数量下降。
- 生成 `goal04` 验收文档。

解锁：`GOAL-5`。

## GOAL-5：motion profile 写入

目标：让 profile 可以通过现有设置链路应用。

交付物：

- `NiriSettings.qml` animation mirror 扩展。
- `niri_settings_tool.py` 写入能力扩展。
- 设置页 profile 选择入口。
- profile 到 KDL/QML token 的实际应用。

通过标准：

- 不新增 KDL 写入工具。
- 不让组件直接写配置。
- profile 可应用、可热重载、可回滚。
- 生成 `goal05` 验收文档。

解锁：`GOAL-6`。

## GOAL-6：修正 edge-reveal 调参语义

目标：消除 `edge-reveal distance` 的误导。

交付物：

- 选择路径 A：保留 edge reveal 完整 retract，隐藏或解释 distance。
- 或选择路径 B：新增明确短距离样式，并保留 edge reveal 原语义。

通过标准：

- 只能选择 A 或 B，不能同时做。
- 不悄悄改变现有 edge reveal 行为。
- 相关测试和文档同步。
- 生成 `goal06` 验收文档。

解锁：`GOAL-7`。

## GOAL-7：open/close 连续性

目标：修复闪透明、double fade、快速 toggle 残影和 snapshot 接管不连续。

交付物：

- close interrupt open 连续性处理。
- open interrupt close 连续性处理。
- snapshot 生命周期验证。
- opacity 与 transform 起点一致性验证。

通过标准：

- 快速 toggle 10 次无明显残影。
- 动画结束后一帧内停止持续 repaint。
- snapshot 结束后释放。
- 生成 `goal07` 验收文档。

解锁：`GOAL-8`。

## GOAL-8：glass 性能预算与质感调整

目标：有预算地提升质感。

交付物：

- TahoeGlass region 数量、面积、sample padding、blur pass 记录。
- framebuffer capture 和 blur render 时间记录。
- 材质参数调整建议和实测结果。

通过标准：

- 先有 baseline，再有调整。
- 材质变更同步治理文档要求的 source of truth。
- 不默认提高 chromatic/refraction。
- 生成 `goal08` 验收文档。

解锁：`GOAL-9`。

## GOAL-9：内存与高频分配治理

目标：修复已测量确认的内存和高频分配问题。

交付物：

- `XrayElement::draw()` filtered damage 分配治理。
- snapshot 和 texture 生命周期检查。
- thumbnail provider cache/queue 优化。
- 优化前后 RSS 和 burst 行为对比。

通过标准：

- 不新增第二套 thumbnail provider。
- 不新增第二套缓存目录。
- 优化有测量前后对比。
- 生成 `goal09` 验收文档。

解锁：`GOAL-10`。

## GOAL-10：默认策略与回退整理

目标：在前面全部验收后，再决定默认体验和旧路径保留策略。

交付物：

- 默认 motion profile 决策。
- compositor layer animation 默认开关决策。
- fallback 保留或移除计划。
- 用户可恢复保守 profile 的路径。

通过标准：

- 不在本 goal 之前删除 fallback。
- 默认策略有数据支持。
- 用户可回退。
- 所有相关文档更新。
- 生成 `goal10` 验收文档。

## 维护状态表

| Goal | 状态 | 验收文档 |
| --- | --- | --- |
| GOAL-0 | complete | `docs/motion-quality-memory-goal00-acceptance-2026-07-06.md` |
| GOAL-1 | complete | `docs/motion-quality-memory-goal01-acceptance-2026-07-06.md` |
| GOAL-2 | complete | `docs/motion-quality-memory-goal02-acceptance-2026-07-06.md` |
| GOAL-3 | complete | `docs/motion-quality-memory-goal03-acceptance-2026-07-06.md` |
| GOAL-4 | complete | `docs/motion-quality-memory-goal04-acceptance-2026-07-06.md` |
| GOAL-5 | complete | `docs/motion-quality-memory-goal05-acceptance-2026-07-06.md` |
| GOAL-6 | complete | `docs/motion-quality-memory-goal06-acceptance-2026-07-06.md` |
| GOAL-7 | complete | `docs/motion-quality-memory-goal07-acceptance-2026-07-06.md` |
| GOAL-8 | complete | `docs/motion-quality-memory-goal08-acceptance-2026-07-06.md` |
| GOAL-9 | complete | `docs/motion-quality-memory-goal09-acceptance-2026-07-06.md` |
| GOAL-10 | complete | `docs/motion-quality-memory-goal10-acceptance-2026-07-06.md` |

状态只能按顺序从 `pending` 改为 `in-progress`，再改为 `complete`。不得跳号。
