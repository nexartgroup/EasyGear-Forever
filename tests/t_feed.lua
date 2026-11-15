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
    local function loot(W, LF, link, count, options)
        local row = LF.loot(link, count, options)
        W.fire("CHAT_MSG_LOOT", "You receive loot")
        W.flush()
        return row
    end
    local function on(part) return part ~= nil and part:IsShown() end
    local function marked(row) return on(row.EasyGearMark) end
    -- left, right, bottom, top of a region on the screen
    local function box(W, region)
        local l, b, w, h = W.rect(region)
        return { l = l, r = l + w, b = b, t = b + h, w = w, h = h }
    end
    local function inside(inner, outer, slack)
        slack = slack or 0
        return inner.l >= outer.l - slack and inner.r <= outer.r + slack and inner.b >= outer.b - slack and inner.t <= outer.t + slack
    end

    ------------------------------------------------------------------ the marking
    T.test("feed: the row of a better item gets the marker in the corner of its icon, a tint in the marker's color and the gain behind the second line", function()
        local W, LF = world({})
        local row = loot(W, LF, W.I.better)
        T.eq(marked(row), true)
        local mark, tint, text = row.EasyGearMark, row.EasyGearTint, row.EasyGearText
        T.eq(mark:GetAtlas(), "bags-greenarrow")
        local point, rel = mark:GetPoint(1)
        T.eq(point, "TOPLEFT") T.eq(rel, row.icon, "in the corner of the row's icon")
        T.near(mark:GetWidth(), 28 * 0.6, 1e-9, "60 % of the icon (28 pixels in a 36 pixel bar row)")
        T.eq(on(tint), true)
        T.eq(tint:GetParent(), row, "the tint lies in the row itself, under its icon and texts") T.eq(tint.__layer, "BORDER")
        T.near(tint.__color[1], 0x40 / 255) T.eq(tint.__color[2], 1) T.near(tint.__color[4], 0.16, 1e-9, "a light tint in the green of the marker")
        T.eq(on(text), true) T.eq(text:GetText(), "+83.1%")
        T.eq(text.__textColor[2], 1) T.near(text.__textColor[1], 0x40 / 255)
        local file, size = text:GetFont()
        T.has(file, "Expressway") T.eq(size, 11, "the font and size of the feed's second line")
        T.eq(text.__wordWrap, false, "one line: the client shortens it when the room runs out")
        T.eq(row.name:GetText(), "Better Chestplate", "the feed's own texts are untouched") T.eq(row.sub:GetText(), "ilvl: 40")
        -- where the words are: on the second line, right behind the feed's text, ending before the price
        local words, sub, value = box(W, text), box(W, row.sub), box(W, row.value)
        T.near(words.l, sub.l + row.sub:GetStringWidth() + 8, 1e-9, "eight pixels behind 'ilvl: 40'")
        T.near(words.t, sub.t, 1e-9, "on the feed's second line")
        T.ok(value.w > 0, "this item has a price") T.ok(words.r <= value.l - 8 + 1e-9, "the words end before the price")
        T.near(words.w, text:GetUnboundedStringWidth(), 1e-9, "all of '+83.1%' is there - nothing bounds the words")
        T.eq(text:GetPoint(2), nil, "one point: behind the feed's text")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("feed: the words never lie on the price - any row height, style and text size; without room they stay away", function()
        for _, style in ipairs({ "BAR", "BOX", "TOAST" }) do
            for _, height in ipairs({ 18, 20, 24, 28, 36, 48 }) do
                for _, size in ipairs({ 10, 13, 18 }) do
                    local W, LF = world({ style = style, rowHeight = height, textSize = size })
                    local row = loot(W, LF, W.I.better)
                    local where = style .. " " .. height .. " " .. size
                    T.eq(on(row.EasyGearText), true, where)
                    local words, value = box(W, row.EasyGearText), box(W, row.value)
                    T.ok(value.w > 0, where)
                    T.ok(words.w > 0, where .. ": the words are there")
                    T.ok(words.r <= value.l - 8 + 1e-9, where .. ": the words end left of the price")
                end
            end
        end
        -- a narrow feed: the second line reaches the price, nothing is left for the words
        local W, LF = world({ width = 150 })
        local row = loot(W, LF, W.I.better, 1, { won = "Need 87" })
        T.eq(row.sub:GetText(), "Won: Need 87  ilvl: 40")
        T.ok(row.sub:GetStringWidth() < row.sub:GetUnboundedStringWidth(), "the feed's own line is cut already")
        T.eq(on(row.EasyGearText), false, "no room: no words") T.eq(marked(row), true, "marker and tint say it") T.eq(on(row.EasyGearTint), true)
        -- the room is measured, not guessed: the widest feed the words do not fit into, and the first one they do
        local need = row.EasyGearText:GetUnboundedStringWidth()
        for _, case in ipairs({ { -1, false }, { 0, true }, { 1, true } }) do
            -- row: bar 3 + 5, icon 28, 6 to the text, "ilvl: 40" (8 letters of 5.5), 8 gap, the words, 8 to the price, the price, 6
            local price = 3 * 6.5                        -- "12g" in the 13 pixel font
            local width = 8 + 28 + 6 + 8 * 5.5 + 8 + need + 8 + price + 6 + case[1]
            local V, VLF = world({ width = width }, function(w) w.state.items[9301].sellPrice = 12 end)
            local vrow = loot(V, VLF, V.I.better)
            T.eq(vrow.value:GetText(), "12g") T.eq(on(vrow.EasyGearText), case[2], "width " .. width)
            if case[2] then T.ok(box(V, vrow.EasyGearText).r <= box(V, vrow.value).l - 8 + 1e-9, "width " .. width) end
        end
    end)

    T.test("feed: without a second line the words follow the name", function()
        local W, LF = world({ ilvl = false })             -- Show Item Level is off in EllesmereUI
        local row = loot(W, LF, W.I.better)
        T.eq(on(row.sub), false, "no second line") T.eq(on(row.EasyGearText), true)
        local words, name, value = box(W, row.EasyGearText), box(W, row.name), box(W, row.value)
        T.near(words.l, name.l + row.name:GetStringWidth() + 8, 1e-9, "eight pixels behind the name")
        T.near((words.b + words.t) / 2, (name.b + name.t) / 2, 1e-9, "on the line of the name")
        T.ok(words.r <= value.l - 8 + 1e-9, "ending before the price")
        -- the same row gets its second line back (the same item again, now won by a roll): the words move there
        local again = loot(W, LF, W.I.better, 1, { won = "Greed 12", ilvl = false })
        T.eq(again, row) T.eq(on(row.sub), true)
        T.near(box(W, row.EasyGearText).t, box(W, row.sub).t, 1e-9, "on the second line now")
        T.near(box(W, row.EasyGearText).l, box(W, row.sub).l + row.sub:GetStringWidth() + 8, 1e-9)
        -- Box rows of a roll-less item keep name and second line; the words go where the second line is
        LF.setStyle("BOX")
        T.near(box(W, row.EasyGearText).t, box(W, row.sub).t, 1e-9)
        T.eq(W.EG.lastError, nil)
        -- a narrow feed: the name fills its line up to the price, the words get no room and do not run over it
        local N, NLF = world({ ilvl = false, width = 170 })
        local narrow = loot(N, NLF, N.I.better)
        T.eq(on(narrow.EasyGearText), false, "no words") T.eq(marked(narrow), true)
        -- the next thing in that row is short: the words are back
        NLF.maxRows = 1
        local short = loot(N, NLF, N.I.ring)
        T.eq(short, narrow) T.eq(short.name:GetText(), "Good Ring")
        T.eq(on(short.EasyGearText), true, "room again")
        T.ok(box(N, short.EasyGearText).r <= box(N, short.value).l + 1e-9)
    end)

    T.test("feed: marker and words lie on a layer of their own above the row's border, the marker inside the row in every style", function()
        for _, style in ipairs({ "BAR", "BOX", "TRAY", "TOAST" }) do
            for _, height in ipairs({ 10, 14, 20, 36, 60 }) do
                local W, LF = world({ style = style, rowHeight = height, borderTexture = "pixels" })
                local row = loot(W, LF, W.I.better)
                local where = style .. " " .. height
                local layer = row.EasyGearLayer
                T.eq(layer:GetParent(), row, where .. ": a child of the row - it fades and hides with it")
                T.eq(row.EasyGearMark:GetParent(), layer, where) T.eq(row.EasyGearText:GetParent(), layer, where)
                T.ok(layer:GetFrameLevel() > LF.borders[row]:GetFrameLevel(), where .. ": above the row's border")
                T.ok(layer:GetFrameLevel() > row.lootBorder:GetFrameLevel(), where .. ": above the textured border")
                local mark, icon = box(W, row.EasyGearMark), box(W, row.icon)
                T.ok(inside(mark, box(W, row), 1e-9), where .. ": the marker stays inside the row")
                if mark.w + 1 <= icon.w then
                    T.ok(inside(mark, icon), where .. ": inside the icon")
                    T.near(mark.l, icon.l + 1, 1e-9, where .. ": in its top left corner") T.near(mark.t, icon.t - 1, 1e-9, where)
                else
                    T.near((mark.l + mark.r) / 2, (icon.l + icon.r) / 2, 1e-9, where .. ": larger than a tiny icon - centred on it")
                    T.near((mark.b + mark.t) / 2, (icon.b + icon.t) / 2, 1e-9, where)
                end
                T.ok(mark.w >= math.min(12, height), where .. ": readable")
                T.ok(inside(box(W, layer), box(W, row)) and inside(box(W, row), box(W, layer)), where .. ": the layer covers the row")
            end
        end
        -- the feed moves a row to another level (it does for Border Behind): the layer follows at the next filling
        local W, LF = world({})
        local row = loot(W, LF, W.I.better)
        row:SetFrameLevel(40)
        loot(W, LF, W.I.better)
        T.eq(row.EasyGearLayer:GetFrameLevel(), 43)
        -- the style changes under a shown row: a low Box row (icon 14) becomes a Bar row (icon 6) - the marker leaves
        -- the corner for the middle of the icon, hung in anew each time
        local S, SLF = world({ style = "BOX", rowHeight = 14 })
        local low = loot(S, SLF, S.I.better)
        T.eq(select(1, low.EasyGearMark:GetPoint(1)), "TOPLEFT")
        SLF.setStyle("BAR")
        T.eq(select(1, low.EasyGearMark:GetPoint(1)), "CENTER") T.eq(low.EasyGearMark:GetPoint(2), nil, "one point, not one more each time")
        T.ok(inside(box(S, low.EasyGearMark), box(S, low), 1e-9), "still inside the row")
        SLF.setStyle("BOX")
        T.eq(select(1, low.EasyGearMark:GetPoint(1)), "TOPLEFT") T.eq(low.EasyGearMark:GetPoint(2), nil)
    end)

    T.test("feed: only what the player got is marked - not what somebody else won, and the history shows the marks again", function()
        local W, LF = world({})
        local roll = LF.roll(W.I.better, "Bob", "Need 99")
        W.fire("CHAT_MSG_LOOT", "x") W.flush()
        T.eq(roll.data.link, W.I.better, "the row carries the link of the better item")
        T.eq(marked(roll), false, "but Bob has it") T.eq(on(roll.EasyGearTint), false) T.eq(on(roll.EasyGearText), false)
        local own = loot(W, LF, W.I.better, 1, { won = "Need 100" })
        T.eq(marked(own), true, "the player's own win is a row of its own")
        T.eq(marked(roll), false)
        -- looking back (Shift and the mouse wheel): the rows are called "history:<n>", the entries know what they were
        local rows = LF.showHistory()
        T.eq(#rows, 2)
        T.eq(rows[1].key, "history:1") T.eq(rows[1].data.key, "item:" .. W.I.better)
        T.eq(marked(rows[1]), true, "the player's item is marked in the history as well")
        T.eq(rows[2].data.key, "roll:1:1") T.eq(marked(rows[2]), false, "Bob's is not")
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
        -- the rule is the hidden name, not the width of a tile: a wide row whose name the feed hides gets no words either
        T.eq(on(tiny.EasyGearText), true)
        tiny.name:Hide()
        small.fire("CHAT_MSG_LOOT", "x") small.flush()
        T.eq(on(tiny.EasyGearText), false, "no name, no words") T.eq(marked(tiny), true)
    end)

    T.test("feed: rows the feed builds without a word - beside a known row, or for its history while Shift is held - are found", function()
        -- beside a known row
        local W, LF = world({})
        local first = loot(W, LF, W.I.better)            -- found through the chat line
        local second = LF.loot(W.I.ring)                 -- a row without a chat line
        W.advance(1)
        T.eq(marked(second), false, "nobody told EasyGear")
        LF.loot(W.I.better)                              -- the feed fills the known row again
        T.eq(marked(first), true) T.eq(marked(second), false, "not in the same moment")
        W.advance(0.2)
        T.eq(marked(second), true, "a look at all rows follows the filling of a known one")
        T.eq(#W.state.timers, 0, "and that is the end of it - looking does not cause more looking")

        -- the history right after login: no row was ever built, entries are kept from an earlier session
        local V, VLF = world({})
        V.fire("CHAT_MSG_LOOT", "x") V.flush()
        for _, link in ipairs({ V.I.weak, V.I.better }) do
            local it = V.state.itemFromAny(link)
            table.insert(VLF.entries, 1, { icon = 1, text = it.name, sub = "ilvl: " .. it.ilvl, link = link, key = "item:" .. link })
        end
        V.state.shift = true
        V.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
        T.eq(#V.state.timers, 2, "a look soon, and the watch")
        V.fire("MODIFIER_STATE_CHANGED", "RSHIFT", 1)
        T.eq(#V.state.timers, 2, "the other Shift key: still one watch")
        V.advance(3)                                     -- Shift is held for a while before the wheel turns
        local rows = VLF.showHistory()
        T.eq(#rows, 2) T.eq(rows[1].data.link, V.I.better)
        T.eq(marked(rows[1]), false, "just built")
        V.advance(0.25)
        T.eq(marked(rows[1]), true, "seen within a quarter second") T.eq(marked(rows[2]), false, "the worse item stays plain")
        V.state.shift = false
        V.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
        T.eq(#V.state.timers, 2, "the running watch and one last look - no second watch")
        V.advance(1)
        T.eq(#V.state.timers, 0, "Shift is up: no more watching")
        V.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
        T.eq(#V.state.timers, 0, "other modifier keys do not matter")
        T.eq(V.EG.lastError, nil)

        -- the key is let go without the client saying so (the window lost the focus): the watch ends by itself
        V.state.shift = true
        V.fire("MODIFIER_STATE_CHANGED", "RSHIFT", 1)    -- the right Shift key this time
        V.advance(1)
        T.eq(#V.state.timers, 1, "watching")
        V.state.shift = false
        V.advance(1)
        T.eq(#V.state.timers, 0)

        -- a quick flick: rows built and Shift let go before the watch looked - the look at letting go finds them
        local Q, QLF = world({})
        Q.fire("CHAT_MSG_LOOT", "x") Q.flush()
        local it = Q.state.itemFromAny(Q.I.better)
        table.insert(QLF.entries, 1, { icon = 1, text = it.name, sub = "ilvl: 40", link = Q.I.better, key = "item:" .. Q.I.better })
        Q.state.shift = true
        Q.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
        Q.advance(0.1)
        local quick = QLF.showHistory()
        Q.state.shift = false
        Q.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
        Q.advance(0.1)
        T.eq(marked(quick[1]), true, "found by the look at letting go")
        Q.advance(1)
        T.eq(#Q.state.timers, 0)

        -- no feed, or the marks switched off: nothing to watch
        local none = world(nil)
        none.state.shift = true
        none.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
        none.advance(1)
        T.eq(#none.state.timers, 0, "no EllesmereUI: one look, then quiet") T.eq(none.EG.lastError, nil)
        local off, OLF = world({})
        loot(off, OLF, off.I.better)
        off.slash("items off") off.flush()
        off.state.shift = true
        off.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
        off.advance(1)
        T.eq(#off.state.timers, 0, "marks off: quiet")
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
        local hooked = row.badge.SetText
        for _ = 1, 5 do loot(W, LF, W.I.better) end       -- the same item again: the feed refills the same row
        T.eq(row.badge.SetText, hooked, "no hook on top of the hook")
        T.eq(rawget(row.icon, "SetTexture"), nil, "the icon is not hooked: its texture comes before the texts")
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
        -- a child that looks like a row but lacks the text EasyGear listens to: left alone as well
        local odd = W.env.CreateFrame("Frame", nil, LF.anchor)
        odd.icon, odd.name, odd.sub, odd.value = odd:CreateTexture(), odd:CreateFontString(), odd:CreateFontString(), odd:CreateFontString()
        odd.key, odd.data = "item:" .. W.I.better, { link = W.I.better }
        loot(W, LF, W.I.ring)
        T.eq(odd.EasyGearMark, nil) T.eq(odd.EasyGearLayer, nil)
        T.eq(W.EG.lastError, nil)
        W.clearChat() W.slash("status")
        T.has(W.chatText(), "(3 rows taken so far)", "two item rows and the tracker row - it counts as a row, it just never holds an item")
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
        T.eq(ring.name:GetText(), "Good Ring", "the feed finished its row")
        T.eq(ring.sub:GetText(), "ilvl: 40")
        T.eq(select(1, ring.name:GetPoint(1)), "RIGHT", "the name was hung in after the badge text - the hook did not stop it")
        T.eq(select(1, ring.name:GetPoint(2)), "BOTTOMLEFT")
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
            local action = rnd(9)
            if action <= 3 then
                LF.loot(W.I.pool[rnd(#W.I.pool)], rnd(2), { ilvl = rnd(3) ~= 1 })
                W.fire("CHAT_MSG_LOOT", "x")
            elseif action == 4 then
                LF.money(rnd(50))
            elseif action == 9 then
                LF.roll(W.I.pool[rnd(#W.I.pool)], "Bob", rnd(2) == 1 and ("Need " .. rnd(100)) or nil)
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
                local link = row.key:sub(1, 5) == "item:" and row.data.link or nil
                local want = (enabled and link) and W.EG.Score.UpgradeState(link) or nil
                T.eq(marked(row), want ~= nil, "step " .. step .. ": the marker of " .. tostring(row.data.text))
                T.eq(on(row.EasyGearTint), want ~= nil, "step " .. step .. ": the tint")
                T.eq(on(row.EasyGearText), want ~= nil and LF.style ~= "TRAY", "step " .. step .. ": the words")
                if want == "UPGRADE" then T.eq(row.EasyGearMark.__desaturated, false, "step " .. step) end
                if want == "LEVEL" then T.eq(row.EasyGearMark.__desaturated, true, "step " .. step) end
                if want ~= nil and LF.style ~= "TRAY" then
                    T.ok(box(W, row.EasyGearText).r <= box(W, row.value).l + 1e-9, "step " .. step .. ": the words end before the price")
                    local line = on(row.sub) and row.sub or row.name
                    T.eq(select(2, row.EasyGearText:GetPoint(1)), line, "step " .. step .. ": the words follow the line that is shown")
                end
                if want ~= nil then
                    T.ok(inside(box(W, row.EasyGearMark), box(W, row)), "step " .. step .. ": the marker inside the row")
                end
            end
            if LF.summary then T.eq(marked(LF.summary), false, "the tracker row, step " .. step) end
            T.eq(W.EG.lastError, nil, "no internal error, step " .. step .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
        end
    end)
end
