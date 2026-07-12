# Tahoe Desktop 源代码独立审查研究报告与 Grok 4.5 串行修复路线图

生成日期：2026-07-12
工作区：`/home/wwt/niri`
用途：交给 Grok 4.5 按任务严格串行修复
研究范围：当前源代码与测试代码；不采用旧文档作为事实依据
执行原则：一次只修一个根因；测试、独立审查、commit、push 全部成功后才能进入下一项

---

## 1. 执行摘要

本次独立审查确认或高度怀疑 22 组会影响用户体验、视觉质量、动画正确性、生命周期或性能的问题。为了坚持“一个根因一个 commit”，其中 Dynamic Island 媒体输入问题被拆成两个原子任务，因此路线图共有 23 个执行任务。最高风险集中在四类：

1. **对象身份错位**：异步结果或延迟回调写入了已经换绑的新对象，例如 AppMenu、应用权限和通知滑动删除。
2. **输入与交互生命周期不完整**：Dynamic Island 的外层输入区遮挡媒体按钮，且 press/release/cancel 不对称。
3. **玻璃协议和渲染生命周期错误**：controller 销毁不清状态，快速反向动画时裁剪与缩放坐标不一致。
4. **重复工作造成性能压力**：玻璃区域全量重发、常驻 Python/剪贴板轮询、重复缩略图捕获和持续重定向动画。

建议按本文给出的 Task 01A、Task 01B、Task 02 至 Task 22 顺序执行。该顺序优先处理直接功能故障和会污染后续验证的基础生命周期问题，再处理数据一致性、渲染语义和性能。

任何任务都不得批量合并执行。即使两个问题位于同一个文件，也必须按任务边界分别修复、审查、提交和推送。

---

## 2. 仓库、分支与提交拓扑

当前项目包含父仓及两个 Git 子仓。执行者必须先确认实际状态，不得假设本文记录永远不变。

| 仓库 | 本地目录 | 当前分支 | push 目标 |
|---|---|---|---|
| 父仓 | `/home/wwt/niri` | `main` | `origin/main`，远端 `https://github.com/skjsbsnq/niri.git` |
| niri 子仓 | `/home/wwt/niri/niri` | `tahoe-layer-animations` | `origin/tahoe-layer-animations`，远端 `https://github.com/skjsbsnq/tahoe-desktop.git` |
| quickshell 子仓 | `/home/wwt/niri/quickshell` | `quickshell-tahoe-desktop` | `origin/quickshell-tahoe-desktop`，远端 `https://github.com/skjsbsnq/quickshell.git` |

### 2.1 子仓任务的强制提交顺序

修改 `niri/` 或 `quickshell/` 时，一个逻辑任务需要两个串行提交阶段，但仍属于同一个任务，不能夹入其他任务：

1. 在子仓中实现、测试并完成独立审查。
2. 在子仓中只暂存本任务文件，commit。
3. push 子仓当前分支。
4. 验证远端分支包含该子仓 commit。
5. 回到父仓，只暂存对应子模块指针。
6. 在父仓创建单独的指针更新 commit。
7. push 父仓 `main`。
8. 验证父仓远端包含指针 commit，且指针指向刚刚推送的子仓 commit。
9. 完成以上全部步骤后，本任务才算完成。

禁止先提交父仓指针再推子仓；否则父仓远端会引用一个其他人无法获取的子仓 commit。

### 2.2 当前脏工作区保护

审查时工作区已经存在用户改动，包括父仓配置、测试、`niri` 子仓渲染代码以及未跟踪文件。执行者必须把这些视为用户资产。

强制规则：

- 禁止 `git reset --hard`、`git clean`、`git checkout -- <path>`、`git restore <path>` 或任何丢弃现有改动的操作。
- 禁止 `git add .` 和 `git add -A`。
- 禁止任何形式的 force push，包括 `--force` 和 `--force-with-lease`；禁止执行未经用户授权的 rebase、merge、pull 或改写远端历史。
- 每个任务开始时分别记录父仓、`niri`、`quickshell` 的 `git status --short` 和 diff 基线。
- 只逐文件、逐 hunk 暂存本任务新增改动。
- 如果本任务与用户既有改动落在同一 hunk，且无法可靠区分，立即停止并报告，不能擅自把整段既有修改纳入提交。
- 不得为了得到“干净工作树”而 stash 用户改动，除非用户明确授权；默认不 stash。

---

## 3. Grok 4.5 总控提示词

使用方式：每次只把本节总控提示词与后文一个 Task 卡片一起交给 Grok 4.5。不得一次发送多个 Task 卡片并让其连续自行执行。

