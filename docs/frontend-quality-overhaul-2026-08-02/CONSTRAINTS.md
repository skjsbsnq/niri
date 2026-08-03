# OpenCode / DeepSeek V4 Flash 执行硬约束

**适用范围**：`roadmap.md` 中 T01-T24 的全部工作。
**执行环境**：OpenCode，执行模型 DeepSeek V4 Flash。
**权威顺序**：用户最新指令 > 本文件 > `roadmap.md` > `execution-plan.md` > `research-report.md` > 旧文档。
**判定原则**：违反任一 MUST / MUST NOT 即任务失败；不得提交，不得推送，不得开始下一任务。

---

## 0. 每次启动必须复述的十二条

1. **MUST 完整实现当前任务，MUST NOT 做最小实现、部分实现、占位实现或 TODO 实现。**
2. **MUST 原地改造现有 authority，MUST NOT 创建功能重叠的平行接口。**
3. **MUST 保持既有功能；唯一允许的行为变化是当前 roadmap 任务明确要求的变化。**
4. **MUST NOT 添加用户未要求的功能、设置、主题、动画模式、开关、依赖或“顺手优化”。**
5. **MUST 严格串行；任意时刻只能有一个 roadmap 任务处于执行中。**
6. **当前任务未完成、未通过独立审查、未 commit、未 push、未验证远端前，MUST NOT 开始下一任务。**
7. **MUST 先核实源码和复现前提；文档行号、旧日志和旧结论不能替代当前源码。**
8. **MUST 用能捕获真实缺陷的测试证明修复，MUST NOT 通过弱化或删除断言换取绿色。**
9. **每个任务 commit 前 MUST 由至少两个全新、互相独立、只读的子代理进行对抗性审查。**
10. **任一 CONFIRMED 审查问题未修复，或任一 PLAUSIBLE 问题未书面裁决，MUST NOT commit。**
11. **修改 niri/Quickshell 源码后 MUST 构建实际二进制；修改 shell 后 MUST 验证 source/deploy parity。**
12. **未经用户明确同意，MUST NOT 重启实时会话、触发 suspend/reboot/poweroff、删除用户数据或破坏当前桌面。**

执行器必须把以上十二条原样放进每个任务的工作上下文。仅“阅读过一次”不算满足。

---

## 1. 完整实现，禁止最小实现

### 1.1 以下全部属于失败

- 只修报告给出的单个调用点，不搜索同类路径。
- 只处理 happy path，忽略 roadmap 验收列出的失败、取消、热插拔、缩放或 reduced-motion 场景。
- 用 early return、默认值或吞错把告警藏起来，但状态机仍然错误。
- 加 `TODO`、`FIXME`、`later`、`temporary`、`compat hack` 作为未完成工作的替代。
- 只增加静态正则测试，却没有能让旧代码失败的行为测试。
- 因改动较大而擅自缩小任务范围。
- 把当前任务的一部分延期到未定义的“后续任务”。

### 1.2 完整性的证明

每个任务在实现前必须：

1. 使用 `rg` 找出相关 symbol、属性、调用点和测试。
2. 把搜索结果数量、需要修改与明确不修改的点写入 `execution-log.md`。
3. 对每个不修改点给出行为理由和 `file:line`。
4. 建立失败基线：测试在旧实现上失败，或以现有日志/可重复 probe 证明缺陷。
5. 完成 roadmap 中该任务的每一项 `Axx` 验收标准。

若发现任务范围比 roadmap 更大，只能在**同一职责边界内**扩展当前任务并记录；若扩展会进入另一个 roadmap 任务的职责，立即停止并请求用户调整路线图，不能越界施工。

---

## 2. 原地收敛，禁止平行接口

### 2.1 平行接口定义

只要同一语义存在两个长期 authority，即属于平行接口，与名称无关。禁止示例：

| 禁止形态 | 失败原因 |
|---|---|
| `fooV2()`、`fooNew()`、`fooFixed()` 与 `foo()` 并存 | 两个入口承担同一职责 |
| `MotionV2.js`、`ThemeNew.js`、`GlassPanelFixed.qml` | 复制既有模块职责 |
| 新增 feature flag 长期保留旧错误路径 | 两套行为长期并存 |
| 复制旧函数后只迁移部分调用点 | authority 分裂 |
| 新 service 旁路现有 Controls/CommandRunner/Appearance | 状态来源不唯一 |
| 为测试专门增加生产入口 | 测试接口污染产品设计 |

