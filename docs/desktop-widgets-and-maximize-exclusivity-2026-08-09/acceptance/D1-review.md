# D1 审查记录

日期：2026-08-12
子代理数：3（Kant / Pauli / Aristotle，均只读审查）

## 各子代理结论

### 子代理 1（Kant —— 线程安全 / 借用 / 性能）
- 结论：APPROVE
- CONFIRMED：
  - C1 `maybe_log_vram_diag` 5 秒节流在启动后前 5 秒失效（`last==0` 哨兵未
    置位导致每帧打日志；仅 `NIRI_LIFECYCLE_DIAG=1` 时可见）→ **已修**
    （niri.rs：首次调用记录基线并跳过本次日志）
  - C2 注释声称「每 5 秒一次时间戳 / 一次原子读」不精确 → **已修**
    （注释改为「开启时每调用一次时钟读 / 关闭时两次 relaxed load」）
- PLAUSIBLE：P1 测试间全局 ENABLED 交叉污染（既有模式，非阻塞）；
  P2 diag_live_counts 不计交互移动中 tile 的快照（短暂、诊断性低估）
- 已核查无问题：借用/重入、关闭成本、原子一致性、workspace 覆盖、
  retained_blur_bytes 语义、无 panic

### 子代理 2（Pauli —— 诊断结论可信度与文档/验收一致性）
- 结论：REJECT
- CONFIRMED：
  - C1 roadmap/execution-plan 完成判据「profile 后显存不再增长并回落」
    与实测相反 → **已修**（判据改为如实记录，不以显存不再增长作为通过判据）
  - C2 `acceptance/D1-review.md` 不存在 → **已生成本文件**
  - C3 「GLVidHeapReuseRatio reuse heap」被标成已实测验证，实际仅「驱动保留」
    是实测、机制归属是上游推断 → **已修**（research-report D-4 改为
    `[实测]` 驱动保留 + `[未确认]` 机制归属）
  - C4 全局判据「全部 12 个任务」过期 → **已修**（改为 13）
  - C5 回归清单缺 D1 → 核对：execution-plan.md 第 4 章已有 `### D1` 段，
    无需修改
- PLAUSIBLE：P1 161 次口径（→ 已勘误为 161 条/546 次 + 大窗 268/683）；
  P2 effects_cache 排除论证缺失（→ 已补进 research-report D-4/D-5 勘误）；
  P3 buffers 启动瞬间为 1（→ 已勘误）；P4 profile 基线跨会话比较（→ 已加
  不归因说明）；P5 早期「永久保留/确定性泄漏」残留（→ 已软化）；P6 两条
  5s 周期日志（既有 maybe_log_periodic + 新增 maybe_log_vram_diag，均 env
  门控、不构成平行状态机，记录为已知遗留）；P7 cargo test 无存档（→ 已加
  证据行）；P8 外部引用未核验（wiki/#1962 已核验，#1869/#3404/#4372/
  egl-wayland#126 以超时未复核，文档按上游引用标注）

### 子代理 3（Aristotle —— 计数正确性与判据）
- 结论：REJECT
- CONFIRMED：
  - C1 `note_dmabuf_hook_removed` 漏计 `remove_default_dmabuf_pre_commit_hook`
    路径 → **已修**（compositor.rs 该函数补计数，四路径配对）
  - C2 roadmap 修复验收判据未达成 → 同 Pauli C1，**已修**
- PLAUSIBLE：P1 文档 `+1/-0` 与当前代码错位（中间构建产物）→ 已勘误；
  P2 dmabuf_cache 峰值 34 → 已勘误；P3 161 口径 → 已勘误
- 已核查无问题：G-6/G-5/G-7/G-8、cargo test 667 全绿、profile 与文档一致、
  边界/失败路径、文档数字自洽

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| 节流首 5 秒失效 | CONFIRMED | 已修 | niri.rs `maybe_log_vram_diag` 首调记录基线 |
| 注释精度 | CONFIRMED | 已修 | niri.rs 注释更新 |
| dmabuf_hook 漏计移除路径 | CONFIRMED | 已修 | compositor.rs `remove_default_dmabuf_pre_commit_hook` 补 `note_dmabuf_hook_removed` |
| 完成判据与实测相反 | CONFIRMED | 已修 | roadmap/execution-plan D1 判据如实化 |
| 机制标成已实测验证 | CONFIRMED | 已修 | research-report D-4 `[实测]`/`[未确认]` 分列 |
| 全局任务数 12→13 | CONFIRMED | 已修 | roadmap 全局判据 |
| 161 次口径 / dmabuf_cache 33 / buffers 全程 | PLAUSIBLE | 已修 | acceptance/D1-diagnostics.md 勘误 |
| 两条 5s 周期日志 | PLAUSIBLE | 不修，理由：既有 `maybe_log_periodic` 非本任务引入；新增 `maybe_log_vram_diag` 与之一致且 env 门控；合并属范围外重构 |
| 移动中 tile 快照不计 | PLAUSIBLE | 不修，理由：诊断性低估、状态短暂、不影响判定；记录于本表 |
| 测试间全局计数交叉 | PLAUSIBLE | 不修，理由：既有模式（with_enabled_for_test 已串行），D1 仅扩大计数面；667 全绿 |

