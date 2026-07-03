# Tahoe niri 设置写入白名单

日期：2026-07-03

对应路线图：`daily-desktop-source-research-anti-corruption-roadmap-2026-07-03.md` Phase 7：niri 配置写入继续白名单化。

## 约束

`tahoe-shell/services/niri_settings_tool.py` 只写本文列出的字段。工具内的 `WRITABLE_FIELD_SPECS` 是机器可读白名单，`update_field()` 在解析 KDL 前先查表，未知字段直接失败。

保持不变的边界：

- 不写 `binds`。
- 不做任意 KDL 编辑。
- 不重排整个 `config.kdl`。
- 不删除用户注释。
- 不开启 `variable-refresh-rate`。
- 不允许 broad `namespace="^quickshell"` layer-rule。
- `layout`、`tahoe-glass`、`blur`、`input`、`animations` 必须被 `// tahoe-managed: begin <block>` 和 `// tahoe-managed: end <block>` 包住，且每个目标顶层 block 恰好一个。
- `output.scale` 是特殊单输出写入路径：只允许配置中恰好一个顶层 `output` block，多输出布局拒绝写入。

表格中的 `atomic/validate` 表示同一回滚策略：写入前跑 guardrail；把更新后的文本写入同目录临时文件并 fsync；执行 `niri validate -c <tmp>`；验证成功后 `os.replace()` 原子替换；任一步失败都删除临时文件并保持 live config 不变。

## Layout

| Field | KDL path | Range | Validation | Rollback |
| --- | --- | --- | --- | --- |
| `layout.gaps` | `layout.gaps` | `0..65535` | numeric `bounded_number` | atomic/validate |
| `layout.focus_ring.enabled` | `layout.focus-ring.on/off` | boolean | `parse_bool` | atomic/validate |
| `layout.border.enabled` | `layout.border.on/off` | boolean | `parse_bool` | atomic/validate |
| `layout.shadow.enabled` | `layout.shadow.on/off` | boolean | `parse_bool` | atomic/validate |
| `layout.shadow.softness` | `layout.shadow.softness` | `0..1024` | numeric `bounded_number` | atomic/validate |
| `layout.shadow.spread` | `layout.shadow.spread` | `-1024..1024` | numeric `bounded_number` | atomic/validate |
| `layout.shadow.offset_x` | `layout.shadow.offset.x` | `-65535..65535` | numeric `bounded_number` | atomic/validate |
| `layout.shadow.offset_y` | `layout.shadow.offset.y` | `-65535..65535` | numeric `bounded_number` | atomic/validate |
| `layout.snap_assist.enabled` | `layout.snap-assist.on/off` | boolean | `parse_bool` | atomic/validate |
| `layout.snap_assist.threshold` | `layout.snap-assist.threshold` | `0..65535` | numeric `bounded_number` | atomic/validate |

## Tahoe Glass

Glass 写入同时白名单 material 和字段名。允许的 material 只有 `panel`、`pill`、`launcher`、`dock`、`menu`、`toast`、`backdrop`。允许的字段只有 `edge-highlight`、`refraction`、`inner-shadow`、`chromatic`、`lens-depth`。其他 material 或 `xray`、`noise`、`saturation`、`contrast`、`tint-*`、`shadow` 等字段不写。

