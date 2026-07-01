# Tahoe Settings GNOME Redesign Research

日期：2026-07-01

状态：研究文档。本文不改代码，不代表已经实现。

## 研究输入

- 本地设置页：
  - `tahoe-shell/components/SettingsPanel.qml`
  - `tahoe-shell/components/settings/SettingsSidebar.qml`
  - `tahoe-shell/components/settings/pages/*.qml`
  - `tahoe-shell/services/Controls.qml`
  - `tahoe-shell/services/DesktopSettings.qml`
  - `tahoe-shell/services/NiriSettings.qml`
  - `quickshell/src/network/*`
  - `quickshell/src/bluetooth/*`
- GNOME Settings 上游源码：
  - 仓库：<https://gitlab.gnome.org/GNOME/gnome-control-center>
  - 本轮拉取 commit：`c9de56d`，日期 `2026-06-30`
  - `meson.build` 项目版本：`51.alpha`
  - 重点文件：
    - `shell/cc-window.blp`
    - `shell/cc-panel-list.c`
    - `shell/cc-panel-loader.c`
    - `panels/network/cc-wifi-panel.blp`
    - `panels/network/cc-network-panel.blp`
    - `panels/network/net-vpn.c`
    - `panels/bluetooth/cc-bluetooth-panel.blp`
    - `panels/applications/cc-applications-panel.blp`
    - `panels/applications/cc-default-apps-page.c`

## GNOME Settings 的结构事实

GNOME Settings 不是一个大页面，而是一个 shell 加多个 panel：

- `CcWindow` 使用 `Adw.NavigationSplitView`，默认窗口 `980x640`，窄于 `550sp` 时折叠侧栏。
- 左侧有 `SearchBar` 和 `CcPanelList`，搜索按 panel 名称、描述、关键词匹配。
- panel 列表不是随手写在 UI 里，而是 `cc-panel-loader.c` 的 `default_panels[]` 加每个 panel 的 `.desktop` 元数据。
- 侧栏顺序是人工固定的，不是字母序。主顺序为：
  - `wifi`
  - `network`
  - `wwan`
  - `mobile-broadband`
  - `bluetooth`
  - 分隔线
  - `display`
  - `sound`
  - `power`
  - `multitasking`
  - `background`
  - 分隔线
  - `applications`
  - `notifications`
  - `search`
  - `online-accounts`
  - `sharing`
  - `wellbeing`
  - 分隔线
  - `mouse`
  - `keyboard`
  - `color`
  - `printers`
  - `wacom`
  - 分隔线
  - `universal-access`
  - `privacy`
  - `system`
- `wifi` 和 `network` 是两个独立 panel。`wifi` 专注无线网络、飞行模式、热点、可见网络；`network` 承载有线、VPN、Proxy 和蓝牙网络设备。
- GNOME 的网络页对硬件和服务缺失有明确状态页，例如 NetworkManager 未运行、Wi-Fi 关闭、无 Wi-Fi 适配器、飞行模式开启。
- VPN 是 `network` panel 的一个 group。已有 VPN 以 row 展示，row 上有开关和齿轮按钮。开关调用 NetworkManager 激活/停用连接，齿轮打开连接编辑器。
- Bluetooth panel 顶部是总开关，主体是状态栈：无设备、已关闭、飞行模式、硬件飞行模式、设备页。
- Apps panel 是独立 panel，不只是应用列表。GNOME 在这里放：
  - 默认应用：链接、文件、媒体等打开方式。
  - 应用详情：打开应用、查看详情、存储用量。
  - 应用权限：搜索、通知、后台运行、截图、壁纸、声音、快捷键抑制、相机、麦克风、位置等。
  - 非 sandbox 应用会显示限制提示：这类权限不能被完全强制执行。

结论：如果要“对标 GNOME 设置中心”，首要目标不是换皮，而是采用同类信息架构：稳定侧栏顺序、内置搜索、按系统域拆 panel、每个 panel 自己处理 unavailable/disabled/empty 状态。

