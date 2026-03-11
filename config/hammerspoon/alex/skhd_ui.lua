local canvas = require("hs.canvas")
local screen = require("hs.screen")
local timer = require("hs.timer")
local styledtext = require("hs.styledtext")
local drawing = require("hs.drawing")
local alert = require("hs.alert")

-- ---------------------------------------------------------------------------
-- Scale system
-- ---------------------------------------------------------------------------

local SCALE = 1.2  -- increase this to make everything bigger

local function S(n) return math.floor(n * SCALE) end

-- ---------------------------------------------------------------------------
-- Color system — three colors, that's it
-- ---------------------------------------------------------------------------

local OUTSIDE_COLOR = { white = 0.91, alpha = 0.97 }  -- light grey
local SLOT_COLOR    = { white = 0.82, alpha = 1.0 }    -- darker grey
local BLOCK_COLOR   = { white = 0.91, alpha = 0.97 }   -- same as outside

local BLOCK_TEXT_CLR = { white = 0.3 }
local KEY_CLR        = { red = 0.3, green = 0.45, blue = 0.7 }
local DESC_CLR       = { white = 0.4 }
local DONE_GREEN     = { red = 0.35, green = 0.68, blue = 0.38 }
local DONE_TEXT_CLR  = { white = 1.0 }
local ACTION_COLOR   = { red = 0.72, green = 0.85, blue = 0.96 }
local ACTION_TEXT_CLR = { red = 0.2, green = 0.4, blue = 0.65 }

-- ---------------------------------------------------------------------------
-- Text measurement helper
-- ---------------------------------------------------------------------------

local function measure_text(st)
    local size = drawing.getTextDrawingSize(st)
    return size and size.w or 0, size and size.h or 0
end

local M = {}

-- ---------------------------------------------------------------------------
-- Mode data
-- ---------------------------------------------------------------------------

local MODES = {
    windows = {
        label = "Windows",
        parent = nil,
        options = {
            { key = "h/j/k/l", desc = "focus" },
            { key = "n/p",     desc = "stack next/prev" },
            { key = "d",       desc = "fullscreen" },
            { key = "u",       desc = "float toggle" },
            { key = "f",       desc = "focus mode" },
            { key = "c",       desc = "create stacks" },
            { key = "r",       desc = "resize" },
            { key = "s",       desc = "swap" },
            { key = "w",       desc = "warp" },
            { key = "t",       desc = "tabs" },
            { key = "\\",      desc = "yabai config" },
            { key = "a",       desc = "actions" },
            { key = "1",       desc = "hyper" },
        },
    },
    focus = {
        label = "Focus",
        parent = "windows",
        options = {
            { key = "h/j/k/l",     desc = "focus window" },
            { key = "n/p",          desc = "stack next/prev" },
            { key = "f",            desc = "focus largest" },
            { key = "⇧ h/j/k/l",   desc = "focus display" },
        },
    },
    create = {
        label = "Create",
        parent = "windows",
        options = {
            { key = "h/j/k/l",     desc = "stack direction" },
            { key = "⌃ h/j/k/l",   desc = "stack (stay)" },
            { key = "u",            desc = "unstack" },
        },
    },
    resize = {
        label = "Resize",
        parent = "windows",
        options = {
            { key = "h/j/k/l",     desc = "resize ±20" },
            { key = "⇧ h/j/k/l",   desc = "resize ±100" },
            { key = "c",            desc = "center" },
            { key = "m",            desc = "small center" },
            { key = "f",            desc = "fullscreen" },
            { key = "b",            desc = "balance" },
            { key = "r",            desc = "rotate" },
            { key = "i",            desc = "grid overlay" },
            { key = "3/4/5",        desc = "thirds/fourths/fifths" },
        },
    },
    swap = {
        label = "Swap",
        parent = "windows",
        options = {
            { key = "h/j/k/l", desc = "swap direction" },
        },
    },
    warp = {
        label = "Warp",
        parent = "windows",
        options = {
            { key = "h/j/k/l",     desc = "warp direction" },
            { key = "⇧ h/j/k/l",   desc = "warp display" },
            { key = "1/2/3",        desc = "warp to display N" },
            { key = "f",            desc = "warp + fullscreen" },
        },
    },
    tabs = {
        label = "Tabs",
        parent = "windows",
        options = {
            { key = "h/l", desc = "prev/next tab" },
        },
    },
    yabai_config = {
        label = "Config",
        parent = "windows",
        options = {
            { key = "f", desc = "layout float" },
            { key = "t", desc = "layout BSP" },
            { key = "r", desc = "reload yabairc" },
        },
    },
    actions = {
        label = "Actions",
        parent = "windows",
        options = {
            { key = "p",          desc = "debug" },
            { key = "m",          desc = "move tab (Chrome)" },
            { key = ",",          desc = "name window (Chrome)" },
            { key = "t",          desc = "new tab right (Chrome)" },
            { key = "d/⇧d",      desc = "show/hide dock" },
            { key = "s/⇧s",      desc = "condensed/airy" },
            { key = "a/⇧a/⌃a",   desc = "manage less/more/none" },
        },
    },
    hyper = {
        label = "Hyper",
        parent = "windows",
        options = {
            { key = "r", desc = "reload skhd" },
            { key = "v", desc = "clipboard" },
            { key = "o", desc = "open" },
            { key = "s", desc = "→ windows" },
            { key = "a", desc = "→ actions" },
        },
    },
    resize_3 = { label = "Thirds",  parent = "resize", options = { { key = "d", desc = "centered" } } },
    resize_4 = { label = "Fourths", parent = "resize", options = { { key = "d", desc = "centered" } } },
    resize_5 = { label = "Fifths",  parent = "resize", options = { { key = "d", desc = "centered" } } },
}