### 2.2 允许的结构性重构

- 可以拆分过长函数，但原公共入口必须删除或成为**无条件委托**的薄包装。
- 可以给现有类型增加完成其既有职责所必需的属性、signal 或内部状态。
- 可以新增当前仓库确实不存在的职责模块，但必须先给出全仓 `rg` 证据，并迁移所有相关调用点，删除被替代的散落 authority。
- Wayland 协议可以在同一协议族中按兼容规则增加版本和 event；Quickshell 对外仍只能暴露一套 TahoeGlass 语义。协议版本兼容分支不是用户可选的第二套接口。
- 硬件 capability fallback 可以存在，但必须位于同一内部接口后，自动选择、等价可观察行为、测试两条 capability 路径，不得暴露新设置开关。

### 2.3 commit 前的平行接口扫描

```bash
cd /home/wwt/niri
git diff --cached --name-status
git diff --cached | rg '^\+.*(V2|New|Fixed|Alt|Legacy2|_new)\b' || true
git diff --cached --name-only --diff-filter=A
```

新增文件不是自动失败，但完成记录必须回答：为什么现有模块不能承担职责、哪些旧 authority 被迁移/删除、为什么不存在双路径。

---

## 3. 保持既有功能，禁止范围蔓延

### 3.1 行为保护

- 改共享模块前必须列出全部调用者并建立回归矩阵。
- 删除或改变带“why”注释的代码前，必须读引入提交和相邻测试。
- 不得改测试断言来适配实现，除非当前任务明确要求该行为改变；此时必须同时提供旧行为失败、新行为通过的证据。
- 不得更换视觉语言、交互语义或默认值，只因为执行模型认为另一种更好。
- 不得新增遥测上报、联网、账户、推荐、通知、设置或后台进程。
- 不得顺手格式化、重命名或重构当前任务之外的文件。

### 3.2 必须保护的不变量

| 不变量 | 保护理由 |
|---|---|
| Smithay pointer/grab 回调内不得调用 `pointer.current_location()` | 会重入 `PointerInternal` mutex；历史已有两个 deadlock core |
| pointer 位置缓存必须随所有真实位置变化同步更新 | 不能以避免死锁为代价使用陈旧坐标 |
| Control Center morph 只能有一个几何 progress authority | 已消除独立 Behavior 竞争和面板底边跳动 |
| Tahoe glass region 不得 overshoot 绘制边界 | 会暴露未绘制的原始 glass 区域 |
| region 尺寸 floor、半径 ceil 的安全方向 | 防止 fractional-scale 外溢；整体替换需等价证明 |
| Dock 磁化现有速度连续策略 | 不得重新引入 `Spring.restart()` 式断速 |
| popup 互斥和 outside-dismiss 仍由 ShellPopupState/PopupDismissLayer 统一管理 | 不允许每个 popup 自建关闭体系 |
| latest-wins/generation/stable identity 现有语义 | 防止异步晚结果覆盖与 delegate 重建 |
| `identifierPairing` fail-closed 清除 | 防止使用陈旧 toplevel id |
| reduced-motion 必须覆盖所有新增/重构动画 | 可访问性与既有用户设置 |

### 3.3 明确非目标

本路线图不授权新增：设置项、主题、皮肤、动画 profile、面板、快捷方式、应用启动逻辑、网络功能、AI 功能、账户功能、插件、后台服务、A/B 开关。需要这些内容时必须由用户另行授权并修改 roadmap。

---

## 4. 严格串行状态机

唯一合法流程：

```text
读取 TNN
  -> 核实前提和工作区
  -> 写失败基线/测试
  -> 完整实现
  -> 专项验证 + 受影响仓库全量验证
  -> 两个独立子代理对抗审查
  -> 修复所有 CONFIRMED / 裁决所有 PLAUSIBLE
  -> 两个全新子代理重新审查
  -> 更新本任务执行记录
  -> stage 并检查范围
  -> 子仓库 commit + push + 远端验证（如涉及）
  -> 主仓库 commit + push + 远端验证
  -> 将 TNN 标为 COMPLETE
  -> 才能读取并开始 T(N+1)
```

### 4.1 不允许跳任务