```text
你正在修复一个已有项目。必须严格遵守以下执行契约。

一、任务范围与严格串行
1. 本轮只允许处理我指定的一个任务，不得提前研究性修改、顺手修复或暂存其他任务。
2. 当前任务必须依次完成：基线检查 → 根因分析 → 实现 → 测试 → 独立子代理审查 → 必要时返工并重新测试/重新审查 → commit → push → 远端确认。
3. 只有测试全部通过、独立审查最终为 APPROVE、commit 成功、push 成功且远端确认包含该 commit，才允许输出 TASK STATUS: COMPLETE。
4. 任一步失败都必须停留在当前任务。不得开始下一任务。
5. push 因权限、认证、网络或远端拒绝失败时，输出 TASK STATUS: BLOCKED 和准确原因，立即停止。

二、反腐化与单一事实来源
1. 必须修复现有状态 owner、生命周期 owner 或现有接口本身。不得创建平行接口、第二套状态、兼容旁路或第二条刷新管线。
2. 禁止新增 safeXxx、newXxx、fixedXxx、xxx2、legacyXxx 等绕开原接口的入口。
3. 禁止复制 active/current/selected/pending/model/cache 等权威状态。
4. 禁止同时保留旧轮询与新事件源、旧全量路径与新增量路径而形成双写或双读。
5. 若确实需要新增字段，它必须只是现有状态机不可缺少的 request generation、稳定对象 ID、生命周期 token 或待执行标记，并由原 owner 唯一维护；不得成为第二份业务状态。
6. 异步竞态必须用对象身份或请求 generation 解决。延迟、debounce、增加 Timer、重复 refresh 或 catch-all 不是身份校验。
7. 生命周期清理必须发生在真正 owner 的 destroy/drop/resource-destroyed 边界，不得依赖下一帧、下一次刷新、下一次 commit 或 UI 隐藏。
8. 不得用关闭动画、禁用 blur/spring/clip、强制 scale=1、降低刷新质量等方式隐藏问题。

三、功能保护
1. 不得破坏现有输入行为、动画语义、协议兼容性、fallback、多屏行为、配置格式和公开 API。
2. 不得做与本任务无关的重构、统一命名、全仓格式化、依赖升级或清理。
3. 不得删除功能、降低断言、扩大容差、跳过测试或把失败测试标记为 flaky。
4. 只以当前源代码、测试和实际接口为事实依据；不要依赖旧文档决定实现。
5. 保留用户已有改动。禁止 reset、clean、checkout 丢弃、全量暂存。

四、实施阶段
A. 基线：输出当前仓库、分支、remote、HEAD、git status；记录用户既有修改；定位状态 owner、调用方和测试。
B. 根因：写出确定的事件顺序/状态转换、错误写入位置、正确修复层、受保护行为和计划修改文件。写代码前完成。
C. 实现：只做最小但完整的架构内修复；添加能复现旧错误的回归测试。
D. 验证：先跑最小相关测试，再跑受影响模块测试；按风险编译或运行更广测试；执行 git diff --check；检查无调试代码、生成文件和无关格式变化。
E. 暂存：测试通过后，只逐文件/逐 hunk 暂存本任务。开始时已脏的文件必须使用交互式逐 hunk 暂存；只有基线确认原本干净的文件才允许整文件暂存。显示最终 staged diff，并计算其稳定哈希。
F. 独立审查：启动一个没有参与实现的独立子代理。子代理只读，不得修改。必须审查最终 staged diff，而不是未暂存 working diff；同时查看原问题、根因、测试和反腐化约束，并输出 VERDICT: APPROVE 或 VERDICT: REQUEST_CHANGES。
G. 返工：若 REQUEST_CHANGES，先取消本任务暂存，修复后重新运行全部相关测试，重新形成 staged diff、重新计算哈希并启动新的独立审查轮次。旧审查结论和旧哈希全部失效。
H. 提交：最终 APPROVE 后，不得再修改 working tree 或 index；重新计算 staged diff 哈希并确认与审查输入完全一致，然后直接创建一个可回滚 commit，记录 hash。
I. 推送：普通 push 到任务指定远端分支并验证远端包含该 hash。禁止 force push、擅自 pull/rebase/merge 或改写历史。子仓任务还必须在父仓提交并 push 子模块指针。

五、停止条件
出现以下任一情况立即停止，不得扩大范围：
- 必须修改未授权的公开协议、配置格式或用户可见语义；
- 无法区分用户原有修改和本任务改动；
- 无关测试失败且无法证明与本任务有关；
- 独立审查要求架构决策；
- 无法 push；
- 修复需要大量无关文件或通用框架重构。

六、最终报告格式
TASK STATUS: COMPLETE | BLOCKED | FAILED
TASK:
ROOT CAUSE:
FIX:
FILES CHANGED:
TESTS ADDED/UPDATED:
VALIDATION COMMANDS AND RESULTS:
INDEPENDENT REVIEW VERDICT AND ROUND:
COMMIT HASH:
PUSH REMOTE/BRANCH AND VERIFICATION:
PARENT SUBMODULE POINTER COMMIT（如适用）:
REMAINING RISKS:
OUT-OF-SCOPE FINDINGS（只记录，不修改）:
```

---

## 4. 独立子代理审查提示词模板

每个任务实现并测试后，必须开启一个没有参与实现的独立子代理，并使用以下模板。若返工，必须重新开启新的审查轮次。

```text
你是本任务的独立审查代理。你没有参与实现，只允许读取源代码、完整 diff、测试输出和 git 状态，不得修改任何文件。

原始问题：
[粘贴当前 Task 的问题和触发过程]

预期根因与状态 owner：
[粘贴根因、权威状态和正确修复层]

实现者声称的修复：
[粘贴具体机制，不要只写“已修复”]

最终 staged diff 及哈希：
[提供 git diff --cached --binary 的完整内容和 SHA-256；子仓任务提供子仓最终 staged diff。父仓 gitlink 指针在子仓 push 后另行形成 staged diff，并按文中门禁复核]

已运行测试：
[命令、退出码、通过/失败数量]

请主动审查：
1. 是否修复真正 owner，而不是在 UI 或调用方掩盖症状；
2. 是否引入平行 API、第二份状态、双刷新、双缓存、兼容旁路或名称相似的新入口；
3. success、failure、cancel、destroy、recreate、旧回调晚到是否都受同一身份/生命周期保护；
4. Timer、动画完成回调和 delegate 换绑是否使用稳定 ID；
5. 输入 press/move/release/cancel/grab loss 是否完整配对；
6. 动画快速反向、非 1.0 scale、多输出 scale、fallback 是否回归；
7. 生命周期清理是否位于资源 owner，并且不会让旧 owner 清掉新 owner 状态；
8. 测试是否能在旧实现上失败，是否只是搜索 token 或验证实现细节；
9. 是否包含无关修改、调试代码、降低断言、功能删除或性能倒退；
10. 用户既有改动是否被意外纳入 staged diff。
11. 当前 staged diff 的 SHA-256 是否与实现者声明一致；若审查后 index 改变，当前 APPROVE 必须失效。

输出格式必须严格为：
VERDICT: APPROVE
或
VERDICT: REQUEST_CHANGES

FINDINGS:
- [严重度] 文件:行号 — 问题、触发条件、影响、修复方向

TEST_GAPS:
- 缺失测试；没有则写 None

ANTI_CORRUPTION_CHECK:
- 单一事实来源是否保持
- 是否存在平行接口/双写路径
- 是否修改了正确 owner

不得因为测试通过而自动批准。没有具体证据时不得输出 APPROVE。
```

---

## 5. 任务依赖与严格执行顺序

