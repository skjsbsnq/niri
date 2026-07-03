.pragma library

var defaultPanelId = "wifi";

var panels = [
    {
        "id": "wifi",
        "title": "Wi-Fi",
        "subtitle": "无线网络、飞行模式和热点",
        "icon": "\ue63e",
        "keywords": ["wifi", "wi-fi", "wireless", "wlan", "无线", "网络", "热点", "飞行模式"],
        "group": "connectivity",
        "component": "wifi",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "network",
        "title": "网络",
        "subtitle": "有线网络、VPN 和代理",
        "icon": "\ue1bd",
        "keywords": ["network", "ethernet", "wired", "vpn", "proxy", "有线", "网络", "代理"],
        "group": "connectivity",
        "component": "network",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [{"id": "wifi", "title": "Wi-Fi"}]
    },
    {
        "id": "bluetooth",
        "title": "蓝牙",
        "subtitle": "蓝牙适配器和设备",
        "icon": "\ue1a7",
        "keywords": ["bluetooth", "bluez", "蓝牙", "配对", "设备"],
        "group": "connectivity",
        "component": "bluetooth",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "displays",
        "title": "显示器",
        "subtitle": "显示输出、夜览和色温",
        "icon": "\ue333",
        "keywords": ["display", "monitor", "screen", "scale", "night light", "显示", "显示器", "缩放", "输出", "夜览", "色温"],
        "group": "hardware",
        "separatorBefore": true,
        "component": "displays",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [{"id": "niri-input", "title": "输入与显示"}]
    },
    {
        "id": "sound",
        "title": "声音",
        "subtitle": "输出、输入和音量",
        "icon": "\ue050",
        "keywords": ["sound", "audio", "volume", "microphone", "声音", "音量", "麦克风", "输入", "输出"],
        "group": "hardware",
        "component": "sound",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "power",
        "title": "电源",
        "subtitle": "电池、电源模式和空闲锁定",
        "icon": "\ue8b2",
        "keywords": ["power", "battery", "brightness", "idle", "电源", "电池", "亮度", "锁定"],
        "group": "hardware",
        "component": "power",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [{"id": "health", "title": "系统健康"}]
    },
    {
        "id": "multitasking",
        "title": "多任务",
        "subtitle": "窗口、工作区、Dock 和动画",
        "icon": "\ue8f9",
        "keywords": ["multitasking", "window", "workspace", "dock", "overview", "多任务", "窗口", "工作区", "dock", "动画"],
        "group": "personal",
        "component": "multitasking",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [
            {"id": "niri-layout", "title": "布局与窗口"},
            {"id": "dock", "title": "Dock"},
            {"id": "niri-animations", "title": "动画"},
            {"id": "dynamic-island", "title": "灵动岛"}
        ]
    },
    {
        "id": "appearance",
        "title": "外观",
        "subtitle": "深浅色、壁纸和图标主题",
        "icon": "\ue51c",
        "keywords": ["appearance", "theme", "icons", "wallpaper", "background", "外观", "主题", "图标", "壁纸", "背景"],
        "group": "personal",
        "component": "appearance",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [{"id": "wallpaper", "title": "壁纸"}]
    },
    {
        "id": "apps",
        "title": "应用",
        "subtitle": "默认应用、应用列表和权限",
        "icon": "\ue5c3",
        "keywords": ["apps", "applications", "default apps", "permissions", "应用", "默认应用", "权限"],
        "group": "apps",
        "separatorBefore": true,
        "component": "apps",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": []
    },
    {
        "id": "notifications",
        "title": "通知",
        "subtitle": "勿扰和通知历史",
        "icon": "\ue7f4",
        "keywords": ["notifications", "dnd", "通知", "勿扰", "历史"],
        "group": "apps",
        "component": "notifications",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "search",
        "title": "搜索",
        "subtitle": "系统搜索和索引入口",
        "icon": "\ue8b6",
        "keywords": ["search", "index", "spotlight", "搜索", "索引"],
        "group": "apps",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "online-accounts",
        "title": "在线账号",
        "subtitle": "账号登录和同步服务",
        "icon": "\ue7fd",
        "keywords": ["online accounts", "accounts", "sync", "在线账号", "账户", "同步"],
        "group": "apps",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "sharing",
        "title": "共享",
        "subtitle": "远程访问、文件共享和媒体共享",
        "icon": "\ue80d",
        "keywords": ["sharing", "remote", "file sharing", "共享", "远程", "文件共享"],
        "group": "apps",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "wellbeing",
        "title": "健康使用",
        "subtitle": "屏幕时间和休息提醒",
        "icon": "\ue87d",
        "keywords": ["wellbeing", "screen time", "break", "健康使用", "屏幕时间", "休息"],
        "group": "apps",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "mouse-touchpad",
        "title": "鼠标与触摸板",
        "subtitle": "指针、滚动和触摸板手势",
        "icon": "\ue323",
        "keywords": ["mouse", "touchpad", "pointer", "scroll", "鼠标", "触摸板", "指针", "滚动"],
        "group": "input",
        "separatorBefore": true,
        "component": "mouse-touchpad",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [{"id": "niri-input", "title": "输入与显示"}]
    },
    {
        "id": "keyboard",
        "title": "键盘",
        "subtitle": "输入、重复按键和快捷键",
        "icon": "\ue312",
        "keywords": ["keyboard", "shortcuts", "binds", "repeat", "input method", "键盘", "快捷键", "按键重复", "输入法"],
        "group": "input",
        "component": "keyboard",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [
            {"id": "niri-keyboard", "title": "快捷键"},
            {"id": "niri-input", "title": "输入与显示"},
            {"id": "screenshot", "title": "截图"}
        ]
    },
    {
        "id": "color",
        "title": "色彩管理",
        "subtitle": "显示器和设备色彩配置",
        "icon": "\ue3b7",
        "keywords": ["color", "icc", "profile", "色彩", "颜色", "校色"],
        "group": "input",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "printers",
        "title": "打印机",
        "subtitle": "打印设备和队列",
        "icon": "\ue8ad",
        "keywords": ["printers", "printing", "cups", "打印机", "打印", "队列"],
        "group": "input",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "accessibility",
        "title": "辅助功能",
        "subtitle": "无障碍访问和交互辅助",
        "icon": "\ue84e",
        "keywords": ["accessibility", "universal access", "a11y", "辅助功能", "无障碍"],
        "group": "system",
        "separatorBefore": true,
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "privacy",
        "title": "隐私与安全",
        "subtitle": "权限、位置、摄像头和麦克风",
        "icon": "\ue897",
        "keywords": ["privacy", "security", "permissions", "camera", "microphone", "location", "隐私", "安全", "权限", "摄像头", "麦克风", "位置"],
        "group": "system",
        "component": "feature",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "system",
        "title": "系统",
        "subtitle": "系统健康、启动项、天气和关于",
        "icon": "\ue88e",
        "keywords": ["system", "about", "health", "startup", "weather", "系统", "关于", "健康", "启动项", "天气"],
        "group": "system",
        "component": "system",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true,
        "related": [
            {"id": "health", "title": "系统健康"},
            {"id": "about", "title": "关于"},
            {"id": "startup", "title": "启动项"},
            {"id": "weather", "title": "天气"}
        ]
    },
    {
        "id": "niri",
        "title": "Niri / Window Manager",
        "subtitle": "niri 和 Tahoe 专用窗口管理设置",
        "icon": "\ue871",
        "keywords": ["niri", "window manager", "tahoe", "window", "layout", "niri", "窗口管理", "布局", "玻璃", "动画"],
        "group": "system",
        "component": "niri",
        "statusBadge": "",
        "sidebar": true,
        "visible": true,
        "enabled": true
    },
    {
        "id": "wallpaper",
        "title": "壁纸",
        "subtitle": "静态图片和动态壁纸",
        "icon": "\ue40b",
        "keywords": ["wallpaper", "background", "壁纸", "背景", "动态壁纸"],
        "group": "legacy",
        "parent": "appearance",
        "component": "wallpaper",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "dynamic-island",
        "title": "灵动岛",
        "subtitle": "顶栏中心胶囊、点击行为和展开偏好",
        "icon": "\ueb81",
        "keywords": ["dynamic island", "top bar", "island", "灵动岛", "顶栏", "胶囊"],
        "group": "legacy",
        "parent": "multitasking",
        "component": "dynamic-island",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "screenshot",
        "title": "截图",
        "subtitle": "保存目录、复制和通知动作",
        "icon": "\ue3b0",
        "keywords": ["screenshot", "screen capture", "截图", "录屏", "保存目录"],
        "group": "legacy",
        "parent": "keyboard",
        "component": "screenshot",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "dock",
        "title": "Dock",
        "subtitle": "窗口按钮显示偏好",
        "icon": "\ue8d0",
        "keywords": ["dock", "panel", "taskbar", "dock", "程序坞", "任务栏"],
        "group": "legacy",
        "parent": "multitasking",
        "component": "dock",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "weather",
        "title": "天气",
        "subtitle": "定位、手动覆盖和温度单位",
        "icon": "\ue2bd",
        "keywords": ["weather", "forecast", "temperature", "天气", "定位", "温度"],
        "group": "legacy",
        "parent": "system",
        "component": "weather",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "startup",
        "title": "启动项",
        "subtitle": "XDG autostart 和会话备注",
        "icon": "\ue89e",
        "keywords": ["startup", "autostart", "login", "启动项", "自启动", "登录"],
        "group": "legacy",
        "parent": "system",
        "component": "startup",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "health",
        "title": "系统健康",
        "subtitle": "依赖项、服务和 Tahoe 会话状态",
        "icon": "\ue868",
        "keywords": ["health", "status", "diagnostics", "系统健康", "状态", "诊断", "依赖"],
        "group": "legacy",
        "parent": "system",
        "component": "health",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "about",
        "title": "关于",
        "subtitle": "Tahoe Shell、niri、Quickshell 和当前会话",
        "icon": "\ue88e",
        "keywords": ["about", "version", "session", "关于", "版本", "会话"],
        "group": "legacy",
        "parent": "system",
        "component": "about",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "niri-layout",
        "title": "布局与窗口",
        "subtitle": "niri 间距、焦点环、边框、阴影与 snap 助手",
        "icon": "\ue871",
        "keywords": ["niri", "layout", "focus", "border", "shadow", "snap", "布局", "窗口", "焦点环", "边框", "阴影"],
        "group": "legacy",
        "parent": "multitasking",
        "component": "niri-layout",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "niri-glass",
        "title": "玻璃材质",
        "subtitle": "tahoe-glass 材质、折射与全局模糊",
        "icon": "\ue3a3",
        "keywords": ["glass", "blur", "refraction", "玻璃", "模糊", "折射"],
        "group": "legacy",
        "parent": "niri",
        "component": "niri-glass",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "niri-input",
        "title": "输入与显示",
        "subtitle": "键盘、触摸板与显示器（输出只读）",
        "icon": "\ue312",
        "keywords": ["input", "display", "keyboard", "touchpad", "输入", "显示", "键盘", "触摸板"],
        "group": "legacy",
        "parent": "keyboard",
        "component": "niri-input",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "niri-animations",
        "title": "动画",
        "subtitle": "工作区、窗口移动/缩放与概览的弹簧动画",
        "icon": "\ue8c1",
        "keywords": ["animation", "spring", "workspace", "动画", "弹簧", "工作区"],
        "group": "legacy",
        "parent": "multitasking",
        "component": "niri-animations",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "niri-keyboard",
        "title": "快捷键",
        "subtitle": "niri binds 只读查看（任务切换 binds 受保护）",
        "icon": "\ue8ef",
        "keywords": ["keyboard", "shortcuts", "binds", "快捷键", "键盘", "绑定"],
        "group": "legacy",
        "parent": "keyboard",
        "component": "niri-keyboard",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    },
    {
        "id": "overview",
        "title": "概览",
        "subtitle": "旧版 Tahoe 偏好摘要，保留为兼容入口",
        "icon": "\ue8b8",
        "keywords": ["overview", "summary", "概览", "摘要"],
        "group": "legacy",
        "parent": "system",
        "component": "overview",
        "statusBadge": "",
        "sidebar": false,
        "visible": true,
        "enabled": true
    }
];

