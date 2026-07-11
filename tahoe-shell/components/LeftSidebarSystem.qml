pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Motion.js" as Motion
import "settings/SettingsTheme.js" as Theme

// T19 system widget page: activity rings + top3 processes collapsed by default.
// Expand reveals full process list with sort/search and right-click ProcessMenu
// (shell.qml ProcessMenu path unchanged). Data still from SystemStats
// fast/medium signals — refresh cadence not increased (rules §4.2).
Item {
    id: root

    property var systemStats: null
    property var batteryService: null
    property var settingsService: null
    property var sidebarPanel: null
    property bool darkMode: false
    property string monoFontFamily: "Noto Sans Mono CJK SC"
    property bool processMenuOpen: false
    property bool cardsEnter: false
    property bool useSpring: false
    property bool processesExpanded: false

    signal openProcessMenu(var proc, var anchorRect)

    // Widget card surfaces: solid-ish plates over the denser glass shell.
    readonly property color cardFill: darkMode ? "#2c2c2e" : "#ffffff"
    readonly property color cardFillAlt: darkMode ? "#242426" : "#f2f2f7"
    readonly property color rowHover: darkMode ? "#3a3a3c" : "#e8e8ed"
    readonly property string accentId: settingsService ? settingsService.accentColor : "blue"
    readonly property color textPrimary: Theme.label(darkMode)
    readonly property color textSecondary: Theme.secondaryLabel(darkMode)
    readonly property color textTertiary: Theme.tertiaryLabel(darkMode)
    readonly property color accentBlue: Theme.accent(darkMode, accentId)
    // Activity palette (macOS-like rings).
    readonly property color colorCpu: darkMode ? "#0a84ff" : "#007aff"
    readonly property color colorRam: darkMode ? "#30d158" : "#34c759"
    readonly property color colorGpu: darkMode ? "#bf5af2" : "#af52de"
    readonly property color colorDisk: darkMode ? "#64d2ff" : "#5ac8fa"
    readonly property color colorBattery: darkMode ? "#30d158" : "#34c759"
    readonly property color dangerRed: Theme.danger(darkMode)
    readonly property color colorNetDown: darkMode ? "#0a84ff" : "#007aff"
    readonly property color colorNetUp: darkMode ? "#ff9f0a" : "#ff9500"

    readonly property int processRowHeight: 36
    readonly property int processLimit: 50
    readonly property real highCpuThreshold: 5.0
    readonly property real highRamThresholdKB: 1048576

    // Histories for optional mini chart (same cadence as before).
    readonly property int historyLen: 30
    property var netDownHistory: []
    property var netUpHistory: []
    property var ramHistory: []
    property real smoothMaxNet: 1024
    property real slideProgress: 0

    Behavior on smoothMaxNet {
        NumberAnimation { duration: 600; easing.type: Motion.emphasizedDecel }
    }
    onSmoothMaxNetChanged: chartCanvas.requestPaint()
    onSlideProgressChanged: chartCanvas.requestPaint()

    NumberAnimation {
        id: slideAnim
        target: root
        property: "slideProgress"
        from: 0
        to: 1
        duration: 1000
    }

    property int currentChartTab: 0

    // Process filter state
    property int procTabIdx: 0
    property int sortCol: 0
    property bool sortAsc: false
    property string searchText: ""
    property var filteredList: []
    // Cached visible rows so Repeater gets a stable JS-array model (not a
    // function call that re-allocates every binding re-eval).
    property var visibleProcessList: []

    onProcTabIdxChanged: refreshProcessLists()
    onSortColChanged: refreshProcessLists()
    onSortAscChanged: refreshProcessLists()
    onSearchTextChanged: refreshProcessLists()
    onProcessesExpandedChanged: refreshVisibleProcesses()
    onFilteredListChanged: refreshVisibleProcesses()

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

    function s() {
        return root.systemStats;
    }

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
            slideAnim.duration = 1000;
            slideAnim.restart();
            if (!root.processMenuOpen)
                root.refreshProcessLists();
        }

        function onMediumDataChanged() {
            if (!root.processMenuOpen)
                root.refreshProcessLists();
        }
    }

    Component.onCompleted: {
        refreshProcessLists();
    }

    function refreshProcessLists() {
        filteredList = getFilteredProcesses();
        refreshVisibleProcesses();
    }

    function refreshVisibleProcesses() {
        visibleProcessList = visibleProcesses();
    }

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

    function gpuAvailable() {
        var stats = root.systemStats;
        return !!stats && (stats.gpuTempC > 0 || stats.gpuUsage > 0);
    }

    function batteryAvailable() {
        return !!root.batteryService && root.batteryService.available;
    }

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
            if (root.procTabIdx === 1 && itemUid < 1000)
                continue;
            if (root.procTabIdx === 2 && itemUid >= 1000)
                continue;
            if (root.searchText.length > 0) {
                var query = root.searchText.toLowerCase();
                var nameMatch = String(item.name).toLowerCase().indexOf(query) >= 0;
                var pidMatch = String(item.pid).indexOf(query) >= 0;
                var cmdMatch = item.cmdline ? String(item.cmdline).toLowerCase().indexOf(query) >= 0 : false;
                if (!nameMatch && !pidMatch && !cmdMatch)
                    continue;
            }
            result.push(item);
        }

        var col = root.sortCol;
        var asc = root.sortAsc;
        result.sort(function(a, b) {
            var va, vb;
            if (col === 0) {
                va = a.cpuPercent;
                vb = b.cpuPercent;
            } else if (col === 1) {
                va = a.memKB;
                vb = b.memKB;
            } else {
                va = a.pid;
                vb = b.pid;
            }
            return asc ? (va - vb) : (vb - va);
        });
        return result;
    }

    function topProcesses(n) {
        var list = filteredList || [];
        var out = [];
        for (var i = 0; i < list.length && out.length < n; i++)
            out.push(list[i]);
        return out;
    }

    function visibleProcesses() {
        if (processesExpanded)
            return (filteredList || []).slice(0, processLimit);
        return topProcesses(3);
    }

    Flickable {
        id: mainFlick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        interactive: contentHeight > height

        Column {
            id: mainColumn
            width: mainFlick.width
            spacing: 10

            // --- Activity rings ---
            SoftCard {
                width: parent.width
                height: 168
                cardIndex: 0

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 14
                    text: "活动"
                    color: root.textSecondary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    spacing: 14

                    ActivityRing {
                        width: 96
                        height: 96
                        progress: numOr(s() ? s().cpuUsage : 0, 0) / 100.0
                        ringColor: root.colorCpu
                        centerValue: Math.round(numOr(s() ? s().cpuUsage : 0, 0)) + "%"
                        centerLabel: "CPU"
                        subLabel: fixed(s() ? s().cpuTempC : 0, 0) + "°"
                    }

                    ActivityRing {
                        width: 96
                        height: 96
                        progress: numOr(s() ? s().ramUsage : 0, 0) / 100.0
                        ringColor: root.colorRam
                        centerValue: Math.round(numOr(s() ? s().ramUsage : 0, 0)) + "%"
                        centerLabel: "内存"
                        subLabel: fixed(s() ? s().ramUsedGB : 0, 1) + "G"
                    }

                    ActivityRing {
                        width: 96
                        height: 96
                        visible: root.gpuAvailable()
                        progress: numOr(s() ? s().gpuUsage : 0, 0) / 100.0
                        ringColor: root.colorGpu
                        centerValue: Math.round(numOr(s() ? s().gpuUsage : 0, 0)) + "%"
                        centerLabel: "GPU"
                        subLabel: fixed(s() ? s().gpuTempC : 0, 0) + "°"
                    }

                    ActivityRing {
                        width: 96
                        height: 96
                        visible: !root.gpuAvailable()
                        progress: Math.min(1, numOr(s() ? s().load1 : 0, 0) / Math.max(1, numOr(s() ? s().cpuCount : 4, 4)))
                        ringColor: root.colorGpu
                        centerValue: fixed(s() ? s().load1 : 0, 2)
                        centerLabel: "负载"
                        subLabel: fixed(s() ? s().cpuFrequencyGHz : 0, 1) + "G"
                    }
                }
            }

            // --- Network mini chart ---
            SoftCard {
                width: parent.width
                height: 100
                cardIndex: 1

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 12
                    text: "网络"
                    color: root.textSecondary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    z: 2
                }

                Canvas {
                    id: chartCanvas
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 28
                    anchors.bottomMargin: 10
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        var net1 = root.netDownHistory.length > 1 ? root.netDownHistory : [0, 0];
                        var net2 = root.netUpHistory.length > 1 ? root.netUpHistory : [0, 0];
                        var datasets = [
                            { pts: net1, color: root.colorNetDown },
                            { pts: net2, color: root.colorNetUp }
                        ];
                        var dynamMax = root.smoothMaxNet > 0 ? root.smoothMaxNet : 1;
                        var maxDisplayHeight = height - 4;
                        var stepX = width / (root.historyLen - 1);
                        for (var d = 0; d < datasets.length; d++) {
                            var set = datasets[d];
                            var pts = set.pts;
                            var len = pts.length;
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
                        }
                    }
                }

                Column {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 2
                    Text {
                        text: "↓ " + root.formatBytes(s() ? s().netDownBps : 0)
                        color: root.colorNetDown
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "↑ " + root.formatBytes(s() ? s().netUpBps : 0)
                        color: root.colorNetUp
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            // --- Stats row ---
            SoftCard {
                width: parent.width
                height: 64
                cardIndex: 2

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 0

                    StatCell {
                        width: parent.width / 3
                        height: parent.height
                        title: "风扇"
                        value: (s() ? s().fanRpm : 0) + " RPM"
                    }
                    StatCell {
                        width: parent.width / 3
                        height: parent.height
                        title: "任务"
                        value: (s() ? s().runningTasks : 0) + "/" + (s() ? s().totalTasks : 0)
                    }
                    StatCell {
                        width: parent.width / 3
                        height: parent.height
                        title: "运行"
                        value: (s() ? s().uptimeText : "--")
                    }
                }
            }

            // Disk
            SoftCard {
                width: parent.width
                height: 68
                cardIndex: 3

                readonly property real perc: (s() ? s().diskUsage : 0) / 100.0

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * parent.perc
                    radius: 18
                    color: Qt.rgba(root.colorDisk.r, root.colorDisk.g, root.colorDisk.b, 0.16)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    TahoeSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "\ue1db"
                        color: root.colorDisk
                        size: 20
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "磁盘  " + fixed(s() ? s().diskUsage : 0, 1) + "%"
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: fixed(s() ? s().diskUsedGB : 0, 1) + " / " + fixed(s() ? s().diskTotalGB : 0, 1) + " GB"
                            color: root.textSecondary
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Battery
            SoftCard {
                width: parent.width
                height: 68
                cardIndex: 4
                visible: root.batteryAvailable()

                readonly property real perc: (root.batteryService ? root.batteryService.percentage : 0) / 100.0

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * parent.perc
                    radius: 18
                    color: Qt.rgba(root.colorBattery.r, root.colorBattery.g, root.colorBattery.b, 0.16)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    TahoeSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.batteryService && root.batteryService.charging ? "\ue1a3" : "\ue1a4"
                        color: root.colorBattery
                        size: 20
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: (root.batteryService ? root.batteryService.stateText : "")
                                + "  "
                                + (root.batteryService ? root.batteryService.roundedPercentage : 0) + "%"
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.batteryService ? root.batteryService.timeText : ""
                            color: root.textSecondary
                            font.pixelSize: 11
                            visible: text.length > 0
                        }
                    }
                }
            }

            // --- Processes ---
            SoftCard {
                id: procCard
                width: parent.width
                height: procInner.implicitHeight + 20
                cardIndex: 5

                Column {
                    id: procInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "进程"
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item { width: 4; height: 1 }

                        Text {
                            text: root.processesExpanded ? "收起" : "展开全部"
                            color: root.accentBlue
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.processesExpanded = !root.processesExpanded
                            }
                        }

                        Item { width: parent.width; height: 1 } // spacer noop
                    }

                    // Expanded chrome: tabs + search
                    Row {
                        width: parent.width
                        spacing: 6
                        visible: root.processesExpanded

                        SegTab {
                            label: "全部"
                            active: root.procTabIdx === 0
                            onActivated: root.procTabIdx = 0
                        }
                        SegTab {
                            label: "用户"
                            active: root.procTabIdx === 1
                            onActivated: root.procTabIdx = 1
                        }
                        SegTab {
                            label: "系统"
                            active: root.procTabIdx === 2
                            onActivated: root.procTabIdx = 2
                        }

                        Item { width: 8; height: 1 }

                        Rectangle {
                            width: 110
                            height: 26
                            radius: 13
                            color: root.darkMode ? "#18ffffff" : "#28ffffff"
                            TextInput {
                                id: searchInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                color: root.textPrimary
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                clip: true
                                onTextChanged: root.searchText = text
                                Keys.onEscapePressed: {
                                    text = "";
                                    root.searchText = "";
                                }
                                Text {
                                    anchors.fill: parent
                                    text: "搜索"
                                    color: root.textTertiary
                                    font.pixelSize: 12
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchInput.text.length === 0
                                }
                            }
                        }
                    }

                    // Sort headers when expanded
                    Row {
                        width: parent.width
                        height: 22
                        visible: root.processesExpanded
                        spacing: 6
                        Text {
                            width: parent.width - 200
                            text: "名称"
                            color: root.textTertiary
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        SortHeader { title: "CPU"; colIdx: 0; width: 56 }
                        SortHeader { title: "内存"; colIdx: 1; width: 70 }
                        SortHeader { title: "PID"; colIdx: 2; width: 48 }
                    }

                    Column {
                        id: procListCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            // JS array model (same pattern as pre-T19 process list).
                            model: root.visibleProcessList

                            delegate: Rectangle {
                                id: procDelegate
                                required property var modelData
                                width: procListCol.width
                                height: root.processRowHeight
                                radius: 8
                                color: procMouse.containsMouse ? root.rowHover : "transparent"

                                property var proc: procDelegate.modelData || ({})
                                property bool cpuHigh: (proc && proc.cpuPercent ? proc.cpuPercent : 0) > root.highCpuThreshold
                                property bool ramHigh: (proc && proc.memKB ? proc.memKB : 0) > root.highRamThresholdKB

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        width: parent.width - 200
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: proc && proc.name ? proc.name : ""
                                        color: root.textPrimary
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: 56
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: fixed(proc && proc.cpuPercent ? proc.cpuPercent : 0, 1) + "%"
                                        color: cpuHigh ? root.dangerRed : root.textSecondary
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Text {
                                        width: 70
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.formatMemKB(proc && proc.memKB ? proc.memKB : 0)
                                        color: ramHigh ? root.dangerRed : root.textSecondary
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Text {
                                        width: 48
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: proc && proc.pid ? proc.pid : ""
                                        color: root.textTertiary
                                        font.pixelSize: 11
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

                        Text {
                            width: parent.width
                            height: 36
                            visible: root.visibleProcessList.length === 0
                            text: root.systemStats && root.systemStats.available ? "无匹配进程" : "系统数据准备中"
                            color: root.textTertiary
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Item { width: 1; height: 8 }
        }
    }

    // --- components ---
    component SoftCard: Item {
        id: card
        property int cardIndex: 0

        // Soft drop shadow plate (no 1px stroke).
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3
            radius: 18
            color: root.darkMode ? "#40000000" : "#18000000"
            z: -1
        }
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: root.cardFill
        }

        property real enterY: Motion.sidebarCardEnterOffsetPx
        property real enterOpacity: 0
        transform: Translate { y: card.enterY }
        opacity: enterOpacity

        SpringAnimation {
            id: enterYSpring
            target: card
            property: "enterY"
            spring: Motion.springSmooth.spring
            damping: Motion.springSmooth.damping
            epsilon: 0.0005
        }
        NumberAnimation {
            id: enterYEase
            target: card
            property: "enterY"
            duration: Motion.sidebarCardEnterDuration(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }
        NumberAnimation {
            id: enterOpacityAnim
            target: card
            property: "enterOpacity"
            duration: Motion.sidebarCardEnterDuration(root.settingsService)
            easing.type: Motion.emphasizedDecel
        }

        function animateEnter(toY, toOpacity) {
            enterYSpring.stop();
            enterYEase.stop();
            enterOpacityAnim.stop();
            if (root.useSpring && !Motion.reducedMotion(root.settingsService)) {
                enterYSpring.to = toY;
                enterYSpring.restart();
            } else {
                enterYEase.to = toY;
                enterYEase.duration = Motion.sidebarCardEnterDuration(root.settingsService);
                enterYEase.restart();
            }
            enterOpacityAnim.to = toOpacity;
            enterOpacityAnim.duration = Motion.sidebarCardEnterDuration(root.settingsService);
            enterOpacityAnim.restart();
        }

        function snapEnter(toY, toOpacity) {
            enterYSpring.stop();
            enterYEase.stop();
            enterOpacityAnim.stop();
            card.enterY = toY;
            card.enterOpacity = toOpacity;
        }

        Connections {
            target: root
            function onCardsEnterChanged() {
                if (!root.cardsEnter) {
                    card.snapEnter(Motion.sidebarCardEnterOffsetPx, 0);
                    return;
                }
                revealTimer.interval = Motion.sidebarCardStaggerDelay(card.cardIndex);
                revealTimer.restart();
            }
        }
        Timer {
            id: revealTimer
            repeat: false
            onTriggered: card.animateEnter(0, 1)
        }
        Component.onCompleted: {
            if (root.cardsEnter)
                card.snapEnter(0, 1);
        }
    }

    component ActivityRing: Item {
        id: ring
        property real progress: 0
        property color ringColor: root.accentBlue
        property string centerValue: ""
        property string centerLabel: ""
        property string subLabel: ""

        Canvas {
            id: ringCanvas
            anchors.fill: parent
            property real p: ring.progress
            onPChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var r = Math.min(width, height) / 2 - 10;
                var pi = Math.PI;
                var start = -pi / 2;
                ctx.lineWidth = 9;
                ctx.lineCap = "round";
                // Track
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, 2 * pi, false);
                ctx.strokeStyle = Qt.rgba(ring.ringColor.r, ring.ringColor.g, ring.ringColor.b, 0.14);
                ctx.stroke();
                // Progress
                var prog = Math.max(0, Math.min(1, ring.progress));
                if (prog > 0) {
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, start, start + prog * 2 * pi, false);
                    ctx.strokeStyle = ring.ringColor;
                    ctx.stroke();
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ring.centerValue
                color: root.textPrimary
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ring.centerLabel
                color: root.textSecondary
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ring.subLabel
                color: root.textTertiary
                font.pixelSize: 10
            }
        }
    }

    component StatCell: Column {
        property string title: ""
        property string value: ""
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.title
            color: root.textTertiary
            font.pixelSize: 11
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.value
            color: root.textPrimary
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width - 4
            horizontalAlignment: Text.AlignHCenter
        }
    }

    component SegTab: Rectangle {
        id: tab
        property string label: ""
        property bool active: false
        signal activated()
        height: 24
        width: labelText.implicitWidth + 14
        radius: 12
        color: active
            ? (root.darkMode ? "#344b62cc" : "#d8ecff")
            : (tabMouse.containsMouse ? root.rowHover : "transparent")
        Text {
            id: labelText
            anchors.centerIn: parent
            text: tab.label
            color: tab.active ? root.accentBlue : root.textSecondary
            font.pixelSize: 11
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

    component SortHeader: Item {
        property string title: ""
        property int colIdx: 0
        property bool isActive: root.sortCol === colIdx
        height: 22
        Text {
            anchors.centerIn: parent
            text: parent.title + (parent.isActive ? (root.sortAsc ? " ↑" : " ↓") : "")
            color: parent.isActive ? root.accentBlue : root.textTertiary
            font.pixelSize: 11
            font.weight: parent.isActive ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sortCol === colIdx)
                    root.sortAsc = !root.sortAsc;
                else {
                    root.sortCol = colIdx;
                    root.sortAsc = false;
                }
            }
        }
    }
}