```text
Task 01A
  → 实现
  → 测试
  → 最终暂存并计算 staged diff 哈希
  → 独立审查最终 staged diff
  → 若需返工：取消暂存 → 修改 → 全量相关测试 → 重新暂存/哈希 → 新审查轮次
  → commit
  → push
  → 远端确认
  → Task 01B
```

推荐顺序：

1. Task 01A–04：直接误操作、不可点击和跨对象状态污染。
2. Task 05–06：协议生命周期和动画裁剪基础正确性。
3. Task 07–12：数据新鲜度、通知/手势和会话生命周期。
4. Task 13–16：玻璃几何、提交成本、fallback 与采样边界。
5. Task 17–22：重复捕获、常驻轮询和低风险体验/性能问题。

Task 03 必须先于 Task 19，因为先解决 AppMenu 身份正确性，再优化其刷新策略，才能避免性能修改掩盖竞态。
Task 05 必须先于 Task 14，因为协议生命周期需要先稳定，再优化 region 更新方式。
Task 06 必须先于 Task 13 和 Task 16，因为裁剪坐标契约是 transform 跟踪和 sample padding 的基础。
Task 01A 必须先于 Task 01B：先补齐媒体按钮的 press/release/cancel 生命周期，再恢复按钮输入可达性，避免短暂引入“按钮可点但 userInteracting 永久卡住”的远端提交。
Task 01B 必须先于 Task 11，因为媒体按钮恢复可达性后，才能可靠验证手势与子控件冲突。

---

## 6. 逐任务修复卡片

下面每个 Task 卡片都要与第 3 节总控提示词一起交给 Grok 4.5。

### Task 01A：闭合 Dynamic Island 媒体按钮交互生命周期

**优先级：高**
**仓库：父仓**
**唯一目标：** 在不改变当前输入层级的前提下，为媒体按钮补齐 press/release/cancel/grab loss 的对称交互生命周期，保证未来按钮恢复可达后不会把 `userInteracting` 永久卡在 true。

**源代码证据：**

- `tahoe-shell/components/DynamicIslandOverlay.qml:233-316`
- `tahoe-shell/components/DynamicIslandOverlay.qml:368-417`
- `tahoe-shell/components/DynamicIslandMediaView.qml:179-219`
- `tahoe-shell/components/DynamicIslandMediaView.qml:318-403`
- `tahoe-shell/services/DynamicIsland.qml:669-677,749-754`

**根因：** 媒体按钮只有 pressed，没有 released/canceled，对 `setUserInteracting(true)` 没有对称释放。这是独立于 z-order 的生命周期根因。

**允许修改：** `DynamicIslandMediaView.qml`、`DynamicIslandOverlay.qml` 中媒体控件信号连接及专门生命周期测试。只有现有 `setUserInteracting()` 调用关系确实无法表达对称生命周期时，才可做最小调整。

**禁止：**

- 禁止修改外层 capsule MouseArea 的 z-order、enabled、事件传播或命中行为；输入可达性属于 Task 01B。
- 禁止复制 `mediaPrevious/mediaTogglePlayPause/mediaNext` 接口。
- 禁止本任务顺手修改 swipe 距离判定；那属于 Task 11。

**实现提示：** 在现有媒体按钮组件上形成完整的 pressed/released/canceled 信号契约，并让 Overlay 对称调用现有 `setUserInteracting()`。注意 disabled 按钮、按下移出、取消、grab loss 和组件销毁。不得新增第二份 interacting 状态。

**验收：**

- press 后移出、cancel、grab loss 均不会遗留 `userInteracting=true`。
- 正常 release 会恢复 false；重复 release/cancel 幂等。
- disabled 按钮不进入 interacting。
- 本任务不声称按钮已经可点击；输入可达性由 Task 01B 完成。

**测试：** 增加可验证 press/release/cancel 信号对称性和 interacting 复位的测试；运行 `python3 -m pytest -q tahoe-shell/tests`。

**独立审查重点：** release/cancel/grab loss 对称性、组件销毁、是否出现第二份 interacting 状态；确认没有提前修改 z-order。

**建议 commit：** `fix(dynamic-island): close media interaction lifecycle`

---

### Task 01B：恢复 Dynamic Island 媒体按钮输入可达性

**优先级：高**
**仓库：父仓**
**依赖：** Task 01A 已 commit、push 并远端确认。

**唯一目标：** 让上一首、播放/暂停、下一首按钮可靠接收输入，同时保持 capsule 空白区域的现有 click/swipe 行为；不得修改通用 swipe 阈值。

**源代码证据：**

- `tahoe-shell/components/DynamicIslandOverlay.qml:233-316,368-417`
- `tahoe-shell/components/DynamicIslandMediaView.qml:179-219,318-403`

**根因：** 后声明、覆盖整个 capsule 的 MouseArea 位于内容之上并抓取输入，内层按钮无法命中。

**实现提示：** 基于现有 QML pointer/MouseArea 层级形成单一事件命中路径。子按钮消费自己的事件，空白区域仍由 capsule 手势处理。复用 Task 01A 已建立的生命周期信号。

**禁止：**

- 禁止新增第二个覆盖层 MouseArea 或按坐标硬编码转发按钮点击。
- 禁止复制媒体控制 API。
- 禁止让按钮点击同时触发 capsule 主点击动作。
- 禁止修改 swipe 阈值或重写整个手势状态机；那属于 Task 11。

**验收：** 三个按钮各自只触发一次正确动作；点击按钮不折叠/展开 island；空白区域保持原行为；disabled 按钮不触发；press 后移出/cancel 仍由 Task 01A 生命周期正确复位。

**测试：** 增加输入层级、父子不双触发和空白区域行为测试；运行完整 Tahoe 测试。

**独立审查重点：** z-order、pointer grab、propagateComposedEvents 导致的双触发、是否绕过 Task 01A 的统一生命周期。

**建议 commit：** `fix(dynamic-island): restore media control hit testing`

---

### Task 02：把通知滑动删除绑定到稳定 notification ID

**优先级：高**
**仓库：父仓**

**唯一目标：** 延迟删除只能作用于手势发起时的通知 A，绝不能在 delegate 换绑后删除 B。

**证据：**

