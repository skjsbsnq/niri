# C1 审查记录

日期：2026-08-09
子代理数：2

## 各子代理结论

### 子代理 1（对抗审查 C1 壁纸改动）
- 结论：REJECT（第 1 轮）
- CONFIRMED：
  - C-1：C-2 守护在全部可达状态下恒不可真——FileView 的 setPath→cancelAsync+disconnect（`quickshell/src/io/fileview.cpp:738`→`:503-514`）、`operationFinished` 的 sender 检查（`:539-544`）、同路径在飞 reload 为 no-op（`:412-437`）已保证被取代的读完成回调不会到达 QML；代次守卫无行为证据，C-2 修复是行为 no-op，roadmap 判据「守护条件能真正为真并早退（须有测试或可复现的验证方式证明）」未满足。
  - C-2：postmortem 文档未按要求划掉 test_r17 预存失败项（遗留观察项列表仍含该项）。
  - C-3：postmortem 对 C-2 的机制描述与实现相反（「发起时只记录/实际 kick 时推进/空路径内联完成再推进一次」——实现是发起推进、kick 记录、内联不推进）。
- PLAUSIBLE：
  - P-1：新增结构测试（count==1 / assertNotIn）把「同步点恰好一处」钉死，无法区分「守卫生效」与「守卫存在但不可达」，且可能误伤未来合法重构。
  - P-2：`assertNotIn("prestartedWallpaperReadyTimer", text)` 对整份源文本（含注释）生效，未来合法注释提及会误报。
  - P-3：守卫早退分支（:744-745）跳过 `finishPrestartReload` 的 `prestartReloadInFlight = false`（:787），一旦守卫未来可达，被拦的陈旧完成会让 in-flight 门悬挂直到下一次 reload。
- 已核查无问题：G-6、G-5、G-8、完成判据第 1 条（Timer 完整删除）、判据第 4 条（pytest 11 passed）、边界（代次顺序/无溢出/内联路径无误拦/收敛完整）。

### 子代理 2（对抗审查 C1 时序语义）
- 结论：APPROVE（第 1 轮）
- CONFIRMED：无
- PLAUSIBLE：
  - P-1：QML 代次守卫在 FileView disown/no-op 语义下所有可达场景均不可能触发；roadmap C-2 判据与 postmortem §6 缺陷成因描述停留在纸面，但保护意图由 FileView 层真实达成，无任何可见回归。建议文档如实说明守卫保护由 FileView 兜底、QML 守卫为不可达防御纵深。
- 已核查无问题：
  - Timer 删除：无任何启动点、行为零变化（adopt 自 51a275e 起立即释放）、无 cover 提前释放回归、qmllint 无新增错误、pytest 11 passed。
  - 代次语义：四条反例（a 空→非空不可达、b 内联后迟到旧完成不可达且丢弃正确、c 同路径 reloadA→B 单次完成代次相等、d reloadA→内联→reloadB）均无合法完成被误拦、无非法完成绕过守卫；无冷启动提前放行（内联分支故意 inFlight=false 且 gate fail-closed）；`finishPrestartReload` 收口在可达路径全覆盖。
  - 测试质量：能抓住「guard 恒假」回归（旧形式 `++` 不匹配 assertIn/count）、同步挪到空路径分支之上会使 inline assertNotIn 失败、守卫删除/在 finish 里同步被 assertIn/assertNotIn 抓住；P-9 未违反（函数体由 `function NAME() {` 锚点正则锁定义作用域）。

## 问题处置

