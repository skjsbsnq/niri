# 2026-08-02 弹层点击/壁纸启动回归 — 修复报告与约束文件

状态:**已修复、已部署、用户实测确认**。
主仓库提交:`ca1c753` → `e0fe12d` → `ca43986` → `f1ba09a` → `e3f7994` → `a1329d2`;
niri 子模块:`d3a3563f` → `0cf398c4`(分支 tahoe-layer-animations)。

本文档兼作**约束文件**:第 5 节的不变量是后续改动的硬性边界,多数已由契约测试
钉死,修改相关代码前必读。

---

## 1. 症状(用户报告原文摘要)

| # | 症状 | 最终判定 |
|---|---|---|
| S1 | 顶栏弹层(剪贴板/控制中心/电池/风扇)打开后,点桌面/窗口不收回,窗口也无法被点击聚焦 | shell:dismissFor 作用域错绑 |
| S2 | 刚呼出的面板首次点击必然无效(点内容/点外皆是),第二次才生效 | 合成器:on-demand 焦点切换时机 ×(次因)零移动 stale focus |
| S3 | 每次进系统动态壁纸闪灰/棕一下,再闪一下"静态壁纸" | shell:T-31 异步化破坏 boot adopt |
| S4 | 点过的顶栏按钮出现蓝色焦点圈,收回后不消失 | shell:键盘模型被指针点击置位且无失焦清除 |

## 2. 根因链(这些问题是怎么导致的)

### S1 — dismissFor 作用域错绑(引入:`1d5a90c`,T-29)

T-29 给收回层加 wheel/right-click 策略时,把共享的 `dismissFor()` 判定函数定义在
**MouseArea** 作用域上,调用却写成 `root.dismissFor(mouse)`(`root` 是 PanelWindow)。
`root.dismissFor === undefined`,**每次点击都抛 TypeError,handler 中止,
`closeRequested()` 一次也没执行过**。收回层持有全屏 input region(减弹层挖洞),
于是外部点击被无声吞掉:面板收不回、下方窗口点不到。

两个放大器让它存活到用户报告:
1. 守护测试 `test_popup_dismiss_layer_policy.py` 只断言了调用形态字符串
   `"if (root.dismissFor(mouse))"` —— **把坏形态原样钉成了规范**,假通过。
2. 运行中 quickshell 的 stderr 指向 `/dev/null`,QML 运行时 TypeError 全部不可见。

### S2 — 首击吞噬(引入:T-29 `focusable: true`;机制横跨 niri/QtWayland/QtQuick 三层)

T-29 为键盘可达性(F-10)把 TopBar 设为 click-focusable(wlr-layer OnDemand)。
由此形成的事件序列:

1. 点顶栏按钮 → niri 给 bar wl 键盘焦点;面板(`focusable: false`)打开,bar 保持焦点。
2. **首次**点击 bar 以外(面板内容/收回层)→ niri 在 **press 时刻**清除 on-demand
   焦点 → `wl_keyboard.leave` 恰好夹在 press 与 release 之间到达 quickshell。
3. QtWayland 把"键盘焦点丢失"映射为 `ApplicationInactive`(Wayland QPA 无独立
   激活态)→ QtQuick 对**该应用全部窗口**取消按住中的 MouseArea 独占 grab。
4. release 到达时无 grabber,`onClicked` 永不触发 —— 点击蒸发。第二次点击时焦点
   已掉、无状态迁移,正常。

指针投递协议级正确(见 §3),吞噬完全发生在客户端内部——这也是它躲过合成器侧
排查的原因。次因:smithay ClickGrab 释放不恢复指针焦点 + niri 早退只看自身缓存,
零移动连击(触摸板 tap)投给过期 surface(独立缺陷,`d3a3563f` 已修)。

### S3 — 壁纸启动闪烁 + 双引擎泄漏(引入:`17981f3`,T-31)

T-31 把 prestart record 读取从同步改为异步两跳链(record JSON → /proc stat),但
`Component.onCompleted` 里的 sync 仍按同步假设立即执行:record 未解析 → adopt 失败
→ 冷启动兜底拉起**重复引擎**(实测两个 linux-wallpaperengine 常驻)+ `#1c1d20`
盖板;异步完成回调只在两种旧条件下 resync,**首启动 adopt 永远不执行**,盖板只能等
4.5s 定时器硬切(那一下"静态壁纸闪"是盖板里的冻结截图帧)。
语法错误修复 `6779c44` 让 T-31 代码第一次真正跑起来,所以回归"看起来"发生在它之后。