- `tahoe-shell/components/NotificationToast.qml:190-195`
- `tahoe-shell/components/NotificationToast.qml:273-287`
- `tahoe-shell/components/NotificationToast.qml:348-360`
- `tahoe-shell/components/NotificationToast.qml:398-407`
- `tahoe-shell/services/Notifications.qml:422-440`

**根因：** Timer 到期时动态读取按 `stackIndex` 换绑的 `cardRoot.notification`，没有捕获动作发起时的稳定 ID。

**反腐化要求：** 使用现有 notification ID 和 `Notifications.dismissId()`；不得在 UI 层复制待删除通知模型，不得保存 index 作为身份，不得复制 Notification 对象作为第二状态源。

**验收：** A 滑出期间 A 被外部关闭、B 顶替 index 时，Timer 最多幂等尝试删除 A，B 必须保留；连续滑动多个通知互不串扰；取消/回弹清理 pending identity。

**测试：** 必须模拟 A→外部删除→B 换绑→Timer 触发的原始错误顺序。运行通知相关测试和完整 Tahoe 测试。

**建议 commit：** `fix(notifications): bind swipe dismissal to stable identity`

---

### Task 03：为 AppMenu probe 增加请求身份与最新请求补跑

**优先级：高**
**仓库：父仓**

**唯一目标：** A 的 probe 结果、错误和退出清理都不能污染已聚焦的 B，且 B 的刷新不能因 A 正在运行而永久丢失。

**证据：** `tahoe-shell/services/AppMenu.qml:35-65,67-95,149-187`。

**根因：** `probe.running` 时直接丢弃新 refresh；结果没有 window/app/request generation；成功和错误均无身份保护。

**实现提示：** 在现有 AppMenu owner 和原 `refresh()`/Process 管线内建立唯一的请求 generation/identity 与“最新请求待执行”语义。捕获 window ID、PID、app ID 等稳定身份。所有状态写入，包括结果、error、probing=false、service/path/items，必须验证所属请求。旧请求结束后，只启动最新待处理请求。

**禁止：** 新增 `safeRefresh()`、第二个 Process、第二套菜单状态、用 debounce/Timer 掩盖、完成后无条件 refresh。

**验收：** 覆盖 A 成功晚到、A 失败晚到、A 被取消、A 运行时切到 B/C；最终菜单只能属于最新聚焦窗口；旧退出不能结束新请求的 loading。

**测试：** 必须有确定性请求代次测试，不能只做文本 token 检查。完整 Tahoe 测试必须通过。

**建议 commit：** `fix(app-menu): reject stale probe results`

---

### Task 04：为 AppsSettings 权限 probe 增加 desktop identity

**优先级：高**
**仓库：父仓**

**唯一目标：** A 的权限结果、失败状态和 loading 清理不能写入已选择的 B；B 请求不能被丢弃。

**证据：** `tahoe-shell/services/AppsSettings.qml:215-299,336-364`。

**实现提示：** 在现有 `refreshPermissions()` 和 `permissionsProbe` 中维护唯一 request generation/desktop ID。成功、JSON 解析失败、Process 失败、fallback sandbox、`permissionsRefreshing` 均使用同一身份检查。running 期间选择新应用时保留最新 selection，并在旧请求稳定退出后执行。

**禁止：** 第二个 permissions service、第二份 selected app、轮询、延迟刷新或只保护成功路径。

**验收：** A→B 快速切换时，A 成功/失败/取消均不能改变 B 页面；B 最终一定获得自己的权限；未选择应用路径保持原行为。

**建议 commit：** `fix(apps-settings): scope permission results to selected app`

---

### Task 05：在 niri 的 Tahoe glass controller 销毁边界清理 surface 状态

**优先级：中高**
**仓库：niri 子仓，然后父仓指针**

**唯一目标：** controller 销毁而 wl_surface 仍存活时，旧 pending/committed glass 不得继续渲染或污染新 controller。

**证据：** `niri/src/protocols/tahoe_glass.rs:98-120,306-353`。

**根因：** 状态存放于 wl_surface data map，但 `tahoe_glass_surface_v1::Destroy` 为空，也没有 resource destroyed 清理。

**实现提示：** 在保存状态的协议 owner 内处理 request destroy 与异常资源销毁。清理 pending、committed、dirty/hook 所需生命周期状态；对旧可见区域产生正确 damage/通知；清理幂等。必须考虑旧 controller 销毁时新 controller 已经附着的所有权问题，必要时用 controller identity/generation 证明谁有权清理，但不得创建平行业务状态。

**验收测试：**

- create→set/commit→destroy controller，surface 保持存活，regions 清空。
- destroy→recreate controller，不继承旧 pending/committed。
- client 异常断开、重复 destroy 幂等。
- 旧可见玻璃被 damage 并消失。

**禁止：** 仅在 QuickShell 客户端析构时补 clear；依赖下一次 surface commit；让旧 controller 清掉新 controller 状态。

**验证：** 运行相关 Rust 单测及 `cargo test` 中受影响协议测试；按项目现有方式格式化/检查，仅限改动文件。

**建议子仓 commit：** `fix(tahoe-glass): clear surface state on controller destroy`
**父仓 commit：** `chore(niri): update tahoe glass lifecycle fix`

---

### Task 06：统一 edge-reveal、rescale 与 Tahoe glass draw clip 的坐标契约

**优先级：中高**
**仓库：niri 子仓，然后父仓指针**

**唯一目标：** 打开/关闭动画中存在非 1.0 scale 时，content、glass、shadow 均不能越过 edge-reveal 边界，draw clip 必须与实际 destination 位于一致坐标空间。

**证据：**

- `niri/src/layer/mapped.rs:393-402,617-670,952-1066`
- `niri/src/layer/opening_layer.rs:190-225`
- `niri/src/layer/closing_layer.rs:38-53,277-303`
- `niri/src/render_helpers/framebuffer_effect.rs:390-445`

**根因：** open path 在 `should_wrap()` 时提前返回并跳过 crop；close path 先包装为 rescale element 后失去 Tahoe 类型匹配；内部 draw clip 仍是未变换绝对矩形。

**实施前必须写清：** surface-local、output-local、physical、缩放前 dst、缩放后 dst、damage-relative 的转换顺序。

