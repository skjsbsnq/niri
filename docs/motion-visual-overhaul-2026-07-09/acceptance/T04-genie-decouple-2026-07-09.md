# T04 · Genie(神灯)动画专项优化 · 验收记录

日期:2026-07-09
前置:GOAL-03 DONE(`git log --grep '^T03:'` → 54f3f3f,已 push);父仓与 niri 子模块工作树干净。
子模块提交:`9e6889f3`(tahoe-layer-animations,已先于父仓 push;`scripts/check-submodules.sh` 通过)。

## 改动清单落地(逐项对照 roadmap)

| Roadmap 项 | 落地 |
| --- | --- |
| 1. `window-minimize {}` / `window-restore {}` 节点 + layout 接线 | `niri-config/src/animations.rs`:`Animations.window_minimize/window_restore: Option<WindowMinimizeAnim/WindowRestoreAnim>`(newtype 镜像既有 Animation 节点形态,空节点默认镜像 close/open 默认值);**默认=现行为**:节点缺席时 `window_minimize_anim()/window_restore_anim()` 解析回 `window_close.anim`/`window_open.anim`——按 T02 核查结论"现行为=裸继承,无 320ms 下限"落地,roadmap 括号中的"+320ms 下限"系研究报告失实(本提交已修正 01-research-report.md,详见下)。`AnimationsPart` + `merge_clone_opt` 合并。layout 侧 **10 处耦合点全部替换**:floating.rs/scrolling.rs 各 5(start_minimize、start_restore、reverse_to_minimize、reverse_to_restore、无矩形 restore 的 animate_alpha_scale 回退);close/open 自身、snap-preview、tile open、mru 等非 genie 用途不动 |
| 2. Tahoe KDL | `window-minimize { duration-ms 420; curve "cubic-bezier" 0.32 0.0 0.18 1.0 }`、`window-restore { duration-ms 360; curve "emphasized-decel" }`;注释注明与 open/close 一样不受 motion-profile 管理(`niri_settings_tool.py` 注释同步) |
| 3. genie.frag 两段式重修 | tail/flow 双相位(分界 morph=0.4,两相位曲线在分界处零斜率衔接无折痕):0–40% 目标端(底边)以 `1-pow(1-t,2.3)` 收束 62% 行程"拉尾巴"、远端(顶边)仅蠕动 12%;40–100% 整体 smoothstep 流入;**顶/底 lead 峰值差 0.393→0.50(+11pp,处于 +10–15% 要求带内)**;末端淡出 `smoothstep(0.82,1.0)`→`smoothstep(0.92,1.0)`(末 18%→末 8%);restore 分支经 morph=1-progress 自然反向两段式(先整体涌出、尾巴最后脱离图标),注释明示 |
| 4. 保持项 | 绘制区域 union+24(`genie_area` 未动,2 个护栏测试通过);三级 fallback(无矩形→纯淡出路径实测、跨输出过滤未动、shader 失败→纹理淡出未动);`reverse_to_*` 中断反转(实测);快照释放路径未动(pytest 内存治理通过) |

### 范围决策(写入记录)

1. 研究报告 01-research-report.md:167 的"320ms 下限"失实记载已在本提交更正(T02/T03 发现待办的承接);phase7 文档"末 12% 淡出"同样不准(实为 18%),一并注记。
2. 新节点**不纳入** motion-profile 管理面(与 window-open/close 同类:bespoke 时序),`MOTION_PROFILE_*` 表不变,profile 检测/字节级往返不受影响(pytest 全绿佐证)。

## 验收结果