## 当前 Tahoe 设置页现状

当前结构更像“偏好面板”，不是系统设置中心：

- `SettingsPanel.qml` 是一个 overlay `PanelWindow`，居中 `900x540`，整体尺寸和行为更接近 macOS/Tahoe 弹窗。
- 页面标题、副标题和索引由 `pageTitle()`、`pageSubtitle()`、`pageIndex()` 多段 `if` 硬编码。
- 内容用单个 `StackLayout` 一次声明所有页面。新增页面需要同时改标题函数、索引函数、StackLayout、侧栏和搜索入口。
- 侧栏目前只有 Tahoe 自己的偏好：概览、外观、壁纸、布局与窗口、通知与输入、灵动岛、截图、Dock、天气、启动项、系统健康、关于。
- `SettingsPanel` 没有接入 `controlsService`，所以设置页无法直接使用现有 Wi-Fi/蓝牙状态。
- `Search.qml` 已经有外部系统设置入口，如 `gnome-control-center network`、`blueman-manager`、`nm-connection-editor`，但这只是跳外部程序，不是 Tahoe 设置页本身。

## 视觉问题与新方向

截图 `Screenshot from 2026-07-01 12-08-36.png` 暴露的主要问题：

- 侧栏顶部的 `Tahoe / Desktop` 品牌块太重，不符合系统设置中心的语义。设置中心应该服务系统域导航，不应该把 shell 品牌作为第一视觉中心。
- `About` 页的 `niri Tahoe Desktop` hero 卡片像产品宣传页，不像系统信息页。系统信息应该是紧凑的键值信息、状态、版本与复制/打开路径操作。
- 彩色渐变圆角方块图标来自 `TahoeCategoryIcon.qml` 和 `SettingsTheme.categoryColor()`，视觉语言接近 macOS/iOS，不接近 GNOME/libadwaita。它们在侧栏里形成过多色块，显得廉价且分散注意力。
- 当前面板、sidebar、section、row 普遍使用 14-18px 大圆角和半透明卡片堆叠，页面读起来像一堆浮动胶囊，不像 GNOME Settings 的安静列表。
- 内容区横向 row 太高、卡片间距太大、很多信息被塞进大块浅灰容器，密度低但噪声高。
- `概览` 页和一堆 Tahoe 功能入口会进一步强化“壳设置/主题设置”的感觉，而不是系统设置中心。

新的视觉原则：

- 对标 GNOME/libadwaita 的克制方向，而不是 macOS System Settings。
- 侧栏使用单色 symbolic icons，默认灰色，选中项只用低调背景或 accent，不使用彩色方块图标。
- 移除侧栏顶部 `Tahoe Desktop` 品牌块。标题应是 `Settings` 或本地化 `设置`，品牌信息放到 `System > About` 的普通 row。
- 默认页不做 `Overview`。启动页应是 `Wi-Fi` 或上次打开页。
- 内容页使用 `PreferencesPage / PreferencesGroup / ActionRow / SwitchRow` 类结构：标题、说明、右侧控件，避免 hero 卡片和 summary tiles。
- 卡片圆角收敛到 8px 左右；sidebar active row、列表 row、按钮都要更扁平、更系统化。
- About/Health 这类页面删除大 hero strip，只保留紧凑 rows、状态 badge、复制/刷新操作。
- 颜色以中性灰、文本层级和少量 accent 为主。只有危险/警告/成功状态使用红/黄/绿，不给每个分类分配品牌色。
- Tahoe/niri 专有内容只作为高级设置或 System/About 信息出现，不作为侧栏主视觉。

已有可复用后端能力：

- `Controls.qml` 已经有 Wi-Fi：
  - 读 `Networking.wifiEnabled`
  - 找 Wi-Fi device
  - 列出网络，按已连接、已保存、信号排序
  - connect/disconnect/rescan
  - PSK 连接
  - nmcli fallback
  - 记住 preferred SSID 并恢复连接
