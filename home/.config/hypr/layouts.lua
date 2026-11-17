-- Custom tiling layouts (Hyprland Lua layout providers), loaded by hyprland.lua.
-- Select one with a workspace rule's layout = "lua:NAME" (the layout menu, Super+A, does this).
--   grid       a grid, even until you drag a divider
--   columns    one full-height column per window, even until you drag a divider
--   deck       a main window beside a deck: one card open, the others folded to strips
--   threecol   main in the centre, a column each side, at most CAP open windows per column
--
-- A provider's recalculate(ctx) gets ctx.area (the usable box; Hyprland applies the gaps
-- to each window itself) and ctx.targets (the tiled windows, in order) and places each one.
-- deck and threecol decide which windows are open from focus history (lower
-- focus_history_id = used more recently), so they are redrawn on every focus change
-- (the window.active hook at the bottom).
--
-- Resizing: grid, columns and threecol have dividers you can drag (and Super+Ctrl+arrows
-- moves them too); deck does not. Hyprland tells a Lua layout nothing about a resize, it
-- only redraws it, so the strict-resize plugin (~/.local/share/hypr-strict-resize) hands
-- the resize in progress to that redraw through hl.plugin.strictresize.take(). Without the
-- plugin these layouts simply stay even. The plugin is also told which directions each
-- layout can resize (AXES below), so a gap that cannot be dragged shows no resize cursor.
-- Layouts.reset() (Super+Ctrl+0) puts the desktop in front back to the default proportions
-- of the layout it is using.

local L = {}
local STRIP = 46        -- height of a folded window, px
local CAP = 3           -- threecol: open windows per side column
local MAIN = 0.58       -- deck: share of the width the main window takes

local function recency(t)
    local w = t.window
    return (w and w.focus_history_id) or 1e9
end

-- Stack `list` (targets) in the box, top to bottom. The `open` most recently used ones
-- share the height left over after the rest are folded to strips at their place in the order.
local function stack(list, box, open)
    local n = #list
    if n == 0 then return end
    open = math.max(1, math.min(open, n))
    local ranked = {}
    for i, t in ipairs(list) do ranked[i] = { i = i, r = recency(t) } end
    table.sort(ranked, function(a, b) return a.r < b.r or (a.r == b.r and a.i < b.i) end)
    local isopen = {}
    for k = 1, open do isopen[ranked[k].i] = true end
    local strip = math.min(STRIP, box.h / (n + 1))
    local each = (box.h - (n - open) * strip) / open
    local y = box.y
    for i, t in ipairs(list) do
        local h = isopen[i] and each or strip
        t:place({ x = box.x, y = y, w = box.w, h = h })
        y = y + h
    end
end

-- deck and threecol: which window is the main one. By default the first in window order;
-- Super+Shift+Return ("swapwithmaster") makes the focused window the main one for its
-- desktop, and it stays so until it closes or another is chosen.
L.main_of = (Layouts and Layouts.main_of) or {}        -- workspace id -> the chosen window's address
L.main_now = {}                                          -- workspace id -> the main window as last drawn
local function ws_of(ctx)
    for _, t in ipairs(ctx.targets) do
        local w = t.window
        if w and w.workspace and w.workspace.id then return tostring(w.workspace.id) end
    end