var CAPABILITY_NATIVE = "native";
var CAPABILITY_PROBE = "probe";
var CAPABILITY_EXTERNAL = "external";
var CAPABILITY_READONLY = "readonly";

var panelCapabilities = {
    "wifi": {
        "capability": CAPABILITY_NATIVE,
        "backend": "NetworkManager via Controls service",
        "externalPanel": "wifi",
        "writeScope": "Wi-Fi 开关、扫描、连接、忘记网络和热点动作"
    },
    "network": {
        "capability": CAPABILITY_NATIVE,
        "backend": "NetworkManager via NetworkSettings service",
        "externalPanel": "network",
        "writeScope": "有线连接、VPN profile 和 proxy 的 NetworkManager 写入"
    },
    "bluetooth": {
        "capability": CAPABILITY_NATIVE,
        "backend": "BlueZ via Controls service",
        "externalPanel": "bluetooth",
        "writeScope": "蓝牙开关、扫描、配对、连接和信任设备"
    },
    "displays": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py and Appearance service",
        "externalPanel": "display",
        "writeScope": "输出缩放和夜览；VRR 保持 guardrail 只读"
    },
    "sound": {
        "capability": CAPABILITY_NATIVE,
        "backend": "PipeWire/WirePlumber via Sound service",
        "externalPanel": "sound",
        "writeScope": "音量、静音、默认输入输出和设备端口"
    },
    "power": {
        "capability": CAPABILITY_NATIVE,
        "backend": "UPower, powerprofilesctl and Tahoe session settings",
        "externalPanel": "power",
        "writeScope": "亮度、电源模式和空闲锁定偏好"
    },
    "multitasking": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe settings and niri settings",
        "externalPanel": "",
        "writeScope": "窗口、工作区、Dock、动画和灵动岛偏好入口"
    },
    "appearance": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe Appearance service and desktop theme commands",
        "externalPanel": "appearance",
        "writeScope": "深浅色、图标主题、壁纸和夜览偏好"
    },
    "apps": {
        "capability": CAPABILITY_NATIVE,
        "backend": "apps_settings_probe.py, xdg-mime and portal stores",
        "externalPanel": "applications",
        "writeScope": "默认应用可写；权限行按 sandbox enforceability 显示只读或可管理范围"
    },
    "notifications": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe Notifications service",
        "externalPanel": "notifications",
        "writeScope": "勿扰、通知历史和 Tahoe 通知偏好"
    },
    "search": {
        "capability": CAPABILITY_PROBE,
        "backend": "Tahoe Search service plus optional tracker3 probe",
        "externalPanel": "search",
        "writeScope": "只显示索引后端状态；搜索 provider 排序和索引配置未在此页写入",
        "featureIds": ["search-index"]
    },
    "online-accounts": {
        "capability": CAPABILITY_EXTERNAL,
        "backend": "GNOME Online Accounts probe",
        "externalPanel": "online-accounts",
        "writeScope": "Tahoe 不保存账号凭据；账号添加和同步由外部设置处理",
        "featureIds": ["online-accounts", "gnome-control-center"]
    },
    "sharing": {
        "capability": CAPABILITY_PROBE,
        "backend": "OpenSSH, Avahi, Samba and Rygel probes",
        "externalPanel": "sharing",
        "writeScope": "只探测共享后端；不写入远程登录、发现、文件共享或媒体共享配置",
        "featureIds": ["remote-login", "discovery", "file-sharing", "media-sharing"]
    },
    "wellbeing": {
        "capability": CAPABILITY_READONLY,
        "backend": "Tahoe session state; no screen-time backend",
        "externalPanel": "",
        "writeScope": "屏幕时间只读说明；页面仅暴露已有勿扰和空闲锁定状态"
    },
    "mouse-touchpad": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py input writes",
        "externalPanel": "mouse",
        "writeScope": "指针、滚动和触摸板输入偏好"
    },
    "keyboard": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Input method service, Tahoe settings and niri read-only binds",
        "externalPanel": "keyboard",
        "writeScope": "输入法、重复按键和相关入口；niri binds 本页不写"
    },
    "color": {
        "capability": CAPABILITY_EXTERNAL,
        "backend": "colord probe via colormgr",
        "externalPanel": "color",
        "writeScope": "只探测 colord；ICC profile 管理由外部设置处理",
        "featureIds": ["color"]
    },
    "printers": {
        "capability": CAPABILITY_EXTERNAL,
        "backend": "CUPS probe via lpstat",
        "externalPanel": "printers",
        "writeScope": "只探测打印服务；设备和队列管理由外部设置处理",
        "featureIds": ["printers"]
    },
    "accessibility": {
        "capability": CAPABILITY_EXTERNAL,
        "backend": "GNOME accessibility gsettings probe",
        "externalPanel": "universal-access",
        "writeScope": "只探测无障碍 schema；具体辅助功能由外部设置处理",
        "featureIds": ["accessibility"]
    },
    "privacy": {
        "capability": CAPABILITY_READONLY,
        "backend": "xdg-desktop-portal and portal permission store probes",
        "externalPanel": "privacy",
        "writeScope": "隐私总览只读；应用权限写入范围由 Apps 页按 sandbox 类型显式限定",
        "featureIds": ["portal-permissions", "desktop-portal"]
    },
    "system": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe settings and status services",
        "externalPanel": "info-overview",
        "writeScope": "系统健康、启动项、天气和关于入口"
    },
    "niri": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py whitelist writes",
        "externalPanel": "",
        "writeScope": "niri 布局、玻璃、输入和动画白名单字段；binds 保持只读"
    },
    "wallpaper": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe settings and wallpaper processes",
        "externalPanel": "background",
        "writeScope": "静态壁纸、动态壁纸和外部壁纸命令偏好"
    },
    "dynamic-island": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe settings",
        "externalPanel": "",
        "writeScope": "顶栏中心胶囊、点击行为和展开偏好"
    },
    "screenshot": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe screenshot command pipeline",
        "externalPanel": "",
        "writeScope": "截图保存目录、复制和通知动作偏好"
    },
    "dock": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe settings and Windows service",
        "externalPanel": "",
        "writeScope": "Dock 窗口标题、任务按钮和最小化窗口显示偏好"
    },
    "weather": {
        "capability": CAPABILITY_NATIVE,
        "backend": "Tahoe Weather service",
        "externalPanel": "",
        "writeScope": "定位、手动城市和温度单位偏好"
    },
    "startup": {
        "capability": CAPABILITY_NATIVE,
        "backend": "XDG autostart manager and Tahoe settings",
        "externalPanel": "",
        "writeScope": "列出、添加、启用、停用和移除用户 autostart .desktop 覆盖；不写系统目录"
    },
    "health": {
        "capability": CAPABILITY_PROBE,
        "backend": "CommandRunner, SystemFeatures and SystemStatus probes",
        "externalPanel": "",
        "writeScope": "只读依赖、服务和 Tahoe 会话状态探测"
    },
    "about": {
        "capability": CAPABILITY_READONLY,
        "backend": "Tahoe, niri and Quickshell runtime metadata",
        "externalPanel": "",
        "writeScope": "只读版本、会话和组件信息"
    },
    "niri-layout": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py whitelist writes",
        "externalPanel": "",
        "writeScope": "间距、焦点环、边框、阴影和 snap helper 白名单字段"
    },
    "niri-glass": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py glass whitelist writes",
        "externalPanel": "",
        "writeScope": "Tahoe glass、模糊、折射和材质参数白名单字段"
    },
    "niri-input": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py input whitelist writes",
        "externalPanel": "",
        "writeScope": "键盘和触摸板输入字段；输出信息保持只读"
    },
    "niri-animations": {
        "capability": CAPABILITY_NATIVE,
        "backend": "niri_settings_tool.py animation whitelist writes",
        "externalPanel": "",
        "writeScope": "工作区、窗口移动、缩放和概览动画白名单字段"
    },
    "niri-keyboard": {
        "capability": CAPABILITY_READONLY,
        "backend": "niri_settings_tool.py binds enumeration",
        "externalPanel": "",
        "writeScope": "只读查看 niri binds；GUI 不写 binds 权威块"
    },
    "overview": {
        "capability": CAPABILITY_READONLY,
        "backend": "Tahoe settings summary",
        "externalPanel": "",
        "writeScope": "兼容入口，只读展示旧版 Tahoe 偏好摘要"
    }
};

