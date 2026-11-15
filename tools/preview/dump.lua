--[[ Draws EasyGear's own windows without the game: builds them on the model of the client (tests/wow_mock.lua),
     resolves the anchors of every region and writes what would be on screen as JSON (rectangles, texts, icons).
     tools/preview/draw.py turns that into a picture. The fonts and icons are stand-ins - this shows layout and colors,
     not the look of the client's text rendering.

       lua5.1 tools/preview/dump.lua <scene> > scene.json        (run from the repository root)
       scenes: window | ring | profile | edit | toast | feed      EUI=1 in the environment: with EllesmereUI's accent
       feed: rows of EllesmereUI's Loot Feed with EasyGear's marks - on the model of the feed (tests/wow_mock.lua),
             whose rows are given plain colors here; it shows where the marks sit, not the feed's real look
]]
package.path = "tests/?.lua;" .. package.path
local Mock = require("wow_mock")
local F = require("fixtures")
local scene = arg[1] or "window"

local W = Mock.new(F.ARMS)
W.load("EasyGear")
W.I = F.armsWarrior(W)
W.I.better = F.gear(W, 7001, "Sturmgepeitschte Brustplatte", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35, quality = 3 })
W.I.ring = F.gear(W, 7002, "Ring der Entschlossenheit", "INVTYPE_FINGER", 40, { STR = 20, HIT = 15 }, { typeText = "", quality = 2 })
W.I.helm = F.gear(W, 7003, "Helm des Vorreiters", "INVTYPE_HEAD", 40, { STR = 20 }, { quality = 4 })
W.I.weak = F.gear(W, 7004, "Rissige Lederweste", "INVTYPE_CHEST", 10, { STR = 1 }, { quality = 1, sellPrice = 3 })
W.I.late = F.gear(W, 7005, "Brustplatte des Feldherrn", "INVTYPE_CHEST", 90, { STR = 100 }, { minLevel = 65, quality = 4, sellPrice = 41 })
local LF = scene == "feed" and W.installLootFeed({ rowHeight = tonumber(os.getenv("ROW")) or 36, style = os.getenv("STYLE") or "BAR" }) or nil
W.bag(0, 16, {})
if os.getenv("EUI") then W.env.EllesmereUI = { ELLESMERE_GREEN = { r = 0.88, g = 0.66, b = 0.51 } } end
W.boot()
W.fire("BAG_UPDATE_DELAYED")

local roots = {}
if scene == "window" then
    W.EG.Window.SetItem(W.I.better)
    roots = { W.env.EasyGearWindow }
elseif scene == "ring" then
    W.EG.Window.SetItem(W.I.ring)
    roots = { W.env.EasyGearWindow }
elseif scene == "profile" then
    W.EG.ProfileWindow.Open()
    W.EG.ProfileWindow.Select("WARRIOR_PROT")
    roots = { W.env.EasyGearProfileWindow }
elseif scene == "edit" then
    W.EG.ProfileWindow.Open()
    W.EG.ProfileWindow.Select("WARRIOR_PROT")
    W.EG.ProfileWindow.ToggleEdit()
    roots = { W.env.EasyGearProfileWindow }
