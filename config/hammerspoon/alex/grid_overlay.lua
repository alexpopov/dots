local cols = 7
local rows = 7
local MIN_GRID = 2
local MAX_GRID = 16

-- Screen layout: used to compute usable area from fullFrame
local MENUBAR_HEIGHT = 37   -- 25 without notch, 37 with notch
local DOCK_ENABLED = true
local DOCK_POSITION = "bottom"  -- "left", "bottom", "right"
local DOCK_SIZE = 70            -- approximate dock thickness in pixels

local canvas = require("hs.canvas")
local screen = require("hs.screen")
local hotkey = require("hs.hotkey")
local eventtap = require("hs.eventtap")
local timer = require("hs.timer")
local alert = require("hs.alert")
local json = require("hs.json")
local fs = require("hs.fs")
local styledtext = require("hs.styledtext")

local M = {}

local overlay = nil
local modal = nil
local confirm_modal = nil
local active = false
local cell_indices = {} -- [row][col] -> canvas element index
local target_window_id = nil
local target_window_frame = nil
local mode = "move" -- "move", "resize", "grid"
local pending_digit = nil

local sel = { x = 2, y = 1, w = 3, h = 4 }
local key_swallower = nil
local swallow_count = 0
local SWALLOW_SHAKE_EVERY = 3

local CELL_PAD = 2
local GRID_PAD = 8  -- inner padding so corner cells clear the rounded background

-- Colors
local COLOR_UNSELECTED = { white = 1, alpha = 0.05 }
local COLOR_STROKE_UNSELECTED = { white = 1, alpha = 0.3 }
local COLOR_BG = { white = 0.1, alpha = 0.3 }

-- Move mode: blue selection
local COLOR_SEL_MOVE = { red = 0.2, green = 0.5, blue = 0.9, alpha = 0.4 }
local COLOR_STROKE_SEL_MOVE = { white = 1, alpha = 0.6 }

-- Resize mode: red selection
local COLOR_SEL_RESIZE = { red = 0.9, green = 0.25, blue = 0.2, alpha = 0.35 }
local COLOR_STROKE_SEL_RESIZE = { red = 1, green = 0.4, blue = 0.3, alpha = 0.6 }

-- Grid mode: red border, pink/red cells throughout
local COLOR_GRID_BORDER = { red = 0.9, green = 0.25, blue = 0.2, alpha = 0.6 }
local GRID_BORDER_WIDTH = 3
local COLOR_UNSELECTED_GRID = { red = 0.9, green = 0.2, blue = 0.15, alpha = 0.15 }
local COLOR_STROKE_UNSELECTED_GRID = { red = 1, green = 0.4, blue = 0.3, alpha = 0.3 }
local COLOR_SEL_GRID = { red = 0.85, green = 0.25, blue = 0.6, alpha = 0.4 }
local COLOR_STROKE_SEL_GRID = { red = 1, green = 0.4, blue = 0.7, alpha = 0.6 }

-- Resolve yabai path once
local yabai_path = (function()
    local candidates = {
        "/opt/homebrew/bin/yabai",
        "/usr/local/bin/yabai",
    }
    for _, path in ipairs(candidates) do
        if fs.displayName(path) ~= nil then
            return path
        end
    end
    return "yabai"
end)()

local function usable_frame()
    local sf = screen.mainScreen():fullFrame()
    local ux = sf.x
    local uy = sf.y + MENUBAR_HEIGHT
    local uw = sf.w
    local uh = sf.h - MENUBAR_HEIGHT
    if DOCK_ENABLED then
        if DOCK_POSITION == "left" then
            ux = ux + DOCK_SIZE; uw = uw - DOCK_SIZE
        elseif DOCK_POSITION == "right" then
            uw = uw - DOCK_SIZE
        elseif DOCK_POSITION == "bottom" then
            uh = uh - DOCK_SIZE
        end
    end
    return { x = ux, y = uy, w = uw, h = uh }
end

local function capture_target_window()
    local output, ok = hs.execute(yabai_path .. " -m query --windows --window 2>/dev/null", true)
    if not ok or not output or output == "" then
        target_window_id = nil
        target_window_frame = nil
        return
    end
    local win = json.decode(output)
    target_window_id = win and win.id or nil
    target_window_frame = win and win.frame or nil
end

