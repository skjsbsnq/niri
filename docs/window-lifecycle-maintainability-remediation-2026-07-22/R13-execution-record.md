# 任务：R13 / 单一 glass schema、默认值与 named blur kernels

待审状态：Author verification complete
开始基线：外层 `c0fceac` / niri `6532c7db` / quickshell `8b71640`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `niri-config/src/tahoe_glass.rs` | named kernels、`ResolvedGlassMaterial`、material 上绑定 `kernel`；`blur-kernel` part；解析后 resolve |
| `niri-config/src/glass_schema.rs` | **新建**：Rust 唯一 defaults JSON 生成 + artifact 防漂移测试 |
| `niri-config/generated/glass_schema_defaults.json` | **新建**：由 Rust 生成的只读 schema artifact |
| `niri-config/src/lib.rs` | `Config.blur_kernels`；`blur-kernel` 节点；根文档结束时 `resolve_named_blur_kernels`；snapshot |
| `src/render_helpers/tahoe_glass.rs` | region 渲染只使用 `material.kernel`；删除 glass 路径上的全局 `blur_config` 参数 |
| `src/layer/mapped.rs` | glass render 调用不再传入全局 blur |

### 外层

| 路径 | 作用 |
| --- | --- |
| `tahoe-shell/services/niri_settings_tool.py` | 删除 `GLASS_MATERIAL_DEFAULTS`；从 artifact 加载 names/fields/defaults；缺省字段返回 `null` + inherited |
| `tahoe-shell/services/NiriSettings.qml` | 删除七套可编辑 glass 默认对象；`glassSchema` + inherited 解析 |
| `tahoe-shell/components/settings/pages/NiriGlassPage.qml` | UI 显示「继承」；值来自 schema 或 KDL |
| `tahoe-shell/tests/test_tahoe_material_governance.py` | 以 artifact 为真源；断言无 `GLASS_MATERIAL_DEFAULTS` |
| `docs/.../R13-execution-record.md` | 本记录 |

Owner：

- **Schema/default**：仅 `niri-config` Rust（`TahoeGlass::default` / `Blur::default` / `glass_schema::defaults_json`）。
- **Kernel 绑定**：`Config::resolve_named_blur_kernels`（解析阶段）；保留名 `default` = 顶层 `blur {}`。
- **Render**：Tahoe region 使用 `material.kernel`；window/layer 非 glass 背景仍用全局 `config.blur`（即 default kernel）。
- **Shell**：不伪造 compositor 默认；显示用 artifact / inherited 标记。

## 目标设计落地

```text
blur { ... }                    → default kernel (reserved name "default")
blur-kernel "name" { ... }      → Config.blur_kernels
material "dock" {
    blur-kernel "name"          → TahoeGlassMaterial.kernel_name
    ...
}
        │
        ▼  Config::resolve_named_blur_kernels (root parse only)
TahoeGlassMaterial { kernel: Blur, effect, shadow, ... }
        │
        ▼  ResolvedGlassMaterial / tahoe_glass render
ResolvedEffectPlan::build(material.kernel, effect, ...)
```

## 旧路径删除

```text
rg -n 'GLASS_MATERIAL_DEFAULTS' tahoe-shell
rg -n 'property var glassMaterials:\s*\(\s*\{' tahoe-shell/services/NiriSettings.qml
rg -n 'legacy_blur|glass_v2' niri/src niri/niri-config
rg -n 'blur_config,' niri/src/render_helpers/tahoe_glass.rs
```

作者验证：

1. `GLASS_MATERIAL_DEFAULTS` **仅**出现在治理测试的“不得存在”断言中。
2. `NiriSettings.qml` 为 `glassMaterials: ({})`，无七套手写默认。
3. glass render 路径 **无** 全局 `blur_config` 参数；`material.kernel` 为 region 唯一 kernel。
4. 无 `legacy_blur` / `glass_v2` 运行时分支。

## 行为契约

- 旧全局 blur-only 配置：全部 material 的 kernel 等于顶层 `blur`（golden 测试）。
- 默认配置引入 named kernel 语法后，未引用时视觉规则不变。
- 单独 `blur-kernel` + dock 引用后，panel/toast kernel 与 dock 隔离（字段级 golden）。
- 未知 kernel / 保留名 `default` 重定义：由现有 knuffel validator 报错。
- KDL 向后兼容：`blur` + `material` 旧写法仍解析到同一 resolver。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo test -p niri-config)` | 42 lib + wiki ok |
| `(cd niri && cargo test -p niri --lib -- resolved_effect_plan tahoe_glass)` | 38 passed（偶发 redraw 计数 flaky 重跑通过） |
| `(cd niri && cargo fmt --all)` | 已格式化 |
| `(cd tahoe-shell && pytest tests/test_tahoe_material_governance.py tests/test_niri_settings_tool.py)` | 31 passed |

未运行：完整 `cargo test -p niri`（时间）；GPU 像素 golden（用 plan/kernel golden + 既有 tahoe 单测替代）。

## 独立审查专属问题（作者自查）

1. 旧配置是否同一 resolver 等价？**是**；`old_blur_only_config_*` + default materials kernel = `config.blur`。
2. material kernel 是否真正隔离？**是**；`named_kernel_isolates_dock_from_panel`；render 用 `material.kernel`。
3. artifact 是否仅 Rust 可编辑并由测试防漂移？**是**；`glass_schema_defaults_artifact_matches_rust_source`；Shell 只读。
4. 是否两套配置语义？**否**；无 migration flag / glass-v2 path。
