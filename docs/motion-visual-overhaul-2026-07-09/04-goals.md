# 04 · GOAL 执行文件：串行执行驱动器

日期：2026-07-09
性质：**本轮升级的执行驱动文件**。任何实施会话（人或 agent）必须按本文件的循环协议推进，直到状态表全部 DONE。
必读前置（按序）：[README.md](README.md) → [02-rules.md](02-rules.md)（红线/防腐化/性能预算）→ [03-roadmap.md](03-roadmap.md)（每个 GOAL 的具体改动内容）→ 本文件。研究背景见 [01-research-report.md](01-research-report.md)。

---

## 1. 核心铁律（三条，凌驾于一切执行便利之上）

1. **串行**：同一时间只允许一个 GOAL 处于 IN_PROGRESS。前一 GOAL 未达到 DONE（= 全部代码完成 + 验收通过 + commit + **push 成功**），绝对不得开始下一 GOAL 的任何代码改动。
2. **全部代码，不是最小化修改**：GOAL 的完成标准是 03-roadmap 中该任务"改动"清单 **逐项 100% 落地**（判定标准见 §3）。禁止"先做核心、以后再补"、禁止砍范围凑验收、禁止用开关把没做完的部分藏起来。大刀阔斧 = 宁可把任务做大做完整，不做最小 diff。
3. **验收 → commit → push → 才算完**：验收通过后必须 commit 并 push 成功，push 成功前该 GOAL 不算 DONE，下一 GOAL 不得启动。push 失败按 §5.4 处理，**不得跳过 push 继续干活**。

## 2. GOAL 执行循环（每个 GOAL 走一遍，共 24 遍）

```
步骤 0  会话准备：读 README → 02-rules → 03-roadmap 对应任务 → 本文件状态表，
        定位第一个非 DONE 的 GOAL。
步骤 1  进入条件检查：
        - 上一 GOAL 状态 = DONE（状态表 + git log 双确认：git log --oneline --grep '^T<xx-1>:'）
        - git status 干净（父仓 + niri 子模块）；有半成品先按 §6 处理
        - 本 GOAL 涉及面的 T00 基线命令当前能跑通（环境没坏）
步骤 2  完整实施：按 03-roadmap 该任务"改动"清单逐项实现，对照 §3 的
        "全部代码"判定标准自查；全程遵守 02-rules 红线与性能预算。
步骤 3  验收：
        - 02-rules §6 命令模板中该任务涉及面的全部命令
        - 03-roadmap 该任务"验收"栏的专属验收项
        - 手测矩阵基线（涉弹窗/dock/genie 必测）：开/关/快速连点/Esc/点外关闭/
          深浅色/reduced profile/compositorLayerAnimations=false 回退
步骤 4  记录：写 acceptance/Txx-<slug>-<日期>.md（命令输出摘要、手测结果、
        性能数据、发现待办）。
步骤 5  commit：一个提交，提交信息 "Txx: <一句话>"；acceptance 记录 +
        本文件状态表勾选（PENDING→DONE）+ 治理测试更新 都进同一提交。
        涉 niri 子模块的 GOAL 按 §5.2 双层提交。
步骤 6  push：按 §5.3。push 成功 → 该 GOAL DONE。
步骤 7  回到步骤 0，进入下一 GOAL。GOAL-23 完成后按 §7 收尾。
```

## 3. "全部代码完成"判定标准（逐条自查，任一不满足 = 未完成）

