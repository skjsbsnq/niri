pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../TahoeGlass.js" as GlassStyle
import "WidgetGrid.js" as Grid

// 桌面小部件基类。职责：
// - 三档尺寸规格（small 2×2 / medium 4×2 / large 4×4），以宿主网格
//   单元格为单位（A-6，照 macOS 网格，不自创）
// - 每小部件 1 个玻璃 region（圆角 RadiusPanelCompact；region 几何
//   走 C++ 侧 1/50 量化，禁用弹簧，见 P-1）
// - hostVisible 门控契约：宿主可见性下降 → 数据刷新/动画必须随之后退
//   （小部件禁止自建轮询，见 A-C3：数据源与定时器一律挂在
//   dataRefreshActive 上，不得另设常驻路径）
// - previewMode（A5 库预览预留，A2 即实现行为）：禁用交互与数据刷新
//
// 位置/尺寸语义归宿主（WidgetHost.qml）：宿主按网格给每个小部件
// 注入 x / y / width / height（中心对齐取整在宿主布局侧），小部件
// 内部只做 anchors.fill 铺满，不持有自己的定位逻辑。
Item {
    id: root

    // 子类内容默认进 contentArea（玻璃之上）：default property 收集器。
    default property alias content: contentArea.data

    // ---- 尺寸规格 ----
    // 规格 id：small / medium / large（A7 三档切换与配置持久化共用）。
    // 网格换算（列数/行数/合法集）唯一来源是 WidgetGrid.js
    // （colsForSize/rowsForSize/validSize），基类不再维护副本（G-6）。
    property string widgetSize: "small"

    // 单元格像素尺寸（宿主注入）。
    property real cellSize: 100

    // ---- 玻璃（每小部件 1 个 region，见 P-5 计数）----
    property string material: GlassStyle.MaterialMenu
    property real materialAlpha: 1
    property bool glassBlur: true
    property bool glassShadow: true

    // ---- 宿主契约 ----
    // hostVisible：宿主可见性门控，由宿主在创建时注入（root.visible，
    // 见 WidgetHost.createWidgetInstance 的 Qt.binding）。A3 起为真实
    // 接线：宿主隐藏 → 数据刷新/动画停止。小部件数据源/定时器/动画
    // 必须挂在 dataRefreshActive 上（A-C3），不得自建常驻轮询。
    property bool hostVisible: true
    readonly property bool dataRefreshActive: root.hostVisible && !root.previewMode
    // previewMode（A5 库预览）：禁用交互与数据刷新。
    property bool previewMode: false
    // 小部件本身体积内的指针事件由宿主 mask 覆盖（点击直达小部件）。
    readonly property bool interactive: !root.previewMode

    // 内容区：子类内容放这里（anchors.fill），玻璃之上。
    // parent 必须显式给 root：default property 收集器不收显式 parent 的
    // 对象，否则 contentArea 会被收进自己的 data（自我 parent 循环）。
    // 内容必须只读 hostVisible / dataRefreshActive 驱动数据，不碰
    // root 的尺寸/定位。
    Item {
        id: contentArea
        parent: root
        anchors.fill: parent

        // 玻璃面板：铺满宿主注入的矩形；region 绑定 root Item，宿主改
        // x/y/width/height 时 region 自动跟随（C++ 侧量化 + changed-only）。
        // 先于子类内容声明 → 渲染垫底。
        GlassPanel {
            anchors.fill: parent
            radius: GlassStyle.RadiusPanelCompact
            material: root.material
            materialAlpha: root.materialAlpha
            blur: root.glassBlur
            shadow: root.glassShadow
            regionRadius: GlassStyle.RadiusPanelCompact
            regionItem: root
            useItemRegion: true
            pressInteractionEnabled: false
        }
    }
}