-- ---------------------------------------------------------------------------
-- Layout constants (all scaled)
-- ---------------------------------------------------------------------------

-- Bar structure: outside [ bar [ slot [ block ] [ block ] ] ]
-- Each padding level is independently configurable:
local OUTER_PAD      = S(6)       -- bar edge → slot edge (all sides)
local BAR_RADIUS     = S(10)      -- outer corners
local SLOT_RADIUS    = S(6)       -- inner slot corners (smaller than bar)
local SLOT_PAD_X     = S(4)       -- slot edge → first/last block (horizontal)
local SLOT_PAD_Y     = S(4)       -- slot edge → block top/bottom (vertical)
local BLOCK_TEXT_PAD = S(16)      -- text padding inside each block (horizontal)
local TEXT_NUDGE_Y   = S(2)       -- text vertical offset within block (+ = down)
local BAR_HEIGHT     = S(44)
local BLOCK_RADIUS   = S(4)       -- block corners (smallest)
local BLOCK_GAP      = S(4)       -- gap between blocks
local BLOCK_FONT_SZ  = S(18)      -- block label font size
local MIN_BAR_W      = S(400)     -- ~4 blocks wide minimum
local BAR_Y_RATIO    = 0.38       -- vertical position (0=top, 0.5=center, 1=bottom)

-- Options
local OPT_PAD        = S(14)
local OPT_ROW_H      = S(22)
local OPT_ROW_GAP    = S(3)
local OPT_RADIUS     = S(10)
local KEY_COL_W      = S(110)
local OPT_FONT_SZ    = S(12)
local OPT_GAP        = S(6)
local OPT_EXTRA_W    = S(12)      -- extra width padding in options panel

