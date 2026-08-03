# OpenCode / DeepSeek V4 Flash 串行执行计划

**用途**：把 `roadmap.md` 转换为 OpenCode 可机械执行、可审查、可提交的流程。
**执行模型**：DeepSeek V4 Flash。
**唯一任务顺序**：T01 -> T24。
**硬约束来源**：`CONSTRAINTS.md`；本文件只能收紧，不能放宽。

---

## 0. OpenCode 启动提示词

每次新 OpenCode 会话必须先提供下面的完整提示词，并把 `<CURRENT_TASK>` 替换为唯一当前任务号：

```text
你正在 /home/wwt/niri 执行 Tahoe Desktop 路线图的 <CURRENT_TASK>。

开始前按顺序完整阅读：
1. docs/frontend-quality-overhaul-2026-08-02/CONSTRAINTS.md
2. docs/frontend-quality-overhaul-2026-08-02/research-report.md
3. docs/frontend-quality-overhaul-2026-08-02/roadmap.md 中 <CURRENT_TASK> 的完整章节
4. docs/frontend-quality-overhaul-2026-08-02/execution-plan.md
5. docs/frontend-quality-overhaul-2026-08-02/execution-log.md 中当前状态和上一任务记录

硬要求：不得最小实现；不得创建平行接口；可以重构现有实现；不得破坏任何非任务目标的既有功能；不得添加用户未要求的功能、设置、开关、依赖或视觉模式；一次只能执行一个任务；当前任务完成、测试通过、两个独立只读子代理终审 CLEAN、commit、push、远端验证之前不得读取或开始下一任务。

源码高于文档。先用 rg 和 file:line 核实前提，再写能让旧代码失败的测试，然后完整实现。子代理只能审查，不能编辑。任何 CONFIRMED finding 必须修复；任何 PLAUSIBLE finding 必须接受修复或以代码/测试反证。最终 diff 有任何变化就必须用两个新的子代理重审。

不得 reset/checkout/clean/stash 用户工作。不得重启实时会话、执行真实电源操作、真实拔插或删除现有日志。需要这些操作时停止并请求用户。

先输出：当前任务、允许范围、禁止范围、前提核实命令、预计验收编号。未完成这一步不得编辑。
```

执行模型不得摘要后跳读 `CONSTRAINTS.md`，也不得把旧执行记录当成当前源码事实。

---

## 1. 嵌入式硬门禁

即使上下文压缩丢失 `CONSTRAINTS.md`，以下门禁仍必须生效：

| Gate | 必须满足 | 失败动作 |
|---|---|---|
| C1 完整性 | 当前任务全部验收项完成，无 TODO/占位/漏调用点 | 停止提交，继续当前任务 |
| C2 单一 authority | 原地改造，无功能重叠新接口/长期 flag | 删除旁路并迁移全部调用者 |
| C3 回归保护 | 除任务指定变化外，既有行为和 protected invariants 不变 | 回滚本任务相关设计并重做 |
| C4 范围 | 无用户未要求功能、设置、依赖、样式或顺手重构 | 移除范围外改动 |
| C5 串行 | 只有一个任务 IN_PROGRESS | 停止，恢复唯一当前任务 |
| C6 真实测试 | 旧实现失败、新实现通过；全量测试诚实记录 | 补行为测试，不得改弱断言 |
| C7 双审查 | 两个新、独立、只读 reviewer 对最终 diff CLEAN | 不得 commit |
| C8 提交推送 | 子仓库先 push，主仓库后 push，远端 ancestor 验证 | 不得进入下一任务 |
| C9 实时边界 | 未重启会话/电源/真实 hot-plug/删用户日志 | 需要时询问用户 |

任何 Gate 不能自动降级为 warning。

---

## 2. 状态机与任务锁

`execution-log.md` 是任务锁。合法转换只有：

```text
PENDING -> IN_PROGRESS
IN_PROGRESS -> BLOCKED
IN_PROGRESS -> RESOLVED-NO-CODE
IN_PROGRESS -> COMPLETE
BLOCKED -> IN_PROGRESS       # 仅用户解除阻塞后
```