### S4 — 蓝圈滞留(引入:`1d5a90c`,T-29)

每个按钮 `onClicked` 都调 `engageKeyboardEntry`(设计意图:Tab 从指针处继续),
而圈的可见性绑定无条件显示 `keyboardCurrent`,清除点只有两个且均不覆盖
"bar 失焦/弹层收回" —— 指针点击召唤出一个永不消失的键盘焦点圈。

## 3. 发现与修复过程(方法论记录)

1. **并行研究**:三个独立子代理分头(shell 收回层 / niri 输入焦点 / 壁纸启动),
   同时主线做部署侦察 —— 当场抓到两个铁证:**双壁纸引擎进程**(PID 父子关系证明
   adopt 失败后 shell 自行二次 spawn)和**运行中的 niri 是脏树 WIP 二进制**
   (`5a8bf3d8-modified`,提交后从未重建)。
2. **S1 实证**:最小 QML 用例复现同构作用域调用 → TypeError 确认;部署副本逐字节
   比对确认线上正带病运行。
3. **S2 两轮逼近**:第一轮修掉零移动 stale-focus(真缺陷但非主因);用户复测仍吞
   (且给出蓝圈新线索)→ 第二轮专项代理用**嵌套会话 + WAYLAND_DEBUG +
   qt.pointer.grab 日志**确定性复现,拿到决定性证据链:press/release 投递正确、
   leave 夹在中间、Qt 层 grab 被取消 —— 根因定位到客户端激活态语义。
4. **对抗审查闭环**(每个修复至少两轮独立攻击):壁纸修复四轮审查揪出并修掉
   3 个衍生硬缺陷(尸体 record 收养/rm 回声重启/SIGTERM 退场竞态);S2 修复
   **第一版(全推迟到 release)被审查否决**——会秒杀窗口右键菜单(press-hold 期间
   残留持有者杀 xdg popup grab)且 release 位置切焦点是语义倒退——重写为非对称
   拆分后复审通过(零 CONFIRMED)。
5. **部署陷阱**:首轮部署 `cp` 覆盖运行中二进制报 ETXTBSY 静默失败,shell 生效而
   合成器修复没上车,险些误判"修复无效"。

## 4. 修复清单

| 提交 | 内容 |
|---|---|
| `ca1c753` | 壁纸:in-flight 门 + 完成必 resync + FileNotFound 确死分流 + sync 尾幂等化 + 健康让位 |
| `e3f7994` | 壁纸:boot-once `waitForJob` 同步解析,残余 1-3 帧盖板闪归零 |
| `e0fe12d` | 收回层:dismissFor 上移 root 作用域 + 定义作用域锁 + node 运行时探针 |
| `ca43986` | T-29 横扫产物:测试缺 `import shutil` ×2 + Tray 键盘函数作用域锁 |
| niri `d3a3563f` | 零移动 stale-focus heal(早退加真实焦点比对,grab 期让位) |
| niri `0cf398c4` | **首击根治**:on-demand 焦点切换非对称拆分(见约束 C7) |
| `a1329d2` | 蓝圈:keyboard-only 显示门 + `Window.active` 失活全清;bump niri |

## 5. 约束(不变量)清单 — 后续改动的硬边界

每条标注执法方式。**改动涉及对应文件时,违反前必须先改这里并说明理由。**

- **C1|收回链路完整性**:PopupDismissLayer 的 onClicked 必须能实际到达
  `closeRequested()`;`dismissFor` 定义必须在其调用限定符指向的作用域上。
  执法:`test_popup_dismiss_layer_policy.py`(定义先于 MouseArea 的作用域锁 +
  node 执行体探针,已双向验证对旧 bug 变红)。
- **C2|QML 结构测试必须锁定义作用域**:凡断言 `<id>.<fn>(...)` 调用形态的测试,
  必须同时断言 `<fn>` 定义在 `<id>` 指向的作用域(参照 C1 与 Tray 键盘函数锁)。
  执法:代码审查惯例(教训:调用形态断言曾把 bug 钉成规范)。