elseif scene == "toast" then
    W.equip(12, nil) W.fire("PLAYER_EQUIPMENT_CHANGED", 12) W.flush() W.fire("BAG_UPDATE_DELAYED")
    W.put(0, 1, W.I.better) W.put(0, 2, W.I.ring) W.put(0, 3, W.I.helm)
    W.fire("BAG_UPDATE_DELAYED")
    W.tick(4)
    for _, f in ipairs(W.EG.Toast.shown) do roots[#roots + 1] = f end
elseif scene == "feed" then
    W.state.items[7001].sellPrice = 12
    W.state.items[7002].sellPrice = 7
    local rows = { LF.loot(W.I.weak), LF.money(1840), LF.loot(W.I.late), LF.loot(W.I.ring), LF.loot(W.I.better) }
    W.fire("CHAT_MSG_LOOT", "x")
    W.flush()
    -- the model of the feed has no colors of its own: a dark row, the bar and the name in the quality color
    local QUALITY = { [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 } }
    for _, r in ipairs(rows) do
        local item = r.data.link and W.state.itemFromAny(r.data.link)
        local c = item and QUALITY[item.quality or 1] or { 1, 0.82, 0 }
        r.bg:SetColorTexture(0.05, 0.05, 0.05, 0.80)
        r.bar:SetColorTexture(c[1], c[2], c[3], 1)
        r.name:SetTextColor(c[1], c[2], c[3], 1)
        r.sub:SetTextColor(0.7, 0.7, 0.7, 1)
        r.value:SetTextColor(1, 1, 1, 1)
    end
    roots = { LF.anchor }
end

local SW, SH = 1280, 800
local UIParent = W.env.UIParent
local HF = { LEFT = 0, CENTER = 0.5, RIGHT = 1, TOP = 0.5, BOTTOM = 0.5, TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
local VF = { LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, TOP = 1, BOTTOM = 0, TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }

local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|[TA].-|[ta]", "#"))
end

local cache = {}
local function rect(r)
    if r == UIParent then return 0, 0, SW, SH end
    local c = cache[r]
    if c then return c[1], c[2], c[3], c[4] end
    local parent = r.__parent or UIParent
    local l, b, w, h
    if r.__allPoints then
        l, b, w, h = rect(r.__allPoints == true and parent or r.__allPoints)
    else
        w, h = r.__w or 0, r.__h or 0
        if r.__kind == "FontString" then
            local size = r.__fontSize or 12
            local lines = 1
            for _ in plain(r.__text):gmatch("\n") do lines = lines + 1 end
            if w == 0 then w = #plain(r.__text) * size * 0.52 end
            if h == 0 then h = size * 1.25 * lines end
        end
        local xs, ys = {}, {}
        for _, p in ipairs(r.__points) do
            local rel = p[2] or parent
            local rl, rb, rw, rh = rect(rel)
            local rp = p[3] or p[1]
            xs[#xs + 1] = { HF[p[1]], rl + rw * HF[rp] + p[4] }
            ys[#ys + 1] = { VF[p[1]], rb + rh * VF[rp] + p[5] }
        end
        -- an edge decides before a centre: a text hung in by TOPLEFT and RIGHT starts at that top (as the client does it)
        local function solve(cons, size)
            local low, high, mid
            for _, c in ipairs(cons) do
                if c[1] == 0 then low = low or c[2] elseif c[1] == 1 then high = high or c[2] else mid = mid or c[2] end
            end
            if low and high then return low, high - low end
            if low then return low, size end
            if high then return high - size, size end
            if mid then return mid - size / 2, size end
            return 0, size
        end
        l, w = solve(xs, w)
        b, h = solve(ys, h)
    end
    cache[r] = { l, b, w, h }
    return l, b, w, h
end

local ops = {}
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
local function emit(frame, alpha)
    if not frame.__shown then return end
    alpha = alpha * (frame.__alpha or 1)
    local regions = {}
    for i, c in ipairs(frame.__children or {}) do regions[#regions + 1] = { c, (LAYER[c.__layer] or 3) * 10 + (c.__kind == "FontString" and 5 or 0), i } end
    table.sort(regions, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[3] < b[3] end)
    for _, e in ipairs(regions) do
        local c = e[1]
        if c.__shown then
            local l, b, w, h = rect(c)
            if c.__kind == "FontString" then
                local col = c.__textColor or { 1, 1, 1, 1 }
                if plain(c.__text) ~= "" then
                    ops[#ops + 1] = string.format('{"t":"text","x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f,"s":%q,"size":%d,"c":[%.3f,%.3f,%.3f,%.3f],"j":%q,"wrap":%s}',
                        l, SH - b - h, w, h, plain(c.__text):gsub("\n", " / "), c.__fontSize or 12, col[1], col[2], col[3], (col[4] or 1) * alpha,
                        c.__justifyH or "LEFT", (c.__wordWrap == false and (c.__w or 0) > 0) and "false" or "true")
                end
            elseif c.__color then
                ops[#ops + 1] = string.format('{"t":"rect","x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f,"c":[%.3f,%.3f,%.3f,%.3f]}',
                    l, SH - b - h, w, h, c.__color[1], c.__color[2], c.__color[3], (c.__color[4] or 1) * alpha)
            elseif c.__texture or c.__atlas then
                local v = c.__vertex or { 1, 1, 1 }
                ops[#ops + 1] = string.format('{"t":"icon","x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f,"n":%q,"c":[%.3f,%.3f,%.3f,%.3f]}',
                    l, SH - b - h, w, h, tostring(c.__atlas or c.__texture), v[1], v[2], v[3], alpha)
            end
        end
    end
    for _, child in ipairs(frame.__frames or {}) do emit(child, alpha) end
end
for _, root in ipairs(roots) do emit(root, 1) end
io.write("[", table.concat(ops, ",\n"), "]\n")
