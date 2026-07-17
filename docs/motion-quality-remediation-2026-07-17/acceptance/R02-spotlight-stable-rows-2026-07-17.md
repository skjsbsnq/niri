# R02 · Spotlight 打字稳定行 · 2026-07-17

覆盖问题：#86（连续输入时结果 delegate 全量重建、整片闪烁、图标逐字重载）。

## 改动摘要

- `Spotlight.qml` 为 header/result flat row 增加全局唯一 `modelKey`：result 使用规范化 provider + result id + kind，header 使用独立命名空间；`ScriptModel.objectProp: "modelKey"` 接入 Tahoe fork 的增量模型路径。
- `buildSections()` 与 `flattenRows()` 分别维护按 key 的缓存并逐轮裁剪；未变化 section 与同 key row 复用原对象，消失 key 不滞留。
- 同 key row 原地同步最新 result/index/fingerprint；delegate 按当前 `results` / `flatRows` 解析 payload 与 selectable index，规避 `ScriptModel` move 分支保留旧 role wrapper 导致的标题、图标、点击目标或高亮索引陈旧。
- `resultsForQuery()` 从声明式 `results` binding 中移出，改由 query/searchService/providerRevision 事件显式刷新。宿主实测消除了每字一组的 `Binding loop detected for property results`，慢 provider 完成后仍由 revision 刷新。
- `Search.qml` 未改：既有 `makeResult()` 已统一提供 id/provider/kind，无需增加服务接口或平行 key 机制。
- 结果渲染样式、hover 过渡和 Spotlight 关闭动画未改，分别留在原设计与 R18 范围。

## 审查

审查方式：多轮独立逐 diff 审查，最终由 2 个独立 reviewer 复审。

审查发现并已修复：

1. 高严重度：初版在 fingerprint/selectableIndex 变化时创建同 key 新 wrapper；Tahoe `ScriptModel` move 分支只移动旧 QVariant，不替换 role，重排后可能留下旧索引与旧 activation。改为 row 永久按 key 原地复用，并让 delegate 从当前模型解析 payload/index；新增重排、收窄、title/subtitle/icon/activation 断言。
2. 运行期：宿主连续输入发现原有 `results` binding 内调用带调度副作用的 `resultsForQuery()`，每字触发 binding loop。改为显式事件刷新，并补 query 单次调用、providerRevision 刷新和日志零 binding-loop 断言。
3. 边界加固：provider 统一规范化，异常缺 id 时回退标题；已移除 key 的索引解析返回 `-1`，避免残留 delegate 短暂误高亮第 0 行。

最终复审结论：**PASS**。未发现 key 冲突、缓存泄漏、陈旧 payload/index、binding loop、玻璃 region 红线、TODO/FIXME 或范围越界。

## 自动验收

- 专项：`pytest -q tests/test_spotlight_refactor.py tests/test_spotlight_stable_rows.py tests/test_search_providers.py tests/test_search_latest_query_qml.py` → **14 passed**。
- 真实 Tahoe `qs` / `ScriptModel` 探针：`SPOTLIGHT_STABLE_ROWS_PASS created=4 destroyed=4`；覆盖同 key 新对象、内容更新、add/remove、reorder、query 收窄、provider revision、row/delegate identity、最新 activation/index 及缓存归零；输出无 `binding loop`。
- 全量：`cd tahoe-shell && pytest tests/ -x -q` → **752 passed, 217 subtests passed in 26.50s**。
- `bash scripts/check-tahoe-glass-guardrails.sh` → passed（24 PanelWindow namespace / 4 TahoeGlassRegion / 22 regions 文件 / popup 几何检查全过）。
- 最终工作树嵌套冒烟：`timeout 25s env NIRI_MODE=nested TAHOE_POWER_PROFILE=keep TAHOE_CONFIG_DIR=$PWD/tahoe-shell ... scripts/run-tahoe-session.sh` → 运行满 25s 后预期 timeout 124；无 QML TypeError/ReferenceError/binding loop，仅既有 EGL warning 与终止时 xwayland-satellite SIGTERM。
- 部署一致性：`arch-update.sh --deploy-tahoe-shell` 后 `--verify-tahoe-shell` → parity OK，manifest `1923e7f5873a2093c007bc52481e004183e60f77b18245b1c1a9345824e63fbf`。
- 本任务不改 KDL，`niri validate` 不适用。

## 宿主会话手测矩阵

- 连续输入/删除/重排：真实 Spotlight 以 70ms 键间隔输入 `niri` → Backspace ×2 → 重新输入 `ri`；既有行无整片闪烁，图标稳定，结果分组正确。
- 选择高亮：上述查询后 Down ×2 / Up ×1，高亮落在正确 selectable row，右侧 preview 与当前行一致；spring 代码路径未改，`useSpring=false` eased fallback 与 reduced duration 路径由既有专项断言复核。
- 开关/关闭：IPC 开关 ×3（150ms 间隔）、Esc、真实虚拟指针点击面板外均成功关闭；`niri msg layers` 无残留 `tahoe-spotlight` surface。
- 浅色：宿主截图核验通过；深色只涉及未改动的 Theme palette 绑定，稳定 identity/payload 路径无颜色分支，独立审查确认无回归。
- 服务不可用：`refreshResults()` 对 null searchService 发布空数组；缓存随空 rows 裁剪，探针覆盖空结果归零。
- 宿主 `qs` 日志：连续输入及全部关闭矩阵后 Spotlight `Binding loop` / `TypeError` / `ERROR` = **0**。
- 截图证据（本机会话）：`r02-spotlight-empty.png`、`r02-spotlight-niri.png`、`r02-spotlight-final-host.png`，位于本任务 visualization 目录。

## 二选一决策

无。本任务按计划采用既有 `ScriptModel.objectProp` + key 缓存机制，未引入平行 diff 框架。

## 范围外发现

- 宿主 Quickshell 启动时存在既有 `LockScreen.qml:23 ReferenceError: lockClock is not defined`；它在打开 Spotlight 前即出现，R02 未触及 LockScreen，记为范围外待办，未顺手修改。
