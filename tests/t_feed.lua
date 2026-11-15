-- Feed.lua: better items in the Loot Feed of EllesmereUI (a model of it, see Mock.installLootFeed, built after its source)
return function(T)
    local F = require("fixtures")

    -- Arms warrior and a Loot Feed (options: see the mock; false = EllesmereUI without the Loot Feed, nil = no EllesmereUI)
    local function world(feedOptions, setup)
        local W = T.world(F.arms(), function(w)
            w.I = F.armsWarrior(w)
            w.I.better = F.gear(w, 9301, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35, sellPrice = 120 })
            w.I.weak = F.gear(w, 9302, "Weak Chestplate", "INVTYPE_CHEST", 10, { STR = 1 })
            w.I.late = F.gear(w, 9303, "Late Chestplate", "INVTYPE_CHEST", 90, { STR = 100 }, { minLevel = 65 })
            w.I.potion = F.gear(w, 9304, "Potion", "", 1, {})
            w.I.ring = F.gear(w, 9305, "Good Ring", "INVTYPE_FINGER", 40, { STR = 20, HIT = 15 }, { typeText = "" })
            if feedOptions then
                w.LF = w.installLootFeed(feedOptions)
            elseif feedOptions == false then
                w.env.EllesmereUI = { IS_FOREVER = true }
            end
            if setup then setup(w) end
        end)
        return W, W.LF
    end
    -- the feed shows the item, the client sends the chat line, a moment passes
    local function loot(W, LF, link, count)
        local row = LF.loot(link, count)
        W.fire("CHAT_MSG_LOOT", "You receive loot")
        W.flush()
        return row
    end
    local function on(part) return part ~= nil and part:IsShown() end
    local function marked(row) return on(row.EasyGearMark) end

    ------------------------------------------------------------------ the marking
    T.test("feed: the row of a better item gets the marker on its icon, a tint in the marker's color and the gain at the bottom right", function()
        local W, LF = world({})
        local row = loot(W, LF, W.I.better)
        T.eq(marked(row), true)
        local mark, tint, text = row.EasyGearMark, row.EasyGearTint, row.EasyGearText
        T.eq(mark:GetAtlas(), "bags-greenarrow")
        local point, rel = mark:GetPoint(1)
        T.eq(point, "TOPLEFT") T.eq(rel, row.icon, "on the corner of the row's icon")
        T.near(mark:GetWidth(), 28 * 0.6, 1e-9, "60 % of the icon (28 pixels in a 36 pixel bar row)")
        T.eq(on(tint), true)
        T.near(tint.__color[1], 0x40 / 255) T.eq(tint.__color[2], 1) T.near(tint.__color[4], 0.16, 1e-9, "a light tint in the green of the marker")
        T.eq(on(text), true) T.eq(text:GetText(), "+83.1%")
        T.eq(text.__textColor[2], 1) T.near(text.__textColor[1], 0x40 / 255)
        T.eq(select(1, text:GetPoint(1)), "BOTTOMRIGHT") T.eq(select(2, text:GetPoint(1)), row)
        local file, size = text:GetFont()
        T.has(file, "Expressway") T.eq(size, 11, "the font and size of the feed's second line")
        T.eq(row.name:GetText(), "Better Chestplate", "the feed's own texts are untouched") T.eq(row.sub:GetText(), "ilvl: 40")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("feed: rows of other things stay as they are - a worse item, a potion, money", function()
        local W, LF = world({})
        local weak = loot(W, LF, W.I.weak)
        local potion = loot(W, LF, W.I.potion, 3)
        local money = LF.money(17)
        W.fire("CHAT_MSG_LOOT", "x") W.flush()
        for name, row in pairs({ weak = weak, potion = potion, money = money }) do
            T.eq(marked(row), false, name) T.eq(on(row.EasyGearTint), false, name) T.eq(on(row.EasyGearText), false, name)
        end
        T.eq(W.EG.lastError, nil)
    end)

    T.test("feed: an upgrade for a later level and an item for the group get their own marker and words", function()
        local W, LF = world({}, function(w)
            local G = w.installGroup()
            local gear = {}
            for slot, loc in pairs({ [1] = "INVTYPE_HEAD", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
                                     [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND" }) do
                gear[slot] = F.gear(w, 9400 + slot, "Cloth" .. slot, loc, 30, { INT = 10, SP = 10 }, { subclassID = 1 })
            end
            G.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            w.I.robe = F.gear(w, 9420, "Robe", "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
        end)
        W.advance(30)
        local late = loot(W, LF, W.I.late)
        T.eq(marked(late), true)
        T.eq(late.EasyGearMark.__desaturated, true, "the yellow arrow of 'not yet'") T.near(late.EasyGearMark.__vertex[2], 0.82, 1e-9)
        T.eq(late.EasyGearText:GetText(), "level 65")
        T.near(late.EasyGearTint.__color[2], 0.82, 0.01, "tinted yellow")

        local robe = loot(W, LF, W.I.robe)
        T.eq(marked(robe), true)
        T.eq(robe.EasyGearMark:GetAtlas(), "tradeskills-star", "the violet star") T.eq(robe.EasyGearText:GetText(), "group")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("feed: a row that was there before the group member was read gets its star when the reading arrives", function()
        local W, LF = world({}, function(w)
            local G = w.installGroup()
            local gear = {}
            for slot, loc in pairs({ [1] = "INVTYPE_HEAD", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
                                     [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND" }) do
                gear[slot] = F.gear(w, 9440 + slot, "Cloth" .. slot, loc, 30, { INT = 10, SP = 10 }, { subclassID = 1 })
            end
            w.G = G
            w.gear = gear
            w.I.robe = F.gear(w, 9460, "Robe", "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
        end)
        local robe = loot(W, LF, W.I.robe)
        T.eq(marked(robe), false, "nobody in the group yet")
        W.G.add("party1", { name = "Bob", class = "PRIEST", gear = W.gear })
        W.G.rosterChanged()
        W.advance(30)                                    -- the member is inspected; the hints are worked out anew
        T.eq(marked(robe), true, "the row on screen follows")
        T.eq(robe.EasyGearMark:GetAtlas(), "tradeskills-star")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("feed: tiles of the Icon Tray style get the marker only - their corner holds the count", function()
        local W, LF = world({ style = "TRAY" })
        local row = loot(W, LF, W.I.better)
        T.eq(marked(row), true) T.eq(on(row.EasyGearTint), true)
        T.eq(on(row.EasyGearText), false, "no words on a tile")
        T.near(row.EasyGearMark:GetWidth(), 20, 1e-9, "a 36 pixel tile: the marker is capped at 20")
        LF.setStyle("BAR")                               -- the user switches the style: the feed fills every row again
        T.eq(on(row.EasyGearText), true, "back in a row style the words are there again, at once")
        T.near(row.EasyGearMark:GetWidth(), 28 * 0.6, 1e-9)
        local small = world({ rowHeight = 20 })
        local _, LF2 = small, small.LF
        local tiny = loot(small, LF2, small.I.better)
        T.eq(tiny.EasyGearMark:GetWidth(), 12, "never smaller than 12 pixels")
    end)

    ------------------------------------------------------------------ rows are reused
    T.test("feed: a row the feed fills again is judged again at that moment - no mark left over from the item before", function()
        local W, LF = world({ maxRows = 1 })
        local row = loot(W, LF, W.I.better)
        T.eq(marked(row), true)
        local again = LF.loot(W.I.weak)                  -- one row only: the feed takes it back and fills it anew - no scan in between
        T.eq(again, row, "the same row object")
        T.eq(marked(row), false, "the mark went with the item") T.eq(on(row.EasyGearTint), false) T.eq(on(row.EasyGearText), false)
        LF.loot(W.I.ring)
        T.eq(marked(row), true, "and comes with the next better one") T.eq(row.EasyGearText:GetText(), "+279.3%")
        LF.money(5)
        T.eq(marked(row), false, "a money row has no item at all")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("feed: each row is taken once - one hook per row however often it is filled or looked at", function()
        local W, LF = world({})
        local row = loot(W, LF, W.I.better)
        local hooked = row.icon.SetTexture
        for _ = 1, 5 do loot(W, LF, W.I.better) end       -- the same item again: the feed refills the same row
        T.eq(row.icon.SetTexture, hooked, "no hook on top of the hook")
        T.eq(row.data.amount, 6) T.eq(marked(row), true)
        W.clearChat() W.slash("status")
        T.has(W.chatText(), "EllesmereUI Loot Feed: found - better items are marked in it (1 rows taken so far)")
    end)

    T.test("feed: an item the feed had to load first is marked when its row shows up", function()
        local W, LF = world({}, function(w)
            w.I.slow = F.gear(w, 9310, "Slow Chestplate", "INVTYPE_CHEST", 60, { STR = 60 }, { armor = 700, uncached = true })
        end)
        T.eq(loot(W, LF, W.I.slow), nil, "no row yet: the client does not have the item")
        W.state.items[9310].uncached = nil
        local row = LF.loaded()                          -- the feed gets its callback and shows the row ...
        T.eq(marked(row), false, "a new row nobody has looked at yet")
        W.fire("GET_ITEM_INFO_RECEIVED", 9310, true)     -- ... and EasyGear hears of the same arrival
        W.flush()
        T.eq(marked(row), true) T.eq(row.EasyGearText:GetText() ~= "", true)
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ settings and changes
    T.test("feed: the setting for loot markers switches the marking off and on; another look repaints the rows", function()
        local W, LF = world({})
        local row = loot(W, LF, W.I.better)
        W.slash("items off") W.flush()
        T.eq(marked(row), false) T.eq(on(row.EasyGearTint), false) T.eq(on(row.EasyGearText), false)
        W.slash("items on") W.flush()
        T.eq(marked(row), true)
        W.slash("marker upgrade star ff8800") W.flush()
        T.eq(row.EasyGearMark:GetAtlas(), "tradeskills-star")
        T.eq(row.EasyGearTint.__color[1], 1) T.near(row.EasyGearTint.__color[2], 0x88 / 255) T.eq(row.EasyGearTint.__color[3], 0)
        T.near(row.EasyGearText.__textColor[2], 0x88 / 255)
    end)

    T.test("feed: a change of equipment changes the verdict of the rows on screen", function()
        local W, LF = world({}, function(w)
            w.I.super = F.gear(w, 9311, "Super Chestplate", "INVTYPE_CHEST", 90, { STR = 200, STA = 100 }, { armor = 900 })
        end)
        local row = loot(W, LF, W.I.better)
        T.eq(marked(row), true)
        W.equip(5, W.I.super) W.fire("PLAYER_EQUIPMENT_CHANGED", 5) W.flush()
        T.eq(marked(row), false, "no upgrade any more")
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ what is not a row, what is missing
    T.test("feed: the pinned tracker row and other children of the feed are left alone", function()
        local W, LF = world({ tracker = true })
        local row = loot(W, LF, W.I.better)
        T.eq(marked(row), true)
        T.eq(marked(LF.summary), false) T.eq(LF.summary.EasyGearTint, nil, "nothing was even made on the tracker row")
        T.eq(LF.callout.EasyGearMark, nil, "the callout has no icon: not a row")
        W.clearChat() W.slash("status")
        T.has(W.chatText(), "(2 rows taken so far)", "the tracker row counts as a row, it just never holds an item")
    end)

    T.test("feed: without EllesmereUI, without its Loot Feed, or with the feed switched off nothing happens - /eg status says which", function()
        local function status(W)
            W.fire("CHAT_MSG_LOOT", "x") W.flush()
            W.clearChat() W.slash("status")
            return W.chatText()
        end
        local none = world(nil)
        T.hasnt(status(none), "Loot Feed", "no EllesmereUI: no line at all")
        local bare = world(false)
        T.has(status(bare), "EllesmereUI Loot Feed: not found (EllesmereUI Forever Essentials)")
        local W, LF = world({ noRegistry = true })
        T.has(status(W), "EllesmereUI Loot Feed: not found")
        local off, LFoff = world({ enabled = false })
        T.has(status(off), "EllesmereUI Loot Feed: switched off in EllesmereUI")
        T.eq(LFoff.anchor, nil, "and EasyGear did not make the feed build its frame")
        LFoff.setEnabled(true)
        local row = loot(off, LFoff, off.I.better)
        T.eq(marked(row), true, "switched on later, it is found")
        T.has(status(off), "found - better items are marked")
        for _, w in ipairs({ none, bare, W, off }) do T.eq(w.EG.lastError, nil) end
        T.eq(LF.anchor, nil)
    end)

    T.test("feed: a failure inside EasyGear does not stop the feed from filling its row", function()
        local W, LF = world({ maxRows = 1 })
        local row = loot(W, LF, W.I.better)
        W.EG.Score.UpgradeState = function() error("boom") end
        local ring = LF.loot(W.I.ring)                   -- the one row is filled again: the hook runs inside the feed's Fill
        T.eq(ring, row)
        T.eq(ring.name:GetText(), "Good Ring", "the feed finished its row: name and the rest come after the icon")
        T.eq(ring.sub:GetText(), "ilvl: 40")
        T.ok(W.EG.lastError and tostring(W.EG.lastError.err):find("boom", 1, true), "reported for /eg status")
    end)

    ------------------------------------------------------------------ random walk
    T.test("feed: random loot, reuse, styles and switches - every row on screen carries exactly the mark its item deserves", function()
        local seed = (tonumber(os.getenv("FUZZ_SEED")) or 9001) % 2147483646 + 1
        local function rnd(n) seed = (seed * 16807) % 2147483647 return seed % n + 1 end
        local W, LF = world({ maxRows = 3, tracker = true }, function(w)
            w.I.pool = { w.I.better, w.I.weak, w.I.late, w.I.potion, w.I.ring }
            for i = 1, 5 do
                w.I.pool[#w.I.pool + 1] = F.gear(w, 9500 + i, "Piece" .. i, ({ "INVTYPE_CHEST", "INVTYPE_HEAD", "INVTYPE_LEGS" })[rnd(3)],
                    rnd(80), { STR = rnd(60), STA = rnd(40) })
            end
        end)
        local styles = { "BAR", "BOX", "TRAY", "TOAST" }
        for step = 1, 100 do
            local action = rnd(8)
            if action <= 3 then
                LF.loot(W.I.pool[rnd(#W.I.pool)], rnd(2))
                W.fire("CHAT_MSG_LOOT", "x")
            elseif action == 4 then
                LF.money(rnd(50))
            elseif action == 5 and LF.active[1] then
                LF.release(LF.active[rnd(#LF.active)])
            elseif action == 6 then
                LF.setStyle(styles[rnd(4)])
            elseif action == 7 then
                W.EG:Set("showItemIcons", rnd(4) ~= 1)
            else
                W.advance(rnd(3))
            end
            W.flush()
            local enabled = W.EG:Get("showItemIcons") ~= false
            for _, row in ipairs(LF.active) do
                local link = row.data.link
                local want = (enabled and link) and W.EG.Score.UpgradeState(link) or nil
                T.eq(marked(row), want ~= nil, "step " .. step .. ": the marker of " .. tostring(row.data.text))
                T.eq(on(row.EasyGearTint), want ~= nil, "step " .. step .. ": the tint")
                T.eq(on(row.EasyGearText), want ~= nil and LF.style ~= "TRAY", "step " .. step .. ": the words")
                if want == "UPGRADE" then T.eq(row.EasyGearMark.__desaturated, false, "step " .. step) end
                if want == "LEVEL" then T.eq(row.EasyGearMark.__desaturated, true, "step " .. step) end
            end
            if LF.summary then T.eq(marked(LF.summary), false, "the tracker row, step " .. step) end
            T.eq(W.EG.lastError, nil, "no internal error, step " .. step .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
        end
    end)
end
