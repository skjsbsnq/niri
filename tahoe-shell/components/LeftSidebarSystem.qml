pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// LS06: 左侧边栏「系统」标签页内容。
//
// 视图职责：CPU/GPU 双弧仪表、Net/RAM/Load 折线图（视图内历史 + 平滑最大值 +
// 滑入动画）、属性网格、磁盘/电池卡、进程列表（分类/排序/搜索）。
//
// 数据职责：只读 services/SystemStats.qml（id: systemStats）暴露的属性与
// fastDataChanged/mediumDataChanged/slowDataChanged 信号。历史折线是表现层关注点，
// 与 Canvas 绘制紧耦合，故放在视图里；服务只做无状态数据泵。
//
// 视觉：全部 Tahoe 玻璃语言（卡片 radius 18、内嵌描边、深/浅色对、TahoeSymbol
// 字形、monoFontFamily 给数字）。不引入 QtQuick.Controls、不引入 MD3 token、
// 不引入 Lottie/SVG。右键菜单不在本任务，留待 LS07。
Item {
    id: root

    property var systemStats: null
    property var batteryService: null
    property var settingsService: null
    property var sidebarPanel: null  // LeftSidebar PanelWindow，用于 itemRect 取进程行屏幕坐标
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"

    // LS07：右键进程行时发出，shell 实例化 ProcessMenu。proc 为 filteredList 条目，
    // anchorRect 为进程行在屏幕坐标系下的 {x,y,width,height}（经 sidebarPanel.itemRect）。
    signal openProcessMenu(var proc, var anchorRect)

    // 由 shell 驱动：ProcessMenu 打开时为 true，暂停进程列表刷新（菜单内容随刷新跳变
    // 会很难用）。shell 在关闭菜单时置回 false。
    property bool processMenuOpen: false

    // --- Section 0: 主题色 token（Tahoe 玻璃语言，照 LeftSidebar/ControlCenter）---
    readonly property color cardFill: darkMode ? "#24ffffff" : "#58ffffff"
    readonly property color cardStroke: darkMode ? "#2effffff" : "#66ffffff"
    readonly property color rowHover: darkMode ? "#28ffffff" : "#48ffffff"
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: darkMode ? "#9da7b1" : "#731d1d1f"
    readonly property color accentBlue: Theme.accent(darkMode, accentId)
    // 折线/网格多色，深浅色都用同一组饱和度适中的强调色（照参考 catppuccin 配色，
    // 但 Tahoe 下放到偏中性的玻璃卡片里，避免太跳）。
    readonly property color colorNetDown: "#2c9cf2"
    readonly property color colorNetUp: darkMode ? "#b48ead" : "#0b6bd3"
    readonly property color colorRam: darkMode ? "#89b4fa" : "#0b6bd3"
    readonly property color colorLoad1: "#e6c07b"
    readonly property color colorLoad5: "#89b4fa"
    readonly property color colorLoad15: "#b48ead"
    readonly property color colorCpu: "#2c9cf2"
    readonly property color colorGpu: "#b48ead"
    readonly property color colorDisk: "#b48ead"
    readonly property color colorBattery: "#a6e3a1"
    readonly property color dangerRed: "#ff453a"


    // --- Section 0.5: 容量 / 历史魔数（提为常量，不散落字面量）---
    readonly property int historyLen: 30
    readonly property int processRowHeight: 38
    readonly property int processLimit: 50
    readonly property real highCpuThreshold: 5.0   // 进程 CPU 高亮阈值 %
    readonly property real highRamThresholdKB: 1048576 // 1 GiB

    // --- Section 1: 折线图历史数组（视图内，30 采样点）---
    property var netDownHistory: []
    property var netUpHistory: []
    property var ramHistory: []
    property var load1History: []
    property var load5History: []
    property var load15History: []

    // 平滑纵坐标最大值（EMA 式平滑：直接取历史峰值 ×1.2，再用 Behavior 缓动过渡）。
    property real smoothMaxNet: 1024
    property real smoothMaxLoad: 1
    Behavior on smoothMaxNet { NumberAnimation { duration: 600; easing.type: Motion.emphasizedDecel } }
    Behavior on smoothMaxLoad { NumberAnimation { duration: 600; easing.type: Motion.emphasizedDecel } }
    onSmoothMaxNetChanged: chartCanvas.requestPaint()
    onSmoothMaxLoadChanged: chartCanvas.requestPaint()

    // 折线滑入进度 0→1：数据到达时从 0 动画至 1，整条曲线向左推一格。
    property real slideProgress: 0
    Behavior on slideProgress {} // 占位，动画走 slideAnim
    onSlideProgressChanged: chartCanvas.requestPaint()

    NumberAnimation {
        id: slideAnim
        target: root
        property: "slideProgress"
        from: 0
        to: 1
        duration: 1000
    }

    // --- Section 1.5: 折线图标签 + 进程过滤状态 ---
    property int currentChartTab: 0 // 0=Net, 1=RAM, 2=Load
    onCurrentChartTabChanged: chartCanvas.requestPaint()

    // 进程过滤状态放在 procSection（ColumnLayout）里，照参考 SystemView 的结构；
    // 这样新值变化信号与 getFilteredProcesses() 同属一个对象，便于 onXChanged 绑定。
    // 此处仅保留 currentChartTab；进程态见 procSection。

    // --- Section 2: 服务数据接入 ---
    function pushHistory(arr, val) {
        arr.push(val);
        if (arr.length > historyLen + 1)
            arr.shift();
        return arr;
    }

    function maxOf(arr) {
        var m = 0;
        for (var i = 0; i < arr.length; i++) {
            var v = Number(arr[i]) || 0;
            if (v > m)
                m = v;
        }
        return m;
    }

    function s() { return root.systemStats; }

    Connections {
        target: root.systemStats || null
        function onFastDataChanged() {
            var stats = root.systemStats;
            if (!stats)
                return;

            root.netDownHistory = pushHistory(root.netDownHistory, stats.netDownBps);
            root.netUpHistory = pushHistory(root.netUpHistory, stats.netUpBps);
            root.ramHistory = pushHistory(root.ramHistory, stats.ramUsage / 100.0);

            var rawNetMax = Math.max(maxOf(root.netDownHistory), maxOf(root.netUpHistory)) * 1.2;
            root.smoothMaxNet = rawNetMax > 0 ? rawNetMax : 1024;

            if (root.currentChartTab !== 2) {
                slideAnim.duration = 1000; // fast timer 间隔
                slideAnim.restart();
            }

            // 进程过滤列表随快拍刷新（medium 每 2s 推一次新 processes；这里也重算，
            // 保证 CPU 排序在两次 medium 之间反映最新值——开销可接受，列表 ≤50）。
            // 右键菜单打开时暂停（processMenuOpen 由 shell 驱动）。
            if (!root.processMenuOpen)
                procSection.filteredList = procSection.getFilteredProcesses();
        }

        function onMediumDataChanged() {
            var stats = root.systemStats;
            if (!stats)
                return;

            root.load1History = pushHistory(root.load1History, stats.load1);
            root.load5History = pushHistory(root.load5History, stats.load5);
            root.load15History = pushHistory(root.load15History, stats.load15);

            var rawLoadMax = Math.max(
                maxOf(root.load1History),
                maxOf(root.load5History),
                maxOf(root.load15History)
            ) * 1.2;
            root.smoothMaxLoad = rawLoadMax > 0 ? rawLoadMax : 1;

            if (root.currentChartTab === 2) {
                slideAnim.duration = 2000; // medium timer 间隔
                slideAnim.restart();
            }

            if (!root.processMenuOpen)
                procSection.filteredList = procSection.getFilteredProcesses();
        }
    }

    Component.onCompleted: {
        procSection.filteredList = procSection.getFilteredProcesses();
    }

    // --- Section 3: 格式化 helper ---
    function formatBytes(bps) {
        var n = Number(bps) || 0;
        if (n >= 1048576)
            return (n / 1048576).toFixed(1) + " MB/s";
        if (n >= 1024)
            return (n / 1024).toFixed(1) + " KB/s";
        return n.toFixed(0) + " B/s";
    }

    function formatMemKB(kb) {
        var n = Number(kb) || 0;
        if (n >= 1048576)
            return (n / 1048576).toFixed(1) + " GB";
        if (n >= 1024)
            return (n / 1024).toFixed(1) + " MB";
        return n + " KB";
    }

    function numOr(v, fallback) {
        var n = Number(v);
        return isFinite(n) ? n : fallback;
    }

    function fixed(v, digits) {
        var n = Number(v);
        return isFinite(n) ? n.toFixed(digits) : "--";
    }

    // GPU 是否可用：服务探测失败时 temp/usage 都为 0。
    function gpuAvailable() {
        var stats = root.systemStats;
        return !!stats && (stats.gpuTempC > 0 || stats.gpuUsage > 0);
    }

    function batteryAvailable() {
        return !!root.batteryService && root.batteryService.available;
    }

    // LS07：右键进程行 → 经 sidebarPanel.itemRect 取进程行屏幕坐标，发信号给 shell
    // 实例化 ProcessMenu。照 Tray.qml/Dock.qml 的 anchorRectFor 模式。
    // processMenuOpen（暂停刷新）由 shell 在 prepareProcessMenu 时置 true，本函数不直接改，
    // 保证开关生命周期都由 shell 的 processMenuOpen 状态掌控。
    function requestProcessMenu(delegateItem) {
        var proc = delegateItem ? delegateItem.proc : null;
        if (!proc || !proc.pid)
            return;

        var rect = null;
        if (root.sidebarPanel && delegateItem) {
            try {
                rect = root.sidebarPanel.itemRect(delegateItem);
            } catch (e) {
                rect = null;
            }
        }

        var anchorRect = null;
        if (rect) {
            anchorRect = {
                "x": Math.round(Number(rect.x) || 0),
                "y": Math.round(Number(rect.y) || 0),
                "width": Math.round(Number(rect.width) || 0),
                "height": Math.round(Number(rect.height) || 0)
            };
        }

        root.openProcessMenu(proc, anchorRect);
    }

    // --- Section 4: 主布局 ---
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // === Section 4.1: 双弧仪表（CPU / GPU）===
        Row {
            Layout.fillWidth: true
            spacing: 12

            // 纯原生宽度平分，从根源掐断 Layout 宽高无限依赖的 polish() 死循环
            // （参考 SystemView 注释）。
            property real itemDim: (width - 12) / 2

            DualArcGauge {
                width: parent.itemDim
                height: parent.itemDim
                titleText: "CPU 温度"
                gapTitleText: "占用"
                mainValue: numOr(s() ? s().cpuTempC : 0, 0)
                secondaryValue: numOr(s() ? s().cpuUsage : 0, 0)
                mainSuffix: "°C"
                secondarySuffix: "%"
                mainMax: 100
                secondaryMax: 100
                mainArcColor: root.colorCpu
                secondaryArcColor: root.colorCpu
                showDanger: true
            }

            DualArcGauge {
                width: parent.itemDim
                height: parent.itemDim
                visible: root.gpuAvailable()
                titleText: "GPU 温度"
                gapTitleText: "占用"
                mainValue: numOr(s() ? s().gpuTempC : 0, 0)
                secondaryValue: numOr(s() ? s().gpuUsage : 0, 0)
                mainSuffix: "°C"
                secondarySuffix: "%"
                mainMax: 100
                secondaryMax: 100
                mainArcColor: root.colorGpu
                secondaryArcColor: root.colorGpu
                showDanger: true
            }

            // 无 GPU 时 CPU 仪表占满（风险 5 对策）。
            DualArcGauge {
                width: parent.itemDim
                height: parent.itemDim
                visible: !root.gpuAvailable()
                titleText: "CPU 频率"
                gapTitleText: "负载"
                mainValue: numOr(s() ? s().cpuFrequencyGHz : 0, 0)
                secondaryValue: numOr(s() ? s().load1 : 0, 0)
                mainSuffix: "GHz"
                secondarySuffix: ""
                mainMax: 6
                secondaryMax: Math.max(1, smoothMaxLoad)
                mainArcColor: root.colorGpu
                secondaryArcColor: root.colorGpu
                showDanger: false
            }
        }

        // === Section 4.2: 折线图标签切换 ===
        Row {
            Layout.fillWidth: true
            spacing: 6

            SegTab {
                label: "网络"
                active: root.currentChartTab === 0
                onActivated: root.currentChartTab = 0
            }
            SegTab {
                label: "内存"
                active: root.currentChartTab === 1
                onActivated: root.currentChartTab = 1
            }
            SegTab {
                label: "负载"
                active: root.currentChartTab === 2
                onActivated: root.currentChartTab = 2
            }

            Item { width: 4; height: 1 }
        }

        // === Section 4.3: 折线图 + 右侧实时数值 ===
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            radius: 14
            color: root.cardFill
            border.color: root.cardStroke
            border.width: 1
            clip: true

            Canvas {
                id: chartCanvas

                anchors.fill: parent
                anchors.margins: 8
                clip: true

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    var datasets = [];
                    var dynamMax = 1.0;
                    var maxDisplayHeight = height - 4;

                    if (root.currentChartTab === 0) {
                        var net1 = root.netDownHistory.length > 1 ? root.netDownHistory : [0, 0];
                        var net2 = root.netUpHistory.length > 1 ? root.netUpHistory : [0, 0];
                        datasets = [
                            { pts: net1, color: root.colorNetDown, fill: true },
                            { pts: net2, color: root.colorNetUp, fill: true }
                        ];
                        dynamMax = root.smoothMaxNet;
                    } else if (root.currentChartTab === 1) {
                        var ram1 = root.ramHistory.length > 1 ? root.ramHistory : [0, 0];
                        datasets = [ { pts: ram1, color: root.colorRam, fill: true } ];
                        dynamMax = 1.0;
                    } else {
                        var load1 = root.load1History.length > 1 ? root.load1History : [0, 0];
                        var load5 = root.load5History.length > 1 ? root.load5History : [0, 0];
                        var load15 = root.load15History.length > 1 ? root.load15History : [0, 0];
                        datasets = [
                            { pts: load1, color: root.colorLoad1, fill: true },
                            { pts: load5, color: root.colorLoad5, fill: true },
                            { pts: load15, color: root.colorLoad15, fill: true }
                        ];
                        dynamMax = root.smoothMaxLoad;
                    }
                    if (dynamMax <= 0)
                        dynamMax = 1;

                    var stepX = width / (root.historyLen - 1);

                    for (var d = 0; d < datasets.length; d++) {
                        var set = datasets[d];
                        var pts = set.pts;
                        var len = pts.length;
                        // 曲线整体向左推 slideProgress 格，新点从右滑入。
                        var startX = width - (len - 1) * stepX - stepX * root.slideProgress + stepX;

                        ctx.beginPath();
                        var firstY = height - (Number(pts[0]) || 0) / dynamMax * maxDisplayHeight;
                        ctx.moveTo(startX, firstY);
                        for (var i = 1; i < len; i++) {
                            var x = startX + i * stepX;
                            var y = height - (Number(pts[i]) || 0) / dynamMax * maxDisplayHeight;
                            ctx.lineTo(x, y);
                        }
                        ctx.lineWidth = 2.0;
                        ctx.strokeStyle = set.color;
                        ctx.stroke();

                        if (set.fill) {
                            var lastX = startX + (len - 1) * stepX;
                            ctx.lineTo(lastX, height);
                            ctx.lineTo(startX, height);
                            ctx.closePath();

                            var c = Qt.color(set.color);
                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                            grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.25));
                            grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.0));
                            ctx.fillStyle = grad;
                            ctx.fill();
                        }
                    }
                }
            }

            // 右上角实时数值小卡，叠在折线图上方。
            Column {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 10
                spacing: 4

                ChartStat {
                    visible: root.currentChartTab === 0
                    iconCode: "\uf090" // download
                    color: root.colorNetDown
                    text: root.formatBytes(s() ? s().netDownBps : 0)
                }
                ChartStat {
                    visible: root.currentChartTab === 0
                    iconCode: "\uf09b" // upload
                    color: root.colorNetUp
                    text: root.formatBytes(s() ? s().netUpBps : 0)
                }
                ChartStat {
                    visible: root.currentChartTab === 1
                    iconCode: "\ue322" // memory
                    color: root.colorRam
                    text: fixed(s() ? s().ramUsedGB : 0, 1) + "/" + fixed(s() ? s().ramTotalGB : 0, 1) + " GiB"
                }
                ChartStat {
                    visible: root.currentChartTab === 2
                    iconCode: "\ue9e4" // speed
                    color: root.colorLoad1
                    text: fixed(s() ? s().load1 : 0, 2)
                }
            }
        }

        // === Section 4.4: 属性网格（风扇/频率/任务/运行时间）===
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 10

            GridCard {
                iconCode: "\uefd8" // air (mode_fan 不在此字体，用 air 代风扇)
                title: "风扇"
                val: (s() ? s().fanRpm : 0) + " RPM"
                accent: root.colorLoad5
            }
            GridCard {
                iconCode: "\ue30d" // developer_board (CPU 频率)
                title: "CPU 频率"
                val: fixed(s() ? s().cpuFrequencyGHz : 0, 2) + " GHz"
                accent: "#e6c07b"
            }
            GridCard {
                iconCode: "\ue97a" // account_tree
                title: "任务"
                val: (s() ? s().runningTasks : 0) + " / " + (s() ? s().totalTasks : 0)
                accent: root.colorLoad15
            }
            GridCard {
                iconCode: "\ue8b5" // schedule
                title: "运行时间"
                val: (s() ? s().uptimeText : "--")
                accent: "#a6e3a1"
            }
        }

        // === Section 4.5: 磁盘卡 + 电池卡 ===
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            RootCard {
                Layout.fillWidth: true
            }

            BatteryCard {
                Layout.fillWidth: true
                visible: root.batteryAvailable()
            }
        }

        // === Section 4.6: 进程列表 ===
        ColumnLayout {
            id: procSection

            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // 分类/排序/搜索状态（与 getFilteredProcesses 同对象，便于 onXChanged）。
            property int procTabIdx: 0    // 0=全部, 1=用户, 2=系统
            property int sortCol: 0       // 0=CPU, 1=内存, 2=PID
            property bool sortAsc: false
            property string searchText: ""
            property var filteredList: []

            onProcTabIdxChanged: procSection.filteredList = procSection.getFilteredProcesses()
            onSortColChanged: procSection.filteredList = procSection.getFilteredProcesses()
            onSortAscChanged: procSection.filteredList = procSection.getFilteredProcesses()
            onSearchTextChanged: procSection.filteredList = procSection.getFilteredProcesses()

            // --- 进程过滤 + 排序 + 搜索（JS，照参考 SystemView.getFilteredProcesses）---
            function getFilteredProcesses() {
                var result = [];
                var stats = root.systemStats;
                var procModel = stats ? stats.processes : null;
                if (!procModel || !procModel.length)
                    return result;

                for (var i = 0; i < procModel.length; i++) {
                    var item = procModel[i];
                    if (!item || !item.name)
                        continue;

                    var itemUid = (item.uid !== undefined && item.uid !== null) ? item.uid : 1000;
                    if (procSection.procTabIdx === 1 && itemUid < 1000)
                        continue; // 用户进程: UID >= 1000
                    if (procSection.procTabIdx === 2 && itemUid >= 1000)
                        continue; // 系统进程: UID < 1000

                    if (procSection.searchText.length > 0) {
                        var query = procSection.searchText.toLowerCase();
                        var nameMatch = String(item.name).toLowerCase().indexOf(query) >= 0;
                        var pidMatch = String(item.pid).indexOf(query) >= 0;
                        var cmdMatch = item.cmdline ? String(item.cmdline).toLowerCase().indexOf(query) >= 0 : false;
                        if (!nameMatch && !pidMatch && !cmdMatch)
                            continue;
                    }

                    result.push(item);
                }

                var col = procSection.sortCol;
                var asc = procSection.sortAsc;
                result.sort(function(a, b) {
                    var va, vb;
                    if (col === 0) { va = a.cpuPercent; vb = b.cpuPercent; }
                    else if (col === 1) { va = a.memKB; vb = b.memKB; }
                    else { va = a.pid; vb = b.pid; }
                    return asc ? (va - vb) : (vb - va);
                });

                return result;
            }

            // --- 控制栏：标题 + 分类标签 + 搜索框 ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TahoeSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    name: "\uf20c" // leaderboard
                    color: root.accentBlue
                    size: 18
                }
                Text {
                    text: "进程"
                    color: root.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.preferredWidth: 6 }

                SegTab {
                    label: "全部"
                    active: procSection.procTabIdx === 0
                    onActivated: procSection.procTabIdx = 0
                }
                SegTab {
                    label: "用户"
                    active: procSection.procTabIdx === 1
                    onActivated: procSection.procTabIdx = 1
                }
                SegTab {
                    label: "系统"
                    active: procSection.procTabIdx === 2
                    onActivated: procSection.procTabIdx = 2
                }

                Item { Layout.fillWidth: true }

                // 搜索框（手搓，不用 QtQuick.Controls TextField，照 DockWindowMenu 风格）。
                Rectangle {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 28
                    radius: 14
                    color: root.cardFill
                    border.color: searchInput.activeFocus ? root.accentBlue : root.cardStroke
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 5

                        TahoeSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "\ue8b6" // search
                            color: root.textTertiary
                            size: 14
                        }

                        TextInput {
                            id: searchInput

                            width: parent.width - 22
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.textPrimary
                            font.pixelSize: 12
                            font.family: root.monoFontFamily
                            clip: true
                            selectByMouse: true
                            verticalAlignment: Text.AlignVCenter

                            onTextChanged: procSection.searchText = text
                            Keys.onEscapePressed: {
                                text = "";
                                procSection.searchText = "";
                            }
                        }
                    }
                }
            }

            // --- 表头：名称 + 排序按钮 ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "名称"
                    color: root.textTertiary
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                SortHeader {
                    title: "CPU"
                    colIdx: 0
                }
                SortHeader {
                    title: "内存"
                    colIdx: 1
                }
                SortHeader {
                    title: "PID"
                    colIdx: 2
                }
            }

            // --- 进程列表主体（ListView，照 ClipboardPopup 模式）---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: root.cardFill
                border.color: root.cardStroke
                border.width: 1
                clip: true

                ListView {
                    id: processList

                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    // model 直接用 filteredList（JS 数组），delegate 经 modelData 拿到条目，
                    // 避免用 int model + index 上下文属性触发的 "index is not defined" 警告
                    // （照 NotificationCenter Repeater 模式）。
                    model: procSection.filteredList

                    delegate: Rectangle {
                        id: procDelegate

                        required property var modelData

                        width: processList.width
                        height: root.processRowHeight
                        radius: 8
                        color: procMouse.containsMouse ? root.rowHover : "transparent"

                        Behavior on color { ColorAnimation { duration: Motion.fadeFast(root.settingsService) } }

                        property var proc: procDelegate.modelData || ({})
                        property bool cpuHigh: (proc && proc.cpuPercent ? proc.cpuPercent : 0) > root.highCpuThreshold
                        property bool ramHigh: (proc && proc.memKB ? proc.memKB : 0) > root.highRamThresholdKB

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: proc && proc.name ? proc.name : ""
                                color: root.textPrimary
                                font.pixelSize: 12
                                font.family: root.monoFontFamily
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            // CPU 胶囊
                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 22
                                radius: 11
                                color: cpuHigh
                                    ? Qt.rgba(root.dangerRed.r, root.dangerRed.g, root.dangerRed.b, 0.15)
                                    : (root.darkMode ? "#18ffffff" : "#28ffffff")

                                Text {
                                    anchors.centerIn: parent
                                    text: fixed(proc && proc.cpuPercent ? proc.cpuPercent : 0, 1) + "%"
                                    color: cpuHigh ? root.dangerRed : root.textSecondary
                                    font.pixelSize: 11
                                    font.family: root.monoFontFamily
                                    font.weight: Font.DemiBold
                                }
                            }

                            // 内存胶囊
                            Rectangle {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 22
                                radius: 11
                                color: ramHigh
                                    ? Qt.rgba(root.dangerRed.r, root.dangerRed.g, root.dangerRed.b, 0.15)
                                    : (root.darkMode ? "#18ffffff" : "#28ffffff")

                                Text {
                                    anchors.centerIn: parent
                                    text: root.formatMemKB(proc && proc.memKB ? proc.memKB : 0)
                                    color: ramHigh ? root.dangerRed : root.textSecondary
                                    font.pixelSize: 11
                                    font.family: root.monoFontFamily
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                text: proc && proc.pid ? proc.pid : ""
                                color: root.textTertiary
                                font.pixelSize: 12
                                font.family: root.monoFontFamily
                                Layout.preferredWidth: 56
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            id: procMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    mouse.accepted = true;
                                    root.requestProcessMenu(procDelegate);
                                }
                            }
                        }
                    }
                }

                // 空态：无匹配进程或服务未就绪。
                Text {
                    anchors.centerIn: parent
                    text: procSection.filteredList.length === 0
                        ? (root.systemStats && root.systemStats.available ? "无匹配进程" : "系统数据准备中")
                        : ""
                    color: root.textTertiary
                    font.pixelSize: 12
                    visible: procSection.filteredList.length === 0
                }
            }
        }
    }

    // --- Section 5: 内联组件 ---

    // 双弧仪表：移植参考 SystemView.DualArcGauge 的 Canvas 几何，配色改 Tahoe。
    // 下半圈=主值（温度/频率），上半圈=次值（占用/负载），右下 45° 大缺口塞次值文字。
    component DualArcGauge: Item {
        id: gauge

        property string titleText: ""
        property string gapTitleText: ""
        property real mainValue: 0
        property real secondaryValue: 0
        property string mainSuffix: ""
        property string secondarySuffix: "%"
        property real mainMax: 100
        property real secondaryMax: 100
        property color mainArcColor: root.accentBlue
        property color secondaryArcColor: root.accentBlue
        // 温度仪表 >85°C 染红（照参考）。
        property bool showDanger: false

        implicitWidth: 120
        implicitHeight: 120

        Canvas {
            id: canvas

            anchors.fill: parent

            property real mVal: gauge.mainValue
            property real sVal: gauge.secondaryValue
            onMValChanged: requestPaint()
            onSValChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var r = Math.min(width, height) / 2 - 12;
                ctx.lineCap = "round";
                ctx.lineWidth = 7;

                var pi = Math.PI;
                var d2r = pi / 180.0;

                var offsetSmall = 6 * d2r;   // 左上小缝隙
                var offsetLarge = 22 * d2r;  // 右下大缝隙

                // T1（主值，下半圈）：右下缺口下方顺时针到左上。
                var t1Base = 45 * d2r + offsetLarge;
                var t1End = 225 * d2r - offsetSmall;
                // T2（次值，上半圈）：左上缺口上方顺时针倒挂回右下。
                var t2Base = 225 * d2r + offsetSmall;
                var t2End = 45 * d2r - offsetLarge + 2 * pi;

                // 轨道底色
                ctx.beginPath();
                ctx.arc(cx, cy, r, t1Base, t1End, false);
                ctx.strokeStyle = Qt.rgba(gauge.mainArcColor.r, gauge.mainArcColor.g, gauge.mainArcColor.b, 0.15);
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, r, t2Base, t2End, false);
                ctx.strokeStyle = Qt.rgba(gauge.secondaryArcColor.r, gauge.secondaryArcColor.g, gauge.secondaryArcColor.b, 0.15);
                ctx.stroke();

                // 主值弧（顺时针生长）；温度超阈染红。
                var mainProgress = Math.min(1.0, Math.max(0.0, gauge.mainValue / gauge.mainMax));
                if (mainProgress > 0) {
                    var t1Sweep = t1End - t1Base;
                    if (t1Sweep < 0) t1Sweep += 2 * pi;
                    var t1ValEnd = t1Base + t1Sweep * mainProgress;

                    ctx.beginPath();
                    ctx.arc(cx, cy, r, t1Base, t1ValEnd, false);
                    ctx.strokeStyle = (gauge.showDanger && gauge.mainValue > 85) ? root.dangerRed : gauge.mainArcColor;
                    ctx.stroke();
                }

                // 次值弧（从左上顺时针攀向右下）。
                var secProgress = Math.min(1.0, Math.max(0.0, gauge.secondaryValue / gauge.secondaryMax));
                if (secProgress > 0) {
                    var t2Sweep = t2End - t2Base;
                    if (t2Sweep < 0) t2Sweep += 2 * pi;
                    var t2ValEnd = t2Base + t2Sweep * secProgress;

                    ctx.beginPath();
                    ctx.arc(cx, cy, r, t2Base, t2ValEnd, false);
                    ctx.strokeStyle = gauge.secondaryArcColor;
                    ctx.stroke();
                }
            }
        }

        // 中央主值
        Column {
            anchors.centerIn: parent
            spacing: 1

            Text {
                text: Math.round(gauge.mainValue) + gauge.mainSuffix
                color: root.textPrimary
                font.pixelSize: 26
                font.family: root.monoFontFamily
                font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: gauge.titleText
                color: root.textSecondary
                font.pixelSize: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // 右下 45° 缺口处的次值
        Item {
            x: gauge.width / 2 + (Math.min(gauge.width, gauge.height) / 2 - 12) * 0.707
            y: gauge.height / 2 + (Math.min(gauge.width, gauge.height) / 2 - 12) * 0.707

            Column {
                anchors.centerIn: parent
                spacing: 1

                Text {
                    text: Math.round(gauge.secondaryValue) + gauge.secondarySuffix
                    color: root.textPrimary
                    font.pixelSize: 12
                    font.family: root.monoFontFamily
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: gauge.gapTitleText
                    color: root.textTertiary
                    font.pixelSize: 9
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // 折线图右上角实时数值小项。
    component ChartStat: Row {
        property string iconCode: ""
        property color color: root.accentBlue
        property string text: ""

        spacing: 4

        TahoeSymbol {
            anchors.verticalCenter: parent.verticalCenter
            name: parent.iconCode
            color: parent.color
            size: 13
        }
        Text {
            text: parent.text
            color: root.textPrimary
            font.pixelSize: 11
            font.family: root.monoFontFamily
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // 标签切换胶囊（不用参考的 StyledButtonGroup，手搓内联）。
    component SegTab: Rectangle {
        id: tab

        property string label: ""
        property bool active: false

        signal activated()

        height: 26
        radius: 13
        color: active
            ? (root.darkMode ? "#344b62cc" : "#d8ecff")
            : (tabMouse.containsMouse ? root.rowHover : "transparent")
        border.color: active ? root.accentBlue : "transparent"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: tab.label
            color: tab.active ? root.accentBlue : root.textSecondary
            font.pixelSize: 12
            font.weight: tab.active ? Font.DemiBold : Font.Medium
        }

        MouseArea {
            id: tabMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.activated()
        }
    }

    // 属性网格卡片：图标 + 标题 + 值。
    component GridCard: Item {
        property string iconCode: ""
        property string title: ""
        property string val: ""
        property color accent: root.accentBlue

        Layout.fillWidth: true
        Layout.preferredHeight: 30

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: parent.parent.iconCode
                color: parent.parent.accent
                size: 15
            }
            Text {
                text: parent.parent.title + ":"
                color: root.textTertiary
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: parent.parent.val
                color: root.textPrimary
                font.pixelSize: 12
                font.family: root.monoFontFamily
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // 磁盘卡：左侧进度条背景 + 图标 + 用量/容量。
    component RootCard: Rectangle {
        id: rootCard

        readonly property real perc: (s() ? s().diskUsage : 0) / 100.0
        readonly property color accent: root.colorDisk

        height: 76
        radius: 14
        color: root.cardFill
        border.color: root.cardStroke
        border.width: 1
        clip: true

        // 进度条渲染层（圆角填充）。
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * rootCard.perc
            color: Qt.rgba(rootCard.accent.r, rootCard.accent.g, rootCard.accent.b, 0.15)
            radius: 14
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 12
                color: Qt.rgba(rootCard.accent.r, rootCard.accent.g, rootCard.accent.b, 0.15)

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: "\ue1db" // storage (hard_drive 不在此字体，用 storage)
                    color: rootCard.accent
                    size: 20
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    spacing: 5
                    Text {
                        text: "磁盘 /"
                        color: root.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: fixed(s() ? s().diskUsage : 0, 1) + "%"
                        color: rootCard.accent
                        font.pixelSize: 16
                        font.family: root.monoFontFamily
                        font.weight: Font.DemiBold
                    }
                }
                RowLayout {
                    Text {
                        text: "已用:"
                        color: root.textTertiary
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: fixed(s() ? s().diskUsedGB : 0, 1) + " / " + fixed(s() ? s().diskTotalGB : 0, 1) + " GB"
                        color: root.textSecondary
                        font.pixelSize: 11
                        font.family: root.monoFontFamily
                    }
                }
            }
        }
    }

    // 电池卡：绑 batteryService，无电池时隐藏（由父级 visible 控制）。
    component BatteryCard: Rectangle {
        id: batCard

        readonly property real perc: (root.batteryService ? root.batteryService.percentage : 0) / 100.0
        readonly property color accent: root.colorBattery

        height: 76
        radius: 14
        color: root.cardFill
        border.color: root.cardStroke
        border.width: 1
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * batCard.perc
            color: Qt.rgba(batCard.accent.r, batCard.accent.g, batCard.accent.b, 0.15)
            radius: 14
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 12
                color: Qt.rgba(batCard.accent.r, batCard.accent.g, batCard.accent.b, 0.15)

                TahoeSymbol {
                    anchors.centerIn: parent
                    name: root.batteryService && root.batteryService.charging
                    color: batCard.accent
                    size: 20
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    Text {
                        text: root.batteryService ? root.batteryService.stateText : ""
                        color: root.batteryService && root.batteryService.charging ? batCard.accent : root.textPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (root.batteryService ? root.batteryService.roundedPercentage : 0) + "%"
                        color: batCard.accent
                        font.pixelSize: 16
                        font.family: root.monoFontFamily
                        font.weight: Font.DemiBold
                    }
                }
                RowLayout {
                    Text {
                        text: root.batteryService ? root.batteryService.timeText : ""
                        color: root.textSecondary
                        font.pixelSize: 11
                        visible: text.length > 0
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.batteryService ? root.batteryService.healthText : ""
                        color: root.textTertiary
                        font.pixelSize: 11
                        visible: text.length > 0
                    }
                }
            }
        }
    }

    // 进程表头排序按钮。
    component SortHeader: Rectangle {
        property string title: ""
        property int colIdx: 0
        property bool isActive: procSection.sortCol === colIdx

        Layout.preferredWidth: colIdx === 0 ? 56 : (colIdx === 1 ? 70 : 48)
        height: 22
        radius: 11
        color: isActive
            ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.18)
            : (sortHover.containsMouse
                ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.08)
                : "transparent")
        Behavior on color { ColorAnimation { duration: Motion.menuEnter(root.settingsService) } }

        Row {
            anchors.centerIn: parent
            spacing: 3

            Text {
                text: parent.parent.title
                color: parent.parent.isActive ? root.accentBlue : root.textTertiary
                font.pixelSize: 11
                font.weight: parent.parent.isActive ? Font.DemiBold : Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
            TahoeSymbol {
                anchors.verticalCenter: parent.verticalCenter
                name: procSection.sortAsc ? "\ue5d8" : "\ue5db" // arrow_upward / arrow_downward
                color: root.accentBlue
                size: 13
                visible: parent.parent.isActive
            }
        }

        MouseArea {
            id: sortHover

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (procSection.sortCol === colIdx) {
                    procSection.sortAsc = !procSection.sortAsc;
                } else {
                    procSection.sortCol = colIdx;
                    procSection.sortAsc = false;
                }
            }
        }
    }
}
