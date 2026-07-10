# T05 · 全局按下态铺开 · 验收记录

日期：2026-07-10

## 实现范围

- `Motion.js` 新增 `reducedMotion`、`pressDurationFor`、`pressScaleFor`，所有按压缩放统一读取 `pressDuration=120`、`pressScale=0.96`、`pressEasing=OutQuad`；reduced profile 返回 0ms、scale 1。
- TopBar 菜单钮、工作区、状态钮和 Tray 项统一接入缩放/变暗；移除 hover 胶囊 1px 描边，保留通知徽标、电池轮廓、工作区 urgent 等非 hover 语义描边。
- Dock pinned 图标、运行窗口、最小化缩略图和工具钮接入按压；图标按下透明度乘以 0.75，并与既有 magnification/minimized/reorder 状态相乘，不覆盖原状态。
- Control Center 的连接磁贴、圆钮、媒体控制、关闭钮、编辑钮和 utility 按钮接入按压。
- 设置控件 `TahoeButton`、`TahoeListRow`、`TahoeSidebarButton`、`TahoeSegmented` 接入按压；只读 ListRow 不产生反馈。
- Spotlight shortcut/结果行、Launchpad 分类/应用格、六类菜单的普通/原生/托盘行接入按压。
- `GlassPanel` 使用被动 `PointHandler` 将左键按压合成为材质 interaction 聚光；不改协议、不改 compositor、不改 region 几何。
- `ProcessMenu` 增量接入既有 `settingsService`，用于读取同一 motion profile；未新增平行状态或服务接口。

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `cd tahoe-shell && python -m pytest tests/ -x` | PASS，84 passed |
| `git diff --check` | PASS |
| quickshell repo 冒烟（12s） | PASS，`Configuration Loaded`；无本任务新增 QML 错误 |

本机 `qmllint 1.0` 对单个现有 QML 文件也会无诊断返回 255，因此不作为有效门禁；QML 语法与运行时类型检查以 repo quickshell 实际加载为准。

治理测试新增约束：目标组件必须以预期调用点数量使用 `Motion.pressScaleFor`/`pressDurationFor`；GlassPanel 必须保留 baseline interaction 并使用被动 `PointHandler`；TopBar 禁止恢复 `buttonBorder` hover 描边 token。

## 实机输入验收

- 在当前 niri 会话启动 repo quickshell 实例，以 `/dev/uinput` 临时绝对指针按住 TopBar 应用菜单按钮：按钮出现 0.96 缩放、变暗和玻璃聚光。
- 松开左键后应用菜单正常打开，证明 `PointHandler` 没有抢占子 `MouseArea` 点击。
- IPC 冒烟开关 Control Center、Spotlight；面板加载、关闭和 compositor layer fallback 协调无新增错误。
- reduced 路径由治理测试验证：`pressScaleFor(...)=1`、`pressDurationFor(...)=0`，颜色状态仍即时切换。

## 基线警告

冒烟仍出现 T00 已记录的既有警告：`shell.qml:479` font 只读赋值、`StartupPage.qml:358` 的 `addCandidateRow` 未定义、第二实例 portal/notification 注册警告，以及 Dock 双 Behavior interceptor 警告。均非 T05 引入，按范围规则不在本任务修复；Dock interceptor 由后续 T07/T08 处理。

## 结论

T05 清单全部落地，自动化和实机按压/释放路径通过，可单独回滚。
