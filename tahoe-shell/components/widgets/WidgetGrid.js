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

// 默认网格维度（A6 起宿主按屏传入实际列/行数；本默认值供库预览、结构
// 测试与窄屏兜底使用，见 WidgetHost.gridCols/gridRows）。网格尺寸语义：
// cellSize 固定（≤90px），列/行数 = floor(屏宽/高 ÷ cellSize) 铺满全屏，
// 小部件可在桌面任意位置摆放（部署反馈：固定 4×6 只能覆盖左下角一块）。
var GRID_COLS = 4;
var GRID_ROWS = 6;

// 默认条目上限（宿主按屏传入 min(32, 网格容量)，P-5 region 上限 32；
// 本默认值仅供不传参数的调用方/单测使用）。
var LIMIT_ITEMS = 24;

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
function gridDims(gridCols, gridRows) {
    return {
        "cols": Math.max(1, Math.round(Number(gridCols) > 0 ? Number(gridCols) : GRID_COLS)),
        "rows": Math.max(1, Math.round(Number(gridRows) > 0 ? Number(gridRows) : GRID_ROWS))
    };
}

function findEmptyCell(state, cols, rows, gridCols, gridRows) {
    var dims = gridDims(gridCols, gridRows);
    gridCols = dims.cols;
    gridRows = dims.rows;
    if (!state || !state.grid || !state.grid.length)
        return { col: 0, row: 0 };

    var occupied = state.grid;
    for (var r = 0; r < gridRows; r++) {
        for (var c = 0; c < gridCols; c++) {
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
                if (c + cols <= gridCols && r + rows <= gridRows)
                    return { col: c, row: r };
            }
        }
    }
    return null;
}

// 占用表 from 配置数组 [{id,size,col,row}]：
// 配置列数不合法（超网格/负值/重叠）时剔除该条目并返回 {state, removed}。
function gridStateFromConfig(list, gridCols, gridRows) {
    var dims = gridDims(gridCols, gridRows);
    gridCols = dims.cols;
    gridRows = dims.rows;
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
            && col + cols <= gridCols
            && row + rows <= gridRows;
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
function findSlot(state, cols, rows, gridCols, gridRows, limitItems) {
    if (!state || !state.grid)
        return null;
    var limit = Number(limitItems) > 0 ? Number(limitItems) : LIMIT_ITEMS;
    // 容量检查必须先于找空位：满网格时 findEmptyCell 返回 null，
    // 容量检查就永远不可达。
    if (state.grid.length >= limit)
        return null;
    return findEmptyCell(state, cols, rows, gridCols, gridRows);
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

// ---- A6 拖动落点（纯函数；宿主拖动提交只读本文件结果）----
// 像素 → 网格坐标换算（与宿主实例布局公式同一来源，G-6）：
// - x 左起：col = xPx / cellSize
// - y 为屏幕坐标（上起），网格行号从底部数起（A2 语义）：
//   row = (screenHeight - yPx) / cellSize - rows
function xPxForCell(col, cellSize) {
    return Math.round(Number(col) * Number(cellSize));
}
function yPxForCell(row, rows, cellSize, screenHeight) {
    return Math.round(Number(screenHeight) - (Number(row) + Number(rows)) * Number(cellSize));
}

// 小部件左上角像素 → 最近合法网格位（clamp 到网格边界）。
// cols/rows 为该小部件跨度；返回 {col, row}。
function snapPosition(cols, rows, xPx, yPx, cellSize, screenHeight, gridCols, gridRows) {
    var dims = gridDims(gridCols, gridRows);
    var cell = Math.max(1, Number(cellSize) || 1);
    var h = Math.max(1, Number(screenHeight) || 1);
    var col = Math.round(Number(xPx) / cell);
    var row = Math.round((h - Number(yPx)) / cell - Number(rows));
    var maxCol = Math.max(0, dims.cols - Number(cols));
    var maxRow = Math.max(0, dims.rows - Number(rows));
    return {
        "col": Math.max(0, Math.min(maxCol, col)),
        "row": Math.max(0, Math.min(maxRow, row))
    };
}

// 落点是否可放置：边界合法 + 与除 id 外的条目无重叠。
// grid 为 GridState.grid（含 gridX/gridY/cols/rows 的条目数组）。
function canPlace(grid, id, col, row, cols, rows, gridCols, gridRows) {
    var dims = gridDims(gridCols, gridRows);
    var entries = Array.isArray(grid) ? grid : [];
    var c = Math.round(Number(col) || 0);
    var r = Math.round(Number(row) || 0);
    var w = Math.round(Number(cols) || 0);
    var h = Math.round(Number(rows) || 0);
    if (c < 0 || r < 0 || c + w > dims.cols || r + h > dims.rows)
        return false;
    for (var i = 0; i < entries.length; i++) {
        var item = entries[i];
        if (!item)
            continue;
        if (id !== undefined && id !== null && String(item.id || "") === String(id))
            continue;
        var cx = Number(item.gridX || 0);
        var cy = Number(item.gridY || 0);
        var cw = Number(item.cols || 0);
        var ch = Number(item.rows || 0);
        if (c < cx + cw && c + w > cx && r < cy + ch && r + h > cy)
            return false;
    }
    return true;
}
