# 01 · 研究报告：Tahoe Shell 动效/质感/衔接全量审计

日期：2026-07-17
方法：4 个并行只读审计（Dock/Launchpad/Spotlight、控制中心/侧栏/设置、通知/锁屏/切换器、niri 合成器层）+ 主会话逐行深读与交叉复核。**结论以源码为准，行号为 2026-07-17 时点，历史文档不作依据。**
基准词表：`components/Motion.js`（balanced 档 fadeFast 120 / menuEnter 180 / menuExit 160 / panelEnter 320 / panelExit 200 / elementMove 130 / elementResize 180ms；emphasizedDecel=OutCubic / emphasizedAccel=InCubic / standardDecel=OutQuad；springSnappy{4.2,0.30} / springSmooth{3.0,0.40} / springPanel{2.5,0.28} / springBouncy{2.5,0.22}）。生产 `shell.qml:79 useSpring=true`。

---

## 0. 一句话结论

动效**能力**已经具备（Motion.js 有整套 Apple 弹簧词汇，Dock 放大波 / Launchpad 整层开合 / Spotlight / ControlCenter / WindowOverview 飞行 / genie 都打磨到位），问题是**覆盖率与一致性**：token 只接了少数文件，大量组件停在静态或数据驱动的瞬变态。用户点名的四个现象全部能定位到精确根因，且指向下面 6 个系统性模式。

---

## 1. 六个系统性模式（每条在几十个现场重复）

| 编号 | 模式 | 机器可验证的证据 | 影响面 |
| --- | --- | --- | --- |
| **S1** | 列表零增删动画：全 shell 没有一处 `add:`/`remove:`/`displaced:`/`move:` Transition | `grep -rn "add:\s*Transition\|remove:\s*Transition\|displaced:" components/ services/` = **0** | 所有列表 |
| **S2** | 服务层"整数组替换"发布状态，视图 `model:` 直绑 → 任何刷新全量销毁重建 delegate | ClipboardHistory.qml:412、Controls.qml:534-588、Notifications.qml:429/465、SystemFeatures.qml:82、LeftSidebarSystem.qml:129-161、Spotlight flatRows(:204-248)、AppMenu | WiFi/剪贴板/进程/通知/搜索/应用菜单 |
| **S2b** | ScriptModel 多数不配 `objectProp`（配了的地方证明本可增量复用 delegate） | Dock 窗口区有 `objectProp:"modelKey"`(:1393) vs 固定区无(:947) | 同 S2 |
| **S3** | 27 个组件文件**零 Behavior**（全静态） | 见 §5 清单 | 半数弹窗+全部灵动岛子视图 |
| **S4** | 按下态覆盖率约一半：Motion 按压 token 只接 13 文件，25 个含 MouseArea 的文件无反馈 | `grep -L pressScaleFor` 交叉 MouseArea | 全局交互一致性 |
| **S5** | hover 颜色几乎全瞬切 | 全 shell 仅 3 文件用 ColorAnimation | 全局 |
| **S6** | 高度/尺寸直通绑定，内容一变面板瞬跳；弹簧只在 9 文件启用 | 高度 Behavior 仅 4 文件 | 所有可变高弹窗 |