## 完成判据核对

| 判据（引 roadmap D1） | 是否满足 | 证据 |
|---|---|---|
| 诊断记录含完整证据并回填 D-4/D-5 | 是 | acceptance/D1-diagnostics.md + research-report.md D-1~D-5 |
| profile 已安装且格式与驱动一致；受控循环实测如实记录 | 是 | `~/.nv/nvidia-application-profiles-rc` + D-5 勘误 |
| cargo test 全绿 | 是 | 667 passed / 0 failed（含 lifecycle 回归） |
| 人工验证开/关、最小化/恢复、最大化无回归 | 待部署后人工验证 | 诊断代码默认关闭（env 门控），测试全绿；部署见 P-10 |
| acceptance/D1-review.md 存在且独立子代理 APPROVE | 是（本文件；2 REJECT 已修复，修复项见处置表，待第 2 轮复核） | 本文件 |

## 最终结论

第 1 轮审查：1 APPROVE / 2 REJECT，全部 CONFIRMED 已修复（代码 3 处 +
文档 6 处）。按流程第 5 步回到第 3 步重新自检，并安排第 2 轮复核后再 commit。


---

## 第 2 轮复核（2026-08-12）

### 子代理 4（Newton —— 代码修复复核）
- 结论：**APPROVE**
- 确认：节流首调修复正确（niri.rs 首调记录基线并 return，CAS 语义正确，
  无新 panic/死锁）；unmapped 计数四路径全配对；dmabuf hook 正常生命周期
  三 add / 二 remove 逐路径净 0。
- 非阻塞瑕疵：`add_default_dmabuf_pre_commit_hook` 的「已有 hook 替换」防御
  分支（不可达的 error 路径）漏计 removed → **已修**
  （compositor.rs 该分支补 `note_dmabuf_hook_removed`）。
- 测试：`cargo test` 667 passed / 0 failed；一次与修复无关的既有 flake
  （`blur_capacity::renderer_reset_releases_global_budget_and_starts_fresh`
  在 NVIDIA 显存保留现象下偶发，复跑通过）。

### 子代理 5（Banach —— 文档复核）
- 结论：**REJECT**（全部为定点可修残留，第 2 轮已全部修复）
- CONFIRMED 残留及处置：
  1. execution-plan.md:218 2.7 注释仍为旧判据 → **已修**
  2. roadmap.md 范围第 3 条「增量归零/回落」与完成判据矛盾 → **已修**
  3. roadmap.md「根因未定位（D-4 三个候选）」陈旧 → **已修**
  4. research-report.md:530「被调用 161 次」与 D-5（546 次）同文件矛盾 → **已修**
  5. execution-plan.md:417「161 次」无勘误指向 → **已修**
  6. acceptance 正文旧值（33/全程恒定/基线归因/应不再增长）靠勘误追认 →
     **已改为正文直改**（峰值 34、受控循环恒 2、不归因、如实记录）
  7. acceptance 结论把机制当事实断言 → **已加 `[实测]`/`[未确认]` 标注**
- PLAUSIBLE：`dmabuf_hook 1 增 2 删共 3 处，文档称「四路径」字面不精确
  （指四个计数函数）→ 措辞已随第 2 轮修订避免歧义；D1-review 判据
  「APPROVE」标记待第 3 轮后更新。

## 第 3 轮复核（2026-08-12）

### 子代理 6（Mill —— 文档最终复核）
- 结论：**APPROVE**
- 清单 7 项（execution-plan 2.7 注释、roadmap 范围/判据、陈旧话、
  glDeleteTextures 口径、acceptance 正文旧值、机制标注、D1-review 完整性）
  全部确认已修；roadmap「全部 13 个任务」、索引状态行、第 4 章 D1 回归段、
  profile 实装均核验一致。
- 附带 3 条 PLAUSIBLE 措辞/数字微调（execution-plan.md:222 大窗注释、
  research-report.md:544 验证方法预期句、acceptance +82 vs +8×10 取整）
  → **已全部顺手修正**。

## 最终结论

3 轮审查：代码 1（Newton APPROVE）+ 文档 2 轮（Banach REJECT 后定点修复、
Mill APPROVE）。全部 CONFIRMED 已修；PLAUSIBLE 不修项已在处置表记录理由。
**允许 commit。**