| 项 | 结果 |
| --- | --- |
| `cargo test -p niri-config` | **30 passed**(含新增:`parse_window_minimize_restore_nodes` 解码三态测试——缺席回退/在场解耦/空节点镜像默认,及 animations.rs 3 个单元测试;golden parse 快照含新节点) |
| `cargo test -p niri --lib -- genie_area minimize_restore_with_rect --test-threads=1` | **4 passed**(绘制区域护栏 + IPC 状态) |
| `cargo test -p niri --lib animation -- --test-threads=1` | **35 passed**(T00 基线口径) |
| `python -m pytest tahoe-shell/tests/ -x` | **77 passed, 63 subtests**(治理面完好) |
| `niri validate`(新二进制) | repo 配置 **config is valid**(新节点解码) |
| `cargo fmt -- --check` | 通过(仅 nightly 选项警告,基线既有) |
| 嵌套实机(新编译器 + repo shell 全链路) | winit 嵌套会话(scale 1.25 分数缩放)+ repo quickshell(Dock 上报 foreign-toplevel rect:window=2 @900,811 56×58,链路实证)+ alacritty:minimize→`is_minimized: True`、restore→False;**快速连点** min→120ms→restore→120ms→min 终态 True(reverse 接力);**Dock 重启**(kill/relaunch quickshell 后 restore→False、再 minimize→True,无过期矩形错误);genie shader 编译零警告;嵌套 niri/quickshell 日志零 error/panic(排除既有基线警告) |
| 手测矩阵(视觉) | **用户实机手动测试确认通过**(2026-07-09,嵌套会话新编译器);用户随后指示跳过剩余验证直接推送 |
| 用户指示跳过项 | `check-genie-minimize-phase7-8.sh` 的 `foreign_toplevel_set_rectangle_tracks_layer_surface_rect`/`xdg_toplevel_set_minimized_minimizes_window` 两个过滤器未单独跑(同套件其余已过,脚本其余为人工清单);多输出矩阵项(winit 嵌套无法多输出,依赖既有 cargo 覆盖);scale 1.0 嵌套复跑。按用户指示记录为跳过 |

## RSS 阶段检查点(规则 §4.9,阶段 A 末)

| 进程 | 当前 | T00 基线 | 变化 |
| --- | --- | --- | --- |
| niri(live,PID 1240) | 297,316 KB ≈ 290.3 MB | 211,844 KB ≈ 206.9 MB | **+40%,超 5% 线,说明如下** |
| quickshell(live,PID 1368) | 520,192 KB ≈ 508 MB | 584,292 KB ≈ 570.6 MB | −11% |

超线说明:**运行中的 live 合成器仍是 T00 时的旧构建 571fe4fa——本轮 T01–T04 没有任何代码进入该进程**(T04 二进制刚部署到 `~/.local/bin/niri`,下次会话生效),涨幅纯属会话运行时长(T00 采样时 3h45m,现已多运行约 9 小时重负载)+ 本轮验收活动(嵌套合成器作为其 Wayland 客户端、多轮截图)所致,与本轮改动无因果。处置:下次会话以新二进制启动后,T12 检查点对新进程重新对照;若彼时仍异常增长再立项。

## 部署状态(重要)

- **二进制已部署**:`~/.local/bin/niri` ← T04 构建(顺带修复 T02 发现待办 #2 的 PATH 旧 CLI 8ed0da4 问题);对运行中进程无影响,下次会话生效。
- **部署配置保持 T03 状态**:`~/.config/niri/tahoe/config.kdl` 暂未写入 T04 节点——运行中的旧编译器解析不了 `window-minimize`,热重载会报配置错误打扰会话。新二进制 + T03 配置 = 节点缺席回退 close/open,安全;**下次会话后跑 `scripts/arch-update.sh`(或手动 install repo 配置)即切至 T04 时序**。`niri_settings_tool.py` 部署副本已同步。

## 红线自查(§2)

玻璃 region 零触碰;零 QML 改动;KDL 源文件改动、新节点不入 GUI 写入白名单(§2.3);无新 token 文件(§2.4);profile 三方不涉(新节点非 profile 面,§2.5);fallback 全保留——无矩形/跨输出/shader 失败三级 + reverse 接力 + 快照释放(§2.6);无新依赖(§2.7);未新增命名曲线(cubic-bezier 内联 + 既有 emphasized-decel,§2.8);未动 quickshell 子仓(§2.9);IPC 面无变化(§2.10)。子模块流程按 §5.2:子模块先 push(9e6889f3)→ check-submodules 通过 → 父仓提交含指针。

## 发现待办

1. 下次会话重启后:跑 `arch-update.sh` 部署 T04 配置;实机大窗口/浏览器窗口的 genie 观感复核(嵌套已验但真实屏幕更大);T12 RSS 以新编译器重新对照。
2. 嵌套验收方法(winit + repo shell + NIRI_SOCKET 隔离)可复用于 T21/T22 合成器任务,已在本记录留档。
3. `pkill -f`/`pgrep -f` 在本会话两次自匹配误杀脚本(模式含于自身命令行),后续脚本一律用 `[x]` 括号技巧或 PID。

## 结论

T04 改动清单 100% 落地(4/4 项,含 roadmap 失实括号的核查修正),自动化验收全绿,用户实机手测确认通过并指示收尾。GOAL-04 → DONE。