var aliases = {
    "settings": "wifi",
    "general": "system",
    "applications": "apps",
    "background": "appearance",
    "mouse": "mouse-touchpad",
    "touchpad": "mouse-touchpad",
    "universal-access": "accessibility",
    "privacy-security": "privacy"
};

function normalizeText(value) {
    return String(value || "").toLowerCase().trim();
}

function normalizedCapability(value) {
    var key = String(value || CAPABILITY_NATIVE).trim().toLowerCase();
    if (key === CAPABILITY_NATIVE || key === CAPABILITY_PROBE || key === CAPABILITY_EXTERNAL || key === CAPABILITY_READONLY)
        return key;
    return CAPABILITY_NATIVE;
}

function capabilityLabel(value) {
    var key = normalizedCapability(value);
    if (key === CAPABILITY_NATIVE)
        return "原生页面";
    if (key === CAPABILITY_PROBE)
        return "功能探测";
    if (key === CAPABILITY_EXTERNAL)
        return "外部设置";
    if (key === CAPABILITY_READONLY)
        return "只读能力";
    return "原生页面";
}

function capabilityDetail(value) {
    var key = normalizedCapability(value);
    if (key === CAPABILITY_NATIVE)
        return "Tahoe 提供页面和可控写入范围";
    if (key === CAPABILITY_PROBE)
        return "Tahoe 只探测后端状态，不写入该系统域配置";
    if (key === CAPABILITY_EXTERNAL)
        return "Tahoe 保留入口和状态说明，具体配置交给外部设置";
    if (key === CAPABILITY_READONLY)
        return "Tahoe 只展示状态或受限入口，不伪装成完整控制面";
    return "";
}