1. **清单覆盖**：03-roadmap 该任务"改动"栏每一项都已实现。允许的例外只有一种：roadmap 文本中明确标注"二选一"/"可选"/"若…则降级"的分支项，选择结果必须写入 acceptance 记录。
2. **零占位**：任务范围内不留 TODO/FIXME/被注释掉的半成品/空函数占位。
3. **零藏匿**：不允许用设置开关、环境变量、注释把未完成部分默认关闭来"通过"验收（合法的开关只有 roadmap/rules 本来要求的：useSpring 门控、compositorLayerAnimations、reduced profile 等既有回退路径）。
4. **全调用点**：涉及合并/迁移/替换的任务必须覆盖全部调用点并可机械验证——例：T06 的 6 处 MenuRow 全部替换；T13 迁移后 `grep -rn "Material Icons" tahoe-shell/` 零残留（除 FontLoader 移除本身）；T14 迁移面内一次性 hex 清零。grep 命令与结果贴进 acceptance。
5. **全状态**：深色/浅色、reduced profile、`useSpring=false`、`compositorLayerAnimations=false`、服务不可用占位态，随主实现同一提交完成，不算"后续优化"。
6. **配套同步**：治理测试（02-rules §1.6 清单）、涉及的文档（policy 文档、本文件夹）同一提交更新。
7. **范围边界**：范围外的问题不修（02-rules §1.5），记入 acceptance "发现待办"——这不算未完成；把范围外工作拉进来导致提交混杂反而是违规。

## 4. 状态表（执行时就地更新，勾选进该 GOAL 的提交）

| GOAL | 任务（详见 03-roadmap） | 规模 | 状态 | 验收记录 |
| --- | --- | --- | --- | --- |
| GOAL-00 | T00 基线锁定 | S | DONE | [acceptance/T00-baseline-2026-07-09.md](acceptance/T00-baseline-2026-07-09.md) |
| GOAL-01 | T01 Motion.js 2.0 弹簧 token + 治理测试同步 | M | DONE | [acceptance/T01-motion-tokens-2026-07-09.md](acceptance/T01-motion-tokens-2026-07-09.md) |
| GOAL-02 | T02 窗口/工作区动画 + 阴影/圆角 KDL 重写 | M | DONE | [acceptance/T02-window-animations-2026-07-09.md](acceptance/T02-window-animations-2026-07-09.md) |
| GOAL-03 | T03 layer-rule 全面弹簧化 + anchor popin | M | DONE | [acceptance/T03-layer-springs-2026-07-09.md](acceptance/T03-layer-springs-2026-07-09.md) |
| GOAL-04 | T04 Genie（神灯）动画专项优化 | M–L | DONE | [acceptance/T04-genie-decouple-2026-07-09.md](acceptance/T04-genie-decouple-2026-07-09.md) |
| GOAL-05 | T05 全局按下态铺开 | M | DONE | [acceptance/T05-global-press-feedback-2026-07-10.md](acceptance/T05-global-press-feedback-2026-07-10.md) |
| GOAL-06 | T06 菜单 macOS 化 + MenuRow 合并 | M | DONE | [acceptance/T06-menu-macos-row-2026-07-11.md](acceptance/T06-menu-macos-row-2026-07-11.md) |
| GOAL-07 | T07 Dock 放大与推挤重写 | L | DONE | [acceptance/T07-dock-magnification-2026-07-11.md](acceptance/T07-dock-magnification-2026-07-11.md) |
| GOAL-08 | T08 Dock 启动弹跳 + autohide 手感 | M | PENDING | — |
| GOAL-09 | T09 通知堆叠与滑出 | M | PENDING | — |
| GOAL-10 | T10 控制中心去 chrome + 控件手感 | M | PENDING | — |
| GOAL-11 | T11 控制中心模块 morph 展开 | L | PENDING | — |
| GOAL-12 | T12 灵动岛 morph 弹簧化 | S | PENDING | — |
| GOAL-13 | T13 图标体系迁移 | L | PENDING | — |
| GOAL-14 | T14 颜色语义化 + accent 系统 | M | PENDING | — |
| GOAL-15 | T15 设置外壳重设计 | L | PENDING | — |
| GOAL-16 | T16 设置控件精修 | M | PENDING | — |
| GOAL-17 | T17 Spotlight 重构 | M | PENDING | — |
| GOAL-18 | T18 Launchpad 全屏重构 | L | PENDING | — |
| GOAL-19 | T19 左侧边栏 widget 化重构 | L | PENDING | — |
| GOAL-20 | T20 任务切换器/窗口概览手感 | M | PENDING | — |
| GOAL-21 | T21 niri fork：layer per-channel spring + pop-slide | M | PENDING | — |
| GOAL-22 | T22 niri fork：origin pointer + shader preset（含降级出口） | M | PENDING | — |
| GOAL-23 | T23 收尾：全量回归、校准、文档 | M | PENDING | — |