local function init_selection_from_window()
    if not target_window_frame then return end
    local uf = usable_frame()
    local wf = target_window_frame

    local rx = (wf.x - uf.x) / uf.w
    local ry = (wf.y - uf.y) / uf.h
    local rw = wf.w / uf.w
    local rh = wf.h / uf.h

    sel.x = math.max(0, math.floor(rx * cols + 0.5))
    sel.y = math.max(0, math.floor(ry * rows + 0.5))
    sel.w = math.max(1, math.floor(rw * cols + 0.5))
    sel.h = math.max(1, math.floor(rh * rows + 0.5))
    clamp_selection()
end

local function is_window_floating()
    local output, ok = hs.execute(yabai_path .. " -m query --windows --window 2>/dev/null", true)
    if not ok or not output or output == "" then return true end
    local win = json.decode(output)
    if not win then return true end
    return win["is-floating"]
end

local function float_focused_window()
    hs.execute(yabai_path .. " -m window --toggle float 2>/dev/null", true)
end

local function overlay_frame()
    local sf = screen.mainScreen():frame()
    return {
        x = sf.x + sf.w / 3,
        y = sf.y + sf.h / 3,
        w = sf.w / 3,
        h = sf.h / 3,
    }
end

local function shake_canvas(c)
    if not c then return end
    local f = c:frame()
    local orig_x = f.x
    local steps = { 3, -3, 2, -2, 0 }
    local i = 0
    timer.doEvery(0.03, function()
        i = i + 1
        if i > #steps then return end
        local cf = c:frame()
        cf.x = orig_x + steps[i]
        c:frame(cf)
        if i >= #steps then return end
    end)
end

local SPECIAL_KEYCODES = {
    [36] = "return", [53] = "escape", [49] = "space",
    [48] = "tab",
    [24] = "=", [27] = "-",
}

local function start_swallower(allowed)
    swallow_count = 0
    if key_swallower then key_swallower:stop() end
    local allowed_set = {}
    for _, k in ipairs(allowed) do allowed_set[k] = true end

    key_swallower = eventtap.new({ eventtap.event.types.keyDown }, function(event)
        local kc = event:getKeyCode()

        local name = SPECIAL_KEYCODES[kc]
        if not name then
            local chars = event:getCharacters()
            if chars and #chars > 0 then name = chars end
        end

        if not name then return true end
        if allowed_set[name] then return false end

        swallow_count = swallow_count + 1
        if swallow_count % SWALLOW_SHAKE_EVERY == 0 then
            shake_canvas(overlay) -- uses current overlay, survives rebuilds
        end
        return true
    end)
    -- Delay start so skhd's back_to_default escape key can land first
    timer.doAfter(0.1, function() if key_swallower then key_swallower:start() end end)
end

local function stop_swallower()
    if key_swallower then
        key_swallower:stop()
        key_swallower = nil
    end
    swallow_count = 0
end

local function show_confirm_alert()
    local app_name = "Window"
    local win = hs.window.focusedWindow()
    if win and win:application() then
        app_name = win:application():name()
    end
    alert.show(app_name .. " is managed. Float it? (y/n)", { textSize = 20 }, 10)
end

local function clamp_selection()
    if sel.w > cols then sel.w = cols end
    if sel.h > rows then sel.h = rows end
    if sel.x < 0 then sel.x = 0 end
    if sel.y < 0 then sel.y = 0 end
    if sel.x + sel.w > cols then sel.x = cols - sel.w end
    if sel.y + sel.h > rows then sel.y = rows - sel.h end
end

local function rescale_selection(old_cols, old_rows)
    sel.w = math.max(1, math.floor(sel.w * cols / old_cols + 0.5))
    sel.h = math.max(1, math.floor(sel.h * rows / old_rows + 0.5))
    sel.x = math.floor(sel.x * cols / old_cols + 0.5)
    sel.y = math.floor(sel.y * rows / old_rows + 0.5)
    clamp_selection()
end

local function is_selected(row, col)
    return col >= sel.x and col < sel.x + sel.w
       and row >= sel.y and row < sel.y + sel.h
end