function capabilityIcon(value) {
    var key = normalizedCapability(value);
    if (key === CAPABILITY_NATIVE)
        return "\ue86c";
    if (key === CAPABILITY_PROBE)
        return "\ue8b6";
    if (key === CAPABILITY_EXTERNAL)
        return "\ue89e";
    if (key === CAPABILITY_READONLY)
        return "\ue8f5";
    return "\ue86c";
}

function metadataFor(panel) {
    if (!panel || !panel.id)
        return {};
    return panelCapabilities[panel.id] || {};
}

function decoratedPanel(panel) {
    if (!panel)
        return null;

    var out = {};
    for (var key in panel)
        out[key] = panel[key];

    var meta = metadataFor(panel);
    out.capability = normalizedCapability(meta.capability);
    out.backend = String(meta.backend || "");
    out.externalPanel = String(meta.externalPanel || "");
    out.writeScope = String(meta.writeScope || "");
    out.featureIds = meta.featureIds || [];
    return out;
}

function panelById(id) {
    var key = String(id || "");
    for (var i = 0; i < panels.length; i++) {
        if (panels[i].id === key)
            return panels[i];
    }
    return null;
}

function resolveId(id) {
    var key = String(id || "").trim();
    if (key.length === 0)
        return defaultPanelId;
    if (aliases[key])
        key = aliases[key];
    return panelById(key) ? key : defaultPanelId;
}

