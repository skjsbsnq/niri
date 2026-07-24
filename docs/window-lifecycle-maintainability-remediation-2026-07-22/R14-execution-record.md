# 任务：R14 / glass client canonicalization 与 redraw owner

待审状态：Author verification complete
开始基线：外层 `b3c49ed` / niri `c1a9e381` / quickshell `8b71640`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/protocols/tahoe_glass.rs` | post-commit 删除内联 `output_for_root` 分支；统一 `queue_redraw_for_tahoe_glass_surface`；测试计数器串行锁 |
| `src/tests/tahoe_glass.rs` | 新增 post-commit 走统一 handler 的集成测试；计数器断言窗口加锁 |

### 外层

| 路径 | 作用 |
| --- | --- |
| `tahoe-shell/components/GlassPanel.qml` | 删除 `quantizeGlass01` 与二次 1/50 量化；原始值交给 C++ setter |
| `tahoe-shell/components/Dock.qml` | 删除 interaction 二次 `*50/50` 量化 |
| `docs/.../R14-execution-record.md` | 本记录 |

未改 quickshell：C++ `TahoeGlassRegion::setInteraction/setMaterialAlpha` 的单一 1/50 量化与 `diffRegions` / `schedulePolish` 保留。

Owner：

- **1/50 量化**：仅 Quickshell C++ 协议边界 setter（`qml.cpp`）。
- **Client transaction**：`schedulePolish → setRegions → diffRegions changed-only commit`。
- **ID diff**：`TahoeGlassSurface::diffRegions`。
- **Server lifecycle redraw**：`TahoeGlassHandler::queue_redraw_for_tahoe_glass_surface`（post-commit / destroy / recreate / abnormal disconnect）。

## 目标设计落地

```text
QML interaction/materialAlpha (raw)
        │
        ▼  C++ setInteraction / setMaterialAlpha  (sole 1/50 quantize)
TahoeGlassRegion state
        │
        ▼  schedulePolish (one polish)
setRegions → diffRegions → wire only if changed
        │
        ▼  surface commit
niri post-commit → queue_redraw_for_tahoe_glass_surface
  · locatable root → queue_redraw(output) + targeted counter
  · else → queue_redraw_all + fallback counter
```

## 旧路径删除

```text
rg -n 'quantizeGlass01|\* 50\) / 50' tahoe-shell/components
# 零命中（QML 二次 1/50 量化已删除）

rg -n 'output_for_root\(surface\)' niri/src/protocols/tahoe_glass.rs
# 零命中（post-commit 内联分支已删除；output_for_root 仅存在于
# handlers/mod.rs 的 TahoeGlassHandler 实现内）

rg -n 'beginBatch|endBatch' tahoe-shell quickshell/src/wayland/tahoe_glass
# 零命中（未新增 batch QML API）

rg -n 'queue_redraw_for_tahoe_glass_surface' niri/src/protocols/tahoe_glass.rs
# post-commit / create(recreate with visible) / Destroy / destroyed 均调用

rg -n 'round\(qBound\(0\.0, interaction|round\(qBound\(0\.0, materialAlpha' quickshell/src/wayland/tahoe_glass/qml.cpp
# C++ 边界量化保留（interaction + materialAlpha）

rg -n 'diffRegions' quickshell/src/wayland/tahoe_glass
# surface.cpp 实现 + region_diff 单测保留
```

作者验证：

1. QML 二次量化 **零**命中（`tahoe-shell/components`）。
2. 协议文件 **无** 独立 redraw 决策分支；仅 handler 方法内 `output_for_root`。
3. **无** `beginBatch`/`endBatch` QML API。
4. C++ 量化与 `diffRegions` **保留**。
5. DynamicIsland 的 geometry floor/ceil quantize **保留**（非 interaction/materialAlpha 二次 1/50，不在 R14 删除范围）。

## 行为契约

- 相同量化值 / pure reorder / duplicate id：不额外 wire（既有 C++ `region_diff` tests）。
- interaction/materialAlpha 高频变化：C++ setter 量化 + fuzzy compare 早退；每 polish 最多一次 `setRegions`（既有 polish 路径）。
- destroy/recreate/disconnect：经同一 handler redraw。
- root 可定位：targeted；不可定位：fallback all + 计数。
- post-commit 区域提交：与 destroy 同一 owner（新集成测试）。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all -- --check)` | 通过（R14 文件；无关 client/foreign_toplevel fmt 已还原） |
| `(cd niri && cargo test -p niri --lib -- tahoe_glass)` | **33 passed** |
| `(cd niri && cargo test -p niri --lib)` | **424 passed**（R14 要求整表自动化可覆盖部分） |
| `(cd tahoe-shell && pytest tests/test_tahoe_glass_incremental_regions.py tests/test_tahoe_glass_fallback_material_alpha.py tests/test_tahoe_glass_scene_transform.py)` | **33 passed** |

未运行：

- 完整 `cargo test -p niri`（含 bin/doctest）：lib 已覆盖矩阵自动化主体；headless fixture 外的 GPU 像素 golden 无本任务新增。
- quickshell C++ rebuild/ctest：未改 C++ 源；`diffRegions`/量化由既有 C++ 单测与源码核验保留。
- 嵌套会话手测 glass 动画；多输出热插拔手测（lib 双输出 fixture 已覆盖 targeted vs fallback）。

### 关键不变量

- post-commit / destroy / recreate / disconnect 均只经 `queue_redraw_for_tahoe_glass_surface`；
- mapped root → targeted counter ≥ 1、fallback = 0；
- unlocatable root → fallback ≥ 1、targeted = 0；
- QML 不再二次量化 interaction/materialAlpha。

## 性能

可维护性与 ownership 收敛。未声称帧时间收益；去重量化减少无意义 wire 的路径已存在于 C++，本任务去掉 QML 重复层。

## 独立审查专属问题（作者自查）

1. 是否误删 C++ 边界量化或 changed-only commit？**否**；`qml.cpp` setter 与 `diffRegions` 未动。
2. 是否新增 polish 并行 batch API？**否**；无 `beginBatch`/`endBatch`。
3. 所有 server lifecycle redraw 是否同一 handler？**是**；post-commit 已并入；Destroy/destroyed/recreate 原已统一。
4. fallback redraw-all 是否仅无法定位且有计数？**是**；handler 内 `test_note_fallback_redraw_all`；集成测试覆盖。