执行前必须确认：

- 当前任务之前的所有任务为 `COMPLETE` 或经双审查的 `RESOLVED-NO-CODE`。
- 当前任务是第一个 `PENDING`。
- 没有其他 `IN_PROGRESS`。
- 本地 branch 与预期 remote branch 明确。

若不满足，停止。不得自行调整状态或跳任务。

---

## 3. 每任务固定执行路线

### Phase 1：前提与基线

1. 读取当前 roadmap 章节，列出 finding、允许文件域、禁止域、`Axx` 验收项。
2. 运行 `git status --short` 于主仓库及可能涉及的子仓库，记录用户已有改动。
3. 用 `rg` 定位定义、调用点、测试、协议生成物和 why 注释。
4. 点验文档给出的 `file:line`，记录已经移动或不成立的行号。
5. 运行专项旧测试和必要的只读 probe，建立失败基线。
6. 将任务状态改为 `IN_PROGRESS`，在 execution log 写前提与搜索清单。

### Phase 2：测试先行

1. 为根因写行为测试、生命周期 harness、像素基线或性能 trace。
2. 证明测试在未修复实现上失败。允许使用临时 worktree/临时 revert，但不得破坏用户工作树。
3. 记录失败输出和为什么测试能捕获真实缺陷。
4. 静态合同测试只能补充 guardrail，不能作为唯一证明。

### Phase 3：完整实现

1. 原地修改现有 authority。
2. 若改变签名/属性/协议，迁移全部调用点和测试。
3. 删除被替代的旧状态、重复 helper、magic constant 和旁路。
4. 处理 roadmap 明列的失败、取消、destroy、hot-plug、scale、reduced-motion 边界。
5. 不触碰下一任务范围。

### Phase 4：验证

1. 运行当前任务专项验收。
2. 运行受影响仓库的 full profile。
3. 运行 cross-repo/protocol/deploy parity profile。
4. 检查日志、warning、资源与视觉证据。
5. `git diff --check`，检查新增文件、平行命名和范围。

### Phase 5：独立审查

1. 冻结实现，不再编辑。
2. 同时创建 Reviewer A、Reviewer B；两个都是全新上下文、只读、互不可见。
3. 收齐两份审查；逐条处理 CONFIRMED/PLAUSIBLE。
4. 只要 diff 改变，回到 Phase 4，然后用两个新的 reviewer 重审。
5. 最终必须是两份 `CLEAN`，或只有有证据的 `NOT-A-FINDING`。

### Phase 6：commit 与 push

1. execution log 保持 `IN_PROGRESS`；只 stage 当前产品实现文件，检查 cached diff。
2. 子仓库按 `CONSTRAINTS.md §7.2` 先 commit/push/远端验证。
3. 主仓库 stage 已推送的子模块指针和当前任务的 shell/root 产品改动，commit/push/远端验证。
4. 收集已经稳定的产品 commit hash 和 remote receipt，更新 execution log 为 `COMPLETE` 或 `RESOLVED-NO-CODE`。
5. 创建一个新的只读 closure reviewer，核对状态、验收摘要、commit hash、remote ref 和 ancestor exit code；不得改产品实现。
6. 只 stage execution log，commit 为 `docs(execution): TNN close task record`，push 并验证远端。
7. 再次确认工作树只剩用户原有改动，才允许打开下一任务章节。

---

## 4. 验证配置

以下是计划中的命令集合名称。执行时必须运行真实命令并保存 exit code，不得只写集合名。

### `NIRI_FULL`

```bash
cd /home/wwt/niri/niri
cargo fmt --all -- --check
cargo test -p niri --lib
cargo check --workspace --all-targets
```

渲染或 backend 任务若 release 行为相关，再运行：

```bash
cargo build --release -p niri
```

### `QUICKSHELL_FULL`

```bash
cd /home/wwt/niri/quickshell
cmake --build build-tahoe
ctest --test-dir build-tahoe --output-on-failure
```

