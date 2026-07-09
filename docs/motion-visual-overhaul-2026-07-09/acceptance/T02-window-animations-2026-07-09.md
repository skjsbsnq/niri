# T02 · 窗口/工作区动画 + 阴影/圆角 KDL 重写 · 验收记录

日期:2026-07-09
前置:GOAL-01 DONE(`git log --grep '^T01:'` → 1e4ee73,已 push);父仓与 niri 子模块工作树干净;`niri validate` 预检通过;实机 niri 会话在跑(compositor 571fe4fa = 子模块 HEAD)。

## 改动清单落地(逐项对照 roadmap)

| Roadmap 项 | 落地 |
| --- | --- |
| window-open spring 主通道 | `spring damping-ratio=0.85 stiffness=300 epsilon=0.001`(epsilon 按规则 §4.6 不透明度类下限);新 shader:中心缩放 0.965→1(`mix` 驱动)+ 淡入(70% 行程内完成,缩放为主视觉),读 `niri_clamped_progress`,弹簧值经 `opening_window.rs:58` `anim.value()` 直喂 uniform |
| window-close 140ms + scale→0.97 | `duration-ms 140` + `curve "ease-out-quad"`(曲线沿用);shader 加中心收缩 1→0.97 + 线性淡出(去掉原 smoothstep 双重缓动) |
| workspace-switch | `spring damping-ratio=0.92 stiffness=420 epsilon=0.0001` |
| window-movement | `spring damping-ratio=0.8 stiffness=480 epsilon=0.001`(KDL 写 `0.8` 非 `0.80`,匹配 `format_float` 保字节往返) |
| window-resize 保持近临界 | 未动(dr=0.96 st=700) |
| layout.shadow | softness 36→60、spread 4→6、y 10→18、color #0006→#0007;inactive-color #0004 保持;**非激活 softness 40** 经既有 `window-rule { match is-active=false }` 加 `shadow { softness 40 }` 表达(Shadow 结构无 per-state softness,`ShadowRule` 合并语义支持单字段覆写,`appearance.rs:342/648`);首个 window-rule(匹配全部窗口)的 shadow 块与 layout.shadow 同步更新(否则其覆写会吞掉 layout 值) |
| geometry-corner-radius | 18→22,popups 14→16 |
| 工具同步(清单外必要项) | `niri_settings_tool.py` MOTION_PROFILE_SPRINGS **balanced** 表同步 ws/wm 新值——animations 区块是 profile 管理面,不同步则 profile 切换回写旧值且字节级往返/profile 检测破坏 |

### 范围决策(写入记录)

1. **fast/liquid/reduced 弹簧表不动**:roadmap T02 文本只给 balanced 语义的新值;“四 profile 复核校准”是 T23 的明确职责。仅 balanced 表与 KDL 对齐即满足治理不变量(检测+往返)。测试钉死的 fast 值(st=860)因此不需改。
2. **genie 不启用回退口**:window-close 保持新值 140ms(见下)。

## 关键发现:genie“320ms 下限”是文档失实

研究报告(01-research-report.md:167)与旧验收文档(`tahoe-shell/docs/old/genie-minimize-phase7-8-acceptance-2026-06-21.md:19`)声称 genie 在有效目标矩形时强制“更平滑曲线 + ≥320ms 下限”,并引用测试 `genie_animation_config_slows_valid_target_rect`。**核实结果:代码里从不存在**——`git log --all -S "from_millis(320"` 全历史零命中,该测试名全仓不存在;`floating.rs:1010/1050`、`scrolling.rs:1875/1911` 均直接使用 `window_close.anim`/`window_open.anim`,无任何调整。

实际耦合(T02 生效后):genie minimize = window-close = **140ms ease-out-quad**(原 100ms);genie restore = window-open = **spring(0.85/300)**,settle ≈470ms(视觉主体 ≈250ms,更接近真 genie ≈500ms 吸入感)。`genie.frag:7` 对 progress 二次 clamp,弹簧过冲不会破形变。T04 解耦时序的必要性因此更强(minimize 140ms 偏快是当前真实观感,无下限兜底)。

## 验收结果

