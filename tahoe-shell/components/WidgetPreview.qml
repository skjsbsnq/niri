pragma ComponentBehavior: Bound

import QtQuick

// A5：小部件库实时预览容器 —— 以 previewMode=true 实例化 catalog 中的
// 真实小部件组件，供侧栏库 tab 渲染缩略预览。
//
// 职责边界（G-6）：本组件只服务「库内预览」这一用途，不参与桌面实例 /
// 网格 / 配置（那是 WidgetHost.createWidgetInstance 的职责）；注册表与
// 尺寸规格仍唯一在 WidgetHost.qml / WidgetGrid.js，本组件只消费注入的
// source / widgetSize / cellSize，不在内部维护第二份数据。
//
// A-C3：previewMode=true → Widget.qml 的 dataRefreshActive 恒为 false →
// 小部件自带 Timer（日历分钟对齐）停摆、显示值锁存快照，不触发数据
// 刷新、不 spawn 进程。服务仍注入，使快照显示真实当前值（A2 语义：
// 「预览显示真实当前值但不随事件刷新」）。
Item {
    id: root

    // catalog 条目来源（注册表单一来源：WidgetHost.qml）。
    property string widgetId: ""
    property string source: ""
    property string widgetSize: "small"
    property real cellSize: 60
    // 服务注入（与桌面实例同一批 singleton；按 widgetId 只注入所需项，
    // 避免向无关小部件传不存在属性）。
    property var batteryService: null
    property var weatherService: null
    property var systemStatsService: null

    // 已创建的预览实例（parent 为本组件，随本组件销毁；换 source 时先销毁）。
    property var instance: null
    // 已加载的 source（防双触发：初始化时 onSourceChanged 与
    // Component.onCompleted 都会到达 load()，无守卫会重复创建再销毁，
    // A5 对抗审查 P1）。
    property string loadedSource: ""

    function load() {
        var src = String(root.source || "");
        if (root.loadedSource === src)
            return;
        root.loadedSource = src;
        if (root.instance) {
            root.instance.destroy();
            root.instance = null;
        }
        if (src.length === 0)
            return;
        // catalog 的 source 相对 components/widgets/；本文件在 components/，
        // 故拼接 "widgets/" 前缀（Qt.createComponent 相对本文件目录解析）。
        var component = Qt.createComponent("widgets/" + root.source, root);
        if (component.status !== Component.Ready) {
            console.warn("[widgets] preview createComponent failed: " + root.source
                + " (" + component.errorString() + ")");
            return;
        }
        var props = {
            "previewMode": true,
            // A8：预览井恒为深色底（A5 可读性修复），预览实例固定深色外观，
            // 与桌面卡片深色玻璃一致。
            "darkMode": true,
            "x": 0,
            "y": 0
        };
        var sid = String(root.widgetId || "");
        if (sid === "battery")
            props.batteryService = root.batteryService;
        else if (sid === "weather")
            props.weatherService = root.weatherService;
        else if (sid === "system-monitor")
            props.systemStatsService = root.systemStatsService;

        var obj = component.createObject(root, props);
        if (!obj) {
            console.warn("[widgets] preview createObject failed: " + root.source);
            return;
        }
        // 几何与规格以绑定跟随宿主：库页换尺寸（widgetSize/cellSize/宽高
        // 变化）无需重建实例。
        obj.width = Qt.binding(function() { return root.width; });
        obj.height = Qt.binding(function() { return root.height; });
        obj.widgetSize = Qt.binding(function() { return root.widgetSize; });
        obj.cellSize = Qt.binding(function() { return root.cellSize; });
        root.instance = obj;
    }

    onSourceChanged: root.load()
    Component.onCompleted: root.load()
}
