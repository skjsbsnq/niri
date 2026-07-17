# 动效/质感/衔接整治 · 2026-07-17

本目录是 2026-07-17 全量前端动效审计的落盘产物与本轮修复的**执行驱动器**。

| 文件 | 作用 |
| --- | --- |
| [01-research-report.md](01-research-report.md) | 研究报告：体系结构、6 个系统性模式、102 条具体问题（全部带 file:line）、合成器层事实、统计 |
| [02-execution-plan.md](02-execution-plan.md) | 修复执行计划：R00–R19 串行任务表 + 每任务改动清单/审查清单/验收标准 + 状态表 |
| acceptance/ | 每任务的审查记录与验收记录（`Rxx-<slug>-<日期>.md`） |

研究方法：4 个并行只读审计（Dock/Launchpad/Spotlight、面板族、通知/锁屏/切换器、niri 合成器层）+ 主会话对全部关键文件逐行深读与交叉复核。**结论一律以源码为准**，不采信历史文档；引用的行号为 2026-07-17 时点。

## 铁律（凌驾于一切执行便利，含用户明令）

1. **严格串行**（用户令）：同一时间只允许一个任务 IN_PROGRESS。上一任务未 DONE（代码完成 + 审查通过 + 验收通过 + commit + push 成功）前，不得开始下一任务的任何代码改动。研究/阅读下一任务的代码不受限。
2. **审查门禁**（用户令）：每个任务实施完成后，**必须先通过代码审查才允许 commit/push**。审查方式：`/code-review`（或等效的独立逐 diff 人工审查），审查发现的问题全部修复并复审通过后，把审查结论写入 `acceptance/Rxx-*.md`，然后才进入 commit。未经审查的提交视为违规，须 revert 重走流程。
3. **禁止平行接口**（用户令，继承 [../motion-visual-overhaul-2026-07-09/02-rules.md](../motion-visual-overhaul-2026-07-09/02-rules.md) §3）：只复用、只收敛。具体到本轮：
   - 弹窗内联的重复控件（IconButton/PillButton/TextButton/ToggleSwitch ×4 份）必须**合并为共享组件并替换全部现场**，禁止新旧并存；
   - 动效 token 只进 `components/Motion.js` / `components/DynamicIslandMotion.js`，不得新开 token 文件；
   - 列表增量化只用 quickshell 既有的 `ScriptModel.objectProp` / 稳定 key 机制（Dock 窗口区 `Dock.qml:1393` 已是范例），不自造 diff 框架；
   - 服务层数据流、接口边界不许另起炉灶；表现层允许推倒重做。
4. **玻璃 region 几何禁 Spring**（guardrail 0704ea4）：GlassPanel 的 x/y/width/height/radius/region\* 只允许 eased NumberAnimation。弹簧只允许出现在"驱动值 → clamp → region"管线或纯内容变换上，提交给 region 的值必须有界。
5. **KDL 纪律**：`animations` 区块中 workspace-switch / window-movement / window-resize / overview-open-close 是 `niri_settings_tool.py` MOTION_PROFILE_SPRINGS 的管理面，本轮任务**默认不碰**；若确需改动必须同一提交同步该表。layer-rule 修改直接编辑 `config/niri/tahoe-phase0.kdl` 并重新部署验证（`niri validate`）。QML 运行期不得写 KDL。
6. **一任务一提交一推送**：提交信息 `Rxx: <一句话>`；acceptance 记录 + 02 状态表勾选 + 受影响的 `tahoe-shell/tests/tst_*` 与治理测试更新进同一提交；必须可 `git revert` 单独回滚。涉 niri 子模块的任务先推子仓分支（tahoe-layer-animations），再推父仓。
7. **失败处理**：审查或验收不过 → 修复后复审/重验；无法当场修复 → revert，任务标 BLOCKED 并在状态表记原因，**不得带病进入下一任务**。

## 每任务执行循环

```
步骤 0  读本 README → 02-execution-plan 对应任务 → 状态表定位第一个非 DONE 任务
步骤 1  进入条件：上一任务 DONE（状态表 + git log 双确认）；git status 干净（父仓+子模块）
步骤 2  实施：按该任务"改动清单"逐项落地；"明确不做"以外不越界
步骤 3  审查（用户令）：/code-review 或独立人工逐 diff 审查 → 修复 → 复审通过
步骤 4  验收：该任务"验收标准"逐条执行（含手测矩阵：开/关/快速连点/Esc/点外关闭/
        深浅色/reduced profile/useSpring=false 回退）
步骤 5  记录：acceptance/Rxx-<slug>-<日期>.md（审查结论、验收输出、遗留待办）
步骤 6  commit（Rxx: …）→ push 成功 → 状态表 PENDING→DONE → 回到步骤 0
```

## 与上一轮（motion-visual-overhaul-2026-07-09）的关系

上一轮 GOAL-00–23 已完成，建立了 Motion.js 2.0 token、layer-rule 弹簧、genie、按下态等基础。本轮是在其之上的**覆盖率与质量整治**：不推翻既有词汇，把没接线的地方接完、把换场架构级的问题（灵动岛、Toast 栈、列表重建）修掉。上一轮 02-rules 的红线、性能预算、防腐化判例继续有效，本 README 冲突之处以本 README（含用户新令）为准。
