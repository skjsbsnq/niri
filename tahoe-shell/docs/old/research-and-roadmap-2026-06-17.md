# Tahoe niri + Quickshell 改进路线图（线性版）

日期：2026-06-17
基准：源码核查 + 真机现场（NVIDIA RTX 4070 Max-Q + AMD Raphael，niri+Quickshell wayland 会话）。

## 阅读规则

1. **严格顺序**。从 T01 做到 T-end，**完成一个再下一个**。
2. **每一项都给**：现象 / 根因 / 命令或代码 / 验收。
3. **任务编号永久不变**。后续讨论引用 `T05`、`T17` 即可。
4. 标记说明：
   - 🔥 = 不修就不能日用
   - ⚠️ = 可用但破体验
   - 💎 = 拟真打磨
5. **所有安装命令一律 `sudo pacman -S`**（你的偏好）。AUR/源码编译只在官方源没有时才用，且会显式说明。

---

## 第一批：系统层断头（不修无法日用）—— T01-T05.5

> 真机现场 niri 在跑、shell 在跑，但 X11 应用全部打不开、中文输入打不出、截屏对话框无人响应、电池显示骗人、**WiFi 选不了网更连不上**。这一批是"应用层根本起不来"和"基本网络不通"的硬阻塞。**先全部完成再进第二批**。

---

### T01 🔥 装 Xwayland 集成（所有 X11 应用打不开的根因）

**现象**
QQ、微信、TIM、Steam、ToDesk、向日葵、JetBrains 旧版、Zoom、腾讯会议、网易云、QQ 音乐、Adobe 系列、老 Electron 应用全部启动失败。

**根因**
niri 启动日志：

```
WARN niri::utils::xwayland::satellite: error spawning xwayland-satellite
    at "xwayland-satellite", disabling integration:
    No such file or directory (os error 2)
```

niri fork 把 `xwayland-satellite` 当**隐式依赖**，缺包只 WARN 不 fail，所以一直没被发现。

**命令**

```bash
sudo pacman -S xwayland-satellite
# extra/xwayland-satellite 0.8.1-2 已在官方源
```

**让 niri 重新启用 X11 集成**

```bash
systemctl --user restart niri.service
# 或者退出再登录
```

**验收**

```bash
pgrep -a xwayland-satellite   # 应该看到一个进程
echo $DISPLAY                 # 应该有值，如 :0
# 装一个测试 X11 应用：
sudo pacman -S xclock
xclock                        # 能出窗口
```

如果还不行，看 `journalctl --user -u niri -n 50` 找 xwayland 相关行。

---

### T02 🔥 启动 fcitx5 输入法（中文打不出）

**现象**
中文用户根本无法输入中文。`pgrep fcitx5` 真机现场返回空。

**根因**
`scripts/arch-zh-setup.sh` 装了 fcitx5 包，但没启动 systemd user 服务，niri session 启动时也没 spawn fcitx5。环境变量也没设。

**第 1 步：确认包已装**

```bash
pacman -Q fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-gtk fcitx5-qt
# 缺哪个补哪个：
sudo pacman -S --needed fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-gtk fcitx5-qt
```

**第 2 步：写环境变量到 niri session**

编辑 `~/.config/environment.d/90-fcitx5.conf`（如果 `arch-zh-setup.sh` 已写过就跳过）：

```
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
INPUT_METHOD=fcitx
```

让 systemd user manager 重读环境：

```bash
systemctl --user daemon-reload
systemctl --user import-environment GTK_IM_MODULE QT_IM_MODULE XMODIFIERS SDL_IM_MODULE INPUT_METHOD
```

**第 3 步：让 fcitx5 跟 niri session 一起起**

编辑 `~/.config/niri/tahoe/config.kdl`，在文件顶部已有 `spawn-sh-at-startup ...` 那一行附近加：

```kdl
spawn-at-startup "fcitx5" "-d" "--replace"
```

**第 4 步：立即手动起一次（不重启 niri）**

```bash
fcitx5 -d --replace
```

**验收**

```bash
pgrep -a fcitx5                 # 看到进程
fcitx5-diagnose | head -40      # 顶部应该全是 ✓
```

打开任意输入框（Spotlight 也行），按 `Ctrl+Space` 切换到拼音，输几个字，能出中文候选词即通过。

---

### T03 🔥 装并启 xdg-desktop-portal（截屏 / 文件对话框 / 录屏 / 浏览器分享屏幕断头）

**现象**
浏览器无法选屏分享；Flatpak、GTK4、Qt6 应用的"打开文件"对话框失败或退化；niri 已有 `xdp-gnome-screencast` feature 但 portal 没人响应。

**根因**
`pgrep xdg-desktop-portal` 真机现场返回空。portal 是 DBus 服务，需要按需启动；如果系统从来没装过 portal 包就完全没人响应。

**命令**

```bash
sudo pacman -S xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
```

**让 niri 用 gnome portal（niri 当前最佳兼容）**

```bash
mkdir -p ~/.config/xdg-desktop-portal
cat > ~/.config/xdg-desktop-portal/niri-portals.conf <<'EOF'
[preferred]
default=gnome;gtk
org.freedesktop.impl.portal.ScreenCast=gnome
org.freedesktop.impl.portal.Screenshot=gnome
org.freedesktop.impl.portal.FileChooser=gtk
EOF
```

**启动 portal 服务**

```bash
systemctl --user enable --now xdg-desktop-portal.service
systemctl --user enable --now xdg-desktop-portal-gnome.service
systemctl --user enable --now xdg-desktop-portal-gtk.service
```

**验收**

```bash
busctl --user list | grep portal
# 应至少看到:
# org.freedesktop.portal.Desktop
# org.freedesktop.impl.portal.desktop.gnome
# org.freedesktop.impl.portal.desktop.gtk

systemctl --user status xdg-desktop-portal-gnome.service | head -5
# Active: active (running)
```

实测：打开 Firefox/Chromium → 进任意视频网站 → 点"屏幕分享" → 应能弹出屏幕选择对话框（之前会卡住）。

---

### T04 🔥 修电池"永远 1%"（QML 计算 bug）

**现象**
顶栏电池显示 1%，BatteryPopup 也 1%。

**真机现场推翻原假设**
UPower 硬件层：

```
BAT0:          state=fully-charged, percentage=100%, model=AEC616864
DisplayDevice: state=fully-charged, percentage=100%
```

**硬件 100%、UPower 100%，shell 显示 1%——纯 QML bug**。原 §1.3 猜的"UPower 占位"被推翻。最可能：Quickshell 0.3.0 对 `UPower.displayDevice.percentage` 暴露成 0~1 制式（不是 0~100），`Math.round(0.01) = 0` 但 outline 宽度 `Math.max(2, ...)` 让肉眼看作"1%"。

**改 `tahoe-shell/services/Battery.qml`**

整个文件替换为：

```qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower

Item {
    id: root
    visible: false

    // 优先扫真电池，displayDevice 仅做最后兜底
    readonly property var realDevice: {
        try {
            var devs = UPower.devices.values;
            for (var i = 0; i < devs.length; i++) {
                var d = devs[i];
                if (d && d.isLaptopBattery) return d;
            }
        } catch (e) {}
        return UPower.displayDevice;
    }

    readonly property bool ready: !!realDevice
        && (realDevice.ready === undefined || realDevice.ready === true)

    // 兼容 0~1 制式和 0~100 制式
    function normalizePercent(raw) {
        var n = Number(raw);
        if (isNaN(n)) return 0;
        if (n > 0 && n <= 1.0) return n * 100;   // 0~1 → 0~100
        return n;
    }

    readonly property real rawPercent: ready ? normalizePercent(realDevice.percentage) : 0
    readonly property bool available: ready && rawPercent > 1
    readonly property real percentage: available ? Math.max(0, Math.min(100, rawPercent)) : 0
    readonly property int roundedPercentage: Math.round(percentage)
    readonly property int state: available ? Number(realDevice.state) : UPowerDeviceState.Unknown
    readonly property bool charging: state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge
    readonly property bool fullyCharged: state === UPowerDeviceState.FullyCharged
    readonly property bool discharging: state === UPowerDeviceState.Discharging || state === UPowerDeviceState.PendingDischarge
    readonly property bool onBattery: UPower.onBattery
    readonly property string iconName: available ? String(realDevice.iconName || "") : ""
    readonly property string stateText: stateLabel(state)
    readonly property string powerSourceText: available
        ? (onBattery ? "电池" : "电源适配器")
        : "不可用"
    readonly property string timeText: timeLabel()
    readonly property string healthText: healthLabel()

    Component.onCompleted: {
        console.log("[Battery] realDevice:", realDevice,
                    "rawPercent:", rawPercent,
                    "isLaptop:", realDevice && realDevice.isLaptopBattery,
                    "ready:", ready);
    }

    // 保留原 stateLabel / formatSeconds / timeLabel / healthLabel 不动
    function stateLabel(value) {
        if (!available) return "无电池";
        if (value === UPowerDeviceState.Charging) return "充电中";
        if (value === UPowerDeviceState.Discharging) return "使用电池";
        if (value === UPowerDeviceState.Empty) return "电量耗尽";
        if (value === UPowerDeviceState.FullyCharged) return "已充满";
        if (value === UPowerDeviceState.PendingCharge) return "等待充电";
        if (value === UPowerDeviceState.PendingDischarge) return "等待放电";
        return onBattery ? "使用电池" : "电源适配器";
    }

    function formatSeconds(value) {
        var seconds = Math.max(0, Math.round(Number(value) || 0));
        if (seconds <= 0) return "";
        var minutes = Math.round(seconds / 60);
        var hours = Math.floor(minutes / 60);
        var mins = minutes % 60;
        if (hours > 0 && mins > 0) return hours + " 小时 " + mins + " 分";
        if (hours > 0) return hours + " 小时";
        return mins + " 分钟";
    }

    function timeLabel() {
        if (!available) return "";
        if (charging) {
            var full = formatSeconds(realDevice.timeToFull);
            return full.length > 0 ? "充满还需 " + full : "";
        }
        if (discharging) {
            var empty = formatSeconds(realDevice.timeToEmpty);
            return empty.length > 0 ? "剩余 " + empty : "";
        }
        return "";
    }

    function healthLabel() {
        if (!available || !realDevice.healthSupported) return "";
        var health = Math.round(Number(realDevice.healthPercentage) || 0);
        if (health <= 0) return "";
        return "健康度 " + health + "%";
    }
}
```

**重启 shell**

```bash
pkill quickshell
quickshell -p ~/.config/quickshell/tahoe &
```

**验收**
顶栏电池显示真实百分比（应该接近 100%）。打开 BatteryPopup 看"已充满 100%"和"电源适配器"。看 stderr 的 `[Battery] ... rawPercent: 100`（或对应真值）确认数据通路。

---

### T05 🔥 改 baremetal-install.sh 把 T01/T03 纳入默认安装

**现象**
你这台真机的现状就是脚本本身的缺陷——重装一台机器还会重复踩同一坑。

**位置**
`scripts/baremetal-install.sh`（找 pacman -S 集中安装的那段）

**改动**
在现有包列表里追加：

```bash
xwayland-satellite
xdg-desktop-portal
xdg-desktop-portal-gnome
xdg-desktop-portal-gtk
```

并新增一段 systemd user 服务自启：

```bash
sudo -u "$TARGET_USER" systemctl --user enable xdg-desktop-portal.service xdg-desktop-portal-gnome.service xdg-desktop-portal-gtk.service
```

`arch-zh-setup.sh` 里 `ENABLE_FCITX_SERVICE` 已默认 true，但需要核查它真的把 fcitx5 自启写进了 niri config 的 spawn-at-startup（T02 第 3 步）——如果没有，加进去。

**验收**
找一台干净的 archinstall 最小 Arch，跑 `bash scripts/baremetal-install.sh`，装完登录到 niri session，无需任何手动命令即可：xclock 能开、fcitx5 能切中文、Firefox 能分享屏、电池显示正确百分比。

---

### T05.5 🔥 修 Wi-Fi（笔记本连不上 WiFi 怎么用？）

**现象**
你原话："控制面板的WiFi按钮跟摆设一样 而且他压根也不能让我连接WiFi呀"。

**根因（源码已定位）**

`tahoe-shell/components/ControlCenter.qml:399-407`：整个 Wi-Fi tile 的 MouseArea 只调 `controls.toggleWifi()`，**没有任何"选网络"或"输密码"入口**。

`tahoe-shell/services/Controls.qml:147-207`：`wifiEnabled` / `wifiConnected` / `wifiName` 是只读属性；`setWifiEnabled` / `toggleWifi` 只能开关网卡。**没暴露 AP 列表、没有 connect 接口**。

但 Quickshell 自带的 `Quickshell.Services.Network`（`quickshell/src/network/wifi.hpp:39`）**有** `Q_INVOKABLE void connectWithPsk(const QString& psk)`，底层走 NetworkManager 的 `AddAndActivateConnection`，能自动建 connection + 输密码 + 激活。tahoe-shell 没用。

`nmcli` 现场实测周围扫到 7 个 AP，已连接 RedmiK60——NetworkManager 后端完全正常，纯 shell 层缺 UI 和 binding。

**你的设计要求（按你原话）**

> 控制面板的WiFi就单纯一个开关
> 顶栏的就像控制中心和电池一样 再单独加一个WiFi按钮
> 点击WiFi按钮，弹出卡片可以连接WiFi

✅ 完全合理，按这个做。

**实现分 4 步**

#### Step 1：services/Controls.qml 暴露 AP 列表 + 连接接口

在现有 `wifiDevice` getter 后追加：