local function redraw()
    if not overlay then return end

    -- Background border for grid mode
    if mode == "grid" then
        overlay:elementAttribute(1, "action", "strokeAndFill")
        overlay:elementAttribute(1, "strokeColor", COLOR_GRID_BORDER)
        overlay:elementAttribute(1, "strokeWidth", GRID_BORDER_WIDTH)
    else
        overlay:elementAttribute(1, "action", "fill")
        overlay:elementAttribute(1, "strokeColor", { white = 0, alpha = 0 })
        overlay:elementAttribute(1, "strokeWidth", 0)
    end

    -- Cell colors based on mode
    local sel_fill, sel_stroke, unsel_fill, unsel_stroke
    if mode == "resize" then
        sel_fill, sel_stroke = COLOR_SEL_RESIZE, COLOR_STROKE_SEL_RESIZE
        unsel_fill, unsel_stroke = COLOR_UNSELECTED, COLOR_STROKE_UNSELECTED
    elseif mode == "grid" then
        sel_fill, sel_stroke = COLOR_SEL_GRID, COLOR_STROKE_SEL_GRID
        unsel_fill, unsel_stroke = COLOR_UNSELECTED_GRID, COLOR_STROKE_UNSELECTED_GRID
    else
        sel_fill, sel_stroke = COLOR_SEL_MOVE, COLOR_STROKE_SEL_MOVE
        unsel_fill, unsel_stroke = COLOR_UNSELECTED, COLOR_STROKE_UNSELECTED
    end

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local idx = cell_indices[row][col]
            if is_selected(row, col) then
                overlay:elementAttribute(idx, "fillColor", sel_fill)
                overlay:elementAttribute(idx, "strokeColor", sel_stroke)
            else
                overlay:elementAttribute(idx, "fillColor", unsel_fill)
                overlay:elementAttribute(idx, "strokeColor", unsel_stroke)
            end
        end
    end
end

local function build_canvas()
    if overlay then
        overlay:delete()
        overlay = nil
    end

    local f = overlay_frame()

    overlay = canvas.new(f)
    overlay:level(canvas.windowLevels.overlay)
    overlay:behavior(canvas.windowBehaviors.canJoinAllSpaces)

    -- Background (element 1)
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = COLOR_BG,
        strokeColor = { white = 0, alpha = 0 },
        strokeWidth = 0,
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
        frame = { x = 0, y = 0, w = f.w, h = f.h },
    })

    -- Grid cells (inset by GRID_PAD to clear rounded background corners)
    local gridW = f.w - GRID_PAD * 2
    local gridH = f.h - GRID_PAD * 2
    local cellW = gridW / cols
    local cellH = gridH / rows
    cell_indices = {}

    for row = 0, rows - 1 do
        cell_indices[row] = {}
        for col = 0, cols - 1 do
            local x = GRID_PAD + col * cellW + CELL_PAD
            local y = GRID_PAD + row * cellH + CELL_PAD
            local w = cellW - CELL_PAD * 2
            local h = cellH - CELL_PAD * 2

            overlay:appendElements({
                type = "rectangle",
                action = "strokeAndFill",
                strokeColor = COLOR_STROKE_UNSELECTED,
                fillColor = COLOR_UNSELECTED,
                strokeWidth = 1,
                roundedRectRadii = { xRadius = 4, yRadius = 4 },
                frame = { x = x, y = y, w = w, h = h },
            })
            cell_indices[row][col] = 1 + row * cols + col + 1
        end
    end
end

-- Mode indicator pill (below grid)
local pill = nil
local PILL_W = 100
local PILL_H = 20

local MODE_PILL_COLORS = {
    move = { white = 1, alpha = 0.7 },
    resize = { red = 1, green = 0.4, blue = 0.3, alpha = 0.9 },
    grid = { red = 1, green = 0.4, blue = 0.3, alpha = 0.9 },
}

local function hide_pill()
    if pill then pill:delete(); pill = nil end
end

local function build_pill()
    hide_pill()
    local f = overlay_frame()
    local px = f.x + (f.w - PILL_W) / 2
    local py = f.y + f.h + 6

    pill = canvas.new({ x = px, y = py, w = PILL_W, h = PILL_H })
    pill:level(canvas.windowLevels.overlay)
    pill:behavior(canvas.windowBehaviors.canJoinAllSpaces)
    pill:appendElements({
        type = "rectangle", action = "fill",
        fillColor = { white = 0.2, alpha = 0.5 },
        roundedRectRadii = { xRadius = 6, yRadius = 6 },
        frame = { x = 0, y = 0, w = PILL_W, h = PILL_H },
    })

    local dim_text
    if pending_digit then
        dim_text = "  " .. pending_digit .. "x_"
    elseif mode == "resize" then
        dim_text = "  " .. sel.w .. "x" .. sel.h
    else
        dim_text = "  " .. cols .. "x" .. rows
    end
    local label = styledtext.new(mode, {
        font = { name = "Menlo", size = 11 },
        color = MODE_PILL_COLORS[mode],
    }) .. styledtext.new(dim_text, {
        font = { name = "Menlo", size = 11 },
        color = pending_digit and { white = 1, alpha = 0.7 } or { white = 1, alpha = 0.4 },
    })
    label = label:setStyle({ paragraphStyle = { alignment = "center" } })

    pill:appendElements({
        type = "text",
        frame = { x = 0, y = 1, w = PILL_W, h = PILL_H },
        text = label,
    })
    pill:show()