若 build-tahoe 不包含新测试，必须重新 configure 同一 build tree；不得改用一个遗漏 feature 的临时 build 来宣称通过。

### `SHELL_FULL`

```bash
cd /home/wwt/niri
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tahoe-shell/tests/
```

涉及生产 QML 行为时必须运行现有 qmltestrunner/真实 `qs` harness；pytest 源码正则不能替代。

### `PROTOCOL_FULL`

```bash
cd /home/wwt/niri
scripts/check-protocol-sync.sh
scripts/check-tahoe-glass-guardrails.sh
```

### `DEPLOY_READONLY`

```bash
cd /home/wwt/niri
scripts/arch-update.sh --verify-tahoe-shell
```

只读 parity 失败说明当前部署与源码不同，不自动部署。部署或重启需用户授权。

### `WORKTREE_GUARD`

```bash
cd /home/wwt/niri
git status --short
git diff --check
git diff --cached --check
git diff --cached --name-status
git diff --cached | rg '^\+.*(V2|New|Fixed|Alt|Legacy2|_new)\b' || true
```

---

## 5. 独立审查提示词

### Reviewer A：正确性、生命周期、并发

```text
你是只读对抗性 reviewer。不要修改文件，不要替实现者辩护。
审查任务 <TNN>，完整阅读 CONSTRAINTS.md、roadmap.md 的 <TNN>、最终 diff、专项/全量测试输出。

必须回答：
1. 根因是否被完整消除，还是仅隐藏告警/增加默认值/early return？
2. 是否遗漏同类调用点？给出 rg 命令和 file:line。
3. 是否引入锁重入、生命周期、late result、UAF、资源泄漏、动画 retarget 或协议时序问题？
4. 是否保持 CONSTRAINTS §3.2 的不变量和任务外行为？
5. 每个 Axx 验收是否有能捕获旧缺陷的证据？测试是否形式化但无效？
6. 注释是否与代码真实机制一致？

每条结论只能标记 CONFIRMED、PLAUSIBLE、NOT-A-FINDING 或 CLEAN。问题必须给 file:line、触发序列和修复要求。
```

### Reviewer B：范围、接口、UX、验收

```text
你是只读对抗性 reviewer。不要修改文件，不要只确认测试绿色。
审查任务 <TNN>，完整阅读 CONSTRAINTS.md、roadmap.md 的 <TNN>、最终 diff、测试与视觉/性能证据。

必须回答：
1. 是否完整迁移所有生产调用点，是否仍有旧 authority？
2. 是否创建功能重叠接口、新文件旁路、长期 feature flag 或可选第二路径？
3. 是否加入用户未要求的功能、设置、依赖、视觉变化或范围外重构？
4. pointer/keyboard/touch/reduced-motion/light/dark/scale/failure/cancel 等适用矩阵是否完整？
5. roadmap 每个 Axx 是否逐条满足？证据是否可重复？
6. 用户可见文案、状态、焦点、错误恢复和注释是否准确？

每条结论只能标记 CONFIRMED、PLAUSIBLE、NOT-A-FINDING 或 CLEAN。问题必须给 file:line 和未满足的 Axx。
```

---

## 6. Commit 与 push 收据

每个仓库提交前记录：

```bash
git branch --show-current
git remote -v
git diff --cached --stat
git diff --cached --name-status
```

push 后记录：

```bash
commit_id="$(git rev-parse HEAD)"
branch_name="$(git branch --show-current)"
git fetch origin "$branch_name"
git merge-base --is-ancestor "$commit_id" "origin/$branch_name"
```

最后一条 exit code 必须为 0。不得使用 force push，除非用户对具体 branch 明确授权。

产品 push 全部成功后，闭环记录必须包含稳定的产品 commit hash。闭环 docs commit 不写自己的 hash；其 remote 可达性在命令输出中验证，并由下一次 `git log -- execution-log.md` 解析。

---

## 7. 任务执行索引

下面每项都引用 `roadmap.md` 的唯一任务定义。执行者必须同时完成通用 `G01-G08` 和列出的专属 `Axx`，不能用本索引替代完整阅读 roadmap。