-- Timing
local OPTIONS_DELAY  = 1.0    -- seconds before showing options grid
local DONE_HOLD      = 0.4    -- seconds to hold "Done" before fading
local FADE_DURATION  = 0.3    -- fade-out duration
local FADE_STEP      = 0.016  -- fade animation interval

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local cv_bar       = nil
local cv_options   = nil
local current_mode = nil
local current_action = nil
local fade_timer   = nil
local options_timer = nil

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function cancel_timers()
    if fade_timer then fade_timer:stop(); fade_timer = nil end
    if options_timer then options_timer:stop(); options_timer = nil end
end

local function hide()
    cancel_timers()
    if cv_bar then cv_bar:delete(); cv_bar = nil end
    if cv_options then cv_options:delete(); cv_options = nil end
    current_mode = nil
end

local function build_breadcrumb_path(mode_name)
    local path = {}
    local m = mode_name
    while m do
        table.insert(path, 1, MODES[m].label)
        m = MODES[m].parent
    end
    return path
end

local function primary_screen_frame()
    return screen.primaryScreen():frame()
end

local function make_block_text(label)
    return styledtext.new(label, {
        font = { name = ".AppleSystemUIFontBold", size = BLOCK_FONT_SZ },
        color = BLOCK_TEXT_CLR,
        paragraphStyle = {
            alignment = "center",
            lineBreakMode = "truncatingTail",
        },
    })
end

-- ---------------------------------------------------------------------------
-- Build breadcrumb bar canvas
-- ---------------------------------------------------------------------------

