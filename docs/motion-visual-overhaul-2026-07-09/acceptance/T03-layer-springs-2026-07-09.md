# T03 · layer-rule 全面弹簧化 + anchor popin · 验收记录

日期:2026-07-09
前置:GOAL-02 DONE(`git log --grep '^T02:'` → efd7f6a,已 push);父仓与 niri 子模块工作树干净;实机 niri 会话在跑(571fe4fa)。

## 改动清单落地(逐项对照 roadmap)

| Roadmap 项 | 落地 |
| --- | --- |
| 菜单类 namespace → `popin origin "anchor" scale-from 0.94` + 主通道 spring(dr≈0.88 st≈500)+ `opacity-from 0 / opacity-duration-ms 90` | small-popup 规则(battery/wifi/fan/clipboard/menu-popup/application-menu/tray-menu 共 7 ns)+ process-menu 规则:`popin origin "anchor" scale-from 0.94 + spring damping-ratio=0.88 stiffness=500 epsilon=0.001 + opacity-from 0 / 90ms standard-decel`;**不写 transform-duration-ms/transform-curve**,transform 通道继承主通道弹簧(`animation_from_optional_easing_params`:override 全缺省时直接返回主通道 anim,`animations.rs:1010-1034`)。epsilon 按规则 §4.6 小元素下限 0.001 |
| 关闭 → 180ms 纯淡出(scale-to 0.98,menu-accel 换 emphasized-accel) | 全部菜单/popover 关闭:`popout scale-to 0.98 opacity-to 0 + transform/opacity 180ms emphasized-accel`;layer-rule 区块内 menu-accel 全部换 emphasized-accel(spotlight/toast 关闭曲线一并换,时长不变) |
| CC/通知中心/左侧边栏 edge-reveal 主通道换 spring(dr≈0.85 st≈380) | 三 namespace layer-open:`spring damping-ratio=0.85 stiffness=380 epsilon=0.0005`(位移类 epsilon 下限 0.0005),删 transform-duration-ms/curve 以继承;opacity 通道与关闭动画不变(关闭未在 roadmap 范围) |
| toast slide 主通道 spring(dr≈0.80 st≈320) | `spring damping-ratio=0.8 stiffness=320 epsilon=0.0005`(KDL 写 `0.8` 保字节往返),slide right distance 28 与 opacity 通道保持 |
| spotlight popin 换 spring + scale-from 0.96 | `scale-from 0.985→0.96 + spring damping-ratio=0.88 stiffness=500 epsilon=0.001`,origin "center" 保持(spotlight surface 四边锚定,anchor origin 等价于 center) |
| 同步 `test_edge_reveal_semantics.py` | 原三断言不涉时长/曲线、全部仍绿;**新增** `test_layer_open_spring_main_channel_has_no_transform_override`:凡带 spring 的 layer-open 块(≥8)必须无 transform-duration-ms/transform-curve override,防止 easing override 静默压掉弹簧 |

### 清单外必要同步(治理不变量)

1. **`niri_settings_tool.py` MOTION_PROFILE_LAYERS 全表重写**:layer-rule animations 是 profile 管理面(T02 结论同理)。新增 `spring_phase()` 词汇:profile 表管理 layer-open 主通道 spring 行(原地重写,`set_phase_spring`)+ 以 `None` 语义**主动移除**叶子(`remove_leaf`/检测要求缺席),使 transform 通道继承弹簧;`apply_layer_profile` 改为每键重查块边界(插删行会使旧边界失效)。fast(菜单 dr0.95/750、面板 dr0.9/520、toast dr0.85/450)/liquid(dr0.82/420、dr0.82/300、dr0.78/260)等比伸缩,**T23 复核校准**;reduced 保持"layer transform 归零"哲学(`transform-duration-ms 0` 覆写,惰性 spring 行原地保留),policy 文档钉住的语义不变。
2. **顺带修复既有潜在往返不对称**:CC/NC layer-close 此前 reduced 会写入 `opacity-curve "menu-accel"` 而 balanced 表不管理该键,reduced→balanced 会残留脏行;现 balanced/fast/liquid 表以 `opacity-curve: None` 主动移除,并把 KDL 源 `opacity-to 1` 规范为 `1.0`(值变化往返时 format_float 规范化所需)。实测四 profile 任意链条字节级往返(见下)。
3. `test_niri_settings_tool.py` 断言更新至新语法 + 新增 `test_motion_profile_reduced_roundtrip_stays_byte_identical`;`tahoe-motion-default-policy.md` 增 T03 注记。

### 范围决策(写入记录)

1. **"菜单类七 namespace"的解读**:roadmap 括号列出 6 个菜单 namespace 但作"七";研究报告 §4(:136)明确 popover 类(电池/WiFi/风扇/剪贴板)同样 `popin origin "anchor" scale-from 0.94 + 弹簧`,且 KDL small-popup 规则本就是 7 namespace 一组。落地为:**7 ns 规则 + dock 2 ns + process 1 ns 共 10 个弹层全部 popin 弹簧化**,超集覆盖两种读法,与任务目标"所有 shell 弹层换 Apple 手感"一致。
2. **dock 菜单 origin 用 "center" 而非 "anchor"**:DockAppMenu/DockWindowMenu 的 PanelWindow 是 **top+left 锚定**(`DockAppMenu.qml:44-52`,margins 计算定位于图标上方),`origin "anchor"` 会以左上角为缩放原点——**背离下方的 dock 图标方向**(anchor 语义见 `opening_layer.rs:204-210`)。顶栏菜单/popover 的 top+left 锚定 ≈ 按钮下沿(方向正确,保持 anchor);process-menu top+left ≈ 点击点(正确,保持 anchor)。dock 菜单改 QML 锚定属 QML 面、超出本任务"同文件 layer-rule 区块"范围(规则 §1.5),真正的"从图标长出"归 T22 origin "pointer"。KDL 注释已记载理由。
3. **spotlight 弹簧参数**:roadmap 未给数值,取与菜单一致的 dr=0.88 st=500(即 Motion.js springSnappy 的 niri 对映),记录于此。
4. **弹簧过冲行为说明**:`OpenAnimationState` 对 transform 进度做 `clamped_value().clamp(0,1)`(`opening_layer.rs:53`),popin/edge-reveal 弹簧无可见过冲穿越,收获的是弹簧的速度包络(快起缓收);玻璃 region 因此天然安全(compositor 侧自裁剪,红线 §2.1 许可项 ②)。

