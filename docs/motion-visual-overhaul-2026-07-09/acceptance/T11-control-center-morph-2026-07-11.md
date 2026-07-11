# T11 · 控制中心模块 morph 展开 · 验收记录

日期：2026-07-11

## 实现范围

### 1. Motion.js morph tokens

| token | 值 |
| --- | --- |
| `ccMorphDurationMs` | 280 |
| `ccMorphSiblingOffsetPx` | 8 |
| `ccMorphListMaxHeight` | 220 |

### 2. ControlCenter.qml morph 状态机

- `expandedModule`: `""` | `"wifi"` | `"bluetooth"`
- `openModule(name)` / `closeModule()`
- 面板 `open=false` 时清零 `expandedModule` + `controlsExpanded`（无布局残留）
- Wi-Fi 展开：`rescanWifi()`；蓝牙展开：若已开且未扫描则 `setBluetoothDiscovering(true)`

### 3. UI 行为

| 交互 | 行为 |
| --- | --- |
| 点 Wi-Fi 磁贴主体 | morph → 整宽网络列表 + 返回箭头 + 电源开关 |
| 点蓝牙圆钮 | morph → 整宽设备列表（不立刻 toggle 电源） |
| 点返回箭头 | 逆向 morph 收起 |
| 其余磁贴/滑块/编辑行 | opacity→0 + 下移 8px（`ccMorphSiblingOffsetPx`） |
| 飞行模式圆钮 | 仍即时 toggle（非 morph） |
| 列表数据 | **仅** `controlsService.wifiNetworks` / `bluetoothDeviceEntries` |

### 4. 玻璃 region 护栏

- 面板 `height` / morphHost `Layout.preferredHeight`：`NumberAnimation` + `emphasizedDecel`，时长 `ccMorphDurationMs`（reduced→0）
- **无** `SpringAnimation` 驱动 glass x/y/w/h
- morph 列表高度钳在 `ccMorphListMaxHeight`，region 始终由 `GlassPanel` 自身 surface 几何产生

### 5. 占位态

- Wi-Fi：服务不可用 / 已关闭 / 未发现网络
- 蓝牙：不可用 / 已关闭 / 附近暂无设备
- 安全未知 Wi-Fi：行内密码框 + 连接
- 蓝牙行：连接中→断开；已配对→连接；附近→配对

### 6. 治理测试

- `test_motion_exports_control_center_morph_tokens`
- `test_control_center_module_morph_expand`
- pressScaleFor 计数保持 8（含 morph 返回/页脚）

## 自动化验收

| 命令 | 结果 |
| --- | --- |
| `python -m pytest tahoe-shell/tests/ -x` | **PASS，96 passed**（+2 相对 T10） |

### 机械验证

```
rg -n 'SpringAnimation' tahoe-shell/components/ControlCenter.qml → 无
rg -n 'expandedModule|ModuleMorphPanel|ccMorphDurationMs|wifiNetworks|bluetoothDeviceEntries' \
  tahoe-shell/components/ControlCenter.qml → 命中
```

## 手测矩阵（路径自查）

| 项 | 结论 |
| --- | --- |
| morph 往返 | open/close 清状态；无 Instantiator 残留 |
| 列表空/服务不可用 | 占位文案齐全 |
| 高度动画玻璃 | 仅 eased height Behavior |
| 既有功能 | 滑块/媒体/编辑行/IPC 关闭路径保留 |

## 审查 follow-up（同日）

- **问题**：morph 展开时 sibling 列仅 opacity→0，仍占 `implicitHeight`，玻璃面板过高。
- **修复**：`siblingColumn` 在 `moduleExpanded` 时 `Layout.preferredHeight/maximumHeight → 0` + `clip`，高度用 emphasized 同步动画。
- 测试：`Layout.preferredHeight: root.moduleExpanded ? 0 : implicitHeight` 断言入治理测试。

## 发现待办

- 实机：reload quickshell 后连点 Wi-Fi morph 10 次目测无残留；`niri` 日志无 region 拒绝。
- T12：灵动岛 morph 弹簧化（已完成）。