**禁止：** 扩大 clip、魔法 padding、强制 scale=1、禁用 edge-reveal、给 Tahoe 单独复制一条渲染管线。

**验收：** open、close、动画中途反转、popin 尚未结束即 edge-reveal close、多个 output scale；content/glass/shadow 边缘逐帧一致；capture geometry 保持完整，draw 只在 reveal viewport 内；damage 覆盖 old/new。

**测试：** 在已有 draw_clip 测试基础上增加 `edge-reveal + inherited scale/rescale wrapper` 回归测试；至少运行 `cargo test -q draw_clip --lib` 和相关 layer animation tests。

**建议子仓 commit：** `fix(layer): preserve edge reveal clipping through rescale`
**父仓 commit：** `chore(niri): update edge reveal clipping fix`

---

### Task 07：让 Apps 应用模型按身份/元数据变化刷新，而非只看数量

**优先级：中高**
**仓库：父仓**

**唯一目标：** 等数量安装/卸载和 `.desktop` 原地修改也能刷新现有 `realApplications` 权威模型。

**证据：** `tahoe-shell/services/Apps.qml:26,74-113`。

**实现提示：** 优先使用现有 DesktopEntries 的变化信号或可重复计算的轻量 fingerprint。若必须生成 fingerprint，应覆盖稳定 desktop ID 及影响 UI/启动行为的关键元数据，并仍由现有 Apps service 唯一拥有 revision/model。不得保留“数量轮询”和“新 fingerprint 管线”两套互相竞争的刷新系统。

**验收：** 等数量替换、Name/Icon/Exec/NoDisplay 修改、单纯数量变化、无变化时不重复重建；Launchpad、搜索、固定应用解析同步更新。

**性能要求：** 不得每 2 秒深拷贝或排序巨大模型造成更高开销；先量化方案成本。

**建议 commit：** `fix(apps): refresh desktop entries on identity changes`

---

### Task 08：为 Weather 城市搜索建立不可串扰的请求代次

**优先级：中**
**仓库：父仓**

**唯一目标：** 连续搜索 A、B 时，旧 curl 的 success/error/cancel 不得清空或覆盖 B 的结果和 loading。

**证据：** `tahoe-shell/services/Weather.qml:322-394,813-821`。

**实现提示：** 在现有 geocode Process 管线内使用 query identity + request generation；明确停止旧进程后旧 `onExited` 与新 command 的关系。所有 `locationSearching/results/error/signals` 写入都必须验证当前代次。最新请求必须最终执行。

**禁止：** 新建第二个 geocode Process、debounce 代替身份、只比较 query 文本、旧错误无条件设置 searching=false。

**测试：** A success 晚到、A failure 晚到、A cancel 晚到、A→B→C，最终只能显示最新请求。

**建议 commit：** `fix(weather): isolate geocode request generations`

---

### Task 09：按通知稳定 ID 追踪 Dynamic Island 新通知

**优先级：中**
**仓库：父仓**

**唯一目标：** 等量替换和一次多项变化时不漏掉真正新增的 ID；replace-id 原地更新时，若该 ID 正在 Dynamic Island 展示，则只更新当前 transient 文本，不重新播放入场动画、不重启展示计时器；若该 ID 当前未展示，则不把更新当作新通知重新弹出。

**证据：** `tahoe-shell/services/DynamicIsland.qml:680-724,1011-1022`，权威模型在 `Notifications.qml:69-76,126-173`。

**实现提示：** 以 `Notifications.activeModel` 中的 live Notification 对象和稳定 ID 为唯一事实来源。新增项用 ID 集合差识别；replace-id 不一定触发 `activeModelChanged`，因此必须观察 live Notification 已有的 summary/body/appName 等属性变化。优先直接连接现有对象属性通知；若 QML 结构确实需要汇总入口，只允许在现有 Notifications service owner 内增加一个 `notificationUpdated(id)` 类型的窄信号，由 live 对象属性变化驱动，不携带第二份快照、不复制模型。DynamicIsland 只消费该 owner 的身份事件。

**批量新增的确定状态机：** 将 DynamicIsland 当前单值 `pendingNotificationEntry` **迁移并替换**为一个由 DynamicIsland 唯一维护的 FIFO `pendingNotificationIds`；修复后不得同时保留 scalar 和 queue 两套 pending 状态。一次模型变化发现多个新 ID 时，按 `activeModel` 的追加顺序入队，最早新增者先展示。每次只展示一条；当前 transient 隐藏且不再被 expanded/userInteracting 阻塞时，再从队首取下一 ID。出队时回到 `Notifications.activeModel` 查找 live 对象并生成现有 `notificationEntry()`，对象已删除则跳过并继续。这样队列只保存稳定 ID，不复制 Notification 数据。DND 开启或 island 禁用时清空队列；通知删除时移除相应待处理 ID；replace-id 更新正在展示的同 ID 文本，排队中的 ID 保持原位置，出队时读取最新 live 内容。重复 ID 不得重复入队。

**验收：** 单项追加、删除后追加、等量替换、潜在批量变化按 FIFO 逐条展示；busy/expanded/userInteracting 时按序等待；排队项删除后安全跳过；DND/禁用清空；replace-id 正在展示时原位更新文本且不重启动画/Timer，排队时保持位置并在出队读取最新内容，未展示且未排队时不重新弹出；不得重复展示旧 ID，也不得漏掉新 ID。

**建议 commit：** `fix(dynamic-island): track notifications by stable identity`

---

### Task 10：停止 Task Switcher release Timer 跨会话确认

**优先级：中低**
**仓库：父仓**

**唯一目标：** 旧会话启动的 40ms modifier-release Timer 绝不能确认后来重新打开的新会话。

**证据：** `tahoe-shell/components/TaskSwitcher.qml:53-72,279-287,320-323`。

**实现提示：** 在现有 open/session 生命周期内 stop Timer 或绑定 session epoch；优先最小生命周期修复。不得新增第二个确认 Timer。

**验收：** release→40ms 内 close→reopen 不触发旧确认；普通 Alt/Meta release 仍正确确认；cancel 和鼠标选择不回归。

**建议 commit：** `fix(task-switcher): cancel stale release confirmation`

---

### Task 11：为 Dynamic Island swipe 建立明确的 click/drag 阈值

