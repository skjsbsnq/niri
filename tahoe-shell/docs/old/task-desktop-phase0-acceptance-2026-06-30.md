# Tahoe 任务桌面反腐化路线图阶段 0 验收记录

日期：2026-06-30

状态：完成

范围：`task-desktop-research-roadmap-2026-06-30.md` 阶段 0。阶段 0 只做文档和边界确认，不做功能代码、QML、niri 配置或部署脚本改动。

## 完成项

- 完整读取并确认路线图全文。
- 确认路线图已保存到仓库文档路径：`tahoe-shell/docs/task-desktop-research-roadmap-2026-06-30.md`。
- 确认完整任务桌面缺口分类：
  - 锁屏、idle、睡眠、会话生命周期未收敛。
  - WindowOverview 和 TaskSwitcher 尚未复用真实窗口缩略图。
  - Spotlight 仍偏应用/设置/命令入口，还不是完整任务搜索。
  - QML 外部命令调用分散，缺统一依赖、错误、超时和结果模型。
  - niri 设置写入边界仍依赖 regex/brace scanning，需要限制 Tahoe 拥有块或迁移 AST。
  - XWayland、legacy tray、AppMenu 兼容路径依赖脚本和补丁状态，需要产品化诊断。
  - 窗口缩略图 IPC 输出路径边界偏宽。
- 确认维护性和腐化风险分类：
  - `shell.qml` 正在承担过多弹层、菜单、页面、IPC 和多屏状态。
  - top bar popup、Launchpad、Spotlight、Dock menu、ProcessMenu 的关闭和切换协调逻辑重复。
  - `Apps.qml`、`Controls.qml`、`Dock.qml`、`DynamicIsland.qml`、`NiriSettings.qml` 等大文件混合 UI、状态和后端调用。
  - 截图、剪贴板、AppMenu、网络、蓝牙、缩略图等路径存在静默失败风险。
  - `scripts/arch-update.sh` 承担过多产品集成职责。
- 确认不可破坏约束：
  - 不移除现有功能。
  - 不削弱现有入口。
  - 不把已可用路径替换成未验收路径。
  - 不删除 fallback，除非新路径已有健康检查和验收记录。
  - 不改变用户可见行为，除非路线图明确列为产品变更。
  - 不把多个独立风险合并到一次大重构里。
  - 先抽 helper 和 provider，再迁移调用点。
  - 迁移时保留旧 API 或兼容包装。
  - 每个阶段都要有可验证的验收清单。
- 确认第一批重构范围：阶段 1 只做 `shell.qml` 弹层状态反腐化，抽取 helper 和公共关闭逻辑；保留现有 property 名称、signal、component binding、IPC 方法、popup 组件和多屏语义。

## 后续映射规则

- 后续每次代码改动必须能映射到 `task-desktop-research-roadmap-2026-06-30.md` 的一个阶段。
- 变更说明或验收记录必须写明阶段编号，例如“阶段 1：`shell.qml` 弹层状态反腐化”。
- 不属于阶段 1-7 的改动，先更新路线图或新增阶段，再实施。
- 单次改动不得夹带多个阶段目标；确需跨阶段时，必须拆成独立验收记录。

## 验收结果

- 路线图存在于仓库文档目录。
- 路线图已标注阶段 0 完成状态和验收记录路径。
- 本验收记录落盘，记录阶段 0 的缺口、风险、不可破坏约束和后续映射规则。
- 本阶段未修改功能代码、QML、niri 配置或部署脚本。

结论：阶段 0 已完成。下一步可进入阶段 1，但阶段 1 只能做低风险结构收敛，不能改变用户可见行为或删除任何现有入口。