- `Controls.qml` 已经有蓝牙基础状态：
  - `Bluetooth.defaultAdapter`
  - `bluetoothAvailable`
  - `bluetoothEnabled`
  - `bluetoothConnectedCount`
  - toggle adapter power
- `quickshell/src/bluetooth` 暴露了比 `Controls.qml` 当前使用更多的能力：
  - adapter discovering/discoverable/pairable
  - device connect/disconnect/pair/cancelPair/forget
  - trusted/blocked/wakeAllowed
  - device battery
- `quickshell/src/network` 暴露 NetworkManager 后端：
  - `Networking.devices`
  - Wi-Fi device/network
  - wired device/network
  - NetworkManager settings profile
  - connect/disconnect/forget
- `Apps.qml` 已经有基础应用索引：
  - 从 `DesktopEntries.applications` 构建 launchpad 应用列表
  - 应用图标解析
  - Dock 固定应用状态
  - 应用启动和搜索路径
  - 但没有默认应用、MIME association、portal permission store 或 Flatpak metadata 读写
- `NiriSettings.qml` 已经能写一部分 niri KDL 配置：
  - layout gaps
  - focus ring/border/shadow
  - snap assist
  - glass/blur
  - keyboard repeat/touchpad
  - animations
  - binds 只读

缺口：

- 设置页没有 Wi-Fi 页面。
- 设置页没有蓝牙页面。
- 设置页没有 Network 页面，也没有 VPN/Proxy/有线网络 UI。
- 设置页没有 Apps 页面，也没有默认应用和应用权限。
- 没有 GNOME 风格搜索侧栏。
- 没有统一 panel registry。
- 页面分组仍是 Tahoe 功能口径，没有按系统域组织。

## 目标信息架构

建议按 GNOME 顺序建立第一版 Tahoe Settings：

1. Wi-Fi
2. Network
3. Bluetooth
4. Displays
5. Sound
6. Power
7. Multitasking
8. Appearance
9. Apps
10. Notifications
11. Search
12. Online Accounts
13. Sharing
14. Wellbeing
15. Mouse & Touchpad
16. Keyboard
17. Color Management
18. Printers
19. Accessibility
20. Privacy & Security
21. System
22. Niri / Window Manager

Tahoe 特有功能不要挤进顶级导航太多。建议落位：

- Dock、灵动岛、窗口布局、动画：归入 `Niri / Window Manager` 或 `Multitasking` 子页。
- 截图：归入 `Keyboard` 或 `Apps/Utilities`，不要顶级独立。
- 天气：可先放 `Apps` 或 `System`，除非后续要做成独立 shell widget 设置。
- 系统健康：放 `System` 子页。
- 关于：放 `System > About`。

保留一个 `Advanced` 或 `Niri / Window Manager` 顶级入口是必要的，因为 niri/Tahoe 的窗口管理、玻璃、layer animation 不存在于 GNOME 原生设置中心。

## 功能矩阵

### Wi-Fi

当前后端成熟度：中等，可先做内置页面。

第一版应实现：

- Wi-Fi 总开关
- 当前连接状态
- 可见网络列表
- 密码连接
- 断开
- 重新扫描
- 已保存网络标识
- NetworkManager 缺失/未运行状态页
- 无适配器状态页
- Wi-Fi 关闭状态页
- 飞行模式状态页

后续补齐：

- 已知网络管理/忘记网络
- 隐藏网络
- 企业 Wi-Fi/802.1X
- IP/DNS/路由详情编辑
- 热点开关和二维码
- 分享 Wi-Fi 二维码

### Network

当前后端成熟度：低到中。

第一版应实现：

- 有线设备列表
- 有线连接状态、速率、断开/连接
- VPN 列表
- VPN 开关
- 打开 `nm-connection-editor` 作为临时“编辑/新增”入口
- Proxy 入口，第一版可打开系统代理编辑或显示未实现状态

后续补齐：