local function build_bar(path, done_text, action_text)
    -- Measure blocks to compute total width
    local block_widths = {}
    local total_blocks_w = 0
    for i, label in ipairs(path) do
        local st = make_block_text(label)
        local tw = measure_text(st)
        local bw = tw + 2 * BLOCK_TEXT_PAD
        block_widths[i] = bw
        total_blocks_w = total_blocks_w + bw
    end

    -- Measure action block if present
    local action_block_w = 0
    if action_text then
        local st = styledtext.new(action_text, {
            font = { name = ".AppleSystemUIFontBold", size = BLOCK_FONT_SZ },
            color = ACTION_TEXT_CLR,
            paragraphStyle = { alignment = "center" },
        })
        action_block_w = measure_text(st) + 2 * BLOCK_TEXT_PAD
        total_blocks_w = total_blocks_w + action_block_w
    end

    -- Measure done pill if exiting
    local done_block_w = 0
    if done_text then
        local st = styledtext.new(done_text, {
            font = { name = ".AppleSystemUIFontBold", size = BLOCK_FONT_SZ },
            color = DONE_TEXT_CLR,
            paragraphStyle = { alignment = "center" },
        })
        done_block_w = measure_text(st) + 2 * BLOCK_TEXT_PAD
        total_blocks_w = total_blocks_w + done_block_w
    end

    local num_gaps = #path - 1 + (action_text and 1 or 0) + (done_text and 1 or 0)
    local gaps_w = num_gaps * BLOCK_GAP
    local slot_content_w = total_blocks_w + gaps_w
    local slot_w = slot_content_w + 2 * SLOT_PAD_X
    local bar_w = math.max(MIN_BAR_W, slot_w + 2 * OUTER_PAD)
    slot_w = bar_w - 2 * OUTER_PAD
    local slot_h = BAR_HEIGHT - 2 * OUTER_PAD
    local block_h = slot_h - 2 * SLOT_PAD_Y

    -- Position: just above center of screen
    local sf = primary_screen_frame()
    local x = sf.x + (sf.w - bar_w) / 2
    local y = sf.y + sf.h * BAR_Y_RATIO - BAR_HEIGHT / 2

    local cv = canvas.new({ x = x, y = y, w = bar_w, h = BAR_HEIGHT })
    cv:level(canvas.windowLevels.overlay)
    cv:behavior(canvas.windowBehaviors.canJoinAllSpaces)

    -- ONE outer bar rect
    cv:appendElements({
        type = "rectangle",
        action = "fill",
        strokeWidth = 0,
        frame = { x = 0, y = 0, w = bar_w, h = BAR_HEIGHT },
        fillColor = OUTSIDE_COLOR,
        roundedRectRadii = { xRadius = BAR_RADIUS, yRadius = BAR_RADIUS },
    })

    -- ONE slot rect
    cv:appendElements({
        type = "rectangle",
        action = "fill",
        strokeWidth = 0,
        frame = { x = OUTER_PAD, y = OUTER_PAD, w = slot_w, h = slot_h },
        fillColor = SLOT_COLOR,
        roundedRectRadii = { xRadius = SLOT_RADIUS, yRadius = SLOT_RADIUS },
    })

    -- Mode blocks: ONE rect + ONE text per block
    local bx = OUTER_PAD + SLOT_PAD_X
    local by = OUTER_PAD + SLOT_PAD_Y
    for i, label in ipairs(path) do
        local bw = block_widths[i]

        cv:appendElements({
            type = "rectangle",
            action = "fill",
            strokeWidth = 0,
            frame = { x = bx, y = by, w = bw, h = block_h },
            fillColor = BLOCK_COLOR,
            roundedRectRadii = { xRadius = BLOCK_RADIUS, yRadius = BLOCK_RADIUS },
        })

        cv:appendElements({
            type = "text",
            text = make_block_text(label),
            frame = {
                x = bx,
                y = by + TEXT_NUDGE_Y,
                w = bw,
                h = block_h - TEXT_NUDGE_Y,
            },
        })

        bx = bx + bw + BLOCK_GAP
    end

    -- Action block: ONE baby-blue rect + ONE darker-blue text
    if action_text then
        cv:appendElements({
            type = "rectangle",
            action = "fill",
            strokeWidth = 0,
            frame = { x = bx, y = by, w = action_block_w, h = block_h },
            fillColor = ACTION_COLOR,
            roundedRectRadii = { xRadius = BLOCK_RADIUS, yRadius = BLOCK_RADIUS },
        })

        local action_st = styledtext.new(action_text, {
            font = { name = ".AppleSystemUIFontBold", size = BLOCK_FONT_SZ },
            color = ACTION_TEXT_CLR,
            paragraphStyle = { alignment = "center", lineBreakMode = "truncatingTail" },
        })
        cv:appendElements({
            type = "text",
            text = action_st,
            frame = {
                x = bx,
                y = by + TEXT_NUDGE_Y,
                w = action_block_w,
                h = block_h - TEXT_NUDGE_Y,
            },
        })

        bx = bx + action_block_w + BLOCK_GAP
    end

    -- Done pill: ONE green rect + ONE white text
    if done_text then
        cv:appendElements({
            type = "rectangle",
            action = "fill",
            strokeWidth = 0,
            frame = { x = bx, y = by, w = done_block_w, h = block_h },
            fillColor = DONE_GREEN,
            roundedRectRadii = { xRadius = BLOCK_RADIUS, yRadius = BLOCK_RADIUS },
        })

        local done_st = styledtext.new(done_text, {
            font = { name = ".AppleSystemUIFontBold", size = BLOCK_FONT_SZ },
            color = DONE_TEXT_CLR,
            paragraphStyle = { alignment = "center", lineBreakMode = "truncatingTail" },
        })
        cv:appendElements({
            type = "text",
            text = done_st,
            frame = {
                x = bx,
                y = by + TEXT_NUDGE_Y,
                w = done_block_w,
                h = block_h - TEXT_NUDGE_Y,
            },
        })
    end

    cv:show()
    return cv, bar_w, y + BAR_HEIGHT
end

-- ---------------------------------------------------------------------------
-- Build options canvas
-- ---------------------------------------------------------------------------