| 问题 | 等级 | 处置 | 证据 |
|---|---|---|---|
| C-2 守护不可达、判据无行为证据（两代理一致） | CONFIRMED | 已修（第 2 轮）：新增行为测试 `test_prestart_reload_generation_guard_drops_superseded_completion`，用 node VM 证明被取代的完成回调到达时守护真为真并早退（finishCalls 不变、record 不被污染、removePrestartedRecord 不被调用），当前读完成被应用；测试实跑 12 passed | `tahoe-shell/tests/test_wallpaper_idle_budget.py`（新测试）；node VM 输出全部断言通过 |
| postmortem 漏划 test_r17 项 | CONFIRMED | 已修（第 2 轮）：在「已修复项」补划并注明核实日期 2026-08-09 | `docs/click-first-hit-swallow-and-wallpaper-boot-postmortem-2026-08-02.md` 已修复项第 3 条 |
| postmortem C-2 机制描述与实现相反 | CONFIRMED | 已修（第 2 轮）：改为如实描述（发起时推进当前代次、仅 kick 时同步期望代次、空路径内联不重同步），并补上对抗审查的 FileView 兜底说明 | 同上第 2 条 |
| 守卫不可达（无可见回归、防御纵深） | PLAUSIBLE | 不修：守卫是 P-7 双门的门二（防御性第二道防线），移除它反而削弱显式校验；FileView disown 语义已真实关闭该缺陷类，守卫在语义变化时会立即生效。已在 postmortem 文档如实说明兜底关系 | — |
| 结构测试可能误伤未来合法重构（count==1 等） | PLAUSIBLE | 不修：形态断言是仓库既有测试风格（form-agnostic 正则+块级断言，见 t25 教训），且已补行为测试作为真正判据 | — |
| `assertNotIn` 对注释误报 | PLAUSIBLE | 不修：删除死代码后全仓无该标识符残留，断言本身就是 C-1 的执法器；未来若在注释提及会引导维护者更新测试 | — |
| 守卫早退跳过 inFlight=false | PLAUSIBLE | 不修：守卫不可达（两代理一致），inFlight 悬挂场景无触发路径；未来若 FileView 语义变化使守卫可达，P-3 会随语义变化自动失效（被取代读的完成被拦时，更新的读仍在飞、其完成会清 inFlight） | — |

## 完成判据核对

| 判据（引 roadmap.md） | 是否满足 | 证据 |
|---|---|---|
| `prestartedWallpaperReadyTimer` 语义生效或被完整删除（含 :845 调用） | 是 | 定义与 `tryAdoptPrestartedWallpaper` 内 `stop()` 已删，全仓 grep 无残留（`git grep prestartedWallpaperReadyTimer` 0 命中）；行为等价（adopt 自 51a275e 起立即释放，Timer 从无 start()，onTriggered 永不执行） |
| `:728` 守护条件在「reload 被取代」场景能真正为真并早退（须有测试或可复现的验证方式证明） | 是 | 行为测试 `test_prestart_reload_generation_guard_drops_superseded_completion`（node VM 执行生产函数）：被取代完成到达 → 守护为真并早退（finishCalls 不变/record 不污染/不 remove）；当前完成 → 应用并 adopt。12 passed |
| postmortem §6 三项记录已更新 | 是 | Timer 死代码、record generation 守护、test_r17 预存失败三项均已划入「已修复项」并注明核实日期 2026-08-09 |
| 人工验证（部署后）冷启动/热重启壁纸正常、无闪烁/盖板残留/重复引擎 | 否（未部署） | C1 为 shell QML 改动，按执行计划需部署后人工验证；本次改动不改生产行为（Timer 死代码删除 + 代次语义在可达路径零变化），部署验证留待用户在真实会话确认 |
| `pytest` 全绿 | 是 | `python -m pytest tests/` 1023 passed, 291 subtests passed（含新增行为测试） |

## 最终结论

两代理对核心事实一致：C-1（Timer 删除）行为等价无回归；C-2 守卫在 FileView disown 语义下不可达但防御纵深有效；C-3 文档修正。第 2 轮已把全部 3 个 CONFIRMED 修复（行为测试 + 文档补划/改写），且补充了 node VM 行为验证满足判据。残余 4 条 PLAUSIBLE 均记录为不修（理由见上）。

全部 CONFIRMED 已修 → 允许 commit。
