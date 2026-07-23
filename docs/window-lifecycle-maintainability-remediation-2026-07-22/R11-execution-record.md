# 任务：R11 / F07 消费既有 ext identifier

待审状态：Author verification complete
开始基线：外层 `a89bee5` / niri `82236d98` / quickshell `bbc267ca`

## 范围

### niri 子模块

| 路径 | 作用 |
| --- | --- |
| `src/tests/client.rs` | 绑定 `ext_foreign_toplevel_list_v1`；记录 ext/wlr 创建序 meta；`pair_ext_wlr_by_creation_order` fail-closed |
| `src/tests/foreign_toplevel.rs` | R11 可行性/跨进程 pairing 测试（shell 先/重启/同标题/close-remap/MappedId 十进制/desync） |

产品路径未改：identifier 仍由既有 `MappedId::to_protocol_identifier` + `add_ext_instance` 发布。

### quickshell 子模块

| 路径 | 作用 |
| --- | --- |
| `src/wayland/toplevel/ext_toplevel.{hpp,cpp}` | 消费 ext-foreign-toplevel-list-v1 |
| `src/wayland/toplevel/identifier_pairing.{hpp,cpp}` | FIFO 协调 pairing；appId 不一致 fail closed；identifier 写入既有 wlr handle |
| `src/wayland/toplevel/wlr_toplevel.{hpp,cpp}` | `identifier` 属性 |
| `src/wayland/toplevel/qml.{hpp,cpp}` | QML `Toplevel.identifier`；`toplevelIdentityChanged` |
| `src/wayland/toplevel/CMakeLists.txt` | 编译 pairing + 共享 ext protocol target |
| `src/wayland/screencopy/image_copy_capture/CMakeLists.txt` | 复用 toplevel 已生成的 `wlp-ext-foreign-toplevel` |

### 外层（tahoe-shell + docs）

| 路径 | 作用 |
| --- | --- |
| `tahoe-shell/services/windows/WindowModel.js` | O(n) `identityKey` map 合并；删除 fuzzy `findMatchingToplevel` |
| `tahoe-shell/services/Windows.qml` | 监听 `ToplevelManager.toplevelIdentityChanged`；删除 fuzzy 转发 |
| `tahoe-shell/tests/...` | fixture 带 identifier；反 fuzzy fixture；identityKey/100 窗线性；导出检查 |
| `docs/.../R11-execution-record.md` | 本记录 |

Owner：

- **Compositor**：`MappedId` ≡ IPC id ≡ ext `identifier` 十进制字符串（既有）。
- **Quickshell**：`IdentifierPairing` 唯一把 ext → 既有 wlr `ToplevelHandle.identifier`；无第二套 QML 窗口模型。
- **Shell**：`mergeWindowModels` 仅按 identifier/idKey 精确合并；activate/minimize/rectangle 仍用已 pairing 的 wlr handle。

## 可行性门（决策前）

跨进程 fixture（niri `tests::foreign_toplevel::r11_pair_*`）证明：

| 场景 | 结果 |
| --- | --- |
| Shell 先启动再开窗 | FIFO pair，identifier = MappedId |
| Shell 重启时已有多窗 | bind 后 pair 集合 = MappedId 集合 |
| 同 appId 同 title | 仍有互异 identifier |
| close/remap | closed 不参与 ready；新 id 不复用 |
| ready 计数 desync | `pair_ext_wlr_by_creation_order` Err（fail closed） |

未新增 compositor id 协议。

## 目标设计落地

```text
niri ToplevelData
  MappedId ──► IPC window.id
           └─► ext_foreign_toplevel_handle_v1.identifier (decimal)
                │
                ▼
Quickshell ExtToplevelList + wlr ToplevelManager
                │  IdentifierPairing FIFO
                ▼
existing QML Toplevel.identifier : string
                │
                ▼
WindowModel.mergeWindowModels  idKey map O(n)
  · match → ipc + wlr handle
  · no match → ipc-only or toplevel-only (no fuzzy)
```

### u64 / JS 策略

- 协议与匹配键一律 **十进制字符串**（`idKey` / `identityKey`）；合并与 CLI 优先 `idKey`。
- `decimalStringIsSafeInteger` 拒绝超过 `Number.MAX_SAFE_INTEGER` 的十进制串；`identityKey` 对 unsafe number/string 返回 null（fail closed）。
- `id` 数字镜像仅在安全范围内填充；匹配**不**依赖可能丢精度的 Number 回推。
- BigInt → 十进制字符串。禁止无条件 `Number(u64)` 当身份源。

## 旧路径删除

```text
rg -n 'findMatchingToplevel|normalizeIdentity\(toplevel\.appId|normalizeTitle\(toplevel\.title' tahoe-shell/services/windows
```

作者验证：**零命中**。`normalizeIdentity`/`normalizeTitle` 仍可被其他非 merge 调用，但不再参与 IPC↔toplevel 配对。

## 行为契约

- 不新增第二 QML model / compositor id 协议 / 永久 fuzzy fallback。
- toplevel-only（无 IPC / 无 identifier）保留为独立路径，不参与 IPC 模糊合并。
- Dock rectangle publisher 仍以 wlr handle 为 key（R04）；R11 只保证 handle 绑对窗口。

## 测试

| 命令 | 结果 |
| --- | --- |
| `(cd niri && cargo test -p niri --lib foreign_toplevel)` | 12 passed（含 5 个 R11 pair） |
| `(cd quickshell/build-tahoe && ninja quickshell-wayland-toplevel-management quickshell-wayland-screencopy-icc)` | 链接成功 |
| `(cd tahoe-shell && pytest tests/test_window_model.py tests/test_dock_rectangle_publisher.py tests/test_windows_workspace_events.py)` | 30 passed |

未运行：完整 `cargo test -p niri`（时间）；qmltestrunner 嵌套会话（环境未要求）；手测多同标题窗口。

## 性能

正确性/身份；100 窗 fixture 证明按 map 一次扫描绑定，无 O(n²) appId 扫描。

## 独立审查专属问题（作者自查）

1. ext↔wlr pairing 是否由跨进程事件测试证明？**是**；`r11_pair_*`。
2. 同标题 command/rectangle 是否精确？**是**；Shell 按 idKey；actions 仍走 wlr handle / IPC id。
3. 是否新增 compositor id 协议、第二 QML model、永久 fuzzy？**否**。
4. u64 在 QML/JS 是否无精度损失策略？**是**；字符串键 + unsafe Number 拒绝。
