pragma ComponentBehavior: Bound

import QtQuick
import "WeatherCodes.js" as WeatherCodes

// LS08: 天气图标 —— 用 Material Icons 字形渲染 WMO 天气码。
//
// 职责：把 Open-Meteo 的 `weather_code`（WMO 码）+ 日夜标志翻译成单个 Material
// Icons 字形并居中绘制。只做渲染，不做数据；码点表在 WeatherCodes.js。
//
// 与参考项目 MeteoIcon.qml 的区别：参考用 Lottie 动画 + SVG 回退（明确不移植，
// 见路线图 §5）；Tahoe 用 Material Icons 字体字形替代，无素材依赖、无 Qt5Compat。
// 日夜区分由字形本身承担（晴日 `sunny`/晴夜 `nights_stay`），不靠颜色。
//
// 接入：LeftSidebarWeather 的主天气图标、逐时 chip 和每日预报行。颜色由父级传入，
// 默认走浅色友好值，深色调用方自行覆盖 `color`。
Item {
    id: root

    // WMO 天气码。-1 / 非数 / 越界 → unknown fallback（cloud 字形）。
    property int weatherCode: -1
    // true = 夜间，影响晴/雾/雷暴等码的日夜字形选择。
    property bool night: false
    // 字号。≤0 时按 Item 尺寸自适应（取宽高较小者，留少量边距，照图标习惯）。
    property real pixelSize: 0
    // 字形颜色。默认浅色背景下的主文字色；深色 / 卡片内由调用方覆盖。
    property color color: "#1d1d1f"
    // Material Icons 字体（shell.qml 已 FontLoader 注册，照全项目一致用法）。
    readonly property string iconFont: "Material Icons"

    // 实际渲染字号：显式优先，否则自适应。
    readonly property real resolvedPixelSize: pixelSize > 0
        ? pixelSize
        : Math.floor(Math.min(root.width, root.height) * 0.86)

    // 暴露解析后的字形与文案，供调用方做无障碍 tooltip / 调试。
    readonly property string glyph: WeatherCodes.materialIcon(weatherCode, night)
    readonly property string label: WeatherCodes.text(weatherCode)

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.color
        font.family: root.iconFont
        font.pixelSize: root.resolvedPixelSize
        // Material Icons 字形基线略偏上，视觉居中微调（照 Launchpad/TopBar 习惯）。
        anchors.verticalCenterOffset: 1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
