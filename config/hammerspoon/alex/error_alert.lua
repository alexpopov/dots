-- error_alert.lua
--
-- A standalone error toast:
--
--        ┌───────────────────────┐
--        │   Failed to focus     │   <- red pill, no grey shell
--        └───────────────────────┘
--        ┌───────────────────────────────────┐
--        │ could not locate a westward       │   <- detail panel, same styling
--        │ managed window                    │      as skhd_ui's options grid
--        └───────────────────────────────────┘
--
-- DELIBERATELY DECOUPLED FROM skhd_ui:
--   * does not require("alex.skhd_ui")
--   * owns its own canvases, timers and state
--   * duplicates the handful of layout/colour constants rather than importing
--     them, so either module can be loaded, reloaded or deleted alone
--   * draws at its own Y_RATIO so the two can be on screen together
--
-- Usage from lua:
--     errorAlert:show("could not locate a westward managed window")
--     errorAlert:show("detail text", nil, "Custom Title")
--     errorAlert:hide()
--
-- Usage from a shell script (fire-and-forget):
--     open -g "hammerspoon://errorAlert?text=some%20detail" &
--     open -g "hammerspoon://errorAlert?text=detail&title=Failed%20to%20focus" &

local canvas     = require("hs.canvas")
local screen     = require("hs.screen")
local timer      = require("hs.timer")
local styledtext = require("hs.styledtext")
local drawing    = require("hs.drawing")

-- ---------------------------------------------------------------------------
-- Scale system (mirrors skhd_ui)
-- ---------------------------------------------------------------------------

local SCALE = 1.2

local function S(n) return math.floor(n * SCALE) end

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------

local ERROR_RED       = { red = 0.78, green = 0.28, blue = 0.28 }
local ERROR_TEXT_CLR  = { white = 1.0 }
local PANEL_BG        = { white = 0.91, alpha = 0.97 }  -- skhd_ui OUTSIDE_COLOR
local DETAIL_TEXT_CLR = { white = 0.35 }                -- ~skhd_ui DESC_CLR

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local PILL_H         = S(34)
local PILL_RADIUS    = S(8)
local PILL_TEXT_PAD  = S(18)
local PILL_FONT_SZ   = S(18)
local PILL_MIN_W     = S(160)
local PILL_NUDGE_Y   = S(2)

local DETAIL_GAP     = S(6)       -- pill bottom -> panel top (skhd_ui OPT_GAP)
local DETAIL_PAD     = S(14)      -- skhd_ui OPT_PAD
local DETAIL_RADIUS  = S(10)      -- skhd_ui OPT_RADIUS
local DETAIL_FONT_SZ = S(12)      -- skhd_ui OPT_FONT_SZ
local DETAIL_LINE_H  = S(17)
local DETAIL_MAX_W   = S(460)     -- wrap beyond this

local Y_RATIO        = 0.30       -- skhd_ui's bar sits at 0.38

-- How long the detail panel waits before appearing. skhd_ui uses 1.0s for its
-- options grid, but an error's detail IS the message -- making you wait for it
-- (and then fading 0.8s later) reads as a glitch. Set to 1.0 to match skhd_ui.
local DETAIL_DELAY   = 0.0

local HOLD           = 2.4
local FADE_DURATION  = 0.3
local FADE_STEP      = 0.016

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local M = {}

local cv_pill      = nil
local cv_detail    = nil
local hold_timer   = nil
local fade_timer   = nil
local detail_timer = nil

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function cancel_timers()
    if hold_timer   then hold_timer:stop();   hold_timer   = nil end
    if fade_timer   then fade_timer:stop();   fade_timer   = nil end
    if detail_timer then detail_timer:stop(); detail_timer = nil end
end

local function teardown()
    cancel_timers()
    if cv_pill   then cv_pill:delete();   cv_pill   = nil end
    if cv_detail then cv_detail:delete(); cv_detail = nil end
end

local function pill_text(s)
    return styledtext.new(s, {
        font  = { name = ".AppleSystemUIFontBold", size = PILL_FONT_SZ },
        color = ERROR_TEXT_CLR,
        paragraphStyle = { alignment = "center", lineBreakMode = "truncatingTail" },
    })
end

local function detail_text(s)
    return styledtext.new(s, {
        font  = { name = ".AppleSystemUIFont", size = DETAIL_FONT_SZ },
        color = DETAIL_TEXT_CLR,
        paragraphStyle = { alignment = "left", lineBreakMode = "clip" },
    })
end

local function measure(st)
    local size = drawing.getTextDrawingSize(st)
    return size and size.w or 0
end