```qml
// AP 列表（去重、按信号强度排序）
readonly property var wifiNetworks: {
    var d = root.wifiDevice;
    if (!d) return [];
    try {
        var nets = d.networks;
        if (!nets || !nets.values) return [];
        // 同 SSID 取最强信号那条
        var bySsid = {};
        for (var i = 0; i < nets.values.length; i++) {
            var n = nets.values[i];
            if (!n) continue;
            var name = String(n.name || "").trim();
            if (name.length === 0) continue;
            var sig = Number(n.signalStrength || n.strength || 0);
            if (!bySsid[name] || sig > bySsid[name]._signal) {
                bySsid[name] = n;
                bySsid[name]._signal = sig;
            }
        }
        var out = [];
        for (var k in bySsid) out.push(bySsid[k]);
        out.sort(function(a, b) { return (b._signal || 0) - (a._signal || 0); });
        return out;
    } catch (e) {
        return [];
    }
}

// 连接到 AP（带密码或不带）
function connectWifi(network, psk) {
    if (!network) return;
    try {
        if (psk && psk.length > 0) {
            network.connectWithPsk(psk);
        } else {
            // 已知网络或开放网络
            network.connect();
        }
    } catch (e) {
        console.warn("[Controls] wifi connect failed:", e);
    }
}

function disconnectWifi() {
    var d = root.wifiDevice;
    if (d && d.disconnect) try { d.disconnect(); } catch (e) {}
}

function rescanWifi() {
    var d = root.wifiDevice;
    if (d && d.scan) try { d.scan(); } catch (e) {}
}
```

#### Step 2：ControlCenter 的 Wi-Fi tile 改成纯开关

`ControlCenter.qml:399-407` 的整 tile MouseArea 保留——`toggleWifi()` 行为就是开关网卡，符合你"单纯一个开关"的要求。

但要做两点优化：

1. **副标题文案优化**：当 Wi-Fi 开但未连接时显示"已开启"，连接时显示 SSID，关闭时显示"已关闭"。改 `ControlCenter.qml:454-461`（`wifiName` 那段）：

```qml
Text {
    Layout.fillWidth: true
    text: {
        if (!ct.controls || !ct.controls.wifiEnabled) return "已关闭";
        if (ct.controls.wifiConnected) return ct.controls.wifiName;
        return "已开启";
    }
    color: root.textTertiary
    font.pixelSize: 11
    elide: Text.ElideRight
    maximumLineCount: 1
}
```

2. **去掉"假装能选网"的暗示**：当前点击只能开关，但用户会预期点击能进选网界面。所以视觉上确保 tile 看起来就像开关（不带 chevron / 箭头），同时配合 Step 3 的顶栏入口。

#### Step 3：新建 components/WifiPopup.qml（独立卡片）

新建文件 `tahoe-shell/components/WifiPopup.qml`：

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "TahoeGlass.js" as GlassStyle

PanelWindow {
    id: root

    property var controlsService
    property bool open: false

    signal closeRequested()

    visible: open
    aboveWindows: true
    focusable: open
    color: "transparent"
    WlrLayershell.namespace: "tahoe-wifi-popup"

    anchors {
        top: true
        right: true
    }

    // 卡片宽 320，高自适应
    margins.top: 8
    margins.right: 8

    implicitWidth: 320
    implicitHeight: cardColumn.implicitHeight + 28

    // 玻璃面板背景
    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 6
        radius: 18
        color: "#cc1d1f24"   // 深色 Tahoe 玻璃；浅色见 ControlCenter
        border.color: "#28ffffff"
        border.width: 1

        TahoeGlass.regions: [
            TahoeGlassRegion {
                x: 0; y: 0
                width: card.width; height: card.height
                material: GlassStyle.MaterialPanel
                radius: 18
                blur: true
                shadow: true
                clip: true
                materialAlpha: 1.0
            }
        ]

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // 头部：标题 + 开关
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi"
                    color: "#f0f2f5"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                // 简易开关
                Rectangle {
                    width: 40; height: 22
                    radius: 11
                    color: (root.controlsService && root.controlsService.wifiEnabled) ? "#34c759" : "#3a3d44"
                    border.color: "#22ffffff"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 160 } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: "#ffffff"
                        y: 2
                        x: (root.controlsService && root.controlsService.wifiEnabled) ? 20 : 2
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.controlsService) root.controlsService.toggleWifi()
                    }
                }
            }

            // 当前连接
            RowLayout {
                Layout.fillWidth: true
                visible: root.controlsService && root.controlsService.wifiConnected

                Text {
                    Layout.fillWidth: true
                    text: root.controlsService ? root.controlsService.wifiName : ""
                    color: "#a0e4ff"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Text {
                    text: "断开"
                    color: "#ff453a"
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.controlsService) root.controlsService.disconnectWifi()
                    }
                }
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#22ffffff"
                visible: root.controlsService && root.controlsService.wifiEnabled
            }

            // 网络列表 + 输密码内联展开
            ListView {
                id: netList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 280)
                visible: root.controlsService && root.controlsService.wifiEnabled
                clip: true
                spacing: 2

                model: root.controlsService ? root.controlsService.wifiNetworks : []

                property string expandedSsid: ""  // 哪个网络在输密码

                delegate: Item {
                    id: row
                    required property var modelData
                    width: netList.width
                    height: 36 + (expanded ? 50 : 0)
                    readonly property bool expanded: netList.expandedSsid === String(row.modelData.name || "")
                    readonly property bool secured: {
                        try { return !!row.modelData.isSecured; } catch (e) { return true; }
                    }
                    readonly property bool isActive: {
                        try { return !!row.modelData.connected; } catch (e) { return false; }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 10
                        color: rowMouse.containsMouse ? "#22ffffff" : "transparent"

                        RowLayout {
                            id: rowTop
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            height: 32
                            spacing: 8

                            Text {
                                text: row.isActive ? "✓" : (row.secured ? "🔒" : "")
                                color: row.isActive ? "#34c759" : "#a0a4ab"
                                font.pixelSize: 12
                                Layout.preferredWidth: 14
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(row.modelData.name || "")
                                color: "#f0f2f5"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            Text {
                                text: {
                                    var s = Number(row.modelData.signalStrength || row.modelData.strength || 0);
                                    return s + "%";
                                }
                                color: "#a0a4ab"
                                font.pixelSize: 11
                            }
                        }

                        // 内联密码输入
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: rowTop.bottom
                            anchors.margins: 8
                            height: row.expanded ? 42 : 0
                            radius: 8
                            color: "#16ffffff"
                            border.color: "#22ffffff"
                            border.width: 1
                            visible: row.expanded
                            clip: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 5
                                spacing: 6

                                TextInput {
                                    id: pskInput
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    echoMode: TextInput.Password
                                    selectByMouse: true
                                    focus: row.expanded
                                    Keys.onReturnPressed: connectBtn.clicked()
                                    Keys.onEscapePressed: netList.expandedSsid = ""
                                }

                                Rectangle {
                                    id: connectBtn
                                    Layout.preferredWidth: 56
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: connectMouse.containsMouse ? "#3a8aff" : "#2871d9"
                                    signal clicked()
                                    onClicked: {
                                        if (root.controlsService)
                                            root.controlsService.connectWifi(row.modelData, pskInput.text);
                                        netList.expandedSsid = "";
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "连接"
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: connectMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: parent.clicked()
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1   // 不挡密码框
                            onClicked: {
                                if (row.isActive) return;
                                if (row.secured) {
                                    netList.expandedSsid = String(row.modelData.name || "");
                                } else {
                                    if (root.controlsService)
                                        root.controlsService.connectWifi(row.modelData, "");
                                }
                            }
                        }
                    }
                }
            }

            // 底部：重新扫描 + Wi-Fi 设置
            RowLayout {
                Layout.fillWidth: true
                visible: root.controlsService && root.controlsService.wifiEnabled

                Text {
                    text: "重新扫描"
                    color: "#a0e4ff"
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.controlsService) root.controlsService.rescanWifi()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Wi-Fi 设置…"
                    color: "#a0e4ff"
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["nm-connection-editor"])
                    }
                }
            }
        }
    }

    // 点空白处关闭
    MouseArea {
        anchors.fill: parent
        z: -10
        onClicked: root.closeRequested()
    }
}
```

#### Step 4：顶栏加 Wi-Fi 图标 + shell.qml 接线

**改 `tahoe-shell/components/TopBar.qml`**（参照电池那段模式）：

在电池入口附近、控制中心入口之前，加一个 Wi-Fi 入口：

```qml
property var controlsService
property bool wifiPopupOpen: false
signal toggleWifi()

