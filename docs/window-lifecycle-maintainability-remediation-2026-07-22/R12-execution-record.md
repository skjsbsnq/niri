# 任务：R12 / immutable `ResolvedEffectPlan`

待审状态：Author verification complete
开始基线：外层 `44e5793` / niri `6b6adcb3` / quickshell `8b71640`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/render_helpers/resolved_effect_plan.rs` | **新建**：不可变 plan 构建与 CPU golden 测试 |
| `src/render_helpers/background_effect.rs` | `BackgroundEffect` 仅持 damage/GPU；`render(&plan)`；删除 `update_config` / `update_render_elements` 可变 options owner |
| `src/render_helpers/tahoe_glass.rs` | region 路径使用同一 `ResolvedEffectPlan::build` |
| `src/render_helpers/mod.rs` | 注册模块 |

### 外层

| 路径 | 作用 |
| --- | --- |
| `docs/.../R12-execution-record.md` | 本记录 |

Owner：

- **Plan builder**（`ResolvedEffectPlan::build` / `resolve_options`）：唯一决定 blur on、xray 默认、noise/saturation fallback、clip 圆角 fit。
- **BackgroundEffect**：damage + `FramebufferEffect` 资源；`note_plan_visual` 指纹损坏；`render` 只读 plan。
- **未**创建 glass-v2 renderer；window/layer tile 与 Tahoe region 共用 plan 语义。

## 目标设计落地

```text
blur_config + BackgroundEffect material + has_blur_region + corner_radius + RenderParams
        │
        ▼
ResolvedEffectPlan::build  (pure, once)
  · options (blur/xray/noise/sat/glass)
  · noise/saturation fully resolved f32
  · blur_options kernel | None
  · clip radius expanded+fit inside params
        │
        ▼
BackgroundEffect::note_plan_visual(key)  // damage only
BackgroundEffect::render(&plan)          // no fallbacks
  ├─ xray path
  └─ FramebufferEffect non-xray path
```

## 旧路径删除

```text
rg -n 'fn update_config|fn update_render_elements' niri/src/render_helpers/background_effect.rs
rg -n 'background_effect\.update_config|update_render_elements\(' niri/src/render_helpers
```

作者验证：

1. `BackgroundEffect` 上 **无** `update_config` / `update_render_elements`。
2. `render()` **不**再从 `self.blur_config` / `self.options` / `self.corner_radius` 取默认或改写 clip。
3. tahoe_glass 与 `render_for_tile` 均走 `ResolvedEffectPlan::build`。

## 行为契约

- 配置语法未改；视觉规则与迁移前一致（xray 默认、blur region 默认 blur on、noise/sat fallback、clip fit）。
- visible geometry vs sample padding vs draw_clip 仍由 `RenderParams` 区分；Tahoe sample 扩展逻辑未并入 plan builder（仍在 tahoe_glass 构造 `params` 时完成）。
- shadow 仍独立于 background plan（本任务不收敛 shadow owner）。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo test -p niri --lib -- resolved_effect_plan background_effect tahoe_glass)` | 42 passed |
| `(cd niri && cargo fmt --all)` | 已格式化 |

未运行：完整 `cargo test -p niri`（时间）；GPU shader pixel golden（用 CPU plan golden + 既有 tahoe/clip 单测替代）。

## 独立审查专属问题（作者自查）

1. plan 是否真正 immutable？**是**；构建后 `render` 只读；可变状态仅 damage 指纹。
2. window/layer/Tahoe 是否同一语义？**是**；同一 `build`/`resolve_options`。
3. visible/sample/draw clip 是否区分？**是**；params 字段保留；Tahoe sample 仍在 builder 外写入 geometry。
4. 视觉参数是否无意变化？**规则复刻**；golden 覆盖 noise/sat/xray/radius/glass。
