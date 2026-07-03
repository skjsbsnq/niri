pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../controls" as Controls

Flickable {
    id: page

    property var panel
    property var theme
    property var appsService
    property string addQuery: ""

    readonly property var settings: panel ? panel.settingsService : null
    readonly property int autostartRevision: settings ? settings.autostartRevision : 0
    readonly property int appsRevision: appsService ? appsService.desktopEntriesRevision : 0
    readonly property var entries: settings ? settings.autostartEntries : []
    readonly property var addCandidates: filteredAddCandidates(autostartRevision, appsRevision, addQuery)

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function normalizedId(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text.length === 0)
            return "";
        if (text.indexOf("/") !== -1)
            text = text.substring(text.lastIndexOf("/") + 1);
        if (text.lastIndexOf(".desktop") === text.length - 8)
            text = text.substring(0, text.length - 8);
        return text.replace(/_/g, "-");
    }

    function desktopIdForApp(app) {
        if (!app)
            return "";
        if (app.desktopEntry)
            app = app.desktopEntry;
        var id = String(app.desktopId || app.pinnedId || app.fallbackId || app.id || "").trim();
        if (id.length === 0 && page.appsService && page.appsService.appStableId)
            id = page.appsService.appStableId(app);
        return id;
    }

    function labelForApp(app) {
        if (!app)
            return "应用";
        if (page.appsService && page.appsService.appLabel)
            return page.appsService.appLabel(app);
        if (app.desktopEntry)
            app = app.desktopEntry;
        return String(app.name || app.id || "应用");
    }

    function detailForApp(app) {
        if (!app)
            return "";
        if (app.desktopEntry)
            app = app.desktopEntry;
        var execLine = String(app.execString || app.exec || "").trim();
        var generic = String(app.genericName || "").trim();
        if (execLine.length > 0 && generic.length > 0)
            return generic + " · " + execLine;
        if (execLine.length > 0)
            return execLine;
        return generic;
    }

    function entryMap() {
        var out = {};
        var values = page.entries || [];
        for (var i = 0; i < values.length; i++) {
            var entry = values[i] || {};
            var key = normalizedId(entry.desktopId || entry.fileName || entry.name);
            if (key.length > 0)
                out[key] = true;
        }
        return out;
    }

    function appSearchText(app) {
        if (!app)
            return "";
        if (app.desktopEntry)
            app = app.desktopEntry;
        return [
            labelForApp(app),
            desktopIdForApp(app),
            app.genericName || "",
            app.categories || "",
            app.keywords || "",
            app.execString || ""
        ].join(" ").toLowerCase();
    }

    function filteredAddCandidates(revision, appsRevisionValue, query) {
        if (!page.appsService)
            return [];

        var apps = page.appsService.realApplications || [];
        var used = entryMap();
        var normalized = String(query || "").trim().toLowerCase();
        var out = [];
        for (var i = 0; i < apps.length && out.length < 12; i++) {
            var app = apps[i];
            var id = desktopIdForApp(app);
            var key = normalizedId(id);
            if (key.length === 0 || used[key])
                continue;
            if (normalized.length > 0 && appSearchText(app).indexOf(normalized) === -1)
                continue;
            out.push(app);
        }
        return out;
    }

    function entryDetail(entry) {
        if (!entry)
            return "";
        var parts = [];
        parts.push(String(entry.statusText || entry.status || "未知"));
        if (entry.source === "system")
            parts.push("系统项");
        else if (entry.source === "user-override")
            parts.push("用户覆盖");
        else
            parts.push("用户项");
        var execLine = String(entry.exec || "").trim();
        if (execLine.length > 0)
            parts.push(execLine);
        return parts.join(" · ");
    }

    function validationDetail(entry) {
        if (!entry)
            return "";
        var issues = entry.validationIssues || [];
        if (issues.length > 0)
            return issues.join("；");
        var only = entry.onlyShowIn || [];
        var notShow = entry.notShowIn || [];
        if (only.length > 0)
            return "OnlyShowIn=" + only.join(";") + ";";
        if (notShow.length > 0)
            return "NotShowIn=" + notShow.join(";") + ";";
        return "Exec 和 Desktop Entry 校验通过";
    }

    ColumnLayout {
        id: settingsColumn
        width: parent.width
        spacing: 12

        Controls.TahoeSection {
            theme: page.theme
            title: "启动项"
            subtitle: page.settings
                ? page.settings.autostartDetail
                : "启动项服务不可用"

            Controls.TahoeListRow {
                theme: page.theme
                label: "自动启动文件夹"
                detail: page.settings && page.settings.autostartUserDir.length > 0
                    ? page.settings.autostartUserDir
                    : "不可用"
                iconCode: "\ue89e"

                Controls.TahoeButton {
                    theme: page.theme
                    label: "打开"
                    enabled: !!page.settings
                    onActivated: page.settings.openAutostartFolder()
                }

                Controls.TahoeButton {
                    theme: page.theme
                    label: "刷新"
                    iconCode: "\ue5d5"
                    enabled: !!page.settings && !page.settings.autostartRefreshing
                    onActivated: page.settings.refreshAutostart()
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "最近操作"
                detail: page.settings && page.settings.autostartActionText.length > 0
                    ? page.settings.autostartActionText
                    : "所有更改只写入用户 autostart 覆盖"
                iconCode: "\ue86c"
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "启动项备注"
                detail: page.settings && page.settings.startupNote.length > 0
                    ? page.settings.startupNote
                    : "未设置"
                iconCode: "\ue873"

                RowLayout {
                    spacing: 7
                    Layout.maximumWidth: 420

                    Controls.TahoeTextField {
                        id: startupNoteInput
                        theme: page.theme
                        text: page.settings ? page.settings.startupNote : ""
                        onEditingFinished: {
                            if (page.settings)
                                page.settings.setStartupNote(text);
                        }
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "保存"
                        enabled: !!page.settings
                        onActivated: page.settings.setStartupNote(startupNoteInput.text)
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "已配置启动项"
            subtitle: page.entries.length > 0
                ? "列出 XDG autostart 的有效项、停用项和无效项"
                : "没有发现启动项"

            Controls.TahoeListRow {
                theme: page.theme
                label: "无启动项"
                detail: "可以从下方应用列表添加"
                iconCode: "\ue89e"
                visible: page.entries.length === 0
            }

            Repeater {
                model: ScriptModel {
                    values: page.entries
                }

                delegate: Controls.TahoeListRow {
                    id: autostartEntryRow

                    required property var modelData

                    theme: page.theme
                    label: String(modelData.name || modelData.desktopId || "启动项")
                    detail: page.entryDetail(modelData)
                    iconCode: modelData.status === "invalid"
                        ? "\ue002"
                        : (modelData.enabled ? "\ue5ca" : "\ue14b")
                    enabled: !!page.settings && !page.settings.autostartActionRunning

                    Controls.TahoeButton {
                        theme: page.theme
                        label: autostartEntryRow.modelData.enabled ? "停用" : "启用"
                        enabled: !!page.settings
                            && autostartEntryRow.modelData.canToggle !== false
                            && autostartEntryRow.modelData.status !== "invalid"
                        onActivated: page.settings.setAutostartEnabled(
                            autostartEntryRow.modelData.desktopId,
                            !autostartEntryRow.modelData.enabled
                        )
                    }

                    Controls.TahoeButton {
                        theme: page.theme
                        label: "移除"
                        enabled: !!page.settings && autostartEntryRow.modelData.canRemove !== false
                        onActivated: page.settings.removeAutostartEntry(autostartEntryRow.modelData.desktopId)
                    }
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "启动项详情"
            subtitle: "Exec、OnlyShowIn、Hidden 和校验结果"
            visible: page.entries.length > 0

            Repeater {
                model: ScriptModel {
                    values: page.entries
                }

                delegate: Controls.TahoeListRow {
                    id: addCandidateRow

                    required property var modelData

                    theme: page.theme
                    label: String(modelData.desktopId || modelData.fileName || "desktop entry")
                    detail: page.validationDetail(modelData)
                    iconCode: modelData.valid ? "\ue86c" : "\ue002"
                }
            }
        }

        Controls.TahoeSection {
            theme: page.theme
            title: "添加应用"
            subtitle: page.appsService
                ? "从已安装桌面应用生成用户 autostart 条目"
                : "应用服务不可用"

            Controls.TahoeListRow {
                theme: page.theme
                label: "搜索应用"
                detail: page.addQuery.length > 0
                    ? page.addCandidates.length + " 个匹配"
                    : "显示尚未配置为启动项的应用"
                iconCode: "\ue8b6"

                Controls.TahoeTextField {
                    theme: page.theme
                    text: page.addQuery
                    onTextChanged: page.addQuery = text
                }
            }

            Controls.TahoeListRow {
                theme: page.theme
                label: "无可添加应用"
                detail: page.appsService ? "所有匹配应用已经在启动项中，或没有可启动桌面项" : "应用服务不可用"
                iconCode: "\ue8b6"
                visible: page.addCandidates.length === 0
            }

            Repeater {
                model: ScriptModel {
                    values: page.addCandidates
                }

                delegate: Controls.TahoeListRow {
                    required property var modelData

                    theme: page.theme
                    label: page.labelForApp(modelData)
                    detail: page.detailForApp(modelData)
                    iconCode: "\ue5c3"
                    enabled: !!page.settings && !page.settings.autostartActionRunning

                    Controls.TahoeButton {
                        id: addCandidateButton

                        property var candidateApp: addCandidateRow.modelData

                        theme: page.theme
                        label: "添加"
                        iconCode: "\ue145"
                        enabled: !!page.settings && !page.settings.autostartActionRunning
                        onActivated: page.settings.addAutostartApp(page.desktopIdForApp(addCandidateButton.candidateApp))
                    }
                }
            }
        }
    }
}
