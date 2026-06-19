pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// S5.0: the niri hub. The sidebar's "布局与窗口" entry now opens this hub,
// which links to one page per niri config domain. Each domain page reads the
// NiriSettings service mirror and writes through setX (optimistic update +
// queued KDL write + hot-reload). Tiles are appended as each S5 sub-step
// lands its page; this first batch wires only the layout domain (moved here
// from the old single NiriPage into NiriLayoutPage).
Flickable {
    id: page

    property var panel
    property var theme

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var svc: page.panel && page.panel.niriSettingsService ? page.panel.niriSettingsService : null
    readonly property bool ready: !!page.svc && page.svc.loaded

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        // Status line: surfaces service-absent, still-loading and write-error
        // states. Hidden once loaded and error-free so it does not clutter
        // the hub in the common case.
        Text {
            Layout.fillWidth: true
            visible: !page.ready || (page.svc && page.svc.lastError.length > 0)
            text: !page.svc ? "niri 设置服务不可用"
                : !page.svc.loaded ? "正在读取 niri 配置…"
                : page.svc.lastError
            color: page.svc && page.svc.lastError.length > 0
                ? (page.theme ? page.theme.danger : "#ff453a")
                : (page.theme ? page.theme.textSecondary : "#721d1d1f")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: "这些设置写入 niri 的 config.kdl，写入后立即热重载，重启 niri 后仍然生效。选择一个分类开始。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: settingsColumn.width >= 560 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10

            Controls.TahoeSummaryTile {
                theme: page.theme
                Layout.fillWidth: true
                iconCode: "\ue871"
                title: "布局与窗口"
                detail: page.svc ? "间距 " + page.svc.gaps + " px · 焦点环/边框/阴影/Snap" : "niri 布局设置"
                accentColor: page.panel ? page.panel.categoryColor("niri") : "#30b0c8"
                onActivated: page.panel.selectedPage = "niri-layout"
            }
        }
    }
}
