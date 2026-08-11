pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Motion.js" as Motion
import "../TahoeGlass.js" as GlassStyle

// 桌面小部件基类。职责：
// - 三档尺寸规格（small 2×2 / medium 4×2 / large 4×4），以宿主网格
//   单元格为单位（A-6，照 macOS 网格，不自创）
// - 每小部件 1 个玻璃 region（圆角 RadiusPanelCompact；region 几何
//   走 C++ 侧 1/50 量化，禁用弹簧，见 P-1）
// - hostVisible 门控契约：宿主可见性下降 → 数据刷新/动画必须随之后退
//   （小部件禁止自建轮询，见 A-C3：数据源与定时器一律挂在
//   dataRefreshActive 上，不得另设常驻路径）
// - previewMode（A5 库预览预留，A2 即实现行为）：禁用交互与数据刷新
// - 编辑模式（A6）：editMode 由宿主以绑定注入；长按进入（Dock 四状态
//   模式，A-C2），编辑态可拖动移位 / 删除，抖动动画门控于编辑模式
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

    // ---- A6 编辑模式 ----
    // 由宿主以 Qt.binding 注入（进入/退出编辑模式时全部实例实时跟随）。
    property bool editMode: false
    // 宿主对象：长按进入 / 拖动提交回滚 / 删除的单一回调入口
    // （Dock 四状态模式的宿主侧状态与网格落点归宿主，本组件只发手势）。
    property var widgetHost: null
    // 本实例 id（宿主注入；删除时传给宿主 removeWidget）。
    property string widgetId: ""

    // 手势阈值（Dock 同款 8px：位移超过即判为拖动而非长按/点击）。
    readonly property real gestureThreshold: 8

    // 手势状态清零（onReleased / onCanceled / 编辑模式中途退出共用）。
    // 注意不动 suppressNextClick：它由 suppressClickReset 计时复位。
    function resetGesture() {
        gesture.dragPressed = false;
        gesture.dragActive = false;
        longPressTimer.stop();
        suppressClickReset.restart();
    }

    // 编辑模式在拖动中被退出（完成按钮/空白点击/宿主隐藏）→ 手势状态
    // 一并清零（宿主 exitEditMode 已回滚实例位置；onReleased 不再 commit）。
    onEditModeChanged: {
        // 拖动预备（dragPressed）与激活（dragActive）任一残留都清零：
        // 退出后即便移动也不会启动陈旧拖动（host 侧 begin 也有 editMode
        // 门，这里是防御对称）。
        if (!root.editMode && (gesture.dragActive || gesture.dragPressed))
            root.resetGesture();
    }

    // 玻璃面板：铺满宿主注入的矩形；region 绑定 root Item，宿主改
    // x/y/width/height 时 region 自动跟随（C++ 侧量化 + changed-only）。
    // 显式 parent: root → 不进 default property 收集器；先于 contentArea
    // 声明 → 渲染垫底。编辑模式抖动只作用于 contentArea（玻璃/region
    // 几何保持不动，P-1：region 几何禁用弹簧与变换）。
    GlassPanel {
        parent: root
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

    // 内容区：子类内容放这里（anchors.fill），玻璃之上。
    // parent 必须显式给 root：default property 收集器不收显式 parent 的
    // 对象，否则 contentArea 会被收进自己的 data（自我 parent 循环）。
    // 内容必须只读 hostVisible / dataRefreshActive 驱动数据，不碰
    // root 的尺寸/定位。编辑模式抖动只变换此层（不碰玻璃 region）。
    Item {
        id: contentArea
        parent: root
        anchors.fill: parent
        transformOrigin: Item.Center
    }

    // 手势层（A6）：普通态长按进入编辑模式；编辑态按住拖动移位。
    // 小部件内容为只读展示（无内部交互元素），此层吞掉点击不改变既有
    // 行为；previewMode 或未注入宿主时禁用（库预览点击由卡片接管）。
    // 四状态模式照 Dock.qml:1396-1470（A-C2）：onPressed 记录起点 /
    // onPositionChanged 位移阈值激活 + suppressNextClick /
    // onReleased 提交 / onCanceled 完整回滚。
    MouseArea {
        id: gesture
        anchors.fill: parent
        z: 10
        enabled: root.interactive && !!root.widgetHost
        acceptedButtons: Qt.LeftButton

        // 长按计时（非编辑态）：位移超阈值取消（判为拖动而非长按）。
        Timer {
            id: longPressTimer

            interval: Motion.widgetLongPressMs
            repeat: false
            onTriggered: {
                // 计时到达 → 进入编辑模式；手指仍按住时置 dragPressed，
                // 使同一按住可继续拖动（iOS 式长按后直接拖动）。
                gesture.dragPressed = true;
                if (root.widgetHost)
                    root.widgetHost.enterEditMode();
            }
        }

        // 点击抑制复位（Dock 同款）：拖动激活置 suppressNextClick，
        // release 后的点击被吞掉，窗口结束后复位。
        Timer {
            id: suppressClickReset

            interval: Motion.widgetSuppressClickMs
            repeat: false
            onTriggered: gesture.suppressNextClick = false
        }

        property bool dragPressed: false
        property bool dragActive: false
        property bool suppressNextClick: false
        property real pressX: 0
        property real pressY: 0

        onPressed: function(mouse) {
            gesture.pressX = mouse.x;
            gesture.pressY = mouse.y;
            if (root.editMode) {
                // 编辑态：按住即进入拖动预备（位移超阈值才激活）。
                gesture.dragPressed = true;
                longPressTimer.stop();
            } else {
                longPressTimer.restart();
            }
        }
        onPositionChanged: function(mouse) {
            var dx = mouse.x - gesture.pressX;
            var dy = mouse.y - gesture.pressY;
            if (!root.editMode) {
                // 位移超阈值 → 判为拖动而非长按，取消长按计时。
                if (Math.sqrt(dx * dx + dy * dy) > root.gestureThreshold)
                    longPressTimer.stop();
                return;
            }
            if (gesture.dragPressed && (mouse.buttons & Qt.LeftButton)) {
                if (!gesture.dragActive && Math.sqrt(dx * dx + dy * dy) > root.gestureThreshold) {
                    gesture.dragActive = true;
                    gesture.suppressNextClick = true;
                    root.widgetHost.beginWidgetDrag(root, gesture.pressX, gesture.pressY);
                }
                if (gesture.dragActive)
                    root.widgetHost.updateWidgetDrag(root, mouse.x, mouse.y);
            }
        }
        onReleased: function(mouse) {
            if (gesture.dragActive)
                root.widgetHost.commitWidgetDrag(root);
            root.resetGesture();
        }
        onCanceled: {
            // 完整回滚（A-C2）：拖动中途失去输入（如顶栏弹层打开、mask
            // 置空）→ 恢复原位置，状态清零，不卡死。
            if (gesture.dragActive)
                root.widgetHost.cancelWidgetDrag(root);
            root.resetGesture();
        }
        onClicked: {
            if (gesture.suppressNextClick) {
                gesture.suppressNextClick = false;
                return;
            }
            // 编辑态点击小部件本体不退出编辑模式（空白/完成按钮负责退出）。
        }
    }

    // 删除按钮（A6）：编辑模式显示；点击经宿主真正销毁实例 + 写盘一次。
    Rectangle {
        id: deleteButton
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 6
        anchors.topMargin: 6
        width: 24
        height: 24
        radius: 12
        color: "#e6ff453a"
        visible: root.editMode && root.interactive
        z: 20

        Text {
            anchors.centerIn: parent
            text: "×"
            color: "#ffffff"
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.widgetHost)
                    root.widgetHost.removeWidget(root.widgetId);
            }
        }
    }

    // 编辑模式抖动（A-C3：门控于编辑模式，退出即停，无常驻动画）。
    // 只变换 contentArea（玻璃 region 跟随 root，保持不动，P-1）；
    // 时长/缓动取自 Motion.js（P-3），禁弹簧。
    SequentialAnimation {
        id: wobble
        running: root.editMode && root.interactive
        loops: Animation.Infinite

        NumberAnimation {
            target: contentArea
            property: "rotation"
            to: -1.2
            duration: Motion.widgetWobbleDurationMs
            easing.type: Motion.standardDecel
        }
        NumberAnimation {
            target: contentArea
            property: "rotation"
            to: 1.2
            duration: Motion.widgetWobbleDurationMs
            easing.type: Motion.standardDecel
        }
        NumberAnimation {
            target: contentArea
            property: "rotation"
            to: -1.2
            duration: Motion.widgetWobbleDurationMs
            easing.type: Motion.standardDecel
        }
        NumberAnimation {
            target: contentArea
            property: "rotation"
            to: 0
            duration: Motion.widgetWobbleDurationMs
            easing.type: Motion.standardDecel
        }

        // 退出编辑模式/失活 → 确保无残留旋转角。
        onRunningChanged: {
            if (!wobble.running)
                contentArea.rotation = 0;
        }
    }
}
