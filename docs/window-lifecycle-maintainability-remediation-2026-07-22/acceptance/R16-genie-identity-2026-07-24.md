# R16 · Genie 每帧分配与 render-element identity · 2026-07-24

## 1. 环境

| 项 | 值 |
| --- | --- |
| 外层开始基线 | `main` / `7fbee3c`（R15 完成） |
| niri 开始基线 | `tahoe-layer-animations` / `13e0fff4` |
| Headless profile | debug unit/integration |
| 对照真源 | R15 acceptance §2.1 / §5.2 |

## 2. 删除证明（render_genie）

命令：

```text
(cd niri && cargo test -p niri --lib r16_render_genie_source_has_zero_per_frame_constructors -- --nocapture)
```

结果：**passed**

`render_genie` 函数体（去行注释）中：

| 构造 | 计数 |
| --- | --- |
| `Rc::new` | 0 |
| `HashMap::from` | 0 |
| `String::from` | 0 |
| `ShaderRenderElement::new` | 0 |

仍存在且**仅一次**（`seed_genie_shader` 于 animation 构造）：

- `ShaderRenderElement::empty` → 单次 `Id::new`
- `seed_uniforms(Rc::new([…7…]))`
- `set_texture("niri_tex", …)` 首次插入 String key

## 3. 逐帧 identity / damage

命令：

```text
(cd niri && cargo test -p niri --lib r16_genie -- --nocapture)
```

| sample | 结果 |
| --- | --- |
| `r16_genie_element_id_stable_across_frames_and_commit_advances` | id 跨帧相等；commit f1≠before、f2≠f1；reverse 同 id |
| `r16_output_target_reuses_stable_binding` | Output 多帧同一 Id |
| `r16_genie_texture_fallback_when_target_rect_invalid` | 无 dock 时不 panic |

`R16_SAMPLE kind=genie_identity_stable id_frames_equal=1 commit_advanced_f1=1 commit_advanced_f2=1 reverse_same_id=1`

## 4. 与 R15 前测对照

| 指标 | R15 | R16 |
| --- | --- | --- |
| per_frame_alloc_groups（四组） | 4 | **0** |
| theoretical_alloc_groups_per_1s@60Hz | 240 | **0**（该四组） |
| element Id | 每帧新 | **稳定** |
| snapshot create peak | ~2.0 MiB | 未作为本任务改动目标 |

## 5. 未运行

- tracy allocation 字节级前后采样（无 feature 会话）；
- 真机多输出 Genie 像素 golden；
- 完整 bin/doctest。