// ... 在电池块之后 ...
Item {
    Layout.preferredWidth: 28
    Layout.preferredHeight: 24
    Layout.alignment: Qt.AlignVCenter
    visible: root.controlsService

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.wifiPopupOpen ? "#38ffffff" : (wifiMouse.containsMouse ? "#30ffffff" : "#22ffffff")
        border.color: "#40ffffff"

        Text {
            anchors.centerIn: parent
            text: {
                if (!root.controlsService || !root.controlsService.wifiEnabled) return "";  // wifi_off
                if (!root.controlsService.wifiConnected) return "";  // wifi (空)
                return "";  // wifi (满)，可按 signalStrength 分级
            }
            color: "#202124"
            font.family: root.iconFont
            font.pixelSize: 16
        }
    }

    MouseArea {
        id: wifiMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleWifi()
    }
}
```

**改 `tahoe-shell/shell.qml`**：

ShellRoot 加状态：

```qml
property bool wifiPopupOpen: false
```

互斥逻辑加一行（参照其它面板）：

```qml
onWifiPopupOpenChanged: if (wifiPopupOpen) {
    controlCenterOpen = false;
    notificationCenterOpen = false;
    batteryPopupOpen = false;
    // ...
}
```

每屏的 TopBar 加：

```qml
TopBar {
    // ... 已有
    controlsService: controls
    wifiPopupOpen: shell.wifiPopupOpen
    onToggleWifi: shell.wifiPopupOpen = !shell.wifiPopupOpen
}
```

每屏加 WifiPopup 实例：

```qml
WifiPopup {
    screen: modelData
    controlsService: controls
    open: shell.wifiPopupOpen
    onCloseRequested: shell.wifiPopupOpen = false
}
```

**包依赖**

```bash
sudo pacman -S --needed nm-connection-editor   # "Wi-Fi 设置…" 入口要用
```

**验收**

1. 重启 shell：`pkill quickshell && quickshell -p ~/.config/quickshell/tahoe &`
2. 顶栏右上区域出现 Wi-Fi 图标。
3. 点击 → 弹出 WifiPopup 卡片。
4. 卡片顶部"Wi-Fi 已开启"和真开关。
5. 列表显示周围 AP（应能看到现场 7 个 RedmiK60/CMCC-405 等）。
6. 点击未加密 AP → 立刻连。
7. 点击加密 AP → 行展开显示密码框 → 输密码 → 按回车 → 连上。
8. 连上后顶栏图标变状态色，控制面板 Wi-Fi tile 副标题显示 SSID。
9. "重新扫描"刷新列表。
10. "Wi-Fi 设置…" 打开 nm-connection-editor 做高级配置。

**踩坑提示**

- 如果 `wifiNetworks` 一直空：Quickshell 的 `WifiNetwork.networks` 在某些 NetworkManager 版本上需要手动 `device.scan()` 才填充。在 `Controls.qml` 加 `Component.onCompleted: rescanWifi()`，每 30 秒自动 rescan。
- 如果 `connectWithPsk` 报错：fallback 走 `Quickshell.execDetached(["nmcli", "device", "wifi", "connect", ssid, "password", psk])`——nmcli 现场实测正常。

**完成检查点**
- [ ] 顶栏 Wi-Fi 图标可见
- [ ] 卡片打开能看到 AP 列表
- [ ] 加密网络输密码能连上
- [ ] 控制中心 Wi-Fi tile 改为纯开关（点击只切 on/off）

---

## 第一批完成检查点 ✅

继续之前确认：

- [ ] `pgrep xwayland-satellite` 有
- [ ] `pgrep fcitx5` 有，能切出中文
- [ ] `busctl --user list | grep portal` 至少 3 条
- [ ] 顶栏电池不是 1%
- [ ] **顶栏 Wi-Fi 图标可见，能连加密网络**

**全部 ✓ 才进入第二批。**

---

## 第二批：体验性大 bug（4 个用户原话问题中的剩余 3 个）—— T06-T11

> 第一批让"机器能用"，第二批让"机器好用"。

---

### T06 ⚠️ 修 Launchpad 动画"既不流畅也不丝滑"

**现象**
你原话："点开应用启动器 动画既不流畅也不丝滑 有一种说不出来的奇怪。"

**根因（源码已定位）**
`tahoe-shell/components/Launchpad.qml`：

| 项 | 行 | 值 |
|---|---|---|
| launcher opacity duration | 102 | 200 ms |
| launcher scale duration   | 110 | 220 ms |
| backdrop opacity duration | 85  | 170 ms |
| scale 起点 | 100 | 1.1（Web 参考是 1.2） |

三段时长错位 30-50 ms、scale 幅度不够；80 张 PNG 在缩放期间每帧重采样（无 `layer.enabled` FBO 缓存）；delegate 首帧才实例化吃掉首段时间。

**改动**

编辑 `tahoe-shell/components/Launchpad.qml`：

第 78-86 行的 `backdrop` 块：

```qml
Behavior on opacity {
    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
}
```

第 95-117 行的 `launcher` 块改为：

```qml
Item {
    id: launcher
    anchors.centerIn: parent
    width: Math.min(parent.width - 72, 820)
    height: Math.min(parent.height - 96, 590)

    opacity: root.open ? 1 : 0
    // 抄 Web 参考：1.2→1
    scale: root.open ? 1 : 1.2

    // 缩放/淡入期间用 FBO 缓存，避免 80 张图每帧重采样
    layer.enabled: scale !== 1 || opacity !== 1
    layer.smooth: true

    Behavior on opacity {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        enabled: !root.useSpring
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        enabled: root.useSpring
        SpringAnimation { spring: 200; damping: 1.0; epsilon: 0.01 }
    }
    ...
}
```

第 23 行 `visible: open || backdrop.opacity > 0.01` 不动——`PanelWindow` 的 visible 控制窗口可见性，必须在动画期间都为 true。（注意：不要改 PanelWindow 的 visible 为 true，会让 layer-shell 一直占屏。）

**验收**
点 Launchpad 入口：
- 整体涌入感统一，无"骨架先动玻璃后到"。
- scale 起点更远，有"从屏外飞入"感。
- 缩放期间图标清晰，无 jitter / blur。
- 关闭对称丝滑。

---

### T07 ⚠️ 修通知"DND 开了仍有声"

**现象**
你原话："通知明明已经打开了静音 但有消息来了依旧有声音"。

**真机现场关键事实**
`org.freedesktop.Notifications` DBus name 唯一持有者就是 quickshell（pid 1242）。没有 mako/dunst/gsd-notify 抢——**声音不可能来自另一个通知 daemon**。

**真实声源候选**（按可能性）
1. **应用自播**：Telegram/Discord/Slack/Element/QQ/微信 直接调 libcanberra 或 PulseAudio 自播声，绕过 freedesktop notification 协议。Shell 永远拦不到。
2. **系统 event sound**：通知客户端发的 `sound-name` hint，shell 不处理时**理论上**没人播。但某些 GTK 应用会自己读 hint 自播。
3. **fcitx5 起手音**（如果 T02 装的是 fcitx5-chinese-addons）：拼音切换/候选词翻页有提示音。

**Step 1：先确认声源到底是哪条路径**

DND 开启后让一条声音响起，立刻在另一个终端：

```bash
# 实时看谁在调声卡
pactl list short sink-inputs
# 看 application.name 是哪个进程
```

记录下来——这决定下面修哪条路径。

**Step 2：shell 层做 suppress-sound hint（对走规范的客户端有效）**

编辑 `tahoe-shell/services/Notifications.qml` 第 103-112 行：

```qml
if (root.dndEnabled) {
    // 1. 标准 hint：让客户端别播声（GTK/Qt notify 库会读）
    try {
        if (notification.hints)
            notification.hints["suppress-sound"] = true;
    } catch (e) {}
    // 2. 历史保留 + 视觉抑制
    notification.expire();
    return;
}
```

**Step 3：DND 翻转时系统级 mute event-sound**

新增 `tahoe-shell/services/Sound.qml`：

```qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    function setEventSoundsMuted(muted) {
        // GNOME desktop event sounds（GTK/Qt 提示音）
        Quickshell.execDetached([
            "gsettings", "set", "org.gnome.desktop.sound",
            "event-sounds", muted ? "false" : "true"
        ]);
        // 通用 alert
        Quickshell.execDetached([
            "gsettings", "set", "org.gnome.desktop.sound",
            "theme-name", muted ? "__no_sounds" : "freedesktop"
        ]);
    }
}
```

`shell.qml` 头部加：

```qml
Sound { id: soundService }
```

把 `Sound` 引用传给 `Notifications`：

```qml
Notifications {
    id: notificationsService
    soundService: soundService
}
```

`Notifications.qml` 加属性 + 在 `dndEnabled` 变化时调用：

```qml
property var soundService: null
onDndEnabledChanged: {
    if (soundService) soundService.setEventSoundsMuted(dndEnabled);
}
```

**Step 4（视情况）：禁用 fcitx5 起手音**

```bash
# fcitx5 GUI：fcitx5-configtool → 全局选项 → "启用提示音" 关
# 或写配置：
sed -i 's/^EnableNotificationSound=True/EnableNotificationSound=False/' \
    ~/.config/fcitx5/conf/notifications.conf 2>/dev/null