- 当前任务被阻塞时，状态是 `BLOCKED`，整个执行停止并请求用户处理。
- 不能因为另一个任务“更容易”而跳过去。
- 不能同时开两个实现分支或让子代理并行写代码。
- 子代理只做只读审查，不得实现、修复、commit 或 push。
- 发现下一任务的问题只能记入当前记录的“后续边界”，不得修改。

### 4.2 前提不成立的任务如何完成

若当前源码已经正确或报告前提错误：

1. 提供能反证原判断的源码、测试与运行证据。
2. 不做无关代码改动。
3. 把任务记为 `RESOLVED-NO-CODE`，补上防止错误前提再次出现的必要测试或文档；若连测试也无合理价值，必须说明。
4. 仍需两个独立子代理审查该处置。
5. 仍需按任务提交并推送证据记录。
6. 完成以上步骤后才可进入下一任务。

---

## 5. 测试与验收真实性

### 5.1 红绿证明

- bugfix 测试必须证明在旧实现上失败，在新实现上通过。
- 无法安全运行真实故障时，必须构造确定性 harness；不得执行真实 reboot/poweroff 或破坏当前会话。
- 正则/源码合同测试只能作为 guardrail，不能替代行为测试。
- 性能任务必须比较同一场景、同一构建、同一输出配置的前后数据，报告 p50/p95/p99 或明确计数，不得只给平均值。
- 图像质量任务必须保存固定场景截图或像素统计，并覆盖亮/暗背景、重叠 glass、fractional scale 和 reduced motion。

### 5.2 全量验证

专项测试通过后，按受影响仓库运行：

```bash
# niri
cd /home/wwt/niri/niri
cargo fmt --all -- --check
cargo test -p niri --lib
cargo check --workspace --all-targets

# Quickshell
cd /home/wwt/niri/quickshell
cmake --build build-tahoe
ctest --test-dir build-tahoe --output-on-failure

# Tahoe shell
cd /home/wwt/niri
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tahoe-shell/tests/

# 协议与部署静态一致性
cd /home/wwt/niri
scripts/check-protocol-sync.sh
scripts/check-tahoe-glass-guardrails.sh
scripts/arch-update.sh --verify-tahoe-shell
```

命令不存在或基线失败时，不得伪造绿色。先在 execution log 记录命令、exit code、完整失败名和“改动前是否已失败”，再按 roadmap 当前任务处置。

---

## 6. 独立子代理审查门禁

### 6.1 数量与隔离

- 至少两个新子代理；不得复用实现上下文或上一次审查上下文。
- 两个代理不得看到对方结论。
- 审查输入只包含：当前任务 roadmap 段、CONSTRAINTS、基线证据、完整 diff、测试输出。
- 审查代理必须只读。任何代理修改文件，审查作废。

### 6.2 两个互补角色

**Reviewer A：正确性/生命周期/并发**，必须检查：

1. 根因是否真实消除，而非隐藏告警。
2. 生命周期、锁、回调、异步晚结果和动画 retarget 是否有新竞态。
3. 旧行为和 §3.2 不变量是否保持。
4. 测试是否能让旧代码失败。

**Reviewer B：范围/接口/UX/验收**，必须检查：

1. 是否遗漏同类调用点。
2. 是否创建平行接口或未迁移旧 authority。
3. 是否加入 roadmap 外功能、开关或依赖。
4. roadmap 的每个验收编号是否有证据。
5. 注释、文档和用户可见语义是否准确。

### 6.3 结论协议

每条 finding 必须是：

- `CONFIRMED`：有 `file:line` 和失败机制；必须修复。
- `PLAUSIBLE`：证据不完整但机制合理；执行者必须接受并修复，或以代码/测试反证。
- `NOT-A-FINDING`：明确说明为何不成立。
- `CLEAN`：在给定范围内未发现问题。

任一修改后，旧审查结论失效。必须让两个**新的**子代理对最终 diff 重新审查。OpenCode 无法提供独立子代理时，任务必须停止，不能用自审替代。

---

## 7. Commit、Push 与多仓库顺序

### 7.1 一个任务一个产品提交闭包