- 内置 VPN 新增/导入
- WireGuard 基础编辑
- OpenVPN/插件式 VPN 导入
- Proxy 页面：None/Manual/Automatic
- 有线 IPv4/IPv6/DNS 编辑

### Bluetooth

当前后端成熟度：中等。`Controls.qml` 只用到开关，但 Quickshell 蓝牙模块能力足够做内置页。

第一版应实现：

- 蓝牙总开关
- adapter 状态
- 扫描开关
- 已连接/已配对/附近设备列表
- 连接/断开
- 配对/取消配对
- 忘记设备
- 信任设备
- 电量显示
- 无 adapter、已关闭、飞行模式状态页

风险：

- 当前 `Controls.qml` 的飞行模式是 Tahoe 内部 bool，不是 GNOME 那种 rfkill/gnome-settings-daemon 状态。需要单独决定是否引入 rfkill DBus 或用 `bluetoothctl`/`rfkill` 做 fallback。

### Displays

当前 `NiriSettings.qml` 只读输出名和 scale。第一版做只读比较稳。

后续如果要写显示配置，需要先确认 niri 输出配置写回策略，不能提供会破坏 guardrails 的 VRR 开关。

### Sound

已有 `Controls.qml` 和 `Sound.qml` 能做音量与音频状态。GNOME 对标页应包括输出、输入、音量、静音、测试音，但第一版可以先做输出音量和默认设备状态。

### Power

已有 Battery、PowerProfiles、Power 服务。第一版可以比 GNOME 更快做出：

- 电池状态
- 电源模式
- 亮度
- 空闲锁定状态

### Apps / Default Apps / App Permissions

当前后端成熟度：低到中。`Apps.qml` 已经能枚举和启动应用，但默认应用和权限管理还没有 service。

GNOME 对标范围：

- Apps 面板顶部有 `Default Apps` 子页入口。
- Apps 面板主体是可搜索应用列表。
- 每个应用有详情页，显示图标、名称、打开按钮、详情入口、权限组和必要权限组。
- 默认应用覆盖 Web、Mail、Calendar、Music、Video、Photos、Calls、SMS，以及可移动介质 autorun。
- 应用权限覆盖搜索、通知、后台运行、截图、壁纸、声音、快捷键抑制、相机、麦克风、位置。
- Flatpak/Snap 等 sandbox 应用可以通过 portal/metadata 表达更多权限；非 sandbox 应用只能显示“不能完全强制执行”的提示。

第一版应实现：

- 新增 `AppsPage.qml`，列出可启动应用，支持搜索。
- 新增 `DefaultAppsPage.qml`：
  - Web：`x-scheme-handler/http`、`x-scheme-handler/https`、`text/html`
  - Mail：`x-scheme-handler/mailto`
  - Calendar：`text/calendar`、`x-scheme-handler/webcal`
  - Music：常见 `audio/*` MIME
  - Video：常见 `video/*` MIME
  - Photos：常见 `image/*` MIME
  - Files：`inode/directory`（GNOME 不一定作为顶级默认项，但对 Tahoe 日用很实用）
- 默认应用读写优先走 `xdg-mime query default` / `xdg-mime default`，候选应用来自 Desktop Entry 支持的 MIME types。
- 新增 `AppPermissionsPage.qml` 或应用详情子页，第一版至少显示：
  - 是否 sandboxed（Flatpak/Snap/普通桌面应用）
  - 通知权限状态
  - 后台运行权限状态
  - 相机/麦克风/位置/截图/壁纸/声音权限状态
  - 非 sandbox 应用的“不完全可强制”提示
- 权限读写第一版优先做 portal permission store 可用路径；不可写或不可识别时显示只读状态，不假装能控制。

后续补齐：

- 可移动介质默认动作和 autorun。
- Flatpak metadata 的静态权限解析：filesystem、network、devices、session/system bus、settings。
- Snap permissions。
- 应用存储用量、清缓存/清数据。
- 默认应用冲突处理：同一类别涉及多个 MIME type 时批量同步。