end

local apply_task = nil
local apply  -- forward declaration

local function set_mode(new_mode)
    mode = new_mode
    pending_digit = nil
    redraw()
    build_pill()
end

local function rebuild_grid()
    clamp_selection()
    hide_pill()
    build_canvas()
    redraw()
    overlay:show()
    build_pill()
    apply()
end

apply = function()
    if not target_window_id then return end
    if apply_task and apply_task:isRunning() then apply_task:terminate() end
    local spec = string.format("%d:%d:%d:%d:%d:%d", rows, cols, sel.x, sel.y, sel.w, sel.h)
    apply_task = hs.task.new(yabai_path, nil, {
        "-m", "window", tostring(target_window_id), "--grid", spec,
    })
    apply_task:start()
end

local function exit_overlay()
    if modal then modal:exit() end
    active = false
end

local function enter_overlay()
    mode = "move"
    pending_digit = nil
    init_selection_from_window()
    if modal then modal:enter() end
    active = true
end

-- Build the modal (no trigger key)
modal = hotkey.modal.new()

modal.entered = function()
    build_canvas()
    redraw()
    overlay:show()
    build_pill()
    start_swallower({
        "h", "j", "k", "l",
        "r", "g", "tab", "q",
        "=", "-", "return", "escape",
        "1", "2", "3", "4", "5", "6", "7", "8", "9",
    })
end

modal.exited = function()
    stop_swallower()
    hide_pill()
    if overlay then
        overlay:delete()
        overlay = nil
    end
    cell_indices = {}
end

-- hjkl: mode-dependent
local function on_h()
    if mode == "move" then
        sel.x = math.max(0, sel.x - 1)
    elseif mode == "resize" then
        if sel.w > 1 then sel.w = sel.w - 1 end
    elseif mode == "grid" then
        if cols > MIN_GRID then
            local oc = cols; cols = cols - 1; rescale_selection(oc, rows)
            rebuild_grid(); return
        end
    end
    redraw(); apply()
end

local function on_l()
    if mode == "move" then
        sel.x = math.min(cols - sel.w, sel.x + 1)
    elseif mode == "resize" then
        if sel.x + sel.w < cols then sel.w = sel.w + 1 end
    elseif mode == "grid" then
        if cols < MAX_GRID then
            local oc = cols; cols = cols + 1; rescale_selection(oc, rows)
            rebuild_grid(); return
        end
    end
    redraw(); apply()
end

local function on_k()
    if mode == "move" then
        sel.y = math.max(0, sel.y - 1)
    elseif mode == "resize" then
        if sel.h > 1 then sel.h = sel.h - 1 end
    elseif mode == "grid" then
        if rows > MIN_GRID then
            local or_ = rows; rows = rows - 1; rescale_selection(cols, or_)
            rebuild_grid(); return
        end
    end
    redraw(); apply()
end

local function on_j()
    if mode == "move" then
        sel.y = math.min(rows - sel.h, sel.y + 1)
    elseif mode == "resize" then
        if sel.y + sel.h < rows then sel.h = sel.h + 1 end
    elseif mode == "grid" then
        if rows < MAX_GRID then
            local or_ = rows; rows = rows + 1; rescale_selection(cols, or_)
            rebuild_grid(); return
        end
    end
    redraw(); apply()
end

modal:bind({}, "h", on_h)
modal:bind({}, "j", on_j)
modal:bind({}, "k", on_k)
modal:bind({}, "l", on_l)

-- Mode switching
modal:bind({}, "r", function() set_mode("resize") end)
modal:bind({}, "g", function() set_mode("grid") end)
modal:bind({}, "tab", function()
    local next_mode = { move = "grid", grid = "resize", resize = "move" }
    set_mode(next_mode[mode])
end)

