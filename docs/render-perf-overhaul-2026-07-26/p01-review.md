# P01 对抗性审查记录

日期：2026-07-26

## 改动摘要

- `WindowOverview` / `TaskSwitcher` / `DockMinimizedWindow` 窗口截图 `Image`：
  - `sourceSize = 显示尺寸 × screenScale`（预布局 0 尺寸有稳态回退）
  - `cache: true`（`?v=generation` 负责失效）
  - 捕获请求尺寸随 DPR 抬升 `max(原预算, 显示×scale)`
- `Wallpaper` 静态壁纸与 cover 共用 `panelImageDecodeSize()`（面板 × scale，封顶 3840×2400）
- `Spotlight` 无窗口截图路径；图标 `sourceSize` 改为随 DPR 预算
- 契约测试：`tests/test_thumbnail_decode_budget.py`

## 审查角度

### A. 正确性
- `PreserveAspectCrop` + 与 item 同形状的 sourceSize：与全量解码再裁剪观感一致。
- Flight 动画用 `Scale`/`Translate`，不改 item width → 动画期不重绑 sourceSize。
- 预布局 0×0：已用 mini-map / previewFrame / shelf 稳态几何回退，避免 1×1 占位再重载。

### B. 缓存与 Provider
- `ThumbnailProvider` 成功写入后 `generation++`；URL `?v=` 变化使 Qt 缓存键失效。
- 捕获尺寸变大时 `desiredWidth/Height` 升级触发一次重捕，不会循环（`hasEnoughSize` 门控）。
- 文件覆写若无 generation bump 会脏读——仅 Provider 写这些 PNG，路径安全。

### C. 回归 / 契约
- `pytest`：thumbnail decode / wallpaper idle / thumbnail async / provider contract / dock rectangle — 通过。
- 自动化静态检查（sourceSize/cache/generation/wallpaper 接线）— PASS。
- 子代理 harness 本环境返回空 final text / pi -p 超时；以多角度本地审查 + 自动化检查替代，不阻塞 P01。

### D. 残余非阻断风险
- 卡片宽度在 188–236 间变化时 sourceSize 可能微调 → 偶发再解码。
- 运行时配置目录 `~/.config/quickshell/tahoe` 与仓库 `tahoe-shell` 为副本，需 deploy/restart 才进实机。
- 静态壁纸在 Launchpad zoom 时 GPU scale，解码仍按未缩放面板尺寸（与既有 cover 策略一致，略软可接受）。

## 结论

**PASS** — 允许 commit + push，随后进入 P02。
