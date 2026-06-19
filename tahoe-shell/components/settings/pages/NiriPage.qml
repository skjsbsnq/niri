pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// S4 first batch: the niri layout domain wired to the NiriSettings service.
// Every control reads the service mirror and writes through setX, which
// updates the property optimistically (so sliders track the drag), queues
// the field write, and hot-reloads niri once the write round-trips. No
// binds/MRU/task-switcher are touched here (guardrail 441b637).
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

    function signed(n) {
        var value = Math.round(Number(n) || 0);
        return value > 0 ? "+" + value : "" + value;
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        // Status line: surfaces service-absent, still-loading and write-error
        // states. Hidden once loaded and error-free so it does not clutter
        // the page in the common case.
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

        Controls.TahoeSection {
            theme: page.theme
            title: "布局间距"
            subtitle: "窗口与边缘之间的留白"

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue256"
                label: "内边距（gaps）"
                valueText: (page.svc ? page.svc.gaps : 16) + " px"
                value: page.svc ? Math.max(0, Math.min(1, page.svc.gaps / 64)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setGaps(Math.round(v * 64));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口装饰"
            subtitle: "焦点环与边框"

            Controls.TahoeListRow {
                theme: page.theme
                label: "焦点环"
                detail: page.svc && page.svc.focusRingEnabled ? "高亮当前焦点窗口" : "关闭"
                iconCode: "\ue873"
                checkable: true
                checked: page.svc ? page.svc.focusRingEnabled : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setFocusRingEnabled(c);
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "边框"
                detail: page.svc && page.svc.borderEnabled ? "为所有窗口绘制边框" : "关闭"
                iconCode: "\ue8c4"
                checkable: true
                checked: page.svc ? page.svc.borderEnabled : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setBorderEnabled(c);
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "窗口阴影"
            subtitle: "柔和度、扩散与偏移"

            Controls.TahoeListRow {
                theme: page.theme
                label: "启用阴影"
                detail: page.svc && page.svc.shadowEnabled ? "已开启" : "关闭"
                iconCode: "\ue53b"
                checkable: true
                checked: page.svc ? page.svc.shadowEnabled : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setShadowEnabled(c);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue3a4"
                label: "柔和度"
                valueText: page.svc ? page.svc.shadowSoftness : ""
                value: page.svc ? Math.max(0, Math.min(1, page.svc.shadowSoftness / 100)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setShadowSoftness(Math.round(v * 100));
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue3aa"
                label: "扩散"
                valueText: page.svc ? page.svc.shadowSpread : ""
                value: page.svc ? Math.max(0, Math.min(1, page.svc.shadowSpread / 40)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setShadowSpread(Math.round(v * 40));
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue915"
                label: "水平偏移"
                valueText: page.svc ? page.signed(page.svc.shadowOffsetX) : ""
                value: page.svc ? Math.max(0, Math.min(1, (page.svc.shadowOffsetX + 40) / 80)) : 0.5
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setShadowOffsetX(Math.round(v * 80 - 40));
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue7c9"
                label: "垂直偏移"
                valueText: page.svc ? page.signed(page.svc.shadowOffsetY) : ""
                value: page.svc ? Math.max(0, Math.min(1, (page.svc.shadowOffsetY + 40) / 80)) : 0.5
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setShadowOffsetY(Math.round(v * 80 - 40));
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "Snap 助手"
            subtitle: "拖近屏幕边缘时自动吸附为半屏"

            Controls.TahoeListRow {
                theme: page.theme
                label: "启用 Snap 助手"
                detail: page.svc && page.svc.snapAssistEnabled ? "已开启" : "关闭"
                iconCode: "\ue8f4"
                checkable: true
                checked: page.svc ? page.svc.snapAssistEnabled : false
                enabled: page.ready
                onToggled: function(c) {
                    if (page.svc)
                        page.svc.setSnapAssistEnabled(c);
                }
            }

            Controls.TahoeSlider {
                theme: page.theme
                iconCode: "\ue859"
                label: "吸附阈值"
                valueText: (page.svc ? page.svc.snapAssistThreshold : 16) + " px"
                value: page.svc ? Math.max(0, Math.min(1, page.svc.snapAssistThreshold / 80)) : 0
                enabled: page.ready
                onUserSet: function(v) {
                    if (page.svc)
                        page.svc.setSnapAssistThreshold(Math.round(v * 80));
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "这些选项写入 niri 的 config.kdl 并在写入后立即热重载，重启 niri 后仍然生效。"
            color: page.theme ? page.theme.textSecondary : "#721d1d1f"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