### T01 -> roadmap `T01 output layer teardown 闭环`

- **路线**：从现有 `remove_output` 和 layer destroy/null-commit 共用 teardown 机制入手；先收集 layer，再移除 output；不保留第二 map。
- **专项方法**：新增 niri lifecycle 测试，检查 `mapped_layer_surfaces`、hook、foreign rect、Tahoe transform 与 layer map；循环虚拟 output 100 次。
- **验收集合**：`A01.1-A01.5` + `NIRI_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：只发送 close、只给 map 加 retain、只在 destroy 分支补 remove 都不算完整。

### T02 -> roadmap `T02 window/output 生命周期 panic 清理`

- **路线**：分别建立 transient-parent placement 和 stale redraw 两条红测试，再原地修正现有 placement/redraw authority。
- **专项方法**：floating/scrolling × parent minimized/restored/destroyed；queued redraw × output removed/last output。
- **验收集合**：`A02.1-A02.5` + `NIRI_FULL`。
- **禁止替代**：删除 unwrap 后静默丢 dialog、用 `if !exists { return }` 隐藏所有 redraw、增加 safe API 旁路。

### T03 -> roadmap `T03 layer map 锁边界与 damage/redraw 归因`

- **路线**：画出 guard lifetime 和调用图；锁内只保留 map 原子操作；damage storage 与 root attribution 使用现有结构收敛。
- **专项方法**：10,000 region commit 的锁屏/DPMS harness；subsurface/root 多输出 attribution；可用时 TSAN。
- **验收集合**：`A03.1-A03.5` + `NIRI_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：增加第二 damage queue、把全输出 redraw 改名、用更大 Vec 上限掩盖无人排空。

### T04 -> roadmap `T04 pointer 缓存与 focus transaction`

- **路线**：枚举所有位置变化入口，统一更新现有缓存；把 focus clear 与 seat/button/surface transaction 绑定。
- **专项方法**：mouse/warp/tablet/touch、多按键交错、lock/VT/destroy、两种 scale/transform；重跑历史 deadlock harness。
- **验收集合**：`A04.1-A04.5` + `NIRI_FULL`。
- **禁止替代**：回调内重新查询 `current_location()`、新增第二坐标缓存、只补 mouse motion。

### T05 -> roadmap `T05 thumbnail 主循环预算`

- **路线**：保持现有 IPC，在内部做有界 request ownership、latest-wins、cache 和 cancellation；先测 event-loop heartbeat。
- **专项方法**：1,000 burst、4096²、client disconnect、window destroy、renderer reset；图像 hash 与旧路径对比。
- **验收集合**：`A05.1-A05.5` + `NIRI_FULL`，必要时 release trace。
- **禁止替代**：降低最大尺寸而无需求、返回占位图、创建 thumbnail-v2 IPC、无限后台队列。

### T06 -> roadmap `T06 QsPaths 失败状态机`

- **路线**：修正现有 DirState 读写与指针复用；用 dependency injection/临时目录制造失败。
- **专项方法**：base/shell/instance mkdir 失败组合、重复调用、link 创建/清理；ASan/UBSan 可用时运行。
- **验收集合**：`A06.1-A06.5` + `QUICKSHELL_FULL`。
- **禁止替代**：只把 Dock/launcher 调用包 try/catch、返回空 QDir 假装成功、增加 safe path helper。

### T07 -> roadmap `T07 FileView 非阻塞写状态机`

- **路线**：将现有 operation ownership 改成异步串行推进；迁移所有 blocking QML 调用者的依赖语义。
- **专项方法**：慢 writer + GUI heartbeat、rapid writes、path change、destroy、I/O failure、atomic/non-atomic；真实 QML harness。
- **验收集合**：`A07.1-A07.5` + `QUICKSHELL_FULL` + `SHELL_FULL`。
- **禁止替代**：把 block 移到另一个 GUI callback、另建 FileViewAsync、丢弃未定义中的在途写入。

