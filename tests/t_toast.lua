-- Toast.lua: the notification "better item" when gear arrives in the bags
return function(T)
    local F = require("fixtures")

    -- Arms warrior, an empty backpack; the first look into the bags (what the client does at login) is taken
    local function world(setup, opts)
        local W = T.world(F.arms(opts), function(w)
            w.I = F.armsWarrior(w)
            w.I.better = F.gear(w, 9101, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35 })
            w.I.weak = F.gear(w, 9102, "Weak Chestplate", "INVTYPE_CHEST", 10, { STR = 1 })
            w.I.late = F.gear(w, 9103, "Late Chestplate", "INVTYPE_CHEST", 90, { STR = 100 }, { minLevel = 65 })
            w.I.potion = F.gear(w, 9104, "Potion", "", 1, {})
            w.I.ring = F.gear(w, 9105, "Good Ring", "INVTYPE_FINGER", 40, { STR = 20, HIT = 15 }, { typeText = "" })
            w.I.helm = F.gear(w, 9106, "Good Helm", "INVTYPE_HEAD", 40, { STR = 20 })
            w.I.legs = F.gear(w, 9107, "Good Legs", "INVTYPE_LEGS", 40, { STR = 20 })
            w.I.boots = F.gear(w, 9108, "Good Boots", "INVTYPE_FEET", 40, { STR = 20 })
            w.bag(0, 16, {})
            if setup then setup(w) end
        end)
        W.fire("BAG_UPDATE_DELAYED")
        return W
    end
    local function loot(W, slot, link, bag)
        W.put(bag or 0, slot, link)
        W.fire("BAG_UPDATE_DELAYED")
    end
    local function shown(W) return W.EG.Toast.shown end

    ------------------------------------------------------------------ what it shows
    T.test("toast: a better item that arrives in the bags is announced - icon, name, gain and what it replaces", function()
        local W = world()
        T.eq(#shown(W), 0)
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 1)
        local f = shown(W)[1]
        T.eq(f:IsShown(), true) T.eq(f.__kind, "Button")
        T.eq(f.caption:GetText(), W.EG.L.TOAST_TITLE)
        T.eq(f.name:GetText(), "Better Chestplate")
        T.has(f.detail:GetText(), "+37") T.has(f.detail:GetText(), "(+83.1%)") T.has(f.detail:GetText(), "Chest: Worn Chestplate")
        T.eq(f.icon.icon:GetTexture(), 100000 + 9101, "the picture of the item") T.eq(f.icon.icon:IsShown(), true)
        T.eq(f.mark:GetAtlas(), "bags-greenarrow", "the marker of an upgrade sits on the icon") T.eq(f.mark:GetWidth(), 20)
        T.near(f.bar.__color[1], 0x40 / 255) T.eq(f.bar.__color[2], 1, "the bar on the left in the green of the marker")
        local point, rel = f:GetPoint(1)
        T.eq(point, "TOP") T.eq(rel, W.env.EasyGearToastAnchor)
        local ap, _, _, ax, ay = W.env.EasyGearToastAnchor:GetPoint(1)
        T.eq(ap, "TOP") T.eq(ax, 0) T.eq(ay, -170, "below the top of the screen unless moved")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: an empty slot says so, a ring names the slot it would go to", function()
        local W = world()
        W.equip(12, nil) W.fire("PLAYER_EQUIPMENT_CHANGED", 12) W.flush()
        W.fire("BAG_UPDATE_DELAYED")
        loot(W, 1, W.I.ring)
        T.eq(#shown(W), 1)
        local detail = shown(W)[1].detail:GetText()
        T.has(detail, "   Finger 2: " .. W.EG.L.NOTHING_EQUIPPED, "the slot it would go to: " .. detail)
        T.hasnt(detail, "Finger 1", "not every slot it could go to")
    end)

    T.test("toast: it stands fifteen seconds - fades in, the line runs down, fades out, is gone", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        T.eq(f.__alpha, 0, "starts invisible") T.eq(f.seconds, 15)
        local full = f.timer:GetWidth()
        W.tick(0.1)
        T.near(f.__alpha, 0.4, 1e-6, "fading in over a quarter second")
        W.tick(0.9)
        T.eq(f.__alpha, 1)
        W.tick(6.5)
        T.near(f.timer:GetWidth(), full * 0.5, 1, "half the time, half the line")
        W.tick(7.2)
        T.eq(f:IsShown(), true) T.ok(f.__alpha < 1 and f.__alpha > 0, "fading out in the last half second: " .. f.__alpha)
        W.tick(0.4)
        T.eq(f:IsShown(), false, "gone after fifteen seconds") T.eq(#shown(W), 0)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: the time on screen is a setting, kept within its range", function()
        local W = world()
        W.slash("toast 5")
        T.eq(W.EG:Get("toastSeconds"), 5)
        loot(W, 1, W.I.better)
        W.tick(4.9)
        T.eq(#shown(W), 1)
        W.tick(0.2)
        T.eq(#shown(W), 0, "five seconds")
        W.slash("toast 500")
        T.eq(W.EG:Get("toastSeconds"), 5, "more than the slider can show is refused")
        W.EG.db.toastSeconds = 9999                     -- a hand-edited saved variable
        T.eq(W.EG.Toast.Seconds(), 60)
        W.EG.db.toastSeconds = "x"
        T.eq(W.EG.Toast.Seconds(), 15, "nonsense counts as the default")
    end)

    ------------------------------------------------------------------ what counts as new
    T.test("toast: what was in the bags at login, a worse item, something that is no gear, or an upgrade for a later level is not announced", function()
        local W = world(function(w) w.put(0, 1, w.I.better) end)
        T.eq(#shown(W), 0, "there at login")
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 0, "and still nothing when the bags are looked at again")
        loot(W, 2, W.I.weak)
        loot(W, 3, W.I.potion)
        loot(W, 4, W.I.late)
        T.eq(#shown(W), 0)
        loot(W, 5, W.I.ring)
        T.eq(#shown(W), 1, "but a real upgrade is") T.eq(shown(W)[1].name:GetText(), "Good Ring")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: an item that was just taken off is not new, although it beats the empty slot", function()
        local W = world()
        W.equip(5, nil)                                  -- the chest piece goes from the body into the bags
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        loot(W, 1, W.I.chest)
        T.eq(#shown(W), 0)
        T.eq(W.EG.Score.UpgradeState(W.I.chest), "UPGRADE", "it would count as an upgrade now")
        -- the same when the client reports the bags first and the equipment afterwards
        local V = world()
        V.equip(5, nil)
        loot(V, 1, V.I.chest)
        V.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        T.eq(#shown(V), 0, "it was worn at the last look into the bags")
    end)

    T.test("toast: moving an item between bags or changing its link (an enchant) is not getting a new one", function()
        local W = world(function(w) w.bag(1, 8, {}) end)
        W.EG:Set("showToast", false)
        loot(W, 1, W.I.better)                           -- it gets there unannounced ...
        W.EG:Set("showToast", true)
        W.put(0, 1, nil) W.put(1, 3, W.I.better)         -- ... and is moved to another bag
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 0, "moved")
        local enchanted = W.I.better:gsub("item:(%d+)", "item:%1:1234")
        T.ok(enchanted ~= W.I.better)
        W.put(1, 3, enchanted)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 0, "the same item with another link")
        W.put(0, 2, enchanted)                           -- a second copy of it, though, is one more
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 1)
    end)

    T.test("toast: nothing is announced out of the open bank, and loot after it closed is", function()
        local W = world()
        W.fire("BANKFRAME_OPENED")
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 0, "taken from the bank: owned already")
        W.fire("BANKFRAME_CLOSED")
        loot(W, 2, W.I.ring)
        T.eq(#shown(W), 1) T.eq(shown(W)[1].name:GetText(), "Good Ring")
    end)

    T.test("toast: quiet for the first seconds after a loading screen - the bags are still filling", function()
        local W = world()
        W.fire("PLAYER_ENTERING_WORLD")
        W.advance(2)
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 0, "two seconds after the loading screen")
        W.advance(4)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 0, "and it is not new afterwards either")
        loot(W, 2, W.I.ring)
        T.eq(#shown(W), 1, "six seconds after: announced")
    end)

    T.test("toast: an item whose data is still loading is announced when the data is there - but not ages later", function()
        local notYet = {}
        local function slowWorld()
            return world(function(w)
                local original = w.env.C_Item.GetItemInfo
                w.env.C_Item.GetItemInfo = function(link)
                    local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
                    if id and notYet[id] then return nil end
                    return original(link)
                end
            end)
        end
        notYet[9101] = true
        local W = slowWorld()
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 0, "nothing known about it yet")
        W.advance(3)
        notYet[9101] = nil
        W.fire("GET_ITEM_INFO_RECEIVED", 9101, true)
        W.flush()
        T.eq(#shown(W), 1, "announced as soon as its data arrived") T.eq(shown(W)[1].name:GetText(), "Better Chestplate")

        notYet[9101] = true
        local V = slowWorld()
        loot(V, 1, V.I.better)
        V.advance(30)
        notYet[9101] = nil
        V.fire("GET_ITEM_INFO_RECEIVED", 9101, true)
        V.flush()
        T.eq(#shown(V), 0, "half a minute later it is no news any more")
        T.eq(W.EG.lastError, nil) T.eq(V.EG.lastError, nil)
    end)

    T.test("toast: the same item is not announced twice within a minute", function()
        local W = world()
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 1)
        local f = shown(W)[1]
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#shown(W), 0)
        loot(W, 1, nil)
        W.advance(20)
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 0, "twenty seconds later: not again")
        loot(W, 1, nil)
        W.advance(45)
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 1, "after more than a minute it is")
    end)

    ------------------------------------------------------------------ several at once
    T.test("toast: three stand below each other, the others wait their turn", function()
        local W = world()
        W.equip(12, nil) W.fire("PLAYER_EQUIPMENT_CHANGED", 12) W.flush() W.fire("BAG_UPDATE_DELAYED")
        W.put(0, 1, W.I.better) W.put(0, 2, W.I.ring) W.put(0, 3, W.I.helm) W.put(0, 4, W.I.legs) W.put(0, 5, W.I.boots)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 3) T.eq(#W.EG.Toast.queue, 2, "five upgrades at once: three shown, two wait")
        local ys = {}
        for i, f in ipairs(shown(W)) do ys[i] = select(5, f:GetPoint(1)) end
        T.eq(ys[1], 0) T.eq(ys[2], -70) T.eq(ys[3], -140, "64 high with a gap of 6")
        local names = {}
        for _, f in ipairs(shown(W)) do names[f.name:GetText()] = true end
        local first = shown(W)[1]
        first.__scripts.OnClick(first, "RightButton")
        T.eq(#shown(W), 3) T.eq(#W.EG.Toast.queue, 1, "one closed: the next one moves up")
        T.eq(select(5, shown(W)[1]:GetPoint(1)), 0, "and the others close the gap")
        for _, f in ipairs(shown(W)) do names[f.name:GetText()] = true end
        W.tick(15.2)
        T.eq(#shown(W), 1, "the two older ones ran out, the last one came after them") T.eq(#W.EG.Toast.queue, 0)
        for _, f in ipairs(shown(W)) do names[f.name:GetText()] = true end
        local n = 0
        for _ in pairs(names) do n = n + 1 end
        T.eq(n, 5, "every one of the five was shown")
        W.tick(15.2)
        T.eq(#shown(W), 0)
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ mouse
    T.test("toast: under the mouse it holds and shows the tooltip with a hint; the time runs on when the mouse leaves", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        W.tick(1)
        f.__scripts.OnEnter(f)
        local tip = W.env.GameTooltip
        T.eq(tip:GetOwner(), f) T.eq(tip:HasLine("Better Chestplate"), true) T.eq(tip:HasLine(W.EG.L.TOAST_HINT), true)
        T.eq(tip:HasLine("EasyGear"), true, "the item tooltip with the comparison of EasyGear")
        W.tick(60)
        T.eq(f:IsShown(), true, "a minute under the mouse") T.eq(f.__alpha, 1)
        f.__scripts.OnLeave(f)
        T.eq(tip.__shown, false)
        W.tick(13.8)
        T.eq(f:IsShown(), true, "one second had passed before: fourteen are left")
        W.tick(0.4)
        T.eq(f:IsShown(), false)
    end)

    T.test("toast: a click opens the comparison with the item, a right-click closes the toast", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        f.__scripts.OnClick(f, "LeftButton")
        T.eq(W.EG.Window.IsShown(), true) T.eq(W.EG.Window.Link(), W.I.better)
        T.eq(f:IsShown(), true, "the toast stays until its time is up")
        f.__scripts.OnClick(f, "RightButton")
        T.eq(f:IsShown(), false) T.eq(#shown(W), 0)
    end)

    T.test("toast: dragging moves the place of the toasts; it is remembered, and reset puts it back", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f, anchor = shown(W)[1], W.env.EasyGearToastAnchor
        f.__scripts.OnDragStart(f)
        T.eq(anchor.__moving, true, "the place moves, the toasts hang on it")
        anchor:ClearAllPoints() anchor:SetPoint("BOTTOMRIGHT", W.env.UIParent, "BOTTOMRIGHT", -300, 200)
        f.__scripts.OnDragStop(f)
        T.eq(anchor.__moving, false)
        local saved = W.env.EasyGearCharDB.toast
        T.eq(saved.point, "BOTTOMRIGHT") T.eq(saved.x, -300) T.eq(saved.y, 200)

        W.clearChat() W.slash("toast reset")
        T.eq(W.env.EasyGearCharDB.toast, nil) T.eq(anchor:GetPoint(1), "TOP") T.eq(select(5, anchor:GetPoint(1)), -170)
        T.has(W.chatText(), "original place")

        -- a saved place is used at the next login
        local V = world(function(w) w.env.EasyGearCharDB = { toast = { point = "LEFT", x = 40, y = -20 } } end)
        loot(V, 1, V.I.better)
        local p, _, _, x, y = V.env.EasyGearToastAnchor:GetPoint(1)
        T.eq(p, "LEFT") T.eq(x, 40) T.eq(y, -20)
        V.slash("reset")
        T.eq(V.env.EasyGearToastAnchor:GetPoint(1), "TOP", "/eg reset puts it back as well")
    end)

    ------------------------------------------------------------------ settings and commands
    T.test("toast: switched off nothing is announced and what stands goes; /eg toast shows the state", function()
        local W = world()
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 1)
        W.clearChat() W.slash("toast off")
        T.eq(W.EG:Get("showToast"), false) T.eq(#shown(W), 0, "closed at once")
        T.has(W.chatText(), "Announce a better item when you get it: disabled") T.has(W.chatText(), "(15 seconds)")
        loot(W, 2, W.I.ring)
        T.eq(#shown(W), 0)
        W.slash("toast on")
        loot(W, 3, W.I.helm)
        T.eq(#shown(W), 1)
        W.clearChat() W.slash("toast")
        T.has(W.chatText(), "enabled", "without a word it only reports")
        T.eq(W.EG:Get("showToast"), true)
        W.clearChat() W.slash("help")
        T.has(W.chatText(), "/eg toast [on|off|test|reset|<3-60>]")
    end)

    T.test("toast: /eg toast test shows the best upgrade in the bags, or an example with something you wear", function()
        local W = world()
        W.slash("toast test")
        T.eq(#shown(W), 1)
        local f = shown(W)[1]
        T.eq(f.caption:GetText(), W.EG.L.TOAST_SAMPLE) T.eq(f.detail:GetText(), W.EG.L.TOAST_SAMPLE_TEXT)
        T.eq(f.name:GetText(), "Worn Chestplate", "the first thing worn stands in")
        f.__scripts.OnClick(f, "RightButton")

        W.EG:Set("showToast", false)                     -- an example also shows while announcements are off
        loot(W, 1, W.I.better)
        W.slash("toast test")
        T.eq(#shown(W), 1) T.eq(shown(W)[1].name:GetText(), "Better Chestplate")
        T.eq(shown(W)[1].caption:GetText(), W.EG.L.TOAST_TITLE)

        local V = T.world(F.arms(), function(w) w.bag(0, 16, {}) end)     -- nothing worn, nothing in the bags
        V.clearChat() V.slash("toast test")
        T.eq(#V.EG.Toast.shown, 0) T.has(V.chatText(), "nothing to show an example with")
    end)

    T.test("toast: the card takes the shape and the color of the upgrade marker chosen in the options", function()
        local W = world()
        W.slash("marker upgrade star ff8800")
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        T.eq(f.mark:GetAtlas(), "tradeskills-star")
        T.eq(f.bar.__color[1], 1) T.near(f.bar.__color[2], 0x88 / 255) T.eq(f.bar.__color[3], 0)
        T.eq(f.caption.__textColor[1], 1) T.near(f.caption.__textColor[2], 0x88 / 255)
        T.near(f.timer.__color[2], 0x88 / 255, 1e-9, "the running line too")
    end)

    T.test("toast: a failure while judging new loot is caught and reported once", function()
        local W = world()
        W.EG.Score.UpgradeState = function() error("boom") end
        loot(W, 1, W.I.better)
        T.eq(#shown(W), 0)
        T.ok(W.EG.lastError and tostring(W.EG.lastError.err):find("boom", 1, true))
    end)

    ------------------------------------------------------------------ random walk
    T.test("toast: random loot, time, clicks and switches keep the invariants", function()
        local seed = (tonumber(os.getenv("FUZZ_SEED")) or 4711) % 2147483646 + 1
        local function rnd(n) seed = (seed * 16807) % 2147483647 return seed % n + 1 end
        local W = world(function(w)
            w.I.pool = {}
            for i = 1, 8 do
                w.I.pool[i] = F.gear(w, 9200 + i, "Piece" .. i, ({ "INVTYPE_CHEST", "INVTYPE_HEAD", "INVTYPE_LEGS", "INVTYPE_FINGER" })[rnd(4)],
                    rnd(80), { STR = rnd(60), STA = rnd(40) }, { typeText = "" })
            end
        end)
        for step = 1, 120 do
            local action = rnd(9)
            if action <= 3 then
                loot(W, rnd(12), W.I.pool[rnd(8)])
            elseif action == 4 then
                loot(W, rnd(12), nil)
            elseif action == 5 then
                W.tick(rnd(8))
            elseif action == 6 and shown(W)[1] then
                local f = shown(W)[rnd(#shown(W))]
                f.__scripts.OnClick(f, rnd(2) == 1 and "RightButton" or "LeftButton")
            elseif action == 7 and shown(W)[1] then
                local f = shown(W)[rnd(#shown(W))]
                if rnd(2) == 1 then f.__scripts.OnEnter(f) else f.__scripts.OnLeave(f) end
            elseif action == 8 then
                W.EG:Set("showToast", rnd(4) ~= 1)
            else
                W.advance(rnd(30))
            end
            T.ok(#shown(W) <= 3, "at most three, step " .. step)
            T.ok(#W.EG.Toast.queue <= 8, "a bounded queue, step " .. step)
            if W.EG:Get("showToast") == false then T.eq(#shown(W), 0, "none while switched off, step " .. step) end
            for i, f in ipairs(shown(W)) do
                T.eq(f:IsShown(), true, "step " .. step) T.ok(f.data and f.data.link, "a shown toast has its item, step " .. step)
                T.eq(select(5, f:GetPoint(1)), -(i - 1) * 70, "stacked without gaps, step " .. step)
                T.ok(f.__alpha >= 0 and f.__alpha <= 1, "alpha, step " .. step)
            end
            if #shown(W) < 3 then T.eq(#W.EG.Toast.queue, 0, "nobody waits while there is room, step " .. step) end
            T.eq(W.EG.lastError, nil, "no internal error, step " .. step .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
        end
    end)
end