local function build_options(bar_w, bar_bottom)
    if not current_mode then return nil end
    local mode_cfg = MODES[current_mode]
    if not mode_cfg or not mode_cfg.options or #mode_cfg.options == 0 then return nil end

    local opts = mode_cfg.options
    local opt_count = #opts

    -- Measure max description width for sizing
    local max_desc_w = 0
    for _, opt in ipairs(opts) do
        local st = styledtext.new(opt.desc, {
            font = { name = ".AppleSystemUIFont", size = OPT_FONT_SZ },
            color = DESC_CLR,
        })
        local w = measure_text(st)
        if w > max_desc_w then max_desc_w = w end
    end

    local opt_w = math.max(bar_w, KEY_COL_W + max_desc_w + 2 * OPT_PAD + OPT_EXTRA_W)
    local opt_h = 2 * OPT_PAD + opt_count * OPT_ROW_H + (opt_count - 1) * OPT_ROW_GAP

    local sf = primary_screen_frame()
    local x = sf.x + (sf.w - opt_w) / 2
    local y = bar_bottom + OPT_GAP

    local cv = canvas.new({ x = x, y = y, w = opt_w, h = opt_h })
    cv:level(canvas.windowLevels.overlay)
    cv:behavior(canvas.windowBehaviors.canJoinAllSpaces)

    -- ONE background rect
    cv:appendElements({
        type = "rectangle",
        action = "fill",
        strokeWidth = 0,
        frame = { x = 0, y = 0, w = opt_w, h = opt_h },
        fillColor = OUTSIDE_COLOR,
        roundedRectRadii = { xRadius = OPT_RADIUS, yRadius = OPT_RADIUS },
    })

    -- Option rows: text elements only
    local row_y = OPT_PAD
    for _, opt in ipairs(opts) do
        local key_st = styledtext.new(opt.key, {
            font = { name = "Menlo-Bold", size = OPT_FONT_SZ },
            color = KEY_CLR,
            paragraphStyle = { lineBreakMode = "truncatingTail" },
        })
        local desc_st = styledtext.new(opt.desc, {
            font = { name = ".AppleSystemUIFont", size = OPT_FONT_SZ },
            color = DESC_CLR,
            paragraphStyle = { lineBreakMode = "truncatingTail" },
        })

        cv:appendElements({
            type = "text",
            text = key_st,
            frame = {
                x = OPT_PAD,
                y = row_y + TEXT_NUDGE_Y,
                w = KEY_COL_W,
                h = OPT_ROW_H - TEXT_NUDGE_Y,
            },
        })
        cv:appendElements({
            type = "text",
            text = desc_st,
            frame = {
                x = OPT_PAD + KEY_COL_W,
                y = row_y + TEXT_NUDGE_Y,
                w = opt_w - OPT_PAD - KEY_COL_W - OPT_PAD,
                h = OPT_ROW_H - TEXT_NUDGE_Y,
            },
        })

        row_y = row_y + OPT_ROW_H + OPT_ROW_GAP
    end

    cv:show()
    return cv
end

-- ---------------------------------------------------------------------------
-- M:enter(mode_name)
-- ---------------------------------------------------------------------------

local last_bar_w = 0
local last_bar_bottom = 0