### T08 -> roadmap `T08 TahoeGlass mapping 生命周期`

- **路线**：在现有 TahoeGlass QML object/attached type 暴露真实 mapping generation，接入 wl_surface mapping 生命周期；保持 Dock 属性名。
- **专项方法**：initial map、ordinary commit、unmap/remap、新 surface、protocol unavailable；日志检查和既有 R17 Dock 测试。
- **验收集合**：`A08.1-A08.5` + `QUICKSHELL_FULL` + `SHELL_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：`Number(undefined)||0`、Dock 私有计数器、timer 猜 mapping、取消 compositor slide。

### T09 -> roadmap `T09 TahoeGlass 完成/拒绝反馈`

- **路线**：先复现 pending morph；按 Wayland 兼容规则扩展同一协议；同任务同步 server、binding、QML authority。
- **专项方法**：permanent/healable overflow、serial supersede、retarget/cancel/destroy、旧 client；protocol generated diff 审查。
- **验收集合**：`A09.1-A09.5` + `NIRI_FULL` + `QUICKSHELL_FULL` + `SHELL_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：固定 timeout 猜完成、增加用户 legacy/new 开关、只改 server 不迁移 QML completion。

### T10 -> roadmap `T10 blur texture 容量复用`

- **路线**：先加入默认关闭/采样式归因，再原地改变 `Blur` pyramid capacity policy；定义 bucket、viewport、memory cap、shrink hysteresis。
- **专项方法**：1/2/8px resize、4K oscillation、format/pass/context/shared-ref、renderer reset；allocation/frame trace。
- **验收集合**：`A10.1-A10.5` + `NIRI_FULL` + release build/trace。
- **禁止替代**：无限保留最大纹理、另建 BlurPooled、只降低日志级别、固定所有 surface 到 4K。

### T11 -> roadmap `T11 glass capture 语义收敛`

- **路线**：稳定 structural padding，现有 plan 内做 alpha no-op，root attribution 收敛；shadow 顺序以像素基线决策。
- **专项方法**：hover/fade capture rect trace、alpha 0/restore、亮暗壁纸像素差、subsurface 多输出归因、scanout/xray。
- **验收集合**：`A11.1-A11.5` + `NIRI_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：取消所有 shadow、把 padding 固定成未经证明的大值、增加 glass-only redraw API。

### T12 -> roadmap `T12 每输出共享 backdrop 证据门禁`

- **路线**：先完成 `A12.G1-G4`。GO 时在现有 effect/blur ownership 内单路径替换；NO-GO 时只提交证据和防回归基线。
- **专项方法**：capture/blur trace、stack/z-order fixtures、memory model、workspace/screenshot/xray/multi-target pixels、output reset。
- **验收集合**：`A12.G1-G4`、`A12.1-A12.5` + `NIRI_FULL`；GO 时必须 release GPU trace。
- **禁止替代**：为了“有代码”强行实现、长期保留用户可选 old/new renderer、忽略 glass interleaving。

### T13 -> roadmap `T13 线性光与高精度 blur 证据门禁`

- **路线**：先建立 8-bit/nonlinear 与 linear reference 的像素误差；GO 时在同一 pipeline 内做 capability-gated format/transfer。
- **专项方法**：10-bit gradient、edge halo、实际壁纸、half-float capability、4K memory/frame/power；支持与不支持设备路径。
- **验收集合**：`A13.1-A13.5` + `NIRI_FULL` + release image/GPU trace。
- **禁止替代**：只有中间一半改 format 却重复 decode、用户开关、没有量化收益就改 shader。

### T14 -> roadmap `T14 灵动岛单一几何 driver`

- **路线**：用 profiler 还原 loop；选定一个现有 driver，删除其他 geometry completion authority；niri retarget 使用解析速度。
- **专项方法**：全部 content states、1,000 随机 retarget、四 motion profiles、fractional scale、region/input/paint pixels、日志零 loop。
- **验收集合**：`A14.1-A14.5` + `NIRI_FULL`（若改 niri）+ `SHELL_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：给 `geometryRevealProgress` 加 fallback 默认值、增加又一个 progress/latch 而不删除旧 owner、禁用 warning。