状态取值：`PENDING` / `IN_PROGRESS` / `DONE` / `BLOCKED(-PUSH)`。改为 DONE 时在"验收记录"列填 `acceptance/Txx-….md` 相对链接。提交 hash 不落盘，由 git 历史承载（查询：`git log --oneline --grep '^Txx:'`）。

## 5. commit / push 细则

### 5.1 父仓（本仓库，分支 main → origin/main）

- 每 GOAL 恰好一个提交：`Txx: <一句话中文或英文摘要>`；任务内 WIP 最终 squash。
- 提交前：`git status` 必须只含本 GOAL 范围内文件；无未跟踪垃圾（构建产物、截图放 acceptance 引用路径或压缩后入 acceptance 目录）。
- 禁止 force push、禁止 rebase 已推送提交、禁止跳过验收的"空提交占位"。

### 5.2 niri 子模块（GOAL-04 / 21 / 22 及任何涉 `niri/` 的改动）

子模块 `niri/` → `https://github.com/skjsbsnq/tahoe-desktop.git`，工作分支 `tahoe-layer-animations`（`.gitmodules:1-4`）。流程：

```
1. cd niri && git checkout tahoe-layer-animations（确认在分支上，不是游离 HEAD）
2. 子模块内提交："Txx: <摘要>"，跑 cargo test 子集
3. git push origin tahoe-layer-animations        # 子模块先 push
4. cd .. && scripts/check-submodules.sh          # 通过后
5. 父仓提交（同一 "Txx:" 提交内含子模块指针更新 + 本任务其余改动）
6. git push origin main
```

子模块 push 失败时父仓不得提交指针（否则远端父仓引用悬空提交）。`quickshell/` 子模块本轮禁改（02-rules §2.9）。

### 5.3 push 成功判定

`git push` 退出码 0 且 `git status` 显示 `Your branch is up to date with 'origin/main'`（子模块同理对其分支）。

### 5.4 push 失败处理

1. 重试 3 次（间隔可加大）；检查网络/凭据。
2. 仍失败：该 GOAL 状态改 `BLOCKED-PUSH`，在 acceptance 记录中注明，**停止执行**——不得开始下一 GOAL（本地提交保留，待 push 恢复后置 DONE 再继续）。
3. 严禁为绕过 push 失败而改 remote、force push 或跳号执行。

## 6. 中断与恢复协议

会话中断（崩溃/上下文断/手动停止）后的恢复步骤：

1. 读本文件状态表 → 找 IN_PROGRESS 或第一个 PENDING 的 GOAL。
2. `git status`（父仓 + niri 子模块）与 `git log --oneline -5` 对账：
   - 工作树干净且上一 GOAL 提交已 push → 正常进入下一 GOAL。
   - 有未提交半成品 → 只有两个选项：**继续完成该 GOAL 到 DONE**，或 `git checkout/reset` 丢弃后重做该 GOAL。禁止带着半成品开始别的 GOAL，禁止把半成品提交成"部分完成"。
   - 已提交未 push → 先 push（按 §5.4），再继续。
3. 若发现状态表与 git 历史不一致，以 git 历史为准修正状态表（该修正可并入当前 GOAL 提交）。

## 7. 全部完成的收尾条件

GOAL-23 验收通过并 push 后：

1. 状态表 24 行全部 DONE，每行有 acceptance 链接。
2. README.md 状态行改为"已完成（日期）"。
3. GOAL-23 的 acceptance 汇总表（每 GOAL 一行：任务 / 结论 / 性能数据 / 残留待办）作为本轮升级的最终交付物。
4. 把执行中积累的"发现待办"整理为下一轮 backlog 段落，附在 GOAL-23 acceptance 末尾。

## 8. 违规兜底

执行中若发现自己已经违反铁律（如提前动了下一 GOAL 的代码、push 前开始新任务）：立即停止，revert 越界改动，在当前 GOAL 的 acceptance 记录"违规与纠正"段如实记录，然后按循环协议继续。规则的目的是可回滚与可审计，如实记录的纠正不算失败。