**修复经济学**：102 条表面问题里，S2 家族一次改造覆盖 7 个现场；灵动岛 8px 量化(#22)、补丁 Timer(#29)都是换场架构的衍生物。按"模式/家族"而非"逐条"修，实际工作量远小于条数。

---

## 2. 用户点名的四个问题：精确根因

### ① 剪贴板"没有动画"
- ClipboardPopup.qml **全文零 Behavior/Transition**。开合 `visible:open`(:31) 靠合成器 edge-reveal，但 opacity-from 0.84（淡入弱）、关闭 opacity-duration-ms 0（零淡出，kdl:558-587）。
- 每次打开必 `refresh()`(:50-53)，cliphist 异步返回后 `entries` 整组替换(ClipboardHistory.qml:412) → **开场动画进行中列表全量重建 + 面板高度瞬跳**（高度 `content.implicitHeight+24` 直通，:36,62-63）。
- 两个 ListView(:145,:193) 无增删动画；行 hover 瞬切(:252)；IconButton/TextButton(:356-449) 无按下态。点"刷新"再触发一次全表重建闪烁。

### ② WiFi 点"重新扫描"整卡闪
- `rescanWifi()` = 关掉再开 scanner(Controls.qml:936-950)，NetworkManager 列表先清空再回填。
- `wifiNetworks` 是**计算绑定**(:534-588)，底层每变返回新数组；`WifiPopup.qml:165 model:root.networks` 直绑 → 全 delegate 重建。
- 列表/面板高度无 Behavior(:160) → 扫描瞬间列表清空→显示"未发现网络"占位(:142-154)→卡片塌缩→网络回来再撑开 = **整卡闪**。
- `wifiRefreshTimer` 每 30s 自动 rescan(:952-961)，面板开着也周期性闪。

### ③ niri 菜单"点击选项只闪几下"
- MenuRow.qml:93-137 点击后用 Timer 70ms 半周期硬切高亮 4 拍，**280ms 后才 emit `activated()`**。高亮是二值色切换(:154)。感知=眨几下才反应。
- 闪完后"下文"断裂："窗口"/当前应用行 onActivated 只 closeRequested()（MenuPopup.qml:105-119，点了不做事）；确认卡触发时窗口高度 300→380 瞬跳(:37)、确认卡无进出动画(:182-234)。
- 菜单行按压 0.96 缩放(MenuRow.qml:77)——macOS 菜单无此行为，反而出戏。
- 关闭动画本身 pop-slide 180ms(kdl:592-624)正确，坏在前面垫了 280ms 闪烁，总链路 ~460ms 重心全错。

### ④ 灵动岛动画/衔接差
- **换场空窗**：任何状态切换走 contentSwap(Overlay.qml:444-467)——整层 110ms 全隐→换→170ms 全现，中间**一帧空胶囊**；几何 morph 从 0ms 起步，与内容 110ms 才换错位。
- **几何呆板**：全部固定时长 OutCubic(IslandMotion.js:34-46)，设计禁弹簧禁缩放(Overlay.qml:18-19,586-589)——形变无生命力。
- **材质抖动**：morph 期玻璃 region 按 8px 量化提交(Overlay.qml:170-178,269-272)，边缘阶梯跳。
- 通知 compact↔expanded 两套布局 visible 硬切(NotifView.qml:52,179,191)；滑动关闭不跟手(:360-403)；OSD 0ms 硬切；收起媒体硬切(Content.qml:583)；换场 280ms 输入死区(Overlay.qml:585)；岛→控制中心零形态衔接(shell.qml:155-160)。
- Content.qml 里大量 latch/hold Timer(:100-101,186-194,230-242,301-311) 是"用补丁对抗换场架构"的症状。

---

## 3. 架构事实（合成器层审计交叉核对确认）

**两种开合范式**：
- **范式 A（委托合成器）**：PanelWindow `visible:open` + 一条 KDL layer-rule → 合成器 map/unmap 播 open/close。共 15 个弹窗。**无 QML 兜底，KDL 参数即全部手感**。
- **范式 B（QML 自绘）**：保持 surface 映射、动内部 Item opacity/scale，用 `visible: open || <opacity>>0.01` 守卫，淡出完才 unmap。settings / window-overview / dynamic-island。
- **task-switcher** = 源码注释明确"故意瞬时"（macOS cmd+tab，TaskSwitcher.qml:344）。

结论：**不存在"该动却完全不动"的弹窗**；问题在参数质量（范式 A）与内部内容层（范式 B）。

**关键订正**：设置面板并非"零动画"——它有蒙层 120ms 淡入(SettingsPanel.qml:227-229)+面板 opacity 200ms/scale 0.985→1 160ms(:253-264)，是范式 B。给它补 layer-rule 前**必须先拆 QML 动画**否则双重动画。它唯一确定缺口是合成器投影（是否由内部 GlassPanel 补偿待运行期确认）。

**运行期风险**：layer 关闭动画依赖 unmap 前快照，若 surface 被硬销毁而 pre-commit hook 未截到 buffer 移除，关闭动画**静默跳过**（仅 warn，niri/src/handlers/layer_shell.rs:286-357,382-431）。"偶尔关闭没动画"若复现先查此处。

**合成器 style/通道/曲线**（niri-config/src/animations.rs）：open style = Fade/Popin/PopSlide/Slide/EdgeReveal(:434-443)，close 对称(:445-454)；origin Center/Anchor/Pointer(:456-464)；transform_anim/opacity_anim 未覆写时继承主通道(:846-847)；spring 与 easing 互斥。**edge-reveal 的 `distance` 是死参数**（实现固定用整面尺寸，opening_layer.rs:187）。

---

## 4. 具体问题清单（102 条，连续编号）

严重度：**高**=用户明显可见/高频/主交互路径；**中**=可感知；**低**=细节；**参数**=KDL 值；**性能/说明/风险**=非视觉或需运行期确认。

### 剪贴板弹窗
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|1|高|ClipboardPopup.qml 全文|零 Behavior/Transition，开合/增删/hover/按压全静态|
|2|高|:50-53 + ClipboardHistory.qml:412|开场必 refresh→整数组替换→动画中列表重建+高度跳|
|3|中|:145/:193|两 ListView 无增删动画，删除/固定/复制置顶瞬跳|
|4|中|:36,62-63|面板高度直通内容高，无 Behavior|
|5|低|:252,372,413|行/按钮 hover 瞬切、无按压；刷新再闪全表|
|6|参数|kdl:558-587|开场 opacity 从 0.84、关闭零淡出|

### WiFi 弹窗
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|7|高|Controls.qml:936-950,534-588 + WifiPopup.qml:165|rescan 清空重建→全 delegate 重建+卡片塌缩=整卡闪|
|8|中|Controls.qml:952-961|30s 定时自动 rescan，开着也闪|
|9|中|WifiPopup.qml:160|列表/面板高度无 Behavior|
|10|低|:377-385|密码框展开 visible+高度瞬切|
|11|低|:222 vs :234-236|开关旋钮滑但轨道色瞬变不同步|
|12|低|:248-283|PillButton 无按压、hover 瞬切|

### 顶栏 niri 菜单 / 应用菜单
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|13|高|MenuRow.qml:93-137 + Motion.js:35-36|闪 4 拍、280ms 后才执行动作|
|14|中|MenuPopup.qml:37|点关机/重启窗口高度 300→380 瞬跳|
|15|中|:182-234|确认卡无进出动画|
|16|中|:105-119|"窗口"/当前应用行动作为空，点了只闪不做事|
|17|低|MenuRow.qml:77|菜单行按压 0.96 缩放，出戏|
|18|低|:254-283|ConfirmButton hover 瞬切无按压|
|19|中|AppMenuPopup.qml 全文,:42-47|零 Behavior；每开必 refresh 整列表重建|

### 灵动岛
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|20|高|Overlay.qml:444-467|换场整层全隐→换→全现，空胶囊帧+几何错位|
|21|高|IslandMotion.js:34-46|几何 morph 固定时长，禁弹簧禁缩放，呆板|
|22|高|Overlay.qml:170-178,269-272|morph 期玻璃 region 8px 量化，边缘阶梯跳|
|23|中|Overlay:539-565 + v2OsdEnterMs=0|时钟→OSD 几何 0ms 硬切|
|24|中|NotifView.qml:52,179,191|通知 compact↔expanded 两套布局硬切，眨眼非生长|
|25|中|NotifView.qml:360-403|滑动关闭不跟手，过 20px 直接触发无回弹|
|26|中|Content.qml:583|展开媒体收起内容硬切（注释自认 Hard-cut）|
|27|中|Overlay.qml:585|每次换场 280ms 输入死区|
|28|低|CompactMediaView.qml:96-104,139|封面无淡入、播放/暂停图标瞬切|
|29|低|Content.qml:100-101,186-194,230-242,301-311|大量 latch/hold Timer 补闪烁，架构症状|
|30|低|shell.qml:155-160|岛→控制中心两 surface 零形态衔接|

### 通知 Toast / 通知中心
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|31|高|Toast.qml:172-183,196-200|固定三槽数据流过，栈重排无位移，关顶卡下卡瞬跳上位+瞬变大|
|32|中|Toast:700,731 vs 399-424|退出词汇分裂：手势滑出 vs 点X/超时淡出瞬移|
|33|低|Toast:450-456|swipeAnim 死代码（只 stop 从不 restart）|
|34|参数|kdl:646|关闭 opacity-to 0.35，降到 35% 就突然消失|
|35|中|NotifCenter.qml:315,383 + Notifications.qml:308-331|历史 Repeater+每次重建分组数组，新通知整树重建无入场|
|36|中|NotifCenter:569-572|单条删除瞬灭，"清空全部"却有飞出，两套语言|
|37|低|NotifCenter:45,125-130|面板开合 visible 瞬切（依赖合成器）|

### 锁屏
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|38|高|LockScreen.qml 全文 287 行|零动画：进锁屏无淡入、解锁瞬消（ext-session-lock，只能 QML 做）|
|39|高|:207|认证失败仅边框硬跳红，无 shake 无反馈|
|40|低|:251-252|提交按钮 opacity/hover 硬跳|

### 任务切换器 / 窗口 Overview
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|41|低(有意)|TaskSwitcher.qml:344-346|面板瞬现瞬失（注释故意 cmd+tab 风格）|
|42|低|:206-217|确认释放无 pop 反馈|
|43|低|:93,584-599,447,552|滚动瞬时 vs 高亮弹簧脱节；卡 hover/焦点点硬跳|
|44|中|WindowOverview.qml:699,701|键盘导航 contentY 直写视口瞬跳|
|45|中|:963-969|选中卡底色/边框/宽度硬切|
|46|低|Flow 布局|窗口增减重排无位移，只有透明度|

### 控制中心
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|47|中|ControlCenter.qml:1381,1402,1417|滑块填充/旋钮直绑，按媒体/亮度键瞬跳到新值|
|48|中|:832-847|WiFi/蓝牙列表无增删动画，周期 rescan 跳动|
|49|低|:994-1001|PSK 密码框瞬弹|
|50|低|:906|列表行 hover 瞬变|

### 设置面板
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|51|中低|SettingsPanel.qml:322-337|换页正文淡入滑动但标题瞬间换字，不同步|
|52|低|:310-316,340-345|返回/刷新按钮随页瞬显瞬隐|
|53|性能|:445-889|约 35 页全量实例化无懒加载，首帧潜在卡顿|
|54|待确认|kdl 无 tahoe-settings 规则|无合成器投影（是否内部 GlassPanel 补偿待确认）|

### 左侧栏（系统/外壳/天气/背景）
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|55|高|LeftSidebarSystem.qml:721,129-161|进程列表每 1-2s 整表重建：排序跳动、hover 丢失、闪烁|
|56|高|:323-368,906-943|CPU/内存/GPU 活动环无插值，弧长每 tick 硬跳|
|57|中高|:599,645,700|"展开全部进程"卡片直接蹦高无 morph（ccMorph token 未用）|
|58|低|:508,559|磁盘条/电池条宽度从 0 跳|
|59|低|:729,1001-1003,1029|进程行/过滤标签/排序头 hover 与激活色瞬变|
|60|中低|LeftSidebar.qml:231-262,284|切标签滑块平滑但子页内容硬切；标签文字色瞬变|
|61|中|LeftSidebarWeather.qml:1031,1026|刷新按钮不旋转；按钮无 hover/按压|
|62|低|:1212-1214|每日温度条刷新时 x/width 跳|
|63|低|:471-475,325-332|空态↔内容硬切；错误横幅瞬显致布局跳|
|64|低|WeatherBackground.qml:1027-1029,867-869|天气/日夜切换整场景重置、天空渐变硬换色|
|65|低|MeteoIcon.qml|天气图标硬切无 crossfade|

### 电池 / 风扇 / 托盘
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|66|中|BatteryPopup.qml:120,123|电量条宽度/颜色（绿↔红）无 Behavior 瞬变|
|67|低|:289,292|性能配置按钮无 hover 过渡、无按压|
|68|中|FanPopup.qml:280,358|开关轨道色瞬跳；预设填充瞬跳|
|69|低|:412,452|预设/图标按钮无 hover、无按压|
|70|低|Tray.qml:132-136|图标增减无进出场直接 pop|
|71|低|:153,38|hover fill 瞬变；跨 0 图标瞬显隐|

### Dock
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|72|高|Dock.qml:833|玻璃 shelf 宽度直绑内容宽，开关窗口/pin 时整块 dock 瞬跳|
|73|高|:947-949 vs :1393-1396|固定区 Repeater 无 objectProp，pin/unpin/重排全量重建丢放大态|
|74|bug|DockMinimizedWindow.qml:101-104,248-259|死 bounce：16ms Timer 归零 vs 170ms Behavior，还原弹跳仅走 9% 不可见|
|75|低|Dock.qml:1253-1260 + WindowButton.qml:321-358|点击 bounce 上行瞬跳 14px 再弹回，像下坠，与启动循环两套物理|
|76|中|:134|全屏时 visible 瞬切 dock 硬消失（无 layer rule）|
|77|低|:1540-1541|悬停名牌图标间瞬移|
|78|低|WindowButton.qml:56,144-145|窗口按钮槽位 x/width 无 Behavior，邻居瞬移|
|79|低|WindowButton.qml:238-243|运行指示点宽度/颜色瞬变|
|80|低|DockMinimizedWindow.qml:123-124|缩略图 hover 边框瞬变|
|81|中|DockMinimizedShelf.qml:27,42,48|最小化缩略图凭空 pop 进出，与 genie 反差大|
|82|中|DockAppMenu.qml:36 / DockWindowMenu.qml:44|右键菜单零 QML 动画；popupOriginX 未接 transformOrigin|

### Launchpad / Spotlight
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|83|中|Launchpad.qml:361-373|每敲一字重放整场 320ms 网格入场+瞬跳回第1页，网格脉冲|
|84|低|Launchpad 筛选路径|筛选结果无逐项过渡|
|85|性能|Launchpad.qml:770|appIcon asynchronous:false，应用多时首帧卡顿|
|86|高|Spotlight.qml:506-509,204-248|结果 ScriptModel 无 objectProp、flatRows 每次全新对象，打字整片闪烁重排|
|87|中|:58 vs 341,356-361|开关不对称：打开 QML 生长，关闭 visible 瞬切|
|88|低|:554-560|结果行 hover 无过渡；结果列无 move 过渡|
|89|参数|kdl:511|popout scale-to 0.992≈纯淡出，与 popin 0.96 不对称|

### 顶栏本体 / 壁纸
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|90|中|TopBar.qml:145|进出全屏顶栏 visible 瞬切硬消失（无 layer rule）|
|91|低|:481,539|通知/剪贴板角标瞬现瞬失|
|92|低|:296,341,459,518,576,613,695,734,769,803|所有按钮 hover 底色瞬切|
|93|低|:650|电池填充宽度无 Behavior|
|94|中|Wallpaper.qml:435,438-439|zoom/dim 只绑 launchpadOpen 且只作用静态层，动态壁纸无反应|

### 合成器 / KDL 参数级 / 全局
| # | 级 | 位置 | 问题 |
|---|---|---|---|
|95|参数|kdl:576-585|状态弹窗组关闭动画全组零淡出|
|96|参数|kdl:563 vs 658|tray-menu 动画归状态弹窗组、几何归菜单组，不一致（有意但需知晓）|
|97|说明|kdl 各 edge-reveal + opening_layer.rs:187|distance 死参数，配置误导|
|98|风险|layer_shell.rs:286-357,382-431|snapshot 缺失关闭动画静默跳过|
|99|说明|GlassPanel.qml:37-46|玻璃 interaction/alpha 0.02 量化（防 60Hz commit 权衡）|
|100|中(主观)|kdl:268-278|窗口开合 220/180ms scale 0.97 偏工具味，与 macOS zoom 有差距|
|101|低|TahoeSymbol.qml:66-69|全局 Material Icons Round 字体，质感基因问题|
|102|低|TahoeSymbol.qml:66|每图标各自 FontLoader（浪费）|

---

## 5. 27 个零 Behavior 文件（S3 清单）

AppMenuPopup、BatteryPopup、ClipboardPopup、DockAppMenu、DockMinimizedShelf、DockWindowMenu、DynamicIslandBluetoothView、DynamicIslandCompactMediaView、DynamicIslandNotificationView、DynamicIslandOsdView、DynamicIslandRestingClockView、DynamicIslandTimerView、DynamicIslandWorkspaceView、GlassPanel、LeftSidebarWeather、LockScreen、MenuPopup、MenuSeparator、MeteoIcon、PopupDismissLayer、ProcessMenu、Screenshot、ShellNavigation、ShellPopupState、TahoeSymbol、TrayMenu、WindowPreviewFallback。

（其中 GlassPanel/PopupDismissLayer/ShellNavigation/ShellPopupState/Screenshot/TahoeSymbol/MenuSeparator 是基建或无 UI，属正常。）

---

## 6. 统计

- **6 个系统性模式 + 102 条具体问题**。
- 高严重度 16 条：#1,2,7,13,20,21,22,31,38,39,55,56,72,73,86 + 确定性 bug #74。
- 中 ~30 条，低/参数/性能/说明 ~56 条。
- **有意设计（列出供知晓，不修）**：#41 任务切换器瞬时、OSD 进度条不加 Behavior（跟手 1:1 正确）、菜单 hover 瞬时高亮（macOS 地道）。
- **待运行期确认**：#54 设置投影、#98 关闭动画跳过、#100 窗口开合主观项。
- **同根家族**：#2/7/19/35/48/55/86 = S2 一个病根七个现场；#22/#29 = 灵动岛换场架构衍生。

---

## 7. 对照组（证明是覆盖率问题不是能力问题）

做得对的样板：Spotlight 高度 250ms 缓动 + 选中高亮弹簧 + 结果淡入(Spotlight.qml:341-495)；ControlCenter morph 280ms + tile 按压缩放 + 色过渡；Toast 新卡右滑弹入(NotifToast.qml:288-352)；Dock 放大波余弦钟形 SmoothedAnimation(Dock.qml:1225-1240) + 启动弹跳抛物线循环(:1322-1341)；WindowOverview 从真实窗口位飞行(springPanel/springSmooth)；genie 神灯（合成器 shader）；LeftSidebarSystem 网络图表插值滚入(:60-73)。

**这些证明词汇与基建都在，缺的是把它接到剩下的现场。**