**优先级：中**
**仓库：父仓**

**唯一目标：** 垂直移动和轻微抖动不被误判为 capsule click，也不启动无意义 settle；保持真正横向 swipe 和普通 click。

**证据：** `DynamicIslandOverlay.qml:368-431`、`DynamicIsland.qml:529-599`。

**依赖：** Task 01B 已完成并 push。

**实现提示：** 在现有手势状态机中区分 armed、dragging、moved、vertical rejection；使用既有 motion token/阈值体系，避免散落魔法数字。低于阈值的稳定 press/release 为 click；达到横向阈值才 beginSwipe；明显垂直手势取消 click；cancel 必须复位。

**禁止：** 新增覆盖层、坐标硬编码按钮区、破坏媒体子控件输入。

**验收：** 普通 click、轻抖、垂直 drag、横向 drag、wheel swipe、从按钮/空白区域开始、cancel。

**建议 commit：** `fix(dynamic-island): separate click and swipe intent`

---

### Task 12：正确标记非中文输入法语言

**优先级：中**
**仓库：父仓**

**唯一目标：** 日语、韩语及其他非英文输入法不再统一显示“中”。

**证据：** `tahoe-shell/services/InputMethod.qml:23` 及其当前输入法识别调用方。

**实现提示：** 扩展现有 `languageLabel()`，保持它是唯一标签入口；基于 fcitx engine/language 的现有数据明确常见映射，并提供不误导的通用 fallback。不得创建第二个标签服务。

**验收：** 中文、英文、日文、韩文、未知输入法、无输入法；现有切换行为不变。

**建议 commit：** `fix(input-method): report non-Chinese language labels`

---

### Task 13：让 QuickShell Tahoe item region 跟踪完整 scene transform

**优先级：中**
**仓库：quickshell 子仓，然后父仓指针**

**唯一目标：** item 或任意祖先发生移动、缩放、旋转、transform origin/parent 变化时，glass region 与真实 scene geometry 同步；旋转包围盒使用四角而非两个对角点。

**证据：** `quickshell/src/wayland/tahoe_glass/qml.cpp:65-90,287-313`。

**依赖：** Task 06 已完成。

**实现提示：** 使用 Qt 已有 scene transform/geometry 通知机制；审计 item、parent chain 和 window/scene 变化的连接生命周期。计算四角映射后的轴对齐包围盒。连接必须在 item/parent 销毁与替换时正确断开，不能每帧轮询。

**禁止：** 新建第二套手工 region 属性作为 fallback；依赖 materialAlpha 顺便刷新；只补 scaleChanged 而忽略祖先。

**验收：** 自身/父级 x/y、scale、rotation、transform origin、reparent、隐藏、销毁；45° 旋转包围盒正确；无悬挂连接和重复 commit。

**建议子仓 commit：** `fix(tahoe-glass): track full item scene transforms`
**父仓 commit：** `chore(quickshell): update glass transform tracking`

---

### Task 14：减少 Tahoe glass 全列表重发与无差别 commit

**优先级：中，低端环境中高**
**仓库：quickshell 子仓；如服务端语义测试需要，可在独立后续 niri 子任务处理，不得同一 commit 跨两个子仓**

**唯一目标：** 单个 region 字段变化时避免 `clear_regions + 重发全部 N 项`，并只在协议状态确实变化时 commit，同时保持删除、重排和重建语义正确。

**证据：** `quickshell/src/wayland/tahoe_glass/surface.cpp:10-71`、`qml.cpp:473-505`；niri 接收语义在 `niri/src/protocols/tahoe_glass.rs`。

**依赖：** Task 05 已完成。

**协议事实与实现要求：** Tahoe glass v3 已有 `remove_region(id)`，niri 服务端已实现按 ID 更新和单项删除。必须直接基于该既有协议做 old/new ID diff：新增或字段变化使用 `set_region(id, ...)`，删除使用 `remove_region(id)`，全部清空时才使用既有 `clear_regions` 语义。region 列表顺序不具有独立视觉语义时，纯重排不得发送请求；若源码证明顺序确有语义，必须在写代码前报告并停止，不能自行引入新排序协议。

**反腐化：** 只能有一个权威 `mRegions` 和一条发送路径。不得保留一个常规全量更新入口与一个增量入口供不同调用方选择；全量 clear 只能是同一 diff 状态机处理“全部删除”的结果。禁止用粗糙浮点 epsilon 吞掉可见末端变化。

**验收：**

- 单项属性变化只发送必要 set_region。
- 新增 region、删除 region、全部清空、ID 改变、顺序变化正确。
- 没有变化时零请求、零额外 commit。
- 动画 0→1 最终精确到达终点，无 0.98 卡住。
- 给出优化前后请求数/commit 数测试或计数证据。

**建议子仓 commit：** `perf(tahoe-glass): update changed regions incrementally`
**父仓 commit：** `chore(quickshell): update incremental glass regions`

---

### Task 15：让 Tahoe glass fallback 遵守 materialAlpha

**优先级：中**
**仓库：quickshell 子仓，然后父仓指针**

**唯一目标：** compositor 不支持 Tahoe 协议时，fallback blur 至少遵守可实现的二值可见性语义：当所有有效 region 的量化后 `materialAlpha` 等于 0 时立即移除 blur region，不在内容完全透明后留下完整强度模糊残影；不得虚假声称能够提供协议路径的连续强度渐变。

**证据：** `quickshell/src/wayland/tahoe_glass/qml.cpp:577-642`。

**现有能力边界：** 当前 `BackgroundEffect` 只提供二值 `blurRegion`，没有 opacity/strength。公开协议也不能表达 blur 强度。因此本任务不授权新增 shader、公开 API 或协议扩展。二值合成规则必须明确且不得新增魔法阈值：直接使用客户端已有的量化后值；只有 `materialAlpha > 0` 且 blur flag 有效的 region 才进入 fallback，`materialAlpha === 0` 的 region 不进入；当没有有效 region 时清除 fallback blur。多个 region 仍由现有 fallback owner 统一合成。

**禁止：** 新写一套 blur shader、增加平行 effect、扩展公开协议/API、删除 fallback，或承诺现有后端无法表达的平滑强度动画。二值 fallback 的限制必须在代码测试/注释中准确表达。