-- Digit input: two single digits, behavior depends on mode
-- move/grid: set grid size (cols x rows)
-- resize: set selection size (width x height)
for i = 1, 9 do
    modal:bind({}, tostring(i), function()
        if pending_digit then
            if mode == "resize" then
                sel.w = math.min(pending_digit, cols)
                sel.h = math.min(i, rows)
                if sel.x + sel.w > cols then sel.x = cols - sel.w end
                if sel.y + sel.h > rows then sel.y = rows - sel.h end
                pending_digit = nil
                set_mode("move")
                apply()
            else
                local oc, or_ = cols, rows
                cols = math.max(MIN_GRID, pending_digit)
                rows = math.max(MIN_GRID, i)
                pending_digit = nil
                rescale_selection(oc, or_)
                mode = "resize"
                rebuild_grid()
            end
        else
            pending_digit = i
            build_pill()
        end
    end)
end

-- Escape: back to move, or exit if already in move
modal:bind({}, "escape", function()
    if pending_digit then
        pending_digit = nil
        build_pill()
    elseif mode ~= "move" then
        set_mode("move")
    else
        exit_overlay()
    end
end)

-- q: always exit
modal:bind({}, "q", function()
    exit_overlay()
end)

-- Scale bindings (+/- and =/-)
local function scale_up()
    if mode == "grid" then
        local oc, or_ = cols, rows
        if cols < MAX_GRID then cols = cols + 1 end
        if rows < MAX_GRID then rows = rows + 1 end
        if cols ~= oc or rows ~= or_ then
            rescale_selection(oc, or_)
            rebuild_grid()
        end
    elseif mode == "resize" then
        if sel.x + sel.w < cols then sel.w = sel.w + 1 end
        if sel.y + sel.h < rows then sel.h = sel.h + 1 end
        redraw(); apply()
    else
        local nx = math.max(0, sel.x - 1)
        local ny = math.max(0, sel.y - 1)
        local nw = math.min(cols, sel.w + (sel.x - nx) + 1)
        local nh = math.min(rows, sel.h + (sel.y - ny) + 1)
        if nx + nw > cols then nw = cols - nx end
        if ny + nh > rows then nh = rows - ny end
        sel.x, sel.y, sel.w, sel.h = nx, ny, nw, nh
        redraw(); apply()
    end
end

local function scale_down()
    if mode == "grid" then
        local oc, or_ = cols, rows
        if cols > MIN_GRID then cols = cols - 1 end
        if rows > MIN_GRID then rows = rows - 1 end
        if cols ~= oc or rows ~= or_ then
            rescale_selection(oc, or_)
            rebuild_grid()
        end
    elseif mode == "resize" then
        if sel.w > 1 then sel.w = sel.w - 1 end
        if sel.h > 1 then sel.h = sel.h - 1 end
        redraw(); apply()
    else
        if sel.w > 1 then
            sel.x = sel.x + 1
            sel.w = sel.w - 2
            if sel.w < 1 then sel.w = 1 end
        end
        if sel.h > 1 then
            sel.y = sel.y + 1
            sel.h = sel.h - 2
            if sel.h < 1 then sel.h = 1 end
        end
        redraw(); apply()
    end
end

modal:bind({}, "=", scale_up)
modal:bind({"shift"}, "=", scale_up)  -- + key
modal:bind({}, "-", scale_down)

-- Apply and exit
modal:bind({}, "return", function()
    apply()
    exit_overlay()
end)

-- Confirmation modal for managed windows
confirm_modal = hotkey.modal.new()

local function confirm_yes()
    confirm_modal:exit()
    alert.closeAll()
    float_focused_window()
    enter_overlay()
end

local function confirm_no()
    confirm_modal:exit()
    alert.closeAll()
end

confirm_modal:bind({}, "y", confirm_yes)
confirm_modal:bind({}, "space", confirm_yes)
confirm_modal:bind({}, "return", confirm_yes)
confirm_modal:bind({}, "n", confirm_no)
confirm_modal:bind({}, "escape", confirm_no)

function M.toggle()
    if active then
        exit_overlay()
    else
        capture_target_window()
        if not is_window_floating() then
            show_confirm_alert()
            confirm_modal:enter()
        else
            enter_overlay()
        end
    end
end

return M