```

**验收**

```bash
# DND 关：
notify-send -h string:sound-name:message-new-instant "test"
# 应有声 + toast 弹出

# 打开 DND（点顶栏铃铛进 NotificationCenter，开 DND 开关）
# 再发：
notify-send -h string:sound-name:message-new-instant "test"
# 应无声 + 无 toast
```

应用层（QQ/微信/Telegram）的自播音如果 Step 1 排查到是它，**记录下来——这类得在应用内禁声**，shell 拦不住。

---

### T08 ⚠️ 修"很多地方都没有中文"——第 1 步：字体兜底 + DesktopEntry 本地化

**现象**
你原话："很多地方都没有中文"。包括：UI 文案全英、应用名英文、可能字符显示豆腐。

**真机现场**

| 项 | 状态 |
|---|---|
| `LANG` | `zh_CN.UTF-8` 全字段配齐 |
| `locale -a` | 含 `zh_CN.utf8` |
| `fc-list :lang=zh` | 85 条命中（noto-fonts-cjk 已装） |
| shell `qsTr` 调用 | **零** |
| `.ts/.qm` 翻译文件 | **无** |
| `assets/fonts/` | 只有 Material Icons |
| `Apps.qml` 读 `Name[zh_CN]` | **无** |

**含义**：系统字体已就位，问题 100% 在 shell QML。

**Step 1：shell 默认字体声明中文优先**

编辑 `tahoe-shell/shell.qml`，在 `ShellRoot { id: shell` 块内加：

```qml
// 全局默认字体（中文优先 → 拉丁 → emoji）
property string baseFontFamily: "Noto Sans CJK SC, Noto Sans, sans-serif"
property string monoFontFamily: "Noto Sans Mono CJK SC, Noto Sans Mono, monospace"
```

**Step 2：每个 Text 默认走 baseFontFamily**

最干净的方式是给所有组件加个引用。但工作量大，先做最小修改：在 `shell.qml` 顶部装 `QApplication` 字体：

```qml
//@ pragma UseQApplication
// 已有

Component.onCompleted: {
    // Qt 全局默认字体
    Qt.application.font = Qt.font({ family: shell.baseFontFamily, pixelSize: 13 });
}
```

注意：这只影响**未显式设 `font.family`** 的 Text。所有已设 `font.family: "Material Icons"` 的图标元素不变。

**Step 3：Apps.qml 优先显示本地化名**

编辑 `tahoe-shell/services/Apps.qml` 的 `appLabel` 函数（第 79 行附近）：

```qml
function appLabel(app) {
    if (!app) return "";
    // Quickshell DesktopEntry 应自动按 LANG 选 Name[zh_CN]；
    // 如果没生效，name 仍是英文，genericName 在某些 .desktop 是中文
    var primary = String(app.name || "").trim();
    var generic = String(app.genericName || "").trim();
    // 优先显示包含 CJK 字符的那个
    function hasCJK(s) { return /[一-鿿]/.test(s); }
    if (hasCJK(generic) && !hasCJK(primary)) return generic;
    return primary || generic;
}
```

如果 Quickshell 的 DesktopEntry 不暴露 `Name[zh_CN]`，需要 fallback 自己读 `.desktop` 文件——先不做，看 Step 2 完成后实际效果再说。

**重启 shell 验**

```bash
pkill quickshell && quickshell -p ~/.config/quickshell/tahoe &
```

**验收**
- 控制中心、菜单、Spotlight、Launchpad 等 UI 的英文文字现在用 Noto Sans CJK SC 渲染（字形可能微妙变化）。
- Launchpad/Spotlight 里的应用名，对 `.desktop` 提供中文 `Name[zh_CN]` 的应用（如"文件"、"终端"、"火狐浏览器"），显示中文名。

英文 UI 文案本身的翻译留给 T09。

---

### T09 ⚠️ 修"很多地方都没有中文"——第 2 步：UI 文案 qsTr + zh_CN 翻译

**目标**
让顶栏、控制中心、Spotlight、Launchpad、菜单、电源对话框等所有英文 UI 文字变中文。

**Step 1：全 shell 把硬编码 text 改成 qsTr**

逐个文件改。优先：

- `components/MenuPopup.qml`：`"Lock Screen" → qsTr("锁定屏幕")` 等所有菜单项
- `components/ControlCenter.qml`：`"Wi-Fi"`、`"Bluetooth"`、`"Display"`、`"Sound"`、`"Edit Controls"` 等
- `components/NotificationCenter.qml`：`"Do Not Disturb"`、`"Clear All"`、`"No Notifications"` 等
- `components/Spotlight.qml`：`"Search"`、`"No Results"` 等
- `components/Launchpad.qml`：`"Search"`、`"No Results"` 等
- `components/BatteryPopup.qml`：`"Power Adapter"`、`"Battery"`、`"Unavailable"` 等
- `components/Power.qml` 相关确认对话框文案
- `services/Battery.qml`：`stateLabel` 已在 T04 改成中文，跳过

举例改法（`MenuPopup.qml`）：

```qml
// 原
text: "Lock Screen"
// 改
text: qsTr("锁定屏幕")
```

**Step 2：生成翻译资源**

确保系统有 Qt6 工具：

```bash
sudo pacman -S --needed qt6-tools
```

新建 `tahoe-shell/i18n/tahoe.pro`：

```
SOURCES = ../shell.qml
SOURCES += $$files(../components/*.qml, true)
SOURCES += $$files(../services/*.qml, true)
TRANSLATIONS = tahoe_zh_CN.ts
```

生成：

```bash
cd tahoe-shell/i18n
lupdate-qt6 tahoe.pro
```

得到 `tahoe_zh_CN.ts`——大部分已是中文了（因为你直接写的中文），剩下纯翻译条目人工补完。

**Step 3：编译并 load**

```bash
lrelease-qt6 tahoe.pro
# 得到 tahoe_zh_CN.qm
```

`shell.qml` 加：

```qml
import QtCore   // QTranslator 不能从 QML 直接 load，但可以通过 C++ 入口；
                // Quickshell 也可能有自带的 LocaleHandler
```

Quickshell 0.3.0 是否支持运行时 QTranslator load 需要查文档；最简方案：

- 写一个最小 C++ shim（如果 Quickshell 接受 plugin），或
- 全部 qsTr 改成手动条件分支（中文环境直接写中文，英文环境查表）：

```qml
// shell.qml
readonly property bool isZh: Qt.locale().name.startsWith("zh")

function tr(key) {
    if (!isZh) return key;
    var dict = {
        "Lock Screen": "锁定屏幕",
        "Wi-Fi": "Wi-Fi",
        ...
    };
    return dict[key] || key;
}
```

更简洁的折中：直接把中文写死（项目本就是中文用户为主），不做 i18n 切换。少一层间接，省一周工作量。

**结论**
按性价比，**Step 1 改成直接写中文字面量** 而非 qsTr，最快。i18n 框架以后再补。命令简化为：

```bash
# 在每个组件文件里，把 "Lock Screen" 这类直接改成 "锁定屏幕"
# 不需要 lupdate/lrelease
```

**验收**
重启 shell。打开控制中心、点 Tahoe 菜单、点 Spotlight、点 NotificationCenter 的 DND 开关——所有可见英文文案变中文。

---

### T10 ⚠️ 试 useSpring（真机 GPU 应支持，spring 才是真正的"丝滑"）

**现象**
真机是 NVIDIA RTX 4070 Max-Q + AMD Raphael，`shell.qml:32 useSpring: false` 的"VM 纹理损坏"免责声明不适用。所有声称"已 spring 化"的动画当前实际是 NumberAnimation 离散 tween——感觉肯定差。

**Step 1：翻开关**

编辑 `tahoe-shell/shell.qml:32`：

```qml
property bool useSpring: true
```

重启 shell。

**Step 2：逐项观察 5 处**

| 项 | 应看到 |
|---|---|
| Dock magnification（鼠标横扫 Dock） | 图标连续涌动，邻居响应 |
| Dock 图标点击 | 1~1.5 次轻微 overshoot |
| ControlCenter 打开 | 锚点 TopRight scale 展开，微弱回弹 |
| MenuPopup 打开（点 Tahoe 菜单） | 锚点 TopLeft scale 展开，微弱回弹 |
| Launchpad 打开 | scale settle 有 spring 收尾 |

**Step 3：判断**

- ✅ 全部正常 → 默认就用 true，不需要再回退。可以删 shell.qml:24-32 那段"VM 警告"注释，写"真机默认 true"。
- ❌ Image 纹理变透明（NVIDIA Wayland 已知坑）→ 翻回 false，记录现象到 T11 处理。
- ⚠️ 部分项 OK 部分项坏 → 把坏的那项的 `Behavior on scale { enabled: root.useSpring; SpringAnimation {...} }` 改成走 NumberAnimation，spring 仅留给正常的。

**验收**
真机录屏 30 秒 Dock 横扫 + 3 次点击 + 3 次打开/关闭面板。回放看动画质感是否接近 macOS。

---

### T11 💎 修 Dock 邻居联动行波（如果 T10 spring 没问题）

**前置**：T10 spring 正常。

**现象**
即使 spring 开了，Dock magnification 仍是"每个图标独立放大"，邻居没动。Web 参考 `script.js:358-404` 的 margin 联动制造行波效应。当前实现 `Dock.qml:168-176` 注释明确"width must NOT depend on magnification → binding loop"。

**根因**
直接绑 width = f(magnification) 会循环。正确做法：用 transform scale 视觉缩放（不参与 layout），用 Row.spacing = f(maxAdjacentMagnification) 制造邻居挤出效果。

**改 `tahoe-shell/components/WindowButton.qml`**

把 width 固定（不依赖 magnification），scale 用 Transform 节点：

```qml
Item {
    id: root
    width: 56   // 逻辑宽度固定
    height: 56
    property real magnification: 1.0
    transform: [
        Scale {
            origin.x: root.width / 2
            origin.y: root.height   // 底对齐放大
            xScale: root.magnification
            yScale: root.magnification
        }
    ]
    // 渲染层（Image / 圆点 / 标签）
    ...
}
```

**改 `tahoe-shell/components/Dock.qml` 的 Row**

```qml
Row {
    id: dockRow
    spacing: 6 + maxNeighborMagnification * 4   // 邻居越大间距越大
    // maxNeighborMagnification 取 dockRow 内所有 WindowButton 的最大 magnification
    property real maxNeighborMagnification: {
        var max = 1.0;
        for (var i = 0; i < children.length; i++) {
            var c = children[i];
            if (c.magnification && c.magnification > max) max = c.magnification;
        }
        return max;
    }
}
```

注：上面 `maxNeighborMagnification` 的实现 QML 上要么用 ScriptModel 同步，要么用一个 Timer 节流——可能要小修。

**验收**
鼠标在 Dock 上横扫，看到中心图标最大、左右两边按距离递减、整条 Dock 间距随之扩张，形成"波沿 Dock 滚动"的视觉效果。

---

## 第二批完成检查点 ✅

- [ ] Launchpad 开合丝滑
- [ ] DND 真无声
- [ ] UI 中文化（除应用菜单/About/Settings 外）
- [ ] Dock 有行波（若 T10 spring 正常）

---

## 第三批：底座升级（让上层可以做更复杂功能）—— T12-T14

> 第二批做完 shell 看起来像样了，但底层有结构性短板，必须先补，否则后面 Stage Manager / 窗口预览 / Dock 真闭环都做不准。

---

### T12 ⚠️ NiriIpc 改事件流（替换 1.2 秒轮询）

**现象**
`services/NiriIpc.qml:24, 181-198` 现在每 1200 ms `spawn niri msg --json windows` 子进程。窗口几何/焦点变化最高 1.2 秒延迟，每秒 fork-exec 一次。

**改动**
把 `NiriIpc.qml` 改为单一 `Process { command: ["niri", "msg", "--json", "event-stream"] }`，stdout 按行解析。

`refresh()` / `Timer { interval: 1200 }` 删除。`refreshSoon()` 也删——事件驱动天然及时。

新结构（伪代码骨架）：

```qml
import Quickshell.Io

Process {
    id: eventStream
    running: true
    command: ["niri", "msg", "--json", "event-stream"]

    stdout: SplitParser {
        splitMarker: "\n"
        onRead: function(line) {
            try {
                var event = JSON.parse(line);
                root.handleEvent(event);
            } catch (e) {}
        }
    }

    onRunningChanged: {
        if (!running) {
            // 自动重连
            Qt.callLater(function() { eventStream.running = true; });
        }
    }
}

function handleEvent(event) {
    if (event.WindowsChanged)        root.handleWindowsChanged(event.WindowsChanged);
    if (event.WindowOpenedOrChanged) root.handleWindowUpsert(event.WindowOpenedOrChanged);
    if (event.WindowClosed)          root.handleWindowClosed(event.WindowClosed);
    if (event.WindowFocusChanged)    root.handleFocusChanged(event.WindowFocusChanged);
    if (event.WorkspacesChanged)     root.handleWorkspacesChanged(event.WorkspacesChanged);
    if (event.WindowLayoutsChanged)  root.handleLayoutsChanged(event.WindowLayoutsChanged);
}
```

具体 event 名/字段对 `niri msg --json event-stream` 实测一遍记录到 `services/NiriIpc.qml` 文件头注释。

**验收**

```bash
top -p $(pgrep quickshell)
# 之前每秒会看到 niri 子进程闪现；现在常驻一个 niri event-stream，CPU≈0
```

把窗口拖一下，Dock 上的活动指示器应**立即**跟上（不是延迟到下个 1.2 秒）。

---

### T13 ⚠️ 合并 Niri.qml + NiriIpc.qml → Windows.qml 统一窗口模型

**前置**：T12 完成。

**现象**
当前 `services/Niri.qml` 同时读 `ToplevelManager` 和 `NiriIpc`，两边数据可能不一致（focus 谁说了算？geometry 哪边准？）。后续 Stage Manager、窗口预览、Dock target rect 都需要单一数据源。

**改动**
- 新建 `services/Windows.qml`，定义统一 Window 对象：`{ id, appId, title, workspace, output, focused, minimized, geometry: {x,y,w,h}, toplevel }`
- 主键用 niri id（IPC 给的），`toplevel` 持有 Quickshell ToplevelManager 对应对象（用于 activate/close action）
- 提供 `activate(id)` / `minimize(id)` / `restore(id)` / `setRectangle(id, x, y, w, h)` 接口
- 老 `Niri.qml` 暴露的 `windowList`、`focusedWindow`、`recentWindowList` 一并迁过来
- 删 `Niri.qml`、`NiriIpc.qml`，shell.qml 改实例 `Windows`

**验收**
Dock、TopBar、所有窗口相关 UI 改读 `Windows` 服务，行为完全一致。代码总量减少。

---

### T14 ⚠️ Snap 补四向（下半屏 + 四角）

**前置**：需要改 niri fork（Rust）。

**位置**
`niri/src/layout/mod.rs:710 compute_snap_target` 当前只判 Top（全屏）/Left/Right。

**改动**
在 `compute_snap_target` 内加：

```rust
let bottom = working_area.loc.y + working_area.size.h;
let half_height = working_area.size.h / 2.;

// Bottom 半屏
if pointer_pos.y >= bottom - threshold && pointer_pos.x > left + threshold && pointer_pos.x < right - threshold {
    return Some(SnapTarget {
        edge: SnapEdge::Bottom,
        rect: Rectangle::new(
            Point::from((left, top + half_height)),
            Size::from((working_area.size.w, half_height)),
        ),
    });
}

// 四角（左上 / 右上 / 左下 / 右下，1/4 面积）
if pointer_pos.x <= left + threshold && pointer_pos.y <= top + threshold {
    return Some(SnapTarget {
        edge: SnapEdge::TopLeft,
        rect: Rectangle::new(working_area.loc, Size::from((half_width, half_height))),
    });
}
// ...右上、左下、右下同理
```

`SnapEdge` enum 加 `Bottom, TopLeft, TopRight, BottomLeft, BottomRight`。

需要同步改 `render_snap_preview_for_output`（已有的圆角毛玻璃预览渲染）确保新方向能画。

**验收**
拖窗口到屏幕底部、四角——出现 1/2 屏 / 1/4 屏预览。松手吸附。

---

## 第三批完成检查点 ✅

- [ ] niri 子进程不再每秒 spawn
- [ ] 拖窗口 → Dock 立即响应
- [ ] 拖到底部 / 四角能吸附

---

## 第四批：补桌面入口（让它像桌面）—— T15-T20

---

### T15 ⚠️ 锁屏自有 UI

新建 `tahoe-shell/components/LockScreen.qml`，接 ext-session-lock 协议（niri 上游 `src/handlers/mod.rs:460` 已实现）。Tahoe 风格：壁纸 + 时钟 + 头像 + 密码框 + 玻璃面板。

`services/Power.qml:78-85` 锁屏命令改成 shell 自己的 `loginctl lock-session`（loginctl 触发 → systemd-logind → ext-session-lock → shell.qml 的 LockScreen 起来），不再调外部 swaylock。

---

### T16 ⚠️ 截屏选区 + 标注

新建 `tahoe-shell/components/Screenshot.qml`：
- 启动选区 `grim + slurp`，截屏到 `~/Pictures/Screenshots/`
- 启动后 toast 提示"截图已保存"，提供"标注"动作 → 开 `swappy` 或自研标注面板
- Spotlight 增 `Screenshot` provider；顶栏加小按钮

包：

```bash
sudo pacman -S grim slurp swappy
```

---

### T17 ⚠️ 输入法状态指示（T02 后顺理成章）

新建 `services/InputMethod.qml`，DBus 跟 `org.fcitx.Fcitx5` 通信读当前 IM 状态（EN/中拼/五笔）。`TopBar.qml` 加图标。

---

### T18 ⚠️ Dock 右段 + 拖拽（Downloads/Trash + 重排 + 固定）

- 现有 `Dock.qml` 分隔线右侧加 Downloads（点开 `xdg-open ~/Downloads`）和 Trash（`gio open trash:///`）
- Repeater 改 ListView 支持 DropArea 重排
- 拖文件到 Dock 图标：DropArea 接 `xdg-open` 传文件路径
- 固定 app 列表持久化到 `~/.config/quickshell/tahoe/pinned-apps.json`

---

### T19 ⚠️ 应用菜单 dbus-menu PoC

新建 `services/AppMenu.qml`：
- DBus 跟 `com.canonical.AppMenu.Registrar` 通信
- 跟 `T13 Windows` 服务的 `focusedWindow` 联动，拿当前窗口的 menu object path
- 用 `QsMenuOpener` 渲染（类似 `TrayMenu.qml`）

`TopBar.qml` 当前 Tahoe 菜单后面加一行"动态应用菜单"。

---

### T20 ⚠️ 夜间模式 / 深浅切换

- ControlCenter 现有"深色模式"按钮 `:241 enabled: false` 启用
- 接 `gammastep` 控制色温（夜间模式）
- 接 `gsettings org.gnome.desktop.interface color-scheme prefer-dark` 切 GTK 深色
- 接 `qt6ct` 或 `kvantum` 切 Qt 深色
- shell.qml 加 `property bool darkMode`，影响所有面板色

---

## 第四批完成检查点 ✅

- [ ] 自有锁屏
- [ ] 截屏闭环（截 → 标 → 复制/保存）
- [ ] 输入法图标
- [ ] Dock 完整（含 Downloads/Trash/重排/固定）
- [ ] 顶栏有应用菜单
- [ ] 深浅切换

---

## 第五批：拟真深水 —— T21-T25

> 上面做完已经能日用。这一批是把"能用"做成"惊艳"。

---

### T21 💎 Spotlight provider 架构

新建 `services/Search.qml` 定义 provider 接口：

```qml
property var providers: [appProvider, calcProvider, cmdProvider, fileProvider, settingsProvider]
```

每个 provider 实现 `function query(text) → [{id,title,subtitle,icon,score,activate()}]`。Spotlight UI 读 Search.qml。

工作量 3-5 天。先做 Apps + Calc + Cmd 三个，File 后置。

---

### T22 💎 Stage Manager / Spaces UI

前置：T13 Windows 服务。在屏幕左侧建 `StageManager.qml` panel，显示其他 workspace 的窗口缩略（通过 niri screencast 抓 thumbnail），点击切到那个 workspace。

---

### T23 💎 niri window-open/close 真做 scale

现 `config/niri/tahoe-phase0.kdl:163-194` 的 custom shader 只乘 opacity。改成 scale 0.96→1 + opacity 0→1（窗口打开）/ 1→0.96 + 1→0（关闭）。

需要改 shader 用 `niri_clamped_progress` 控制 scale matrix（uniform 应用层面有限制，可能要看 niri shader API）。

---

### T24 💎 触控板手势 → UI

niri 内部已有手势框架。映射：
- 三指上滑 → niri overview（Mission Control 感）
- 四指左右 → 切 workspace
- 三指捏合 → Launchpad

需 niri config 加 `gestures { ... }` 或写 input handler。

---

### T25 💎 Genie minimize + Dock target rect

文档原 Phase 5。需要 niri shader mesh deformation。工作量极大（2-3 周）。仅在 T01-T24 全部完成且有余力时做。

---

## 第五批完成检查点 ✅

到这就是"完整桌面"。

---

## 任务依赖图

```
T01 → T02 → T03 → T04 → T05 → T05.5    （第一批，严格顺序）
        ↓
T06 → T07 → T08 → T09 → T10 → T11   （第二批）
        ↓
T12 → T13 → T14    （第三批，T13 前置 T12）
        ↓
T15 → T16 → T17 → T18 → T19 → T20   （第四批，可并行但建议顺序做）
        ↓
T21 → T22 → T23 → T24 → T25    （第五批）
```

并行例外：T08/T09/T10/T11 之间互不阻塞，可同时改不同文件；但建议仍然按编号顺序做完一个测一个再下一个。

---

## 单人节奏估算

| 批 | 任务数 | 累计人天 | 累计周（5d/w） |
|---|---|---|---|
| 第一批 T01-T05.5 | 6 | 2.5 | 0.5 |
| 第二批 T06-T11 | 6 | 7 | 1.4 |
| 第三批 T12-T14 | 3 | 11 | 2.2 |
| 第四批 T15-T20 | 6 | 26 | 5.2 |
| 第五批 T21-T25 | 5 | 61 | 12.2 |

**第一批 2-3 天搞定**（pacman 装包 + Battery.qml 改 + Wi-Fi 弹层新增 320 行 QML）。
**第二批 1-1.5 周**。
**第三批 1.5 周**。
**前三批做完——shell 已可日用。**

---

## 不该做的事（再强调）

- 不重写 Nautilus/Thunderbird/邮件客户端等大型应用——是 GNOME/KDE 工作量级。
- 不做服务端窗口装饰（红黄绿）——破坏 Linux Wayland 应用兼容性。
- 不追求 macOS 像素级复刻——抓"丝滑 + 玻璃 + 信息架构"。
- 不在 T01-T05 完成前做任何动画/视觉优化——根都没站稳，叶子白做。

---

## 单点速查

| 你想知道 | 看哪里 |
|---|---|
| 一个 bug 怎么修 | 找对应 T 编号，从"现象"读到"验收" |
| 总体进度 | 看每批的 "完成检查点 ✅" |
| 当前阻塞 | 现在停在哪个 T 编号，向前找前置 |
| 后续讨论 | 直接说 "T07 做完了 / T13 卡在 xxx" |