function resolvedPanel(id) {
    return decoratedPanel(panelById(resolveId(id)) || panels[0]);
}

function parentId(id) {
    var panel = resolvedPanel(id);
    if (panel.parent)
        return resolveId(panel.parent);
    return panel.id;
}

function pageIndex(id) {
    var key = resolveId(id);
    for (var i = 0; i < panels.length; i++) {
        if (panels[i].id === key)
            return i;
    }
    return 0;
}

function title(id) {
    return resolvedPanel(id).title;
}

function subtitle(id) {
    return resolvedPanel(id).subtitle;
}

function capability(id) {
    return resolvedPanel(id).capability;
}

function backend(id) {
    return resolvedPanel(id).backend;
}

function externalPanel(id) {
    return resolvedPanel(id).externalPanel;
}

function writeScope(id) {
    return resolvedPanel(id).writeScope;
}

function featureIds(id) {
    return resolvedPanel(id).featureIds || [];
}

function matchesPanel(panel, query) {
    if (!panel || query.length === 0)
        return true;

    var info = decoratedPanel(panel);
    var haystack = [
        info.id,
        info.title,
        info.subtitle,
        info.group,
        info.statusBadge || "",
        info.capability || "",
        info.backend || "",
        info.externalPanel || "",
        info.writeScope || ""
    ];
    var keywords = info.keywords || [];
    for (var i = 0; i < keywords.length; i++)
        haystack.push(keywords[i]);

    return normalizeText(haystack.join(" ")).indexOf(query) >= 0;
}

function sidebarItems(query) {
    var q = normalizeText(query);
    var out = [];

    for (var i = 0; i < panels.length; i++) {
        var panel = panels[i];
        if (panel.visible === false)
            continue;

        if (q.length === 0) {
            if (panel.sidebar !== true)
                continue;
            if (panel.separatorBefore)
                out.push({"separator": true, "id": "separator-" + panel.id});
            out.push(decoratedPanel(panel));
        } else if (matchesPanel(panel, q)) {
            out.push(decoratedPanel(panel));
        }
    }

    return out;
}