end
-- The targets with the chosen main window moved to the front (the rest keep their order).
local function main_first(ctx)
    local id = ws_of(ctx)
    local want = id and L.main_of[id]
    if not want then return ctx.targets end
    local out, main = {}, nil
    for _, t in ipairs(ctx.targets) do
        if not main and t.window and t.window.address == want then main = t else out[#out + 1] = t end
    end
    if not main then
        -- Not among the targets: forget it only if the window is really gone from this desktop
        -- (while a layout is being switched the targets arrive one at a time).
        local there = false
        for _, w in ipairs(hl.get_windows()) do
            if w.address == want and w.workspace and tostring(w.workspace.id) == id then there = true; break end
        end
        if not there then L.main_of[id] = nil end
        return ctx.targets
    end
    table.insert(out, 1, main)
    return out
end
-- Make the focused window the main one; if it already is, the most recently used other one.
local function promote(ctx)
    local id = ws_of(ctx)
    if not id then return end
    local list = main_first(ctx)
    local pick
    for i, t in ipairs(list) do
        if t.window and t.window.active then pick = (i > 1) and t or nil; break end
    end
    if not pick then
        for i = 2, #list do
            if not pick or recency(list[i]) < recency(pick) then pick = list[i] end
        end
    end
    if pick and pick.window then L.main_of[id] = pick.window.address end
end

-- ---- Dividers you can drag (grid, columns, threecol) ----
-- What has been dragged, as weights (1 = an even share):
--   columns   per window (by address): a widened window stays wide when others come and go
--   grid      per desktop and window count, by place: [id][n] = { w = {slot -> weight within
--             its row}, r = {row -> weight} }. A grid changes shape when a window opens or
--             closes, so each count keeps its own sizes (and starts even).
--   threecol  per desktop: the two side columns' shares
L.adj = (Layouts and Layouts.adj) or {}
L.adj.col, L.adj.three = L.adj.col or {}, L.adj.three or {}
if not L.adj.v2 then L.adj.grid, L.adj.rows, L.adj.v2 = {}, nil, true end      -- grid used to be keyed by window
local MINPX = 80                                        -- nothing is dragged narrower than this
local TOP, BOTTOM, LEFT, RIGHT = 1, 2, 4, 8             -- the edge bits take() reports (0 = keyboard)

-- The resize this redraw is for, if any: { i = index in ctx.targets, addr, dx, dy, e = edges }.
local function drag_for(ctx)
    local ok, addr, dx, dy, e = pcall(function() return hl.plugin.strictresize.take() end)
    if not ok or not addr then return end
    for i, t in ipairs(ctx.targets) do
        if t.window and t.window.address == addr then return { i = i, addr = addr, dx = dx, dy = dy, e = e } end
    end
end

-- Item i of n in a row (or row i of n): which divider does the resize move, and by how much?
-- `lo`/`hi` are the edge bits on this axis. Returns the two neighbours' indexes and the px.
local function pair(i, n, e, lo, hi, d)
    if e & lo ~= 0 then if i > 1 then return i - 1, i, d end return end
    if e & hi ~= 0 then if i < n then return i, i + 1, d end return end
    if e ~= 0 then return end                           -- a drag on the other axis only
    if i < n then return i, i + 1, d end                -- keyboard: grow to the right / down,
    if i > 1 then return i - 1, i, -d end               -- or, for the last one, to the left / up
end

-- Move the divider between neighbours a and b by d px. `keys` are all that share `total` px.
local function shift(tbl, keys, a, b, d, total)
    local sum = 0
    for _, k in ipairs(keys) do sum = sum + (tbl[k] or 1) end
    local per = sum / total
    local min = math.min(MINPX, total / (#keys * 2)) * per
    local wa, wb = tbl[a] or 1, tbl[b] or 1
    local dw = math.max(math.min(d * per, math.max(0, wb - min)), -math.max(0, wa - min))
    tbl[a], tbl[b] = wa + dw, wb - dw
end

local function addresses(targets)
    local keys = {}
    for i, t in ipairs(targets) do keys[i] = (t.window and t.window.address) or ("#" .. i) end
    return keys
end
local function total(tbl, keys)
    local sum = 0
    for _, k in ipairs(keys) do sum = sum + (tbl[k] or 1) end
    return sum
end

L.grid = function(ctx)
    local n, area = #ctx.targets, ctx.area
    if n == 0 then return end
    local a = math.ceil(math.sqrt(n))
    local b = math.ceil(n / a)
    local wide = area.w >= area.h
    local cols, rows = (wide and a or b), (wide and b or a)
    local id = ws_of(ctx) or "?"
    L.adj.grid[id] = L.adj.grid[id] or {}
    local G = L.adj.grid[id][n] or { w = {}, r = {} }
    L.adj.grid[id][n] = G
    local rowkeys = {}
    for r = 1, rows do rowkeys[r] = r end
    local function members(r)                            -- the last row's windows stretch to fill it
        local m = {}
        for i = (r - 1) * cols + 1, math.min(r * cols, n) do m[#m + 1] = i end
        return m
    end

    local d = drag_for(ctx)
    if d then
        local r, c = (d.i - 1) // cols + 1, (d.i - 1) % cols + 1
        local m = members(r)
        local p, q, dx = pair(c, #m, d.e, LEFT, RIGHT, d.dx)
        if p then shift(G.w, m, m[p], m[q], dx, area.w) end
        local p2, q2, dy = pair(r, rows, d.e, TOP, BOTTOM, d.dy)
        if p2 then shift(G.r, rowkeys, p2, q2, dy, area.h) end
    end

    local rsum, y = total(G.r, rowkeys), area.y
    for r = 1, rows do
        local h = area.h * (G.r[r] or 1) / rsum
        local m = members(r)
        local wsum, x = total(G.w, m), area.x
        for _, i in ipairs(m) do
            local w = area.w * (G.w[i] or 1) / wsum
            ctx.targets[i]:place({ x = x, y = y, w = w, h = h })
            x = x + w
        end
        y = y + h
    end
end

L.columns = function(ctx)
    local n, a = #ctx.targets, ctx.area
    if n == 0 then return end
    local W, keys = L.adj.col, addresses(ctx.targets)
    local d = drag_for(ctx)
    if d then
        local p, q, dx = pair(d.i, n, d.e, LEFT, RIGHT, d.dx)
        if p then shift(W, keys, keys[p], keys[q], dx, a.w) end
    end
    local sum, x = total(W, keys), a.x
    for i, t in ipairs(ctx.targets) do
        local w = a.w * (W[keys[i]] or 1) / sum
        t:place({ x = x, y = a.y, w = w, h = a.h })
        x = x + w
    end
end

L.deck = function(ctx)
    local n, a = #ctx.targets, ctx.area
    if n == 0 then return end
    if n == 1 then ctx.targets[1]:place(a); return end
    local mw = a.w * MAIN
    local list = main_first(ctx)
    L.main_now[ws_of(ctx) or "?"] = list[1].window and list[1].window.address
    list[1]:place({ x = a.x, y = a.y, w = mw, h = a.h })
    local cards = {}
    for i = 2, n do cards[#cards + 1] = list[i] end
    stack(cards, { x = a.x + mw, y = a.y, w = a.w - mw, h = a.h }, 1)
end

L.threecol = function(ctx)
    local n, a = #ctx.targets, ctx.area
    if n == 0 then return end
    if n == 1 then ctx.targets[1]:place(a); return end
    local id = ws_of(ctx) or "?"
    local S = L.adj.three[id] or { l = 0.25, r = 0.25, two = 0.6 }     -- side columns' shares; the split with two windows
    L.adj.three[id] = S
    local d = drag_for(ctx)
    local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    if n == 2 then
        if d then
            local dx = d.dx / a.w
            if d.i == 1 and (d.e == 0 or d.e & RIGHT ~= 0) then S.two = S.two + dx
            elseif d.i == 2 and d.e & LEFT ~= 0 then S.two = S.two + dx
            elseif d.i == 2 and d.e == 0 then S.two = S.two - dx end
            S.two = clamp(S.two, 0.2, 0.8)
        end
        ctx.targets[1]:place({ x = a.x, y = a.y, w = a.w * S.two, h = a.h })
        ctx.targets[2]:place({ x = a.x + a.w * S.two, y = a.y, w = a.w * (1 - S.two), h = a.h })
        return
    end
    local list = main_first(ctx)
    L.main_now[id] = list[1].window and list[1].window.address
    if d then
        local k = 1
        for i, t in ipairs(list) do if t.window and t.window.address == d.addr then k = i; break end end
        local dx, key = d.dx / a.w, (d.e == 0)
        if k == 1 then                                  -- the main window: its left or right divider
            if d.e & LEFT ~= 0 then S.l = S.l + dx elseif key or d.e & RIGHT ~= 0 then S.r = S.r - dx end
        elseif k % 2 == 0 then                          -- right column
            if d.e & LEFT ~= 0 then S.r = S.r - dx elseif key then S.r = S.r + dx end
        else                                            -- left column
            if key or d.e & RIGHT ~= 0 then S.l = S.l + dx end
        end
        S.l, S.r = clamp(S.l, 0.1, 0.4), clamp(S.r, 0.1, 0.4)
    end
    local lw, rw = a.w * S.l, a.w * S.r
    list[1]:place({ x = a.x + lw, y = a.y, w = a.w - lw - rw, h = a.h })
    local right, left = {}, {}
    for i = 2, n do
        if i % 2 == 0 then right[#right + 1] = list[i] else left[#left + 1] = list[i] end
    end
    stack(left,  { x = a.x, y = a.y, w = lw, h = a.h }, CAP)
    stack(right, { x = a.x + a.w - rw, y = a.y, w = rw, h = a.h }, CAP)
end

-- Register each, guarded: if one throws, fall back to plain columns rather than leave
-- windows unplaced. Any layout message just redraws.
L.names = { "grid", "columns", "deck", "threecol" }
L.by_focus = { ["lua:deck"] = true, ["lua:threecol"] = true }
for _, name in ipairs(L.names) do
    local fn = L[name]
    local function run(ctx)
        local ok, err = pcall(fn, ctx)
        if not ok then
            pcall(L.columns, ctx)
            hl.notification.create({ text = "layout " .. name .. ": " .. tostring(err), duration = 8000 })
        end
    end
    hl.layout.register(name, { recalculate = run, layout_msg = function(ctx, msg)
        if msg == "swapwithmaster" and L.by_focus["lua:" .. name] then pcall(promote, ctx) end
        run(ctx); return true
    end })
end

-- Which layout each workspace was given (by the per-screen rules and the layout menu),
-- so the focus hook knows when a redraw is needed. Layouts.set is what the menu calls.
L.current = {}
-- The directions each custom layout can resize, for the strict-resize plugin: a gap that
-- cannot be dragged then shows no resize cursor and ignores a press. Built-in layouts: both.
local AXES = { ["lua:grid"] = "xy", ["lua:columns"] = "x", ["lua:threecol"] = "x", ["lua:deck"] = "" }
local function tell_axes(ws, layout)
    pcall(function() hl.plugin.strictresize.axes(tonumber(ws), AXES[layout] or "xy") end)
end
function L.set(ws, layout, opts)
    ws = tostring(ws)
    hl.workspace_rule({ workspace = ws, layout = layout, layout_opts = opts })
    L.current[ws] = layout
    tell_axes(ws, layout)
end
-- hyprland.lua calls this once the plugin is loaded (this file runs before it is).
function L.sync_axes()
    for ws, layout in pairs(L.current) do tell_axes(ws, layout) end
end
-- Keyed on the focused window's own workspace, not the monitor's active one: with a special
-- workspace shown (ncmpcpp on special:music, the scratchpad) focus sits there, its layout
-- is a built-in one, and "redraw" sent to it raises a dwindle layout-message error.
hl.on("window.active", function()
    local w = hl.get_active_window()
    local ws = w and w.workspace
    if ws and ws.id and L.by_focus[L.current[tostring(ws.id)] or ""] then
        hl.dispatch(hl.dsp.layout("redraw"))
    end
end)

-- ---- Which layout where ----
-- Named choices (the layout menu, Super+A, offers these).
L.presets = {
    dwindle  = { "dwindle" },                                  -- split the window you drop on
    main     = { "master", { orientation = "left" } },         -- main window + a stack beside it
    centre   = { "master", { orientation = "center" } },       -- main in the middle, stacks both sides
    top      = { "master", { orientation = "top" } },          -- main across the top, the rest below
    scroll   = { "scrolling" },                                -- columns on a strip you scroll
    monocle  = { "monocle" },                                  -- one window at a time
    grid     = { "lua:grid" }, columns = { "lua:columns" }, deck = { "lua:deck" }, threecol = { "lua:threecol" },
}
-- Each screen's default, by its slot (desktop N on slot i is workspace N*10+i; slots count
-- screens left to right): left Dell (or the laptop alone), portrait Dell, Samsung, laptop.
L.slot_default = { "main", "top", "centre", "dwindle" }
L.file = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/hypr-layouts"
L.chosen = {}                                                  -- workspace id (string) -> preset, set from the menu

function L.default_for(ws) return L.slot_default[tonumber(ws) % 10] or "dwindle" end
function L.apply(ws)
    local key = L.chosen[tostring(ws)] or L.default_for(ws)
    local p = L.presets[key] or L.presets.dwindle
    L.set(ws, p[1], p[2])
    return key
end
function L.save()
    local f = io.open(L.file, "w")
    if not f then return end
    for ws, key in pairs(L.chosen) do f:write(ws, " ", key, "\n") end
    f:close()
end
-- Layouts.choose("grid"): give the desktop in front of you that layout and remember it.
-- Layouts.choose("default") goes back to the screen's default.
function L.choose(key)
    local ws = hl.get_active_workspace()
    if not (ws and ws.id and ws.id >= 11) then return "no desktop" end
    local id = tostring(ws.id)
    if key == "default" then L.chosen[id] = nil elseif L.presets[key] then L.chosen[id] = key else return "unknown layout" end
    L.save()
    return L.apply(id)
end
function L.name()                                              -- what the desktop in front of you uses
    local ws = hl.get_active_workspace()
    if not (ws and ws.id) then return "" end
    return (L.chosen[tostring(ws.id)] or L.default_for(ws.id)) .. (L.chosen[tostring(ws.id)] and "" or " (default)")
end

do
    local f = io.open(L.file, "r")
    if f then
        for line in f:lines() do
            local ws, key = line:match("^(%d+) (%w+)$")
            if ws and L.presets[key] then L.chosen[ws] = key end
        end
        f:close()
    end
    for n = 1, 10 do for slot = 1, 4 do L.apply(n * 10 + slot) end end
end

-- For the layout menu's live preview: try a layout on a desktop without remembering it,
-- then either keep it (Layouts.keep) or put back what was there (Layouts.apply).
function L.preview(ws, key)
    local p = L.presets[key == "default" and L.default_for(ws) or key]
    if p then L.set(ws, p[1], p[2]) end
end
function L.keep(ws, key)
    ws = tostring(ws)
    if key == "default" then L.chosen[ws] = nil elseif L.presets[key] then L.chosen[ws] = key else return end
    L.save()
    L.apply(ws)
end

-- ---- Window keys that depend on the layout (bound in hyprland.lua) ----
-- Super+H/K (focus previous / next) and Super+Y / Shift+Y (swap with the next / previous)
-- work in every layout; Super+Shift+M (focus the main window) wherever there is one; the
-- rest (Shift+I/U, X) only in main-and-stack, and the key says so elsewhere.
-- The layout the desktop in front is using now ("master", "dwindle", "lua:grid", ...): what
-- L.set last applied, else what the remembered choice or the screen's default says.
local function layout_here()
    local ws = hl.get_active_workspace()
    local id = ws and ws.id and tostring(ws.id)
    if not id then return nil, nil end
    local p = L.presets[L.chosen[id] or L.default_for(id)]
    return id, L.current[id] or (p and p[1])
end
-- The tiled windows on the desktop in front, in reading order (rows top to bottom, each
-- left to right; windows whose tops are within 24 px count as one row), and which one has
-- focus. Super+H/K and Super+Y outside main-and-stack go by this, so Shift+Y undoes Y.
local function in_reading_order()
    local ws = hl.get_active_workspace()
    if not (ws and ws.id) then return {}, nil end
    local list = {}
    for _, w in ipairs(hl.get_workspace_windows(ws.id) or {}) do
        if w.mapped ~= false and not w.hidden and not w.floating and w.at and w.address then list[#list + 1] = w end
    end
    local function xy(w) return (w.at.x or w.at[1] or 0), (w.at.y or w.at[2] or 0) end
    table.sort(list, function(a, b)
        local ax, ay = xy(a)
        local bx, by = xy(b)
        if math.abs(ay - by) > 24 then return ay < by end
        return ax < bx
    end)
    local active = hl.get_active_window()
    for i, w in ipairs(list) do
        if active and w.address == active.address then return list, i end
    end
    return list, nil
end
local function step_from_focus(dir)
    local list, i = in_reading_order()
    if not i or #list < 2 then return nil end
    return list[(i - 1 + dir) % #list + 1]
end

function L.master(msg)
    local id, cur = layout_here()
    if cur == "master" then
        hl.dispatch(hl.dsp.layout(msg))
    elseif msg == "cyclenext" or msg == "cycleprev" then
        local w = step_from_focus(msg == "cyclenext" and 1 or -1)
        if w then hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address })) end
    elseif msg == "swapnext" or msg == "swapprev" then
        local w = step_from_focus(msg == "swapnext" and 1 or -1)
        if w then hl.dispatch(hl.dsp.window.swap({ target = "address:" .. w.address })) end
    elseif L.by_focus[cur or ""] and msg == "swapwithmaster" then
        hl.dispatch(hl.dsp.layout(msg))             -- deck, three columns: the layout picks its own main window
    elseif L.by_focus[cur or ""] and msg == "focusmaster" then
        local addr = L.main_now[id]
        if addr then hl.dispatch(hl.dsp.focus({ window = "address:" .. addr })) end
    elseif L.by_focus[cur or ""] then
        hl.notification.create({ text = "Deck and three columns have one main window: Super+Shift+Return picks it, Super+Shift+M goes to it", duration = 3500 })
    else
        hl.notification.create({ text = "Only the main-and-stack layouts have a main window (Super+A to change)", duration = 2500 })
    end
end
-- Super+J: flip the split around the focused window (dwindle only).
function L.flip()
    local _, cur = layout_here()
    if cur == "dwindle" then
        hl.dispatch(hl.dsp.layout("togglesplit"))
    else
        hl.notification.create({ text = "Flip split works in the dwindle layout only (Super+A to change)", duration = 2500 })
    end
end

-- From a script: hyprctl eval 'Layouts.set_main(94, "0x55...")' ("" clears it).
function L.set_main(ws, address)
    ws = tostring(ws)
    L.main_of[ws] = (address ~= nil and address ~= "") and address or nil
    local cur = L.current[ws]
    if cur then L.set(ws, "lua:columns"); L.set(ws, cur) end        -- switching away and back redraws a desktop that is not in front
end

-- Back to default proportions on the desktop in front (Super+Ctrl+0), for the layout it
-- is using now: what was dragged in grid, columns or threecol is forgotten; for dwindle and
-- main-and-stack the strict-resize plugin evens out the splits. Sizes kept for a layout the
-- desktop is not showing are left alone.
function L.reset()
    local ws = hl.get_active_special_workspace() or hl.get_active_workspace()
    if not (ws and ws.id) then return end
    local id = tostring(ws.id)
    local cur = L.current[id] or ""
    local function say(text) hl.notification.create({ text = text, duration = 2500 }) end
    if cur == "lua:grid" then
        L.adj.grid[id] = nil
    elseif cur == "lua:columns" then
        for _, w in ipairs(hl.get_windows()) do
            if w.address and w.workspace and tostring(w.workspace.id) == id then L.adj.col[w.address] = nil end
        end
    elseif cur == "lua:threecol" then
        L.adj.three[id] = nil
    elseif cur:match("^lua:") then
        say("This layout has no window sizes to reset")
        return
    else
        local ok, kind = pcall(function() return hl.plugin.strictresize.reset() end)
        if not ok then say("Reset needs the strict-resize plugin (run its build.sh after a Hyprland update)")
        elseif kind == "none" then say("This layout has no window sizes to reset") end
        return
    end
    hl.dispatch(hl.dsp.layout("redraw"))
end
-- A closed window takes its dragged column width with it.
hl.on("window.close", function(w)
    if w and w.address then L.adj.col[w.address] = nil end
end)

Layouts = L
return L
