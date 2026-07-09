# T01 · Motion.js 2.0:弹簧 token 与治理测试同步 · 验收记录

日期:2026-07-09
前置:GOAL-00 DONE(`git log --grep '^T00:'` → eaf74e5,已 push)。

## 二选一决策(roadmap 明确要求写入验收记录)

**选择:以 `balanced` 承载 Tahoe Motion 2.0 新值,不新增 `macos` profile。**

理由:
1. 04-goals §3.3"零藏匿"——新手感必须是默认体验,不能藏在非默认 profile 后面;
2. policy 文档的"balanced 字节级回滚基线"指 profile writer 的往返一致性(fast→balanced 回到字节一致 KDL),不是数值冻结;本任务实测往返仍字节一致(见下);
3. 不新增 profile 则 `niri_settings_tool.py` / `DesktopSettings.qml` 无需改动,同步面最小;roadmap 文本"四 profile 等比联动"本身即指现有四个 profile。

`tahoe-motion-default-policy.md` 已加 2026-07-09 注记说明此语义(回滚 = `git revert` T01 提交)。

## 改动清单落地(逐项对照 roadmap)

| Roadmap 项 | 落地 |
| --- | --- |
| 弹簧 token 导出 | `Motion.js` 新增 `springSnappy{4.2,0.30}`(niri dr=0.88 st=500)/`springSmooth{3.0,0.40}`(dr=1.0 st=250)/`springPanel{2.5,0.28}`(dr=0.85 st=160)/`springBouncy{2.5,0.22}`(dr=0.70 st=160),每个 token 注释内含对应 niri KDL 参数与用途;文件头注明 Apple response/bounce→niri 换算公式;token 注释重申玻璃 region 禁弹簧红线与 useSpring 门控 |
| pressIn token | `pressDuration=120`、`pressScale=0.96`、`pressEasing=OutQuad`(T05 唯一出口) |
| 时长重调 | balanced:menuEnter 150→**180**、menuExit 120→**160**、panelEnter 180→**320**、panelExit 140→**200**;fast 等比(145/130/260/160);liquid 等比(210/185/370/230);reduced 不变(70/60/80/60,保持极短);fadeFast/elementMove/elementResize 三键 roadmap 未列,保持原值 |
| 治理测试同步 | `test_motion_token_convergence.py` 新增 2 测试(弹簧词汇表数值+niri 注释同步断言、press token 断言);`test_motion_default_policy.py` 新增 2 测试(balanced 2.0 时长断言、reduced ≤80ms 极短断言) |
| 不改任何组件 | 本提交无任何 .qml 改动(`git show --stat` 可验证);32 个组件经 `Motion.menuEnter(...)` 等函数取值,数值变化自动生效 |

## 验收结果

| 项 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/` | **75 passed**(71 基线 + 4 新增治理断言) |
| quickshell 冒烟(repo 版,7s 加载 + IPC 驱动) | 加载正常;`toggleControlCenter`×2 / `toggleLeftSidebar`×2 开关动画正常(QML fallback 路径吃到新时长);对比 T00 基线无新增 QML 错误(仅第二实例的 portal 注册环境警告) |
| 设置页 motion profile 切换链路 | 治理测试断言 `setMotionProfile` 函数与 profile 名三方同步仍成立;`niri_settings_tool.py` 在 KDL 副本上 balanced→fast→balanced 往返 **字节级一致**(GOAL-5 回滚性质保持) |
| 红线自查 | 无 KDL 改动、无组件改动、无新 token 文件(convergence 测试锁定)、balanced 回滚地位不变 |

## 发现待办

1. quickshell 冒烟实例被 SIGTERM/SIGKILL 结束时会在 `/run/user/1000/quickshell/{by-id,by-pid,by-shell}` 留失效条目,导致下次 `-n` 启动误判"已运行"。本任务两次手工清理;后续任务冒烟建议统一 SIGINT + 等待退出。不涉仓库代码。
2. 02-rules §6 模板 `quickshell -p tahoe-shell -n` 的 `-n`(--no-duplicate)在存在失效锁时会静默退出,冒烟脚本判定需看日志行数而非退出码(本轮已按此执行)。

## 结论

T01 改动清单 100% 落地,验收全绿。GOAL-01 → DONE。
