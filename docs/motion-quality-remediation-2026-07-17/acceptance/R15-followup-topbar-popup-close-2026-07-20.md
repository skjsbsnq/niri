# R15 follow-up · 顶栏弹窗退出统一 · 2026-07-20

## 结论

用户确认 Control Center 与 Notification Center 的进入/退出观感正确；Battery、WiFi、Fan、Clipboard 的退出与它们不一致。直接原因不是 QML 生命周期，而是 compositor close opacity 分叉：前两者在完整 top edge-reveal 期间保持不透明，小弹窗则在前 120ms 淡到透明，卡片尚未收回顶边就先消失。

确定的重新引入提交是 `48729afe322299852dccd157b296fef6810350b1`（2026-07-19，`R15: tune compositor motion parameters`）。它把 `small_popup` 从 `opacity-to 1.0 / opacity-duration-ms 0` 改为 `opacity-to 0 / 120ms`，并同步修改 profile writer 与测试。此前 `51607321eca64fe0883c7c4d156c4dafdd5a907a` 已明确让这些弹窗与 Control Center 使用同一种完整顶边收回。

R15 之后没有提交再次改动这组动画；回归从 R15 一直保留到本次修复。

## 为什么反复出现

1. 同一种顶边关闭语义原先在 `control_center`、`notification_center`、`small_popup` 三组 profile 字典中分别硬编码，改一组不会影响另外两组。
2. 直接 KDL 与 `niri_settings_tool.py` 同时保存参数，切换 motion profile 会重新写回 KDL；只修其中一处会再次复发。
3. R15 测试只锁定 `small_popup` 自身的 fade 参数，没有断言它必须与 Control Center / Notification Center 相等，因而把错误分叉固化为“remediation”。
4. 动画 rule ownership 过去靠 namespace tuple 推断，没有显式的受管 rule 身份；历史上多次在规则分组与配置生成之间来回调整，审查难以区分材质重叠与动画 owner。

## 实施

- 默认 balanced KDL：Battery/WiFi/Fan/Clipboard/Tray-menu close 改回 `edge-reveal + edge top + opacity-to 1.0 + opacity-duration-ms 0`，与 Control Center / Notification Center 一致；open 参数保持 `opacity-from 0.68` 与原 spring，不改进入动画。
- `TOP_EDGE_PANEL_CLOSE_PHASES` 成为四 profile 的唯一关闭策略源；`control_center`、`notification_center`、`small_popup` 均通过 `top_edge_panel_close_phase()` 取独立副本，不共享可变 dict，也没有第二个 writer。
- fast / balanced / liquid 使用完整、不透明的 top edge-reveal；reduced 改用 60ms `fade`。原因：`edge-reveal + transform-duration-ms 0` 会在首帧把 snapshot 整体移出 crop，使 opacity fade 实际不可见。
- 七个受管动画 rule 增加既有 `tahoe-managed` 词汇下的 `layer-animation <group>` marker。writer 只按 marker 编辑受管 rule，并校验：marker 全集、未知/缺失/重复/悬空、精确 namespace 集、canonical `match namespace="^literal$"`、无 exclude、额外 exact animation owner。
- 无 marker 的用户自定义 Rust regex rule 保持用户所有；Python writer 不重新解释 Rust regex，避免建立第二套 regex 语义。
- 直接 KDL 测试锁定三组 opaque close；profile 测试使用独立四档 oracle，真实执行写入、检测、回 balanced 字节级往返；对 wildcard、alternation、未锚定、`.` 元字符、match 属性、exclude、marker 异常、namespace 重排和 exact overlap 均有对抗测试。

## 范围说明

本次没有修改任何 popup QML 生命周期、服务接口、GlassPanel region、motion token 或 niri compositor 源码。Tray-menu 仍在 `small_popup` 的 top edge-reveal 动画组中，不迁入 pointer pop-slide。

同时修正两条远端基线已经陈旧的测试断言，不改产品代码：

- `WindowButton.restoreOrActivate()` 自 `7014e1c` 起在 restore 前调用 `updateDockRectangle(true)`；测试同步该强制发布参数。
- TopBar 自 `00014d6e` 起为避免 fullscreen remap 后遮住 Dynamic Island 而立即 unmap；Dock 仍保留淡出后 unmap。R17 测试改为分别固定两种既有生命周期。

## 独立审查

实施后进行了多轮全新子代理对抗审查。审查先后发现并修复：

1. KDL owner 测试只检查 Python registry、未检查实际 rule。
2. profile 时长缺少独立 oracle。
3. reduced 的 0ms edge-reveal 会让 fade 不可见。
4. 字面 namespace 交集无法处理 wildcard/alternation/属性/exclude，且 Python `re` 与 niri Rust regex 语义不同。
5. 初版全局 exact-only 限制会误伤无关用户自定义 regex rule。
6. `.` 被误当字面字符、无 namespace match/exclude 可绕过 managed contract。
7. 未知、悬空、重复和叠放 marker 未全局 fail-closed。
8. 两项测试最初替换到更早的材质 rule 而非标记动画 rule，形成假阳性；现改为从 marker 后精确定位。
9. 早期遗留的未使用 marker 反向解析函数与正式 registry 平行表达 ownership；终审后删除，仅保留 registry 单一路径。

最终三路独立终审均为 **FINAL CLEAN**；其中一次外部代理 502 失败已由全新代理替代，不计作审查结论。

## 自动验收

- 全量：`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tahoe-shell/tests/` → **838 passed, 267 subtests passed in 47.74s**。
- 最终定向：`test_niri_settings_tool.py` + `EdgeRevealSemanticsTests` → **34 passed, 51 subtests passed**。
- fast / balanced / liquid / reduced 四份 writer 生成 KDL 均通过 `/home/wwt/.local/bin/niri validate`。
- 当前 source 与 deployed KDL 均通过 `niri validate`。
- `bash scripts/check-tahoe-glass-guardrails.sh` → **passed**。
- `git diff --check` → 通过。

## 部署与运行态

- Tahoe shell deploy + verify：parity OK，manifest `3074a16f2d4524b01937b870ec6affb15fe08f3b1d77012da69cc22acc7bad7c`。
- KDL source / deployed config / deployed baseline SHA-256 均为 `6a1b38ceca24e0cf64af37878d288c6b1b3d21666b37a9f981d544cf9578bf73`。
- settings writer source / deployed SHA-256 均为 `2422fa6064618f1be3ad4b902731c3099b0ef191e9809391888c6e240c6798ab`。
- 部署来自尚未提交的工作树；deploy state 中的 root commit `6a5d0b5` 仅表示部署基底，实际内容由 manifest 与文件哈希证明。
- Quickshell 部署后自动 reload，日志出现 `Configuration Loaded`。既有 portal、StatusNotifier、Controls FileView 与 `activePlayer` warning 不属于本任务。
- 在行为参数部署后，Control Center、Notification Center、Battery、WiFi、Fan、Clipboard 各执行 3 次 180ms 中途关闭循环；IPC 全部成功，相关日志无 TypeError / ReferenceError / popup binding loop / snapshot / animation warning，关闭后无目标 layer 残留。

## 残余人工项

自动测试可证明配置语义、writer 往返、ownership 与渲染分支，不能替代主观观感。仍建议在真实桌面逐一肉眼观察 Control Center、Notification Center、Battery、WiFi、Fan、Clipboard、Tray-menu 的正常关闭、打开中途关闭、快速重开，以及 reduced 60ms fade；重点覆盖 fractional scale 与多输出。该项不影响本次代码与配置门禁结论。