## 验收结果

| 项 | 结果 |
| --- | --- |
| `niri validate --config config/niri/tahoe-phase0.kdl` | **config is valid**(spring 主通道 + popin origin anchor 组合解码通过) |
| `python -m pytest tahoe-shell/tests/ -x` | **77 passed, 63 subtests passed**(75 基线 + 2 新增;含 profile 检测=balanced、fast/liquid/reduced 三往返字节级一致、链式 reduced→fast→liquid→reduced→balanced 字节级一致) |
| 实机部署 | 部署前确认 target==deploy-baseline==HEAD 基线(无用户手改);install 到 `~/.config/niri/tahoe/config.kdl` + 部署基线;session.log 11:07:12Z 热重载成功;`niri_settings_tool.py` 部署副本确认==HEAD 后同步覆盖 |
| 逐 namespace IPC 开关目测 | control-center / notification-center / left-sidebar / spotlight / battery / wifi / fan / clipboard 八项:开(900ms 静置)→关 全部无错误 |
| 快速连点中断反转 | 同八项各 3 连点(120/100ms 间隔)+ 收尾关闭,`reverse` 接力路径无错误、无残留(终态全关) |
| toast | `scripts/test-notification.sh` 触发 slide 弹簧路径,无错误 |
| `compositorLayerAnimations=false` 回退 | 经 desktop-settings.json(FileView watchChanges)置 false → spotlight/left-sidebar/CC/battery 开关正常、无错误 → 恢复 true。T03 零 QML 改动,QML fallback 分支结构未触碰 |
| reduced profile 实机 | repo 工具对**部署副本** write reduced(niri validate 原子路径)→ CC/battery 开关正常(transform 归零、纯淡)→ write balanced → **部署副本与 repo 源字节级一致** |
| 目测对照 | [T03-screenshots/t03-battery-popin.png](T03-screenshots/t03-battery-popin.png)(popover 静止态,玻璃/圆角/阴影正常)、[t03-control-center.png](T03-screenshots/t03-control-center.png);对照 T00 `02-control-center.png` |
| 日志静默期核查 | 验收窗口(11:07Z 部署起)带时间戳可疑行 **0**(排除 foreign-toplevel 噪声;08:43Z 的 IPC broken-pipe 警告早于本任务数小时,非本任务产物) |

手测矩阵说明:Esc/点外关闭为 QML 键鼠路径,本任务零 QML 改动、协调机制未触碰,IPC 关闭等价覆盖出场动画;深浅色与 layer 动画正交(材质/主题未动)。dock-app-menu/dock-window-menu/process-menu 无 IPC 入口,其规则语法与实测通过的 small-popup 规则同构(仅 origin 差异,origin 解码经 validate + spotlight center/小弹窗 anchor 两路径实测),日常右键使用的观感确认列入"发现待办"。

## 红线自查(§2)

玻璃 region 零触碰(全部 compositor 侧,§2.1 许可 ②);零 QML 改动(useSpring 门控不涉,§2.2);KDL 改的是源文件本身、运行时写入仍走工具(§2.3);无新 token 文件(§2.4);profile 三方:profile 名/数量未变,Motion.js/DesktopSettings 无需动,`niri_settings_tool.py` 表+policy 文档同提交更新(§2.5);未删任何 fallback,reduced 语义保持(§2.6);无新依赖(§2.7);未新增命名曲线,emphasized-accel/standard-decel 均为在用单调曲线(§2.8);未动 quickshell 子仓(§2.9);IPC 面无变化,八项入口实测可用(§2.10);Launchpad 未触碰(§2.11)。epsilon 下限:位移类 0.0005 / 小元素 0.001(§4.6)。

## 发现待办

1. dock-app-menu/dock-window-menu/process-menu 的弹簧 popin 观感需日常右键使用确认(无 IPC 驱动入口);若 dock 菜单 center popin 观感不足,T22 origin "pointer" 是正解,届时可顺带评估 dock 菜单 QML 改 bottom 锚定的备选。
2. T02 发现待办 #1(01-research-report.md:167 genie"320ms 下限"失实)仍未修正,归 T04 实施时一并处理(T04 即将改该耦合)。
3. session.log 中偶发 `niri::ipc::server` broken-pipe 警告(08:43Z,IPC 客户端提前断开),与动画无关,观察即可。
4. fast/liquid 的 layer 弹簧数值为本任务合理外推,T23 四 profile 复核校准时统一调音。

## 结论

T03 改动清单 100% 落地(含 2 项清单外治理必要同步、4 项范围决策),验收全绿。GOAL-03 → DONE。