function M:enter(mode_name)
    local ok, err = pcall(function()
        cancel_timers()
        current_action = nil

        if not MODES[mode_name] then return end
        current_mode = mode_name

        -- Tear down existing canvases
        if cv_bar then cv_bar:delete(); cv_bar = nil end
        if cv_options then cv_options:delete(); cv_options = nil end

        -- Build breadcrumb bar
        local path = build_breadcrumb_path(mode_name)
        cv_bar, last_bar_w, last_bar_bottom = build_bar(path)

        -- Schedule options display after delay
        options_timer = timer.doAfter(OPTIONS_DELAY, function()
            options_timer = nil
            local ok2, err2 = pcall(function()
                cv_options = build_options(last_bar_w, last_bar_bottom)
            end)
            if not ok2 then
                print("[skhdUI] ERROR in show_options: " .. tostring(err2))
            end
        end)
    end)

    if not ok then
        print("[skhdUI] ERROR in enter: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- M:exit()
-- ---------------------------------------------------------------------------

function M:exit()
    local ok, err = pcall(function()
        -- If already fading, don't restart
        if fade_timer then return end

        cancel_timers()

        -- Hide options immediately
        if cv_options then cv_options:delete(); cv_options = nil end

        if not cv_bar or not current_mode then
            hide()
            return
        end

        -- Rebuild bar with action (if any) + "Done" pill
        local path = build_breadcrumb_path(current_mode)
        cv_bar:delete()
        cv_bar = build_bar(path, "Done", current_action)

        -- Hold for 1 second, then smooth ease-out fade
        fade_timer = timer.doAfter(DONE_HOLD, function()
            fade_timer = nil
            local elapsed = 0
            fade_timer = timer.doEvery(FADE_STEP, function()
                elapsed = elapsed + FADE_STEP
                local t = elapsed / FADE_DURATION
                if t >= 1.0 then
                    hide()
                    return
                end
                -- ease-out: starts fast, slows down
                local alpha = 1.0 - (t * t)
                if cv_bar then cv_bar:alpha(alpha) end
            end)
        end)
    end)

    if not ok then
        print("[skhdUI] ERROR in exit: " .. tostring(err))
        hide()
    end
end

-- ---------------------------------------------------------------------------
-- M:action(name)  — show a temporary action block (sticky mode)
-- ---------------------------------------------------------------------------

function M:action(name)
    local ok, err = pcall(function()
        if not current_mode then return end

        current_action = name

        -- Reset options timer — each keypress restarts the delay
        if options_timer then options_timer:stop(); options_timer = nil end
        if cv_options then cv_options:delete(); cv_options = nil end

        -- Rebuild bar with action block
        if cv_bar then cv_bar:delete(); cv_bar = nil end
        local path = build_breadcrumb_path(current_mode)
        cv_bar, last_bar_w, last_bar_bottom = build_bar(path, nil, current_action)

        -- Restart options delay
        options_timer = timer.doAfter(OPTIONS_DELAY, function()
            options_timer = nil
            local ok2, err2 = pcall(function()
                cv_options = build_options(last_bar_w, last_bar_bottom)
            end)
            if not ok2 then
                print("[skhdUI] ERROR in show_options: " .. tostring(err2))
            end
        end)
    end)

    if not ok then
        print("[skhdUI] ERROR in action: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- M:exit_with_action(name, context)  — show action + done, then fade (1-shot)
-- context: optional mode key (e.g. "focus") to insert into the breadcrumb path
-- ---------------------------------------------------------------------------

function M:exit_with_action(name, context)
    local ok, err = pcall(function()
        -- If already fading, don't restart
        if fade_timer then return end

        cancel_timers()
        current_action = name

        -- Hide options immediately
        if cv_options then cv_options:delete(); cv_options = nil end

        if not cv_bar or not current_mode then
            hide()
            return
        end

        -- Rebuild bar with action block + done pill
        local path = build_breadcrumb_path(current_mode)
        if context and MODES[context] then
            table.insert(path, MODES[context].label)
        end
        cv_bar:delete()
        cv_bar = build_bar(path, "Done", current_action)

        -- Hold for 1 second, then smooth ease-out fade
        fade_timer = timer.doAfter(DONE_HOLD, function()
            fade_timer = nil
            local elapsed = 0
            fade_timer = timer.doEvery(FADE_STEP, function()
                elapsed = elapsed + FADE_STEP
                local t = elapsed / FADE_DURATION
                if t >= 1.0 then
                    hide()
                    return
                end
                -- ease-out: starts fast, slows down
                local alpha = 1.0 - (t * t)
                if cv_bar then cv_bar:alpha(alpha) end
            end)
        end)
    end)

    if not ok then
        print("[skhdUI] ERROR in exit_with_action: " .. tostring(err))
        hide()
    end
end

return M
