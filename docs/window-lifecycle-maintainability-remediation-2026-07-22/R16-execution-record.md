# 任务：R16 / Genie 每帧分配与 render-element identity

待审状态：Author verification complete
开始基线：外层 `7fbee3c` / niri `13e0fff4` / quickshell `8b71640`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/render_helpers/shader_element.rs` | 通用 mutation API：`seed_uniforms`、`with_uniforms_mut`、`set_texture`、`set_geometry`、`set_location`；`uniform_value` 原地写 f32/rect/mat3 |
| `src/layout/minimize_window_animation.rs` | `MinimizeWindowAnimation` 持有稳定 `genie_shader`；构造时 seed 一次；`render_genie` 仅原地更新 progress/矩阵/area/texture 并 `damage_all` |
| `src/layout/scrolling.rs` | test-only 观察入口：`test_for_each_minimize_restore` / `test_render_minimize_restore_overlays` |
| `src/tests/r16_genie_identity.rs` | 源码删除证明 + 逐帧 Id 稳定 + commit 前进 + reverse 同 Id + Output 多帧绑定 |
| `src/tests/mod.rs` | 注册 `r16_genie_identity` |

### 外层

| 路径 | 作用 |
| --- | --- |
| `docs/.../R16-execution-record.md` | 本记录 |
| `docs/.../acceptance/R16-genie-identity-2026-07-24.md` | 前后对照与删除证明 |

未改 quickshell；未引入 Genie 专属第二套 draw API；未改 R17–R19 范围。

Owner：

- **Genie render-element identity**：`MinimizeWindowAnimation.genie_shader`（`ShaderRenderElement`，构造时 `empty` + seed）。
- **逐帧动态数据**：`render_genie` → `set_geometry` / `set_texture` / `with_uniforms_mut` / `damage_all`。
- **通用 mutation API**：`ShaderRenderElement`（可供其他 shader element 复用；border/shadow 仍走既有 `update`）。

## 目标设计落地

```text
MinimizeWindowAnimation::new_inner
        │
        ▼  seed_genie_shader (once)
  ShaderRenderElement::empty(Genie) + Id::new once
  seed_uniforms(Rc<[Uniform;7]>)  // static names
  set_texture("niri_tex", primary) // String key once
        │
        ▼  each frame render_genie
  set_geometry(area, scale, alpha)
  set_texture(name, variant tex)   // key reuse; value only
  with_uniforms_mut → set_rect4 / set_mat3 / set_f32
  damage_all → commit++
  clone stable element into render list
```

## 旧路径删除

```text
# render_genie 函数体（去注释）中下列构造为零：
rg -n 'Rc::new|HashMap::from|String::from|ShaderRenderElement::new' \
  niri/src/layout/minimize_window_animation.rs
# 仅注释与 seed_genie_shader / 单测 seed 中仍有 Rc::new（构造时一次）

# 自动化删除证明：
cargo test -p niri --lib r16_render_genie_source_has_zero_per_frame_constructors
# 通过：render_genie 无 Rc::new / HashMap::from / String::from / ShaderRenderElement::new

# 无 object pool / 第二 draw API：
rg -n 'GeniePool|genie_pool|render_genie_legacy|ProgramType::Genie' niri/src
# ProgramType::Genie 仍为唯一 shader 程序类型；无 pool / legacy fallback 路径
```

作者验证：

1. `render_genie` **零** 每帧 `Rc::new` / `HashMap::from` / `String::from` / `ShaderRenderElement::new`。
2. 稳定 `Id` 跨帧、跨 reverse 保持；`CommitCounter` 每帧前进。
3. 仍走现有 `ShaderRenderElement` draw path；shader unavailable 时 `None` → 既有 texture 回退。
4. 未保留 per-frame `new()` 作为正常 fallback。

## 行为契约

适用 1.4 节：minimize / restore / reverse / target rect / view movement / scale / 三种 snapshot variant 选择 / shader unavailable 回退均保持。
坐标空间仍为 R02 output-local；不改 lifecycle ownership（R05）。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all -- --check)` | 通过（仅本任务路径；无关 client/foreign_toplevel fmt 已还原） |
| `(cd niri && cargo test -p niri --lib r16_genie -- --nocapture)` | **4 passed** |
| `(cd niri && cargo test -p niri --lib minimize_window_animation -- --nocapture)` | **5 passed**（含 2 个 R16 单测） |
| `(cd niri && cargo test -p niri --lib lifecycle -- --nocapture)` | **41 passed** |
| `(cd niri && cargo test -p niri --lib)` | **441 passed**（R15 为 435；+4 R16 集成 +2 单测） |

未运行：

- 完整 `cargo test -p niri`（含 bin/doctest）：lib 为矩阵自动化主体；
- tracy allocation 会话：环境无 `profile-with-tracy-allocations`；以源码删除 + 稳定 Id/commit 作为对照；
- 真 4K/多输出像素 golden；
- quickshell ctest：未改。

### 关键不变量

- 逐帧 element Id 稳定；动态 commit 前进；
- reverse_to_restore 复用同一 animation / 同一 Id；
- `render_genie` 源码删除证明测试通过；
- Output 目标多帧复用同一 binding/Id。

## 性能

对照 R15 前测（`acceptance/R15-baseline-2026-07-24.md` §5.2）：

| 指标 | R15 前测 | R16 后 |
| --- | --- | --- |
| `render_genie` 每帧分配组 | **4**（Rc / HashMap / String / ShaderRenderElement::new） | **0**（源码 + 自动化删除证明） |
| 理论 1s@60Hz alloc groups | **240** | **0** 上述四组 |
| create 峰值字节 | ~2.0 MiB（1080 客户端） | 未改 create 路径（seed 仅一次 Id + uniforms + key） |
| element Id | 每帧新 Id | 动画生命周期内稳定 |

硬件：同 R15（Linux WWT / Ryzen 7 7745HX）。Headless debug 集成测试；非 tracy 分配采样。

## 独立审查专属问题（作者自查）

1. element ID 稳定时，damage 是否仍覆盖动态 uniform 变化？**是；每帧 `damage_all()` 递增 `CommitCounter`。**
2. texture/renderer context 变化是否安全重建，而非使用失效资源？**variant 纹理每帧 `set_texture` 换绑定；动画仍持有 `TextureBuffer` 生命周期。无第二假路径。**
3. 所有 render-target variants 是否复用正确 binding？**是；`render()` 先选 buffer，再 `set_texture` 到同一稳定 element；Id 共用、纹理按 target 更新。**
4. 是否保留了隐藏的 per-frame legacy path？**否；`render_genie` 仅稳定更新路径；shader 不可用返回 `None` 走既有 texture 回退（非 `ShaderRenderElement::new`）。**

审查后小修（仍属 R16，重审前并入）：

- `set_geometry(None)` 不再每帧 `unwrap_or_default` 空 `Vec`；
- Genie uniform 使用 `genie_uniform::*` 命名下标；
- 无 dock 路径断言 texture fallback（非空观测）。
