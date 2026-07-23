# 任务：R10 / F08 无尺寸差 unmaximize 观测与条件修复

待审状态：Author verification complete
开始基线：外层 `0d57838` / niri `350ced40` / quickshell `bbc267ca`（未改）

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/window/mapped.rs` | F08 门 1：`request_size` / `request_size_once` 在 **size 或 expanded-mode state** 变化且 `animate` 时入 `animate_serials`；test helper `test_animate_serials_len` |
| `src/layout/tile.rs` | F08 门 2：既有 resize owner 在 size delta ≤ threshold **但** fullscreen/expanded progress 会跳变时仍创建 `ResizeAnimation`；**不**降低 `RESIZE_ANIMATION_THRESHOLD` |
| `src/layout/tests.rs` | TestWindow 镜像门 1；`f08_same_size_unmaximize_*` / 无 mode 变化不发明动画 |
| `src/tests/lifecycle_observe.rs` | 真实 Mapped serial：same-size unmaximize 入 `animate_serials`；无 mode 变化基线 |

### 外层仓库

| 路径 | 作用 |
| --- | --- |
| `docs/.../R10-execution-record.md` | 本执行记录（观测结论 + 修复证据） |

Owner：

- **Mapped configure animate 标记**：唯一决定哪些 serial 进入既有 resize snapshot 链。
- **Tile::update_window ResizeAnimation**：唯一 resize / expanded / fullscreen progress 视觉 owner（R08 visual exclusivity 无关）。
- **未**新增 unmaximize 专用动画旁路或 Genie 复制。

## 观测结论（决策前锁定）

### 两道独立门（与 F01/F03 分离）

| 门 | 位置 | 旧行为 | F08 风险 |
| --- | --- | --- | --- |
| 1 | `Mapped::request_size`：`changed && animate` 仅看 **size** | 最大化状态变、请求尺寸相同 → configure 有、**无** `animate_serials` | snapshot 链不启动 |
| 2 | `Tile::update_window`：`change > RESIZE_ANIMATION_THRESHOLD` | size/tile delta ≤ 10 时 **清空** resize anim，即使 `expanded_from != expanded_to` | 边框/圆角/expanded progress 瞬时跳变 |

F01（overlay draw policy）与 F03（Genie 坐标）不在本任务路径内；本项只断言 configure serial → snapshot → resize/expanded owner。

### 场景矩阵（测试覆盖）

| 场景 | 结果（修复后） |
| --- | --- |
| 同尺寸 unmaximize（layout TestWindow + forced size） | `resize_animation.is_some()`，走 expanded progress |
| 同尺寸 unmaximize（真实 Mapped serial） | `animate_serials_len > 0` |
| 无 mode 变化的 settled normal | 不发明 `animate_serials` / resize anim |
| 既有 floating same-size configure 契约 | 全部仍通过（含 no extra configure） |

### 决策：**Go — 在现有 owner 内修复**

证据：mode 变化时 `expanded_from`（maximized=1）→ `expanded_to`（normal=0）必然不同；跳过动画会造成 chrome 跳变，**不是**“视觉无差异”。因此：

- 不采用 No-go；
- 不降低全局 `RESIZE_ANIMATION_THRESHOLD`（避免连续 resize 抖动）；
- 不建 parallel unmaximize/Genie 路径；
- 仅当 size 超阈值 **或** fullscreen/expanded progress 变化时创建既有 `ResizeAnimation`。

## 目标设计落地

```text
request_size / request_size_once (animate=true)
  size_changed OR mode_state_changed
        │
        ▼
  animate_serials.push(serial)
        │
        ▼
commit → should_animate_commit → store snapshot
        │
        ▼
Tile::update_window
  if size_delta > THRESHOLD || fullscreen/expanded progress changes
      → ResizeAnimation { size, expanded_progress, fullscreen_progress }
  else
      → no anim (truly identical visual)
```

## 旧路径 / 禁止项

```text
rg -n 'RESIZE_ANIMATION_THRESHOLD' niri/src
# 仍为 10.0；未无条件降低

rg -n 'unmaximize.*[Aa]nim|Genie.*unmax' niri/src/layout
# 无 unmaximize 专用平行动画
```

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo fmt --all)` | 已格式化；无关 fmt 已还原 |
| `(cd niri && cargo test -p niri --lib -- f08_)` | **4 passed** |
| `(cd niri && cargo test -p niri --lib layout::)` | **187 passed** |
| `(cd niri && cargo test -p niri --lib -- unmaximize_to_same floating::)` | **29 passed** |
| `(cd niri && cargo test -p niri)` | **412 passed** |

未运行：嵌套会话手测；reduced-motion 专项手测（window_resize anim 仍走配置；off 时 anim 即时完成属既有语义）。

### 关键不变量

- 真实 configure serial 链：mode-only unmaximize 入 `animate_serials`；
- 零尺寸差 + mode 变 → 既有 resize owner 有 expanded progress；
- 无 mode/size 变化 → 不发明动画；
- 阈值 10 保持；无 parallel 动画路径。

## 性能

条件修复 / 正确性。未声称帧时间收益；仅在有 mode progress 变化时多一次既有 resize anim（与有尺寸差 unmaximize 同路径）。

## 独立审查专属问题（作者自查）

1. 结论是否把 F01/F03 与独立 F08 分开？**是**；记录与测试只覆盖 serial/snapshot/resize owner。
2. 测试是否走真实 configure serial 和 snapshot 链？**是**；`f08_same_size_unmaximize_queues_animate_serial_on_mapped` 用 Fixture+Mapped；layout 测 TestWindow 镜像 + Tile owner。
3. 新增动画是否属于现有 owner 而非平行实现？**是**；仅扩展 `animate_serials` 入队条件与 `ResizeAnimation` 创建谓词。
4. 若不实施，证据是否足够？**N/A — 已实施**；跳变证据为 `expanded_from != expanded_to` 在 size delta=0 时被旧 threshold 清空。