### T15 -> roadmap `T15 灵动岛交互/退场状态机`

- **路线**：统一 release-inside、reversible OSD retarget、velocity swipe 和 completion-derived mask/dismiss timing；删除重复裸常量。
- **专项方法**：drag-out/cancel/multi-touch、任意退场进度更新、fast/slow/reverse swipe、四 profile、destroy/unavailable。
- **验收集合**：`A15.1-A15.5` + `SHELL_FULL` + 真实 qmltestrunner。
- **禁止替代**：只把 onPressed 改 onReleased、固定一个新 timeout、增加手势模式设置。

### T16 -> roadmap `T16 shell active-state 工作预算`

- **路线**：在现有 Weather/Controls/Windows/Dock publisher authority 内加入 accumulator、backoff、frame coalescing 和正确 identity。
- **专项方法**：240 Hz paint/GC/CPU trace、udevadm missing/recovery、60/144/240 latency、Dock IPC dedupe/Genie endpoint。
- **验收集合**：`A16.1-A16.5` + `SHELL_FULL`；资源采样必须给前后数据。
- **禁止替代**：新增 FPS 设置、第二 brightness poller、固定换成另一个毫秒常量、丢弃合法 rect 更新。

### T17 -> roadmap `T17 主题、材质与字体 authority`

- **路线**：扩展现有 SettingsTheme 语义 tokens，迁移所有生产 surface/control，删除散落 authority，加入治理测试。
- **专项方法**：light/dark × 8 accent × 亮/暗壁纸视觉矩阵；literal/font 调用点清单；contrast 与 focus pixels。
- **验收集合**：`A17.1-A17.5` + `SHELL_FULL`。
- **禁止替代**：ThemeV2、新主题/皮肤、逐组件传一组新硬编码颜色、替用户增加字体设置。

### T18 -> roadmap `T18 共享控件键盘与 Accessibility`

- **路线**：原地升级共享原语并迁移生产交互点；自定义 gesture 控件实现同一 activation/accessibility 契约。
- **专项方法**：Qt accessibility tree、Tab/Backtab/Enter/Space/arrows/Home/End、pointer focus-ring、动态 delegate focus。
- **验收集合**：`A18.1-A18.5` + `SHELL_FULL` + 真实 qmltestrunner/accessibility probe。
- **禁止替代**：KeyboardButton/AccessibleToggle 旁路、仅给根窗口 Accessible name、只添加 Tab 而无 activation。

### T19 -> roadmap `T19 popup 几何、滚动与焦点闭环`

- **路线**：扩展现有 PopupGeometry，迁移全部 popup；统一 capped Flickable、overflow indicator、Escape/initial/restore focus。
- **专项方法**：3 分辨率 × 3 scale、anchor 边界、动态 menu、pointer/touch/wheel/keyboard、outside dismiss。
- **验收集合**：`A19.1-A19.5` + `SHELL_FULL` + 截图/geometry assertions。
- **禁止替代**：每个 popup 自己 clamp、强制最小高度越界、增加新的 popup manager。

### T20 -> roadmap `T20 图标、圆角、阴影与 fallback 收敛`

- **路线**：收敛现有 symbol/icon resolver、theme radii 和 niri shadow；所有视觉变化由固定场景证据驱动。
- **专项方法**：unknown icon/symbol、多个同类应用、nested radii、亮暗/重叠/fallback glass 快照与像素差。
- **验收集合**：`A20.1-A20.5` + `NIRI_FULL`（若改 shadow）+ `SHELL_FULL`。
- **禁止替代**：新图标主题/选择器、把应用伪装为其他品牌、纯装饰性大改、平行 squircle 控件。

### T21 -> roadmap `T21 异步操作真实完成状态`