**验收：** 量化 alpha 0 时无 fallback blur；任意量化 alpha > 0（包括最小正步长）、0.5、1 时 blur region 正常；退出到精确 0 后同一更新周期内清除，不残留；中途反向和多个 region 合成正确；协议可用路径不受影响。

**建议子仓 commit：** `fix(tahoe-glass): honor material alpha in fallback`
**父仓 commit：** `chore(quickshell): update glass fallback alpha`

---

### Task 16：分离 Tahoe glass sample geometry 与 visible geometry

**优先级：中**
**仓库：niri 子仓，然后父仓指针**

**唯一目标：** `clip=false` 时仍允许矩形材质语义，但 blur/refraction 的 sample padding 不能成为可见 halo。

**证据：** `niri/src/render_helpers/tahoe_glass.rs:270-325`。

**依赖：** Task 06 已完成。

**实现提示：** 明确 capture/sample geometry 与 draw/visible geometry 的职责。采样可以扩大，绘制目标必须保持协议 region 的可见范围；`clip` flag 应控制圆角/内容裁剪语义，而不是决定是否绘制 sample padding。复用现有 framebuffer effect clip/damage 契约。

**禁止：** 把 sample padding 设为 0、禁用 refraction/blur、魔法缩小 region。

**验收：** clip true/false、不同 padding、不同 output scale、edge reveal、边缘 region；外部不出现 2–64px halo，采样质量不下降。

**建议子仓 commit：** `fix(tahoe-glass): keep sample padding outside visible bounds`
**父仓 commit：** `chore(niri): update glass sample bounds fix`

---

### Task 17：合并 ThumbnailProvider loading 期间的等价请求

**优先级：中**
**仓库：父仓**

**唯一目标：** 相同窗口、相同或更小尺寸、非 force 的并发请求不再无条件安排第二次捕获，同时保留尺寸升级、force 和缓存失效语义。

**证据：** `tahoe-shell/services/ThumbnailProvider.qml:246-269,416-432`。

**实现提示：** 在现有 per-window state/queue owner 中合并请求。明确 loading request 的尺寸、consumer、force 和 pending upgrade。不得建立第二个 capture queue。

**验收：** 等价请求一次捕获；更大尺寸在必要时追加一次；force 不被吞；多个 consumer 均收到最终 state；失败后可重试；窗口关闭清理 pending。

**性能证据：** 测试或计数展示重复消费者下 capture 次数从 2 降为 1。

**建议 commit：** `perf(thumbnails): coalesce duplicate in-flight captures`

---

### Task 18：取消 ClipboardHistory 无条件每 4 秒完整轮询

**优先级：中**
**仓库：父仓**

**唯一目标：** 利用现有 watcher/事件链刷新历史，避免 shell 全生命周期每 4 秒启动 `cliphist list`，同时保留初次加载、服务重启和丢事件恢复能力。

**证据：** `tahoe-shell/services/ClipboardHistory.qml:287-303,546-574`、`shell.qml:690`。

**实现提示：** 先审计 `wl-paste --watch cliphist store` 是否能在写入后触发现有 refresh；若 watcher 命令无法直接发 QML 事件，优先复用现有 Process 生命周期或只在 UI 打开/明确变化时刷新。可以保留低频健康恢复机制，但不得与事件刷新形成双权威路径。

**禁止：** 仅把 4 秒改成更长；新增第二个 watcher；缓存永不失效。

**验收：** 初次加载、复制新内容、删除/清空、watcher 重启、弹窗打开；空闲一小时不再产生约 900 次完整 list 进程。

**建议 commit：** `perf(clipboard): remove unconditional history polling`

---

### Task 19：在保持正确性的前提下降低 AppMenu 常驻 probe

**优先级：中**
**仓库：父仓**

**依赖：** Task 03 已完成。

**唯一目标：** 不再无界面需求地每 5 秒启动 Python/D-Bus probe，同时保持焦点切换、registrar 变化、菜单打开和错误恢复的及时性。

**证据：** `tahoe-shell/services/AppMenu.qml:149-185`、`shell.qml:601`。

**实现提示：** 以 Task 03 修复后的唯一 request 管线为基础，优先由 focused window identity、菜单打开需求和真实依赖变化驱动。若 registrar 缺少事件 API，可保留明确、低频、条件化的恢复探测，但不能与事件路径竞争写状态。

**禁止：** 删除错误恢复；仅把 5 秒改成 30 秒；新增第二个 probe service/Process。

**验收：** 焦点 A→B 立即正确；打开菜单时数据新鲜；registrar 出现/消失可恢复；完全空闲且菜单不用时不再每小时约 720 次 Python 启动。

**建议 commit：** `perf(app-menu): gate native menu probing by demand`

---

### Task 20：对 Dynamic Island 音量/静音 OSD 做语义去重

**优先级：中低**
**仓库：父仓**

**唯一目标：** 后端重复发出相同 volume/muted 值时不重复展示和重启 OSD；真实变化仍即时反馈。

**证据：** `tahoe-shell/services/DynamicIsland.qml:757-836,1024-1043`。

**实现提示：** 使用现有 `lastVolume/lastMuted` 作为唯一 baseline；处理初始化、服务替换、浮点量化和 mute/volume 同一操作连续发两个信号的顺序。一次用户操作最多形成一次语义正确的 OSD，不能吞掉 mute 状态变化。

**禁止：** 新增 debounce Timer、第二份 OSD baseline、粗糙 epsilon 导致小步音量变化不显示。

**验收：** 相同值重复信号无 OSD；volume 变化、mute 变化、同时变化、服务重连、首次 baseline；pending OSD 逻辑不回归。

**建议 commit：** `fix(dynamic-island): suppress duplicate volume osd updates`

---

### Task 21：停止媒体可视化持续重定向未完成动画

**优先级：中低**
**仓库：父仓**

**唯一目标：** 保留播放可视化质感，同时避免 64ms 目标更新持续打断 120ms 的五条动画。

**证据：** `tahoe-shell/components/DynamicIslandMediaView.qml:139-158,289-305`。

