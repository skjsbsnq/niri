.pragma library

// 桌面小部件网格布局核心：单元格划分、占用表、「找第一个可容纳空位」。
//
// 与宿主（WidgetHost.qml）的边界：
// - 本文件是纯函数 + 数据表，不碰 QML 场景图，可被结构测试逐函数断言；
// - 宿主持有对象实例（Widget.qml 子类），布局/写盘只读本文件的
//   GridState 结果，不在宿主内复制一套网格逻辑（G-6）。
//
// 网格原点：屏幕左下角（wallpaper 层 y 向下；行号从底部数起）。
// 单元坐标以【单元格左上角】为锚（x = col，y = row），与 pixel
// 换算一致：pixel = (unit + offset) * cellSize，offset 恒 ≤1。
//
// 表格只存 gridX / gridY / cols / rows 四元组 + 顺序数组（顺序 =
// 渲染 z 顺序：后添加的盖在前面的上面）。

var GRID_COLS = 4;   // 屏宽 4 列（A-6：medium/large 占满一行）
var GRID_ROWS = 4;   // 屏高方向最多 4 行（每屏最多 16 个单元格）

// region 上限（niri tahoe_glass MAX_REGIONS_PER_SURFACE=32）不是本文件的
// 常量：每小部件 1 个 region、每屏网格 ≤16，单屏不可能超 32；跨屏总量
// 由宿主在加载时按每屏上限截断并给出可见反馈（P-5）。
var LIMIT_ITEMS = 16;   // 单元格总数上限（4×4）

// 规格 → 网格占用（A-6）。
function colsForSize(size) {
    switch (size) {
    case "medium":
    case "large":
        return 4;
    default:
        return 2;
    }
}
function rowsForSize(size) {
    return size === "large" ? 4 : 2;
}
function validSize(size) {
    return size === "small" || size === "medium" || size === "large";
}

// 找「第一个可容纳空位」：行主序扫描（行 0 = 底部），跳过被占用单元格。
// 返回 {col, row}，找不到返回 null。
function findEmptyCell(state, cols, rows) {
    if (!state || !state.grid || !state.grid.length)
        return { col: 0, row: 0 };

    var occupied = state.grid;
    for (var r = 0; r < GRID_ROWS; r++) {
        for (var c = 0; c < GRID_COLS; c++) {
            var fits = true;
            for (var i = 0; i < occupied.length; i++) {
                var w = occupied[i];
                var cx = Number(w.gridX || 0);
                var cy = Number(w.gridY || 0);
                var cw = Number(w.cols || 0);
                var ch = Number(w.rows || 0);
                if (c >= cx && c < cx + cw && r >= cy && r < cy + ch) {
                    fits = false;
                    break;
                }
            }
            if (fits) {
                if (c + cols <= GRID_COLS && r + rows <= GRID_ROWS)
                    return { col: c, row: r };
            }
        }
    }
    return null;
}

// 占用表 from 配置数组 [{id,size,col,row}]：
// 配置列数不合法（超网格/负值/重叠）时剔除该条目并返回 {state, removed}。
function gridStateFromConfig(list) {
    var state = { grid: [], removed: [] };
    if (!Array.isArray(list))
        return state;

    var present = {};
    for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (!item || typeof item !== "object")
            continue;

        var id = String(item.id || "");
        var size = String(item.size || "small");
        var col = Math.round(Number(item.col) || 0);
        var row = Math.round(Number(item.row) || 0);
        if (id.length === 0)
            continue;
        if (!validSize(size))
            size = "small";
        var cols = colsForSize(size);
        var rows = rowsForSize(size);
        var ok = col >= 0 && row >= 0
            && col + cols <= GRID_COLS
            && row + rows <= GRID_ROWS;
        if (ok && !present[id]) {
            // 重叠检查：与已接受条目矩形相交 → 剔除新条目。
            for (var j = 0; j < state.grid.length; j++) {
                var w = state.grid[j];
                if (col < w.gridX + w.cols && col + cols > w.gridX
                        && row < w.gridY + w.rows && row + rows > w.gridY) {
                    ok = false;
                    break;
                }
            }
        } else if (ok && present[id]) {
            ok = false; // 重复 id：只保留首个
        }
        if (ok) {
            present[id] = true;
            state.grid.push({ id: id, gridX: col, gridY: row, cols: cols, rows: rows });
        } else {
            state.removed.push(item);
        }
    }
    return state;
}

// 追加一个小部件：找空位（不写表）。返回 {col, row} 或 null。
// 调用方（宿主）负责：构造新配置数组 → 重建 GridState → 建实例。
// 表格本身由 GridState 在配置变化时整体重建（单一数据流，宿主不在
// 表外维护第二份位置状态，G-6）。
function findSlot(state, cols, rows) {
    if (!state || !state.grid)
        return null;
    // 容量检查必须先于找空位：满网格时 findEmptyCell 返回 null，
    // 容量检查就永远不可达。
    if (state.grid.length >= LIMIT_ITEMS)
        return null;
    return findEmptyCell(state, cols, rows);
}

// 序列化：表格 → 配置数组 [{id,size,col,row}]（A2 格式）。
function serializeEntries(state) {
    var out = [];
    if (!state || !state.grid)
        return out;
    for (var i = 0; i < state.grid.length; i++) {
        var w = state.grid[i];
        out.push({
            "id": String(w.id || ""),
            "size": sizeForSpan(w.cols, w.rows),
            "col": Math.round(w.gridX),
            "row": Math.round(w.gridY)
        });
    }
    return out;
}

function sizeForSpan(cols, rows) {
    if (cols >= 4 && rows >= 4)
        return "large";
    if (cols >= 4)
        return "medium";
    return "small";
}