### Keyboard / Mouse & Touchpad

`NiriSettings.qml` 已支持键盘 repeat、numlock、触摸板 tap/natural scroll/dwt/accel。应从当前 `NiriInputPage` 拆出来，放到 GNOME 对应域。

快捷键第一版继续只读，避免破坏 niri binds 和 MRU/task-switcher 护栏。

## 推荐重构路线

### S1：设置 shell 与导航重构

目标：先把结构和视觉改成 GNOME 型，不碰功能深水区。

- 新增 panel registry，例如 `components/settings/SettingsModel.js`。
- registry 统一定义：
  - `id`
  - `title`
  - `subtitle`
  - `icon`
  - `keywords`
  - `group`
  - `component`
  - `statusBadge`
  - `enabled/visible`
- 替换 `pageTitle()`、`pageSubtitle()`、`pageIndex()` 这类散落硬编码。
- 侧栏改为 GNOME 顺序和分隔线。
- 加搜索框，搜索 title/subtitle/keywords。
- 默认打开第一项 `wifi` 或上次打开项，不再以“概览”为中心。
- 移除侧栏顶部 `Tahoe / Desktop` 品牌块。
- 停用 `TahoeCategoryIcon` 的彩色渐变方块侧栏样式，改为单色 symbolic icon。
- 停用 overview summary tiles 作为默认首页；旧 `OverviewPage` 只保留兼容跳转或删除。
- About/Health 删除 hero strip，改成普通 preferences groups。
- 收敛圆角、间距和半透明卡片层级，优先做安静列表而不是浮动胶囊。
- 保持现有 overlay、TahoeGlass region、dismiss 和快捷入口不变。

验收：

- 设置页能打开/关闭。
- 现有页面仍可进入。
- 搜索能过滤页面。
- 没有引入玻璃 region、dismiss、focus 回归。
- 侧栏无彩色分类方块，无 `Tahoe Desktop` 品牌块。
- 默认打开页不是 `概览`。
- About 页不再显示 `niri Tahoe Desktop` hero。

### S2：Wi-Fi 页面

目标：把已有 `WifiPopup.qml` 能力迁进设置页。

- `SettingsPanel` 增加 `controlsService`。
- 新增 `WifiPage.qml`。
- 复用 `Controls.qml` 的 Wi-Fi 网络模型和动作。
- 不直接复用 popup UI，popup 适合顶栏，设置页需要 GNOME preference-page 结构。
- 状态页必须覆盖：NetworkManager 不可用、无 adapter、Wi-Fi off、飞行模式。

验收：

- 能开关 Wi-Fi。
- 能列出网络。
- 能连开放网络/已保存网络。
- 能输入密码连接 WPA-PSK/SAE。
- 能断开和 rescan。

### S3：Bluetooth 页面

目标：用 Quickshell.Bluetooth 做内置蓝牙设置。

- 扩展 `Controls.qml` 或新建 `BluetoothSettings.qml` service。
- 暴露 adapter、device list、pair/connect/forget/trust/block。
- 新增 `BluetoothPage.qml`。
- 做 GNOME 式状态栈。

验收：

- 无蓝牙硬件时显示状态页。
- 有 adapter 时可开关、扫描、连接/断开、配对/忘记。
- 不因 BlueZ 缺失导致 shell 崩溃。

### S4：Network / VPN 页面

目标：补上 VPN 和有线网络。

- 新建 `NetworkSettings.qml` service。
- 第一版可使用 `nmcli -t` 做 VPN list/up/down/import fallback。
- 同时复用 Quickshell.Networking 的 wired device。
- 新增 `NetworkPage.qml`。
- VPN 编辑/新增第一版打开 `nm-connection-editor`，后续再内置编辑器。

验收：

- NetworkManager 不运行时显示状态页。
- 有线网络显示设备、link、状态。
- VPN profile 能显示、开关。
- 新增/编辑入口可用。

### S5：Apps / 默认应用 / 应用权限