**实现提示：** 复用现有 motion token 和单一 phase owner。可选择让采样周期与动画 settle 匹配，或使用适合连续追踪的现有动画类型；必须先给出更新频率和动画持续时间模型。暂停、隐藏、非 expanded media 时不得继续无意义更新。

**禁止：** 删除可视化、降低到明显跳变、再增加第二个 Timer、在每根柱子维护独立 phase。

**验收：** 播放时平滑；暂停稳定；隐藏/非媒体状态停止更新；低端/软件渲染工作量下降；reduced motion 语义正确。

**建议 commit：** `perf(dynamic-island): align visualizer updates with animation`

---

### Task 22：让锁屏分钟时钟按分钟边界更新

**优先级：低**
**仓库：父仓**

**唯一目标：** 只显示 `HH:mm` 的时钟不再每秒更新 Date，同时在分钟边界和唤醒/重新显示时准确。

**证据：** `tahoe-shell/components/LockScreen.qml:91-97,117-130`。

**实现提示：** 使用单一 Timer 对齐下一分钟边界，并在触发后重新计算下一间隔；处理系统挂起/恢复、时间跳变和组件重新显示。不得再增加一个并行 Timer。

**验收：** 分钟切换准确；打开锁屏立即显示当前时间；挂起恢复不延迟；每分钟而非每秒更新。

**建议 commit：** `perf(lock-screen): update clock on minute boundaries`

---

## 7. 每任务通用测试与提交门禁

### 7.1 测试门禁

每个父仓 Tahoe QML/service 任务至少执行：

```bash
python3 -m pytest -q tahoe-shell/tests
git diff --check
```

此外必须执行该任务新增的最小回归测试。纯文本搜索测试不能作为异步、输入、生命周期或动画竞态的唯一验证。

每个 Rust/C++ 子仓任务必须执行：

- 新增的最小回归测试；
- 受影响模块测试；
- 能证明编译通过的目标；
- `git diff --check`；
- 如运行全量测试成本过高，必须说明未运行项、原因和剩余风险。

### 7.2 审查门禁

- 独立代理必须未参与实现。
- 独立代理只读，不能边审边修后自批。
- 必须查看完整 diff，不接受只看摘要。
- 结论必须是 `APPROVE` 或 `REQUEST_CHANGES`。
- `REQUEST_CHANGES` 后任何代码修改都会使旧审查失效；必须重新测试并开启新审查轮次。

### 7.3 commit/push 门禁

```text
1. 显示 git status --short。
2. 确认用户原有修改仍未被暂存。
3. 对基线已脏的文件强制使用 `git add -p` 逐 hunk 暂存；只有基线干净文件才允许整文件 `git add <path>`。禁止 git add . / git add -A。
4. 显示 `git diff --cached --binary` 并核对只含当前任务。
5. `git diff --cached --check` 必须通过；保存 staged diff 的 SHA-256。
6. 独立子代理审查的输入必须是这份最终 staged diff，并记录其 SHA-256。
7. APPROVE 后不得再修改 index 或 working tree；commit 前重新计算 SHA-256，必须与获批哈希一致。
8. 创建一个清晰、可回滚的 commit并记录 hash。
9. 使用普通 push 推送指定远端分支。禁止 `--force`、`--force-with-lease`，禁止擅自 pull/rebase/merge 或改写历史。
10. fetch/ls-remote/branch contains 等方式确认远端包含 hash。
11. 子仓任务再回父仓，以相同“暂存→哈希→独立审查→commit→普通 push”流程提交子模块指针。
12. 所有 push 均确认成功后才能进入下一 Task。
```

如果 commit hook 自动修改了文件，必须重新查看 diff、重跑受影响测试，并重新进行独立审查；不能直接再次 commit。

---

## 8. 反腐化检查清单

每个任务完成前逐项回答“是/否”，任何一项无法回答都不能提交：

- 修复是否落在真正的状态或资源 owner？
- 是否仍只有一个权威模型、状态、队列、缓存和刷新入口？
- 是否没有新增名称相似的平行 API？
- 是否没有旧路径和新路径双写同一状态？
- request generation 是否只服务于现有请求管线，而非成为第二业务状态？
- Timer 是否表达真实产品时序，而不是降低竞态概率？
- lifecycle cleanup 是否发生在 destroy/drop 边界？
- delayed callback 是否捕获稳定 ID，而非动态 index/delegate？
- fallback 是否与主路径保持相同语义？
- 性能优化是否消除重复工作，而非降低功能或视觉质量？
- 是否审计了 success、failure、cancel、destroy、recreate？
- 是否保持多屏、reduced motion、DND、force refresh、缓存失效等既有行为？
- staged diff 是否不含用户原有或下一任务改动？

---

## 9. 研究验证基线

审查阶段已执行：

- `python3 -m pytest -q tahoe-shell/tests`
  - 156 项测试通过，94 个 subtests 通过。
- `cargo test -q draw_clip --lib`
  - 3 个 draw_clip 相关测试通过。

这些结果只能说明现有静态约束和普通 draw clip 路径通过，不能否定本文问题。原测试没有覆盖：

- A 请求晚到覆盖 B；
- delegate 在 Timer 等待期间换绑；
- 父子 MouseArea 命中与 grab lifecycle；
- controller 销毁但 wl_surface 存活；
- edge-reveal 继承非 1.0 scale；
- region 动画的协议请求/commit 数量；
- watcher 已存在时的常驻轮询成本。

---

## 10. 完成定义

整个路线图只有在 Task 01A、Task 01B、Task 02–22 共 23 个原子任务全部满足以下条件时才算完成：

1. 每项都有能够证明原问题的回归测试或明确、可重复的人工验证记录。
2. 每项最终都有独立子代理 `APPROVE`。
3. 每项都有独立 commit；没有“misc fixes”或跨根因大提交。
4. 每个 commit 都成功 push 并在远端确认。
5. 子仓 commit 与父仓指针 commit 均已推送且引用有效。
6. 工作区用户原有改动未被丢弃或错误混入。
7. 没有引入平行接口、双状态、双刷新路径或临时兼容层。
8. 全部 Tahoe 测试、相关 niri/quickshell 测试和最终集成验证通过。

在此之前，Grok 4.5 不得宣称“全部修复完成”。
