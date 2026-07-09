# Tahoe 视觉·手感·动效全面升级（Motion & Visual Overhaul）

日期：2026-07-09
状态：研究完成，未开始实施。本文件夹是本轮升级的唯一事实来源。

## 文档索引（按阅读顺序）

| 文件 | 内容 |
| --- | --- |
| [01-research-report.md](01-research-report.md) | 研究报告：现状源码审计（带 file:line）、与真 macOS 的差距、目标动效规范（Apple 弹簧参数体系）、Genie（神灯）动画现状与优化方向、性能与内存观察 |
| [02-rules.md](02-rules.md) | 规则文件：红线（不能做）、许可（能做）、防腐化条例（禁止平行接口、复用清单）、性能与内存预算、验收命令模板 |
| [03-roadmap.md](03-roadmap.md) | 执行路线图：T00–T23 严格串行任务，每任务含目标/改动/验收/回滚 |
| [04-goals.md](04-goals.md) | **GOAL 执行文件（执行驱动器）**：GOAL-00–23 状态表、执行循环协议、"全部代码完成"判定标准、commit/push 细则（含 niri 子模块双层流程）、中断恢复协议。实施会话从这里开始 |

## 执行总则（一句话版）

1. **严格串行**：上一 GOAL 未达到 DONE（全部代码完成 + 验收通过 + commit + **push 成功**），不得开始下一 GOAL（见 04-goals.md 铁律）。
2. **全部代码，不是最小化修改**：完成标准是 03-roadmap 该任务"改动"清单逐项 100% 落地（判定标准见 04-goals.md §3）。
3. **大刀阔斧只作用于表现层**：视觉参数、动效、组件内部结构可以推倒重做；服务层、数据流、接口边界只许复用与收敛，不许另起炉灶。
4. **每任务一个提交、push 后才算完、可单独回滚**；验收记录写入本文件夹 `acceptance/` 子目录（`acceptance/Txx-<slug>-YYYY-MM-DD.md`）。
5. 与既有治理文档的关系：本文件夹的规则是 `tahoe-shell/docs/tahoe-motion-default-policy.md` 与 `tahoe-shell/docs/tahoe-material-governance.md` 的**扩展**，不推翻其中任何条款（fallback 保留、profile 三方同步、材质词汇表等继续有效）。