目标：补上 GNOME Apps panel 的核心能力。

- 新建 `AppsSettings.qml` service，复用现有 `Apps.qml` 的 Desktop Entry 枚举。
- service 增加默认应用读写：
  - `xdg-mime query default <mime>`
  - `xdg-mime default <desktop-id> <mime...>`
  - 候选应用按 desktop entry supported MIME types 过滤。
- 新增 `AppsPage.qml`：
  - 顶部 `Default Apps` 入口。
  - 搜索应用。
  - 应用列表进入详情页。
- 新增 `DefaultAppsPage.qml`：
  - Web、Mail、Calendar、Music、Video、Photos、Files。
  - 每类显示当前默认应用和候选列表。
- 新增应用详情/权限页第一版：
  - 显示应用图标、名称、打开按钮。
  - 显示 sandbox 状态。
  - 显示 portal permission store 能读到的权限。
  - 对非 sandbox 或无法写的权限显示只读/不可完全强制提示。

验收：

- 能列出应用并搜索。
- 能查看当前默认浏览器/邮件/图片/视频等。
- 能修改至少 Web、Mail、Files 三类默认应用，且 `xdg-mime query default` 返回新值。
- Flatpak/portal 权限不可用时不崩溃，页面显示明确状态。
- 普通非 sandbox 应用不会显示成“权限已完全受控”。

### S6：把现有 Tahoe 页面归档到 GNOME 域

目标：减少“乱七八糟”的根因。

- `Appearance`：外观、壁纸、图标主题。
- `Displays`：输出只读、夜览/色温，后续加写显示。
- `Power`：电池、亮度、电源模式、空闲锁。
- `Keyboard`：快捷键只读、repeat、输入法。
- `Mouse & Touchpad`：触摸板设置。
- `Multitasking`：窗口布局、Dock、工作区、动画。
- `Notifications`：通知和 DND，输入法不要再混在通知页。
- `System`：健康、关于、启动项。
- `Niri / Window Manager`：保留高级项，承载无法归入 GNOME 标准域的 niri/Tahoe 专用配置。

验收：

- 顶级导航不再按 Tahoe 组件碎片排列。
- 每个现有设置项都有明确归属。
- 旧入口页 id 有兼容跳转，避免 Search/IPC 打开失效。

### S7：高级补齐

目标：接近 GNOME 的完整基础功能。

- Wi-Fi hidden network、known networks、forget network、hotspot、QR。
- VPN import/edit 内置化。
- Proxy 页面。
- wired IPv4/IPv6/DNS 编辑。
- display 写配置。
- sound 输入输出设备选择。
- Apps：可移动介质默认动作、Flatpak 静态权限、Snap 权限、应用存储用量。
- privacy/security/sharing 的可用子项。

## 技术护栏

- 不改 `SettingsPanel` 的 overlay/dismiss 基线，除非专门验收。
- 不给 TahoeGlass region 几何加 spring。
- `NiriSettings` 写 KDL 后必须继续走现有校验路径，不能默认启用 VRR。
- 快捷键编辑继续保守，MRU/task-switcher binds 不能被覆盖。
- Network/VPN 操作必须在 NetworkManager 缺失时降级为状态页，不允许 shell load failure。
- BlueZ 缺失或无 adapter 时同样必须降级为状态页。
- `nmcli`、`bluetoothctl` fallback 必须经过 `CommandRunner`，不要在页面组件里散落 shell 命令。

## 当前最小可执行结论

下一步应先做 S1，而不是直接补 Wi-Fi/VPN。原因是当前设置页缺的是“设置中心骨架”和 GNOME 视觉语言。如果先把 Wi-Fi、蓝牙、VPN 塞进现有彩色 Tahoe 侧栏，会继续放大当前的结构和审美问题。

S1 完成后，Wi-Fi 是最适合的第一个功能页，因为现有 `Controls.qml` 已经有网络列表、连接、断开、扫描和 nmcli fallback。