- **路线**：在现有 CommandRunner/Process/service 内建立 action identity 和完成状态；Appearance 分离 desired/applied；复用现有反馈 UI。
- **专项方法**：fake success/nonzero/FailedToStart/timeout/cancel/late result；Power/Search/Appearance restart persistence；禁止真实 power。
- **验收集合**：`A21.1-A21.5` + `SHELL_FULL` + 真实 Process harness。
- **禁止替代**：spawn 后 delay 猜成功、所有失败都只 notify missing dependency、新状态页/高级开关。

### T22 -> roadmap `T22 日志轮转与诊断入口`

- **路线**：在现有 session wrapper 做 size/count rotation，现有 env 控制 debug sampling，提供只读实例日志定位。
- **专项方法**：临时目录超限/并发/rename fail/read-only、敏感字段扫描、默认/诊断日志量对比。
- **验收集合**：`A22.1-A22.5` + shell script tests + `SHELL_FULL`（若改 shell）。
- **禁止替代**：删除现有 3.55GB 文件、system daemon、把 Quickshell stdout 无界追加到同一文件、记录敏感内容。

### T23 -> roadmap `T23 多输出/混合缩放/热插拔整体验收`

- **路线**：扩展现有虚拟 output harness，验证所有 lifecycle；定义并实现 Genie cancel/reproject/endpoint strip 的唯一语义。
- **专项方法**：scale 1/1.25/2 × transform、100 hot-plug、mid-Genie、primary switch、renderer reset、last output。
- **验收集合**：`A23.1-A23.5` + `NIRI_FULL` + `QUICKSHELL_FULL` + `SHELL_FULL` + `PROTOCOL_FULL`。
- **禁止替代**：依赖真实拔线作为唯一测试、原样迁移旧 output-local rect、加 hotplug 专用动画接口。

### T24 -> roadmap `T24 全量回归、长时 soak 与收尾`

- **路线**：不开发新功能，只运行最终矩阵并修复 T01-T23 引入的可归因回归；更新证据状态。
- **专项方法**：60 分钟 idle + 场景 soak、PSS/FD/thread/QObject/texture/mapped-layer/log、frame p50/p95/p99、全部视觉/输入矩阵。
- **验收集合**：`A24.1-A24.7` + 所有 full profiles。
- **禁止替代**：短采样冒充 soak、RSS 单点冒充泄漏结论、修复路线图外历史问题、把需用户操作项标为通过。

---

## 8. `RESOLVED-NO-CODE` 路线

仅当任务前提被当前源码和可重复测试反证时允许：

1. 在旧实现上运行原计划的复现，证明不失败。
2. 给出源码不变量和为什么旧报告失效。
3. 检查是否已有测试真正保护该不变量。
4. 必要时只补测试/证据；不得做无关代码改动。
5. 两个独立 reviewer 审查“无需产品代码”的判断和测试充分性。
6. 提交/push execution log、测试或报告校正。

T12/T13 的 GO 门禁不满足时，按本路线关闭是预期结果，不等于跳过任务。

---

## 9. 必须询问用户的节点

以下情况停止当前任务并请求明确授权：

- 需要重启 niri、Quickshell 或登录会话完成验收。
- 需要真实拔插显示器、切换 VT 或触发系统 suspend/reboot/poweroff。
- 需要删除/压缩现有用户日志或其他用户数据。
- 需要 force push、改 remote、改默认 branch 或解决远端非 fast-forward。
- 发现 roadmap 任务方向错误且会改变任务边界。
- 用户同时修改了当前任务的同一逻辑，无法安全合并。

等待授权期间任务保持 `BLOCKED`，不得开始下一任务。

---

## 10. 最终完成定义

路线图只有在以下条件全部满足时结束：

- T01-T24 全部为 `COMPLETE` 或双审查的 `RESOLVED-NO-CODE`。
- 每项都有专项/全量测试、两份终审、commit/push/remote receipt。
- 所有子模块 remote 包含主仓库指向的 commit。
- 当前源码、部署版本和最终证据的 commit 指纹明确。
- 没有未裁决 finding、TODO、临时 flag、平行接口或用户未要求功能。
- 需要用户现场完成的验证单独列出，未伪装成自动验收通过。