| 项 | 结果 |
| --- | --- |
| `niri validate --config config/niri/tahoe-phase0.kdl` | **config is valid**(spring 主通道 + custom-shader 组合解码通过) |
| `python -m pytest tahoe-shell/tests/ -x` | **75 passed, 63 subtests passed**(含 `test_motion_profile_write_updates_springs_and_layer_rules`:新 KDL 检测为 balanced,balanced→fast→balanced **字节级一致**) |
| 实机部署 | 按 `deploy_niri_config` 语义 install 到 `~/.config/niri/tahoe/config.kdl` + 部署基线(部署前确认 target==基线,无用户手改);session.log 09:46:01 热重载成功,无错误。`niri_settings_tool.py` 同步部署(确认部署副本==repo HEAD 后覆盖);部署侧检测:`profile: balanced`,ws/wm 新值 |
| 实机开/关 | `spawn alacritty` → open spring+shader 无 shader/GL 错误;`close-window --id` 无错误 |
| 实机换工作区 | `focus-workspace-down/up` 新弹簧,无错误 |
| 实机拖动/移动 | `move-floating-window` 两段位移,movement 弹簧路径无错误 |
| genie 双向 | `minimize-window --id` → `is_minimized: True`;`restore-window --id` 恢复正常(注意:fork CLI 需 `--id`,PATH 里的 niri CLI 是旧构建 8ed0da4,不能用于 minimize) |
| genie 快速连点/中断反转 | minimize→150ms→restore(中途反转)、minimize→100ms→restore→100ms→minimize 三连,全部无错误无残留(`reverse_to_*` 接力路径) |
| 目测对照 | `acceptance/T02-screenshots/t02-open.png`(22px 圆角+加深投影清晰可见)、`t02-restored.png`;对照 T00 `01-idle-dock.png` |
| 日志静默期核查 | 演练全程 session.log 无 error/warn/fail/reject/panic/fallback(排除 foreign-toplevel rect 噪声) |

手测矩阵说明:深浅色/reduced profile/`compositorLayerAnimations=false` 属 QML/layer 面,T02 未触及 QML 与 layer-rule,不适用;快速连点已按 genie 中断反转覆盖。动画主观手感(弹簧“落座”、阴影景深)待用户日常使用确认,回滚 = `git revert` 本提交 + 重部署。

## 红线自查(§2)

玻璃 region 未触碰(窗口动画全部 compositor 侧,红线 1 明确许可);无 QML 改动(useSpring/门控不涉);KDL 改的是源文件 tahoe-phase0.kdl 本身(§2.3 管的是 QML 运行时写入路径,不适用);无新 token 文件;profile 三方:balanced 表已同步、profile 名未变、DesktopSettings 无需动;未删任何 fallback;未动 quickshell 子仓;IPC 面无变化。

## 违规与纠正

第一轮实机演练中 `restore-window` 因缺 `--id` 失败后,后随的无 id `close-window` 关闭了当时焦点窗口。核对窗口清单:关闭的是本演练自己 spawn 的 alacritty,用户 7 个既有窗口(id 2/3/4/11/17/19/27)全部健在,无实际损害。纠正:后续演练全部改用显式 `--id`。

## 发现待办

1. **文档失实修正**:01-research-report.md:167 与记忆中的“genie 320ms 下限”需修正(本记录已核实为不存在);T04 设计 `window-minimize {}`/`window-restore {}` 默认值时不要按“镜像 320ms 下限”理解“默认=现行为”——现行为就是裸继承 close/open。
2. PATH 中 `niri` CLI(8ed0da4)与 fork compositor(571fe4fa)不同构建,缺 minimize/restore 动作;涉 fork 专有 IPC 的验收一律用 `~/.local/bin/niri`。
3. genie minimize 140ms 偏快(macOS ≈400ms+),T04 的 minimize 420ms 解耦是正确方向;restore 已因 spring 接近目标手感。
4. `niri msg windows` 人类可读输出不含 minimized 字段,查询用 `--json` 的 `is_minimized`。

## 结论

T02 改动清单 100% 落地(含 1 项清单外治理必要同步、2 项范围决策),验收全绿,genie 无回归且未启用回退口。GOAL-02 → DONE。