| Field | KDL path | Range | Validation | Rollback |
| --- | --- | --- | --- | --- |
| `glass.panel.edge_highlight` | `tahoe-glass.material["panel"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.panel.refraction` | `tahoe-glass.material["panel"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.panel.inner_shadow` | `tahoe-glass.material["panel"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.panel.chromatic` | `tahoe-glass.material["panel"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.panel.lens_depth` | `tahoe-glass.material["panel"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.pill.edge_highlight` | `tahoe-glass.material["pill"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.pill.refraction` | `tahoe-glass.material["pill"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.pill.inner_shadow` | `tahoe-glass.material["pill"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.pill.chromatic` | `tahoe-glass.material["pill"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.pill.lens_depth` | `tahoe-glass.material["pill"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.launcher.edge_highlight` | `tahoe-glass.material["launcher"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.launcher.refraction` | `tahoe-glass.material["launcher"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.launcher.inner_shadow` | `tahoe-glass.material["launcher"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.launcher.chromatic` | `tahoe-glass.material["launcher"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.launcher.lens_depth` | `tahoe-glass.material["launcher"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.dock.edge_highlight` | `tahoe-glass.material["dock"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.dock.refraction` | `tahoe-glass.material["dock"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.dock.inner_shadow` | `tahoe-glass.material["dock"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.dock.chromatic` | `tahoe-glass.material["dock"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.dock.lens_depth` | `tahoe-glass.material["dock"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.menu.edge_highlight` | `tahoe-glass.material["menu"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.menu.refraction` | `tahoe-glass.material["menu"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.menu.inner_shadow` | `tahoe-glass.material["menu"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.menu.chromatic` | `tahoe-glass.material["menu"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.menu.lens_depth` | `tahoe-glass.material["menu"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.toast.edge_highlight` | `tahoe-glass.material["toast"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.toast.refraction` | `tahoe-glass.material["toast"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.toast.inner_shadow` | `tahoe-glass.material["toast"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.toast.chromatic` | `tahoe-glass.material["toast"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.toast.lens_depth` | `tahoe-glass.material["toast"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.backdrop.edge_highlight` | `tahoe-glass.material["backdrop"].edge-highlight` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.backdrop.refraction` | `tahoe-glass.material["backdrop"].refraction` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.backdrop.inner_shadow` | `tahoe-glass.material["backdrop"].inner-shadow` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.backdrop.chromatic` | `tahoe-glass.material["backdrop"].chromatic` | `0..1000` | numeric + material/field whitelist | atomic/validate |
| `glass.backdrop.lens_depth` | `tahoe-glass.material["backdrop"].lens-depth` | `0..1000` | numeric + material/field whitelist | atomic/validate |

## Blur

| Field | KDL path | Range | Validation | Rollback |
| --- | --- | --- | --- | --- |
| `blur.enabled` | `blur.on/off` | boolean | `parse_bool` | atomic/validate |
| `blur.passes` | `blur.passes` | `0..255` | numeric `bounded_number` | atomic/validate |
| `blur.offset` | `blur.offset` | `0..100` | numeric `bounded_number` | atomic/validate |
| `blur.noise` | `blur.noise` | `0..1000` | numeric `bounded_number` | atomic/validate |
| `blur.saturation` | `blur.saturation` | `0..1000` | numeric `bounded_number` | atomic/validate |

## Input

| Field | KDL path | Range | Validation | Rollback |
| --- | --- | --- | --- | --- |
| `input.keyboard.repeat_rate` | `input.keyboard.repeat-rate` | `0..255` | numeric `bounded_number` | atomic/validate |
| `input.keyboard.repeat_delay` | `input.keyboard.repeat-delay` | `0..65535` | numeric `bounded_number` | atomic/validate |
| `input.keyboard.numlock` | `input.keyboard.numlock` | boolean | `parse_bool` | atomic/validate |
| `input.touchpad.tap` | `input.touchpad.tap` | boolean | `parse_bool` | atomic/validate |
| `input.touchpad.natural_scroll` | `input.touchpad.natural-scroll` | boolean | `parse_bool` | atomic/validate |
| `input.touchpad.dwt` | `input.touchpad.dwt` | boolean | `parse_bool` | atomic/validate |
| `input.touchpad.accel_speed` | `input.touchpad.accel-speed` | `-1..1` | numeric `bounded_number` | atomic/validate |

## Output

| Field | KDL path | Range | Validation | Rollback |
| --- | --- | --- | --- | --- |
| `output.scale` | `output.<single-output>.scale` | `0.5..4.0` | numeric `bounded_number`; exactly one top-level `output` block | atomic/validate |

## Animations

只写已有四个 spring action：`workspace-switch`、`window-movement`、`window-resize`、`overview-open-close`。`window-open` 和 `window-close` 带 custom shader，仍然不写。

| Field | KDL path | Range | Validation | Rollback |
| --- | --- | --- | --- | --- |
| `animations.workspace_switch.damping_ratio` | `animations.workspace-switch.spring.damping-ratio` | `0.1..10` | numeric + action/param whitelist | atomic/validate |
| `animations.workspace_switch.stiffness` | `animations.workspace-switch.spring.stiffness` | `1..100000` | numeric + action/param whitelist | atomic/validate |
| `animations.workspace_switch.epsilon` | `animations.workspace-switch.spring.epsilon` | `0.00001..0.1` | numeric + action/param whitelist | atomic/validate |
| `animations.window_movement.damping_ratio` | `animations.window-movement.spring.damping-ratio` | `0.1..10` | numeric + action/param whitelist | atomic/validate |
| `animations.window_movement.stiffness` | `animations.window-movement.spring.stiffness` | `1..100000` | numeric + action/param whitelist | atomic/validate |
| `animations.window_movement.epsilon` | `animations.window-movement.spring.epsilon` | `0.00001..0.1` | numeric + action/param whitelist | atomic/validate |
| `animations.window_resize.damping_ratio` | `animations.window-resize.spring.damping-ratio` | `0.1..10` | numeric + action/param whitelist | atomic/validate |
| `animations.window_resize.stiffness` | `animations.window-resize.spring.stiffness` | `1..100000` | numeric + action/param whitelist | atomic/validate |
| `animations.window_resize.epsilon` | `animations.window-resize.spring.epsilon` | `0.00001..0.1` | numeric + action/param whitelist | atomic/validate |
| `animations.overview_open_close.damping_ratio` | `animations.overview-open-close.spring.damping-ratio` | `0.1..10` | numeric + action/param whitelist | atomic/validate |
| `animations.overview_open_close.stiffness` | `animations.overview-open-close.spring.stiffness` | `1..100000` | numeric + action/param whitelist | atomic/validate |
| `animations.overview_open_close.epsilon` | `animations.overview-open-close.spring.epsilon` | `0.00001..0.1` | numeric + action/param whitelist | atomic/validate |

## Test Fixtures

Phase 7 增加的 fixture 覆盖：

- `malformed-layout.kdl`：目标 block 花括号不闭合，写入前拒绝。
- `comments-and-multiline.kdl`：带 inline comments 和 raw shader，多行内容在无关写入后保持不变。
- `missing-blur.kdl`：目标顶层 block 缺失，拒绝写入。
- `missing-child-block.kdl`：目标父 block 存在但子 block 缺失时，只在 managed 父 block 内创建最小子 block。
- `multi-output.kdl`：`output.scale` 遇到多输出配置时拒绝写入。

这些测试补充既有原子写回测试，确保 validate 失败时 live config 不变、临时文件被清理。