- 同一产品仓库内一个 roadmap 任务对应一个实现 commit；跨子仓库时每个受影响仓库各有一个同任务 commit。
- 不得把两个任务合并。
- 不得把无关工作树改动带入 stage。
- commit message 必须包含任务编号和验收/审查摘要。
- push 收据只能在 push 后产生，因此每个任务最后允许并要求一个**主仓库 docs-only 闭环 commit**，只记录精确 remote receipt、最终状态和现场验证清单。它不得包含产品代码。

```text
<type>(<scope>): TNN <简述>

根因：...
实现：...
验收：Axx...Ayy
审查：Reviewer A CLEAN；Reviewer B CLEAN
```

### 7.2 子仓库与闭环顺序

涉及 `niri/` 或 `quickshell/` 时：

1. 在子仓库完成实现、测试、双审查。
2. 子仓库 commit。
3. 子仓库 push。
4. 用 `git merge-base --is-ancestor <hash> <remote>/<branch>` 验证远端包含该 commit。
5. 回到主仓库，只 stage 子模块指针与本任务的 Tahoe shell/root 产品改动；此时 execution log 保持 `IN_PROGRESS`，不得伪造尚未发生的 push 收据。
6. 对主仓库最终 diff 再执行范围检查；跨层任务的 reviewer 必须已看过完整组合 diff。
7. 主仓库 commit、push、验证远端。
8. 收集所有真实 remote receipt，更新 execution log 为 `COMPLETE` 或 `RESOLVED-NO-CODE`。
9. 用一个新的只读子代理只审查闭环记录的准确性、任务状态和 remote receipt；产品实现不得在此阶段改变。
10. 创建并 push `docs(execution): TNN close task record` 主仓库 commit，再验证远端。

主仓库绝不能先指向远端不存在的子仓库 commit。

### 7.3 execution log 的 hash 与收据

产品 commit 的 hash 在 docs-only 闭环 commit 生成前已经稳定，因此日志必须记录产品 commit hash、subject、仓库、branch、remote ref、push 验证命令与结果。闭环 commit 不记录自己的自引用 hash；它用固定 subject 和 remote ref，可由 `git log --format=%H -- execution-log.md` 解析。

### 7.4 未经授权不得替用户做的事

本文件约束未来执行器的 commit/push 顺序，但不扩大当前会话权限。若用户只要求研究或文档，不能据此修改代码、commit 或 push。真正执行 T01-T24 时，OpenCode 会话必须确认用户已经授权执行该路线图。

---

## 8. 构建、部署和实时会话边界

- 修改 niri：必须构建并确认二进制 commit；运行时验证若需替换当前 compositor，停下来请用户操作。
- 修改 Quickshell C++：必须构建和 ctest；安装或重启当前 shell 前请用户授权。
- 修改 Tahoe shell：可以构建/测试；部署前运行 manifest parity 预检，热重载可能影响当前桌面时请用户授权。
- power action 测试必须使用 fake Process/harness，禁止真实 suspend/reboot/poweroff。
- hot-plug 测试优先虚拟 output/headless harness；真实拔插只由用户执行。
- 日志轮转测试必须使用临时目录，禁止删除现有 3.55 GB 用户日志，除非用户单独授权。

---

## 9. 工作树保护

当前已知用户项包括 `.zcode/`、`Testing/` 和本 docs 目录。执行器必须把所有未知改动视为用户工作，不得 reset、checkout、clean、stash 或删除。

每个任务开始和 commit 前运行：

```bash
git status --short
git diff --check
git diff --cached --check
git diff --cached --name-status
```

若用户改动与当前任务重叠，先理解并兼容；确实无法安全继续时停下询问。禁止 `git reset --hard`、`git checkout -- <path>`、`git clean` 和针对宽目录的删除命令。

---

## 10. 文档与状态

- `research-report.md` 是可校正的证据文档，不是不可变历史。只有发现可引用的新证据时才能修改，并在 changelog 段说明。
- `roadmap.md` 是唯一任务边界。执行器不得从研究报告自行新增任务。
- `execution-plan.md` 是执行机制和命令入口，不能改变 roadmap 顺序。
- `execution-log.md` 是证据账本，不得写入未执行、未测量或未推送的结论。
- 任务状态只允许 `PENDING`、`IN_PROGRESS`、`BLOCKED`、`RESOLVED-NO-CODE`、`COMPLETE`。

只要当前任务不是 `COMPLETE` 或经过双审查的 `RESOLVED-NO-CODE`，下一任务就必须保持 `PENDING`。
