# Tahoe 任务桌面阶段 5 验收记录

日期：2026-06-30

对应路线图：`task-desktop-research-roadmap-2026-06-30.md` 阶段 5：设置和 niri config 写入边界收敛。

## 结论

阶段 5 已完成。

本阶段没有把设置 UI 扩张成全量 KDL 编辑器，而是收紧现有写入能力：Tahoe 模板显式标注 UI 拥有的可写顶层块，`niri_settings_tool.py` 在任何写入前校验目标字段只能落在这些 Tahoe 管理块内。读路径保持兼容，`niri validate` 和原子写入路径保持不变。

## 改动范围

- 修改 `config/niri/tahoe-phase0.kdl`，给 `input`、`layout`、`blur`、`tahoe-glass` 和 `animations` 增加 `// tahoe-managed: begin <block>` / `// tahoe-managed: end <block>` 标记。
- 修改 `tahoe-shell/services/niri_settings_tool.py`。
  - 新增字段到可写顶层块的映射。
  - 写入前要求目标顶层块唯一存在。
  - 写入前要求目标块前后有相邻 Tahoe managed marker。
  - 未知结构、缺 marker 或重复同名块会拒绝写入，并给出恢复建议。
- 新增 `tahoe-shell/tests/test_niri_settings_tool.py`。
- 新增 `tahoe-shell/tests/fixtures/niri-settings/managed.kdl` 和 `managed-gaps-24.kdl`。

## 验收点

- 现有设置项仍可写入：`layout.gaps` 已通过 fixture、CLI 和真实 niri validate round-trip 验证。
- 非 Tahoe 管理段落保持不变：fixture 中未标记的 `window-rule` 块按字节保持不变。
- 未标记或重复的目标顶层块会拒绝写入，不会猜测用户手写配置。
- 生成非法配置时拒绝替换：fake niri validate 失败测试确认 live config 内容保持原样，临时文件被清理。
- 错误信息包含字段、目标块、缺失 marker 或重复块数量，并包含恢复建议。
- `niri validate` 和原子写入路径未移除。

## 验证

已执行：

```sh
python3 -m py_compile tahoe-shell/services/niri_settings_tool.py tahoe-shell/tests/test_niri_settings_tool.py
```

结果：通过。

```sh
python3 -m unittest discover -s tahoe-shell/tests -p 'test_*.py'
```

结果：通过，5 个测试全部通过。

```sh
python3 tahoe-shell/services/niri_settings_tool.py read --config config/niri/tahoe-phase0.kdl
```

结果：退出码 0，成功读取 layout、glass、blur、input、animations 和 binds。

```sh
niri/target/release/niri validate -c config/niri/tahoe-phase0.kdl
```

结果：退出码 0，输出 `config is valid`。

```sh
tmp=$(mktemp -d)
cp config/niri/tahoe-phase0.kdl "$tmp/config.kdl"
python3 tahoe-shell/services/niri_settings_tool.py write --config "$tmp/config.kdl" --field layout.gaps --value 17 --niri-bin "$PWD/niri/target/release/niri"
rm -rf "$tmp"
```

结果：退出码 0，返回 JSON 中 `changed=true`，`layout.gaps=17`。

```sh
git diff --check -- tahoe-shell/services/niri_settings_tool.py config/niri/tahoe-phase0.kdl tahoe-shell/tests/test_niri_settings_tool.py tahoe-shell/tests/fixtures/niri-settings/managed.kdl tahoe-shell/tests/fixtures/niri-settings/managed-gaps-24.kdl
```

结果：通过。

```sh
tmp=$(mktemp -d)
sed '/tahoe-managed:/d' config/niri/tahoe-phase0.kdl > "$tmp/config.kdl"
PYTHONDONTWRITEBYTECODE=1 python3 tahoe-shell/services/niri_settings_tool.py write --config "$tmp/config.kdl" --field layout.gaps --value 17
rm -rf "$tmp"
```

结果：按预期退出 1；JSON 错误包含 `refusing to edit layout.gaps`、缺失 `// tahoe-managed: begin layout` / `end layout`，以及重新部署 Tahoe config 或手动添加 marker 的恢复建议。

## 未执行项

未重启 live Tahoe shell，也未对真实设置面板做鼠标交互验收。原因：本阶段是写入边界收敛和 fixture 验证，为避免影响正在运行的桌面会话，本记录只做 helper、配置模板、单元测试和 niri validate 验收。