-- Greedy word wrap. getTextDrawingSize only reports a string's natural width,
-- so we measure candidate lines ourselves rather than relying on the layout
-- engine to wrap inside a fixed frame.
local function wrap_detail(s, max_w)
    local lines, cur = {}, nil
    for word in tostring(s):gmatch("%S+") do
        local candidate = cur and (cur .. " " .. word) or word
        if cur == nil or measure(detail_text(candidate)) <= max_w then
            cur = candidate
        else
            lines[#lines + 1] = cur
            cur = word
        end
    end
    if cur then lines[#lines + 1] = cur end
    if #lines == 0 then lines[1] = "" end
    return lines
end

local function origin_for(w)
    local sf = screen.primaryScreen():frame()
    return sf.x + (sf.w - w) / 2, sf.y + sf.h * Y_RATIO
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function build_pill(title)
    local st = pill_text(title)
    local w  = math.max(PILL_MIN_W, measure(st) + 2 * PILL_TEXT_PAD)
    local x, y = origin_for(w)

    local cv = canvas.new({ x = x, y = y, w = w, h = PILL_H })
    cv:level(canvas.windowLevels.overlay)
    cv:behavior(canvas.windowBehaviors.canJoinAllSpaces)

    cv:appendElements({
        type = "rectangle", action = "fill", strokeWidth = 0,
        frame = { x = 0, y = 0, w = w, h = PILL_H },
        fillColor = ERROR_RED,
        roundedRectRadii = { xRadius = PILL_RADIUS, yRadius = PILL_RADIUS },
    })

    cv:appendElements({
        type = "text", text = st,
        frame = { x = 0, y = PILL_NUDGE_Y, w = w, h = PILL_H - PILL_NUDGE_Y },
    })

    cv:show()
    return cv, w, y + PILL_H
end

local function build_detail(msg, pill_w, top_y)
    if msg == nil or msg == "" then return nil end

    local lines = wrap_detail(msg, DETAIL_MAX_W)

    local widest = 0
    for _, l in ipairs(lines) do
        local lw = measure(detail_text(l))
        if lw > widest then widest = lw end
    end

    local w = math.max(pill_w, widest + 2 * DETAIL_PAD)
    local h = 2 * DETAIL_PAD + #lines * DETAIL_LINE_H

    local x = select(1, origin_for(w))
    local y = top_y + DETAIL_GAP

    local cv = canvas.new({ x = x, y = y, w = w, h = h })
    cv:level(canvas.windowLevels.overlay)
    cv:behavior(canvas.windowBehaviors.canJoinAllSpaces)

    cv:appendElements({
        type = "rectangle", action = "fill", strokeWidth = 0,
        frame = { x = 0, y = 0, w = w, h = h },
        fillColor = PANEL_BG,
        roundedRectRadii = { xRadius = DETAIL_RADIUS, yRadius = DETAIL_RADIUS },
    })

    local row_y = DETAIL_PAD
    for _, l in ipairs(lines) do
        cv:appendElements({
            type = "text", text = detail_text(l),
            frame = { x = DETAIL_PAD, y = row_y, w = w - 2 * DETAIL_PAD, h = DETAIL_LINE_H },
        })
        row_y = row_y + DETAIL_LINE_H
    end

    cv:show()
    return cv
end

local function start_fade()
    fade_timer = nil
    local elapsed = 0
    fade_timer = timer.doEvery(FADE_STEP, function()
        elapsed = elapsed + FADE_STEP
        local t = elapsed / FADE_DURATION
        if t >= 1.0 then
            teardown()
            return
        end
        -- ease-out, same curve as skhd_ui
        local alpha = 1.0 - (t * t)
        if cv_pill   then cv_pill:alpha(alpha)   end
        if cv_detail then cv_detail:alpha(alpha) end
    end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- show(detail [, hold] [, title]) -- a new error replaces any current one
function M:show(detail, hold, title)
    local ok, err = pcall(function()
        detail = detail and tostring(detail) or ""
        title  = (title and title ~= "") and tostring(title) or "Error"

        teardown()

        local pill_w, pill_bottom
        cv_pill, pill_w, pill_bottom = build_pill(title)

        local function show_detail()
            cv_detail = build_detail(detail, pill_w, pill_bottom)
        end

        if DETAIL_DELAY <= 0 then
            show_detail()
        else
            detail_timer = timer.doAfter(DETAIL_DELAY, function()
                detail_timer = nil
                local ok2, err2 = pcall(show_detail)
                if not ok2 then print("[errorAlert] detail: " .. tostring(err2)) end
            end)
        end

        hold_timer = timer.doAfter(hold or HOLD, function()
            hold_timer = nil
            start_fade()
        end)
    end)

    if not ok then
        print("[errorAlert] ERROR in show: " .. tostring(err))
        teardown()
    end
end

function M:hide()
    teardown()
end

-- ---------------------------------------------------------------------------
-- URL handler -- fire-and-forget from shell scripts
-- ---------------------------------------------------------------------------

-- NOTE: Hammerspoon lower-cases the incoming url event name before dispatch,
-- so this MUST be registered lower-case even though callers use the camelCase
-- url `hammerspoon://errorAlert?...`. skhd_ui.lua does the same (it binds
-- "skhdenter" but is invoked as skhdEnter). Binding "errorAlert" never fires.
hs.urlevent.bind("erroralert", function(_, params)
    M:show(params.text, tonumber(params.hold), params.title)
end)

return M