- **C3|异步化双门不变量**:把同步读改异步时,①所有依赖该状态的决策点必须加
  "未解析早退门",②完成回调必须重新驱动被门挡掉的决策。只做其一必炸。
  执法:`test_wallpaper_idle_budget.py::test_boot_record_resolution_gates_cold_start_and_resyncs`。
- **C4|/proc 探活语义**:`FileViewError.FileNotFound`(ENOENT)= 进程确死,必须
  判死;仅其余瞬态 IO 错误保持"假定存活"。执法:同文件 FileNotFound 分流 ×2 计数断言。
- **C5|壁纸 sync 幂等契约**:运行尾只在 spawn 命令真实变化时重启引擎;每个非
  cycle 停止写点必须清 spawnedCommand(quickshell `Process.running` 在 SIGTERM
  退场期仍读 true)。执法:spawn 捕获 ×4 + 停止清除计数断言。
- **C6|waitForJob 仅限 boot-once**:`Component.onCompleted` 之外禁止 waitForJob
  (R-5:周期路径必须异步)。执法:onCompleted 块外 waitForJob=0 断言。
- **C7|on-demand 焦点切换时机(niri)**:press 目标为 on-demand layer → 立即设;
  目标无 layer(窗口/桌面)→ 立即清(否则残留持有者秒杀 press-open 的 xdg popup
  grab);目标为**非 on-demand layer(与持有者同客户端)→ 延迟到 release 清**,
  且 release 位置永不参与焦点决策。背景:wl 键盘焦点=Qt 应用激活态,失焦会取消
  该应用按住中的全部 pointer grab。执法:`src/input/mod.rs` 注释 + 本文档
  (合成器无 headless 输入测试设施,列为人工审查约束;改动此块必须重跑嵌套
  WAYLAND_DEBUG 复现脚本验证)。
- **C8|键盘圈 keyboard-only**:焦点圈只在键盘导航后显示;指针点击只重定位不显圈;
  bar 失活(`Window.active`)全清。执法:
  `test_topbar_keyboard_focus_model.py::test_focus_ring_is_keyboard_only`(计数
  相等门)+ `test_focus_ring_clears_when_bar_loses_keyboard_focus`。
- **C9|部署纪律**:①提交后必须重建再部署(禁 `-modified` 二进制上线,部署前
  `niri --version` 核验);②替换运行中二进制必须 `cp 到临时名 && mv -f`(ETXTBSY);
  ③shell QML 改动 cp 后需重启 quickshell/会话。执法:人工;违例后果本次已演示。
- **C10|子代理 live 会话纪律**:研究代理在真实会话上做实验,进程操作必须限定
  精确 PID,禁止 `pkill -f` 宽匹配(本次事故:误杀 live quickshell,桌面缺席 80 分钟)。
- **C11|工具链**:qmllint 必须用 `/usr/lib/qt6/bin/qmllint --bare`(PATH 里是
  Qt5.15,对 `pragma ComponentBehavior` 静默失败)。
- **C12|可观测性(待办)**:start-quickshell.sh 应把 qs stderr 接入日志文件/journal
  —— stderr→/dev/null 是 S1 的 TypeError 长期不可见的直接原因。

## 6. 遗留观察项(未修,低优先)

- touch(`input/mod.rs:4425`)/tablet(`:3855`)仍 down 时切焦点,触摸屏用户存在
  同类首击吞(镜像需 per-slot 位置缓存,单独立项)。
- warp/`set_location` 后 `pointer_pos` 缓存不回写(影响 warp 后立即 pick);
  `16696344` 的 cursor_position_hint hunk 属过度修复(该回调不持锁)。
- supervisor 被单独 SIGKILL 而引擎孤儿存活 → FileNotFound 判死删 record 后冷启动
  会叠第二实例(可达性极低,审查权衡接受;根治=按 token/cmdline 扫孤儿)。
- `prestartedWallpaperReadyTimer` 死代码;record generation 守护恒假(722 行)。
- 预存失败:`test_r17_dock_layout_motion.py:259`(quickshell tahoe_glass
  `mappingGeneration`,与本批无关)。
- 四条理论级 PLAUSIBLE(Exclusive 层 defer 差异/VT-switch 残留标志/chord 拖移/
  press 驱动换代误清)详见审查记录,现实触发≈0。
