# 03 · 串行执行计划入口

日期：2026-07-22

用途：后续实施的短入口；不复制技术设计、测试矩阵或验收细节。

技术真源：[重构改进路线图](./02-refactor-roadmap.md)

研究依据：[源代码研究报告](./01-research-report.md)

## 不可变约束

1. **严格串行。** 永远只执行一个 Rxx。当前任务完成独立审查、commit、push、fetch 后远端哈希核对之前，不得开始、预写或 stage 下一任务；不得合并两个任务。
2. **不以最小实现为目标。** 允许完成当前任务所必需的局部重构，但不得借机扩大到后续任务或外围清理；实现应解决 ownership 和状态模型根因，而不是只加参数或局部 `if`。
3. **禁止平行接口和双事实源。** 新 owner、接口、schema、controller 或 render path 在同一任务内必须迁移全部生产调用者并删除旧 owner；兼容解析只能归一到同一内部模型，不得保留可独立决定同一语义的 legacy 正常路径。
4. **不得破坏既有功能。** scrolling、floating、tabbed、no-output、maximize/fullscreen 组合、全部 lifecycle 动画及反转、interactive move、xray、blocked-out、screencast、overview、reduced motion、多输出/缩放/旋转/热插拔、现有协议能力、Shell fallback 和 KDL 兼容行为均须保持；只有路线图明确要求的修复可以改变错误行为。
5. **优先相信源代码。** 开始任务时以锁定 revision 的生产源码、测试和协议 XML 重新核验路线图主张；一般文档只作导航。若源码已经变化到使任务前提不成立，先停止并报告，不得照抄旧方案。
6. **测试约束。** 新测试必须能捕获旧风险，并断言逐帧或逐事件不变量；同时运行受影响的既有回归。未运行项必须如实记录原因，不能把环境缺失或旧二进制结果写成通过。
7. **只冻结当前任务。** 只 stage 当前任务路径并记录 staged name-status、blob/tree、未跟踪文件和子模块 gitlink；保留用户原有无关改动。审查期间任何受审内容或 index 变化都会使该轮审查失效。
8. **先审查，后提交。** 作者验证完成后，必须启动一个无作者历史、全新、独立、只读的审查会话。任何 finding 都要修复、重新冻结并由另一个全新会话重审；只有明确的 `FINAL PASS` 才能 commit。
9. **提交后才可推进。** commit tree 必须等于 reviewed tree；随后 push、`git fetch origin` 并核对本地与远端 hash。失败或残留当前任务改动时，该任务仍未完成。
10. **跨子模块任务采用两阶段审查。** 先审全部内容，再提交、推送并核对各子模块；然后只推进外层 gitlink，冻结最终 outer tree，再由另一个全新会话完成集成审查；第二次 `FINAL PASS` 后才能提交和推送外层仓库。
11. **条件任务也必须闭环。** No-go 必须依据预先固定的门槛和可复核数据，保存版本化执行记录，并照常独立审查、commit、push、远端核对；不得为了制造改动而新增无收益抽象。
12. **约束不得静默降级。** 本文件与路线图约束累计生效；若二者或实际 Git 边界无法同时满足，将任务标为 blocked 并报告，不得自行放宽规则或绕过到下一任务。

## 任务选择

按下列序列查找第一个没有“完成记录 + 已推送提交 + 远端哈希核对”的任务；它就是唯一可执行任务。初始入口为 **R00**。

[R00](./02-refactor-roadmap.md#4-r00回归与观测地基)
→ [R01](./02-refactor-roadmap.md#5-r01f01-lifecycle-overlay-render-ownership)
→ [R02](./02-refactor-roadmap.md#6-r02f03-类型化坐标与统一转换)
→ [R03](./02-refactor-roadmap.md#7-r03f04-单一内部-lifecycle-command)
→ [R04](./02-refactor-roadmap.md#8-r04f05f06-当前输出-anchor-ownership-与发布生命周期)
→ [R05](./02-refactor-roadmap.md#9-r05minimizerestore-lifecycle-controller-收敛)
→ [R06](./02-refactor-roadmap.md#10-r06closing-animation-lane-收敛)
→ [R07](./02-refactor-roadmap.md#11-r07removedtile-状态运输修复)
→ [R08](./02-refactor-roadmap.md#12-r08最大化视觉-fsm-与-f02-serial-判定)
→ [R09](./02-refactor-roadmap.md#13-r09workspace-expanded-mode-编排)
→ [R10](./02-refactor-roadmap.md#14-r10f08-无尺寸差-unmaximize-观测与条件修复)
→ [R11](./02-refactor-roadmap.md#15-r11f07-消费既有-ext-identifier)
→ [R12](./02-refactor-roadmap.md#16-r12immutable-resolvedeffectplan)
→ [R13](./02-refactor-roadmap.md#17-r13单一-glass-schema默认值与-named-blur-kernels)
→ [R14](./02-refactor-roadmap.md#18-r14glass-client-canonicalization-与-redraw-owner)
→ [R15](./02-refactor-roadmap.md#19-r15性能基线复测与实施门槛)
→ [R16](./02-refactor-roadmap.md#20-r16genie-每帧分配与-render-element-identity)
→ [R17](./02-refactor-roadmap.md#21-r17lifecycleforeignglass-定向-redraw)
→ [R18](./02-refactor-roadmap.md#22-r18snapshot-variant-cache-与显存预算条件任务)
→ [R19](./02-refactor-roadmap.md#23-r19tahoe-render-batching条件任务)

任务名称、范围、依赖、源码起点、目标设计、回归、删除证明和专属审查问题均以对应链接为准，不在本文件维护副本。

## 每次执行只打开这些索引

1. [严格串行总序列](./02-refactor-roadmap.md#3-严格串行总序列)与上方唯一当前任务；
2. [不可变执行门禁](./02-refactor-roadmap.md#1-不可变执行门禁)和[目标 ownership](./02-refactor-roadmap.md#2-目标-ownership)；
3. 当前任务实施与验证所需的[全局回归矩阵](./02-refactor-roadmap.md#24-全局回归矩阵)及[验证命令分层](./02-refactor-roadmap.md#25-验证命令分层)；
4. 提交前使用[独立审查通用清单](./02-refactor-roadmap.md#26-独立审查通用清单)和[每任务执行记录模板](./02-refactor-roadmap.md#27-每任务执行记录模板)；
5. 性能任务同时检查[预期收益与停止条件](./02-refactor-roadmap.md#28-预期收益与停止条件)。

若路线图章节改名或重排，必须在同一个路线图文档任务中同步修复本文件的失效链接；不得复制章节正文来规避索引维护。
