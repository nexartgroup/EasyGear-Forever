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
    -- Shift + right-click closes a card (a plain right-click equips its item)
    local function close(W, f)
        W.state.shift = true
        f.__scripts.OnClick(f, "RightButton")
        W.state.shift = false
    end

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
        local qr, qg, qb = W.env.C_Item.GetItemQualityColor(3)
        T.eq(f.name.__textColor[1], qr) T.eq(f.name.__textColor[2], qg) T.eq(f.name.__textColor[3], qb, "the name in the color of its quality")
        T.eq(f.icon.ring.__color[1], qr, "and the ring around the icon")
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
        W.tick(6.5)
        T.eq(f.__alpha, 1, "fourteen seconds: still fully visible")
        W.tick(0.7)
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
        T.eq(W.env.EasyGearToastAnchor, nil, "no card was even made for them")
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

    T.test("toast: a second piece of something worn is new - the same ring again, for the other finger", function()
        local W = world()
        W.equip(11, W.I.ring) W.fire("PLAYER_EQUIPMENT_CHANGED", 11) W.flush()
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(W.EG.Score.UpgradeState(W.I.ring), "UPGRADE", "a second one beats what is on the other finger")
        loot(W, 1, W.I.ring)
        T.eq(#shown(W), 1, "worn once, looted once more: announced")
        T.has(shown(W)[1].detail:GetText(), "Finger 2")
        -- taking one of two off is still no gain: both are worn, one goes to the bags
        local V = world()
        V.equip(11, V.I.ring) V.equip(12, V.I.ring) V.fire("PLAYER_EQUIPMENT_CHANGED", 11) V.flush()
        V.fire("BAG_UPDATE_DELAYED")
        V.equip(12, nil) V.fire("PLAYER_EQUIPMENT_CHANGED", 12)
        loot(V, 1, V.I.ring)
        T.eq(#shown(V), 0, "one of the two rings was taken off")
        -- taken off AND one more looted in the same moment: one of the two in the bags is new
        local U = world()
        U.equip(11, U.I.ring) U.fire("PLAYER_EQUIPMENT_CHANGED", 11) U.flush()
        U.fire("BAG_UPDATE_DELAYED")
        U.equip(11, nil) U.fire("PLAYER_EQUIPMENT_CHANGED", 11)
        U.put(0, 1, U.I.ring) U.put(0, 2, U.I.ring)
        U.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(U), 1, "two arrive, one was worn before: one is new")
        for _, w in ipairs({ W, V, U }) do T.eq(w.EG.lastError, nil) end
    end)

    T.test("toast: what is worn is known by its item, not its link - a link that changed on the body (a level-up) does not make it new when taken off", function()
        local W = world()
        local leveled = W.I.chest:gsub("item:(%d+)", "item:%1:0:0:0:0:0:0:0:61")
        T.ok(leveled ~= W.I.chest)
        W.equip(5, leveled)                              -- the client rewrites the link of worn gear; no event tells of it
        W.equip(5, nil) W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        loot(W, 1, leveled)
        T.eq(W.EG.Score.UpgradeState(leveled), "UPGRADE", "it beats the empty slot")
        T.eq(#shown(W), 0, "the chest piece that was worn all along")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: gear put on without passing through the bags (from the bank, from a vendor) is not new when it is taken off", function()
        local W = world()
        W.equip(5, W.I.better) W.fire("PLAYER_EQUIPMENT_CHANGED", 5) W.flush()     -- no look into the bags in between
        W.equip(5, nil) W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        loot(W, 1, W.I.better)
        T.eq(W.EG.Score.UpgradeState(W.I.better), "UPGRADE")
        T.eq(#shown(W), 0, "it was worn a moment ago")
        W.advance(120)
        loot(W, 2, W.I.better)
        T.eq(#shown(W), 1, "a second one that drops later is new: the worn one is long counted")
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
        W.advance(120)
        W.put(0, 4, W.I.better)                          -- and a third one with the plain link: only that one is new
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 2, "one more toast, not one for every copy that lies there")
        T.eq(shown(W)[2].data.link, W.I.better)
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
        close(W, f)
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
        close(W, first)
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

    T.test("toast: no more than eight wait - with more, the oldest waiting ones are dropped", function()
        local W = world(function(w)
            w.I.many = {}
            for i = 1, 13 do
                w.I.many[i] = F.gear(w, 9700 + i, "Chest" .. i, "INVTYPE_CHEST", 40 + i, { STR = 30 + i, STA = 40 }, { armor = 500 })
            end
        end)
        for i = 1, 13 do W.put(0, i, W.I.many[i]) end
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 3) T.eq(#W.EG.Toast.queue, 8, "thirteen at once: three shown, eight wait, two dropped")
        W.EG:Set("showToast", false)
        T.eq(#shown(W), 0) T.eq(#W.EG.Toast.queue, 0, "switched off: nobody shown, nobody waiting")
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
        T.ok(f.__alpha < 1, "fading out")
        f.__scripts.OnEnter(f)                          -- caught while it fades: fully visible again while the mouse is on it
        W.tick(0.1)
        T.eq(f.__alpha, 1)
        f.__scripts.OnLeave(f)
        W.tick(0.4)
        T.eq(f:IsShown(), false)
    end)

    T.test("toast: a click opens the comparison with the item, Shift + right-click closes the toast", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        f.__scripts.OnClick(f, "LeftButton")
        T.eq(W.EG.Window.IsShown(), true) T.eq(W.EG.Window.Link(), W.I.better)
        T.eq(f:IsShown(), true, "the toast stays until its time is up")
        T.eq(#W.state.equipRequests, 0, "a left click equips nothing")
        close(W, f)
        T.eq(f:IsShown(), false) T.eq(#shown(W), 0)
        T.eq(#W.state.equipRequests, 0, "closing equips nothing") T.eq(W.state.cursor, nil)
        T.eq(W.state.bags[0].items[1], W.I.better, "the item lies where it lay")
        T.eq(W.env.EasyGearCharDB.toast, nil, "closing a toast that was not dragged saves no place")
        T.eq(W.env.EasyGearToastAnchor.__moving, nil, "and touches no movement")
    end)

    ------------------------------------------------------------------ equipping
    T.test("toast: a right-click equips the item - picked up from its bag slot and put into the slot the comparison names; the card goes when it is worn", function()
        local W = world()
        loot(W, 3, W.I.better)
        local f = shown(W)[1]
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 1)
        local r = W.state.equipRequests[1]
        T.eq(r.link, W.I.better) T.eq(r.slot, 5, "the chest slot") T.eq(r.bag, 0) T.eq(r.bagSlot, 3, "taken from where it lies")
        T.eq(W.state.cursor, nil, "nothing is left on the cursor")
        T.eq(W.chatText(), "", "nothing to say")
        T.eq(f:IsShown(), true, "the card stays until the item is really worn")
        W.serverAnswers(true)
        T.eq(W.state.equipped[5], W.I.better) T.eq(W.state.bags[0].items[3], W.I.chest, "the old chest piece lies in its place")
        T.eq(#shown(W), 0, "worn: the card is gone - and the piece that was taken off is no news")
        T.eq(W.EG.lastError, nil)

        -- a ring goes to the finger the comparison names (the weaker of the two rings), not to the first ring slot
        local V = world()
        loot(V, 1, V.I.ring)
        local g = shown(V)[1]
        T.has(g.detail:GetText(), "Finger 2")
        g.__scripts.OnClick(g, "RightButton")
        T.eq(V.state.equipRequests[1].slot, 12)
        V.serverAnswers(true)
        T.eq(V.state.equipped[12], V.I.ring) T.eq(V.state.equipped[11], V.I.ring1, "the other ring stays")
        T.eq(#shown(V), 0)

        -- two copies with different links: the one the card is about is taken
        local U = world()
        local enchanted = U.I.better:gsub("item:(%d+)", "item:%1:1234")
        U.put(0, 1, enchanted) U.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(U), 1)
        close(U, shown(U)[1])
        U.advance(120)
        loot(U, 2, U.I.better)
        local h = shown(U)[1]
        T.eq(h.data.link, U.I.better)
        h.__scripts.OnClick(h, "RightButton")
        T.eq(U.state.equipRequests[1].bagSlot, 2, "the plain one in the second slot, not the enchanted one before it")

        -- something else on the cursor is let go first, as the game's equipment manager does
        local C = world()
        loot(C, 1, C.I.better)
        C.state.cursor = { id = 9105, link = C.I.ring }
        local c = shown(C)[1]
        c.__scripts.OnClick(c, "RightButton")
        T.eq(C.state.equipRequests[1].link, C.I.better) T.eq(C.state.cursor, nil)
        T.eq(#C.state.dropped, 0, "what was held is not dropped into the bags in exchange")
    end)

    T.test("toast: equipping only when it is possible - not in combat, not dead; the chat says why and the card stays", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        W.state.lockdown = true
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 0, "nothing was asked of the server") T.eq(W.state.cursor, nil, "nothing was picked up")
        T.has(W.chatText(), "Not possible in combat") T.has(W.chatText(), "Better Chestplate")
        T.eq(f:IsShown(), true, "the card waits for the end of the fight")
        W.state.lockdown = false
        W.state.dead = true
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 0) T.eq(W.state.cursor, nil)
        T.has(W.chatText(), "Not possible while dead") T.eq(f:IsShown(), true)
        W.state.dead = false
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 1, "now it works") T.eq(W.chatText(), "")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: an item that cannot be taken or cannot go to its slot stays where it is - the chat says so", function()
        -- the item is being moved (locked): nothing to pick up
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        local function click()
            W.advance(2)                                 -- well apart: not a double click
            W.clearChat()
            f.__scripts.OnClick(f, "RightButton")
        end
        local tried = 0                                  -- how often the item was dropped on an equipment slot
        local drop = W.env.PickupInventoryItem
        W.env.PickupInventoryItem = function(...) tried = tried + 1 return drop(...) end
        W.state.bags[0].locked = { [1] = true }
        click()
        T.eq(#W.state.equipRequests, 0) T.has(W.chatText(), "cannot be equipped right now") T.eq(f:IsShown(), true)
        W.state.bags[0].locked = nil

        -- the slot is busy (another swap is under way): the item goes back from the cursor
        W.state.lockedSlots[5] = true
        click()
        T.eq(#W.state.equipRequests, 0) T.eq(W.state.cursor, nil, "back in its bag slot")
        T.has(W.chatText(), "cannot be equipped right now") T.eq(f:IsShown(), true)
        T.eq(tried, 0, "not even tried")
        W.state.lockedSlots[5] = nil

        -- the game does not let it into that slot: asked first, not tried (the game would complain aloud)
        local can = W.env.C_PaperDollInfo.CursorCanGoInSlot
        W.env.C_PaperDollInfo.CursorCanGoInSlot = function() return false end
        click()
        T.eq(#W.state.equipRequests, 0) T.eq(W.state.cursor, nil) T.has(W.chatText(), "cannot be equipped right now")
        T.eq(tried, 0, "not even tried")

        -- nothing was picked up (locked) and the game would not even say no to the slot: still nothing is tried
        W.env.C_PaperDollInfo.CursorCanGoInSlot = function() return true end
        W.state.bags[0].locked = { [1] = true }
        click()
        T.eq(tried, 0, "no dropping on the slot with an empty cursor") T.has(W.chatText(), "cannot be equipped right now")
        W.state.bags[0].locked = nil
        W.env.C_PaperDollInfo.CursorCanGoInSlot = can

        -- the game says the slot fits and then does not take the item: it is not left hanging on the cursor
        W.state.clientRefuses = true
        click()
        T.eq(tried, 1) T.eq(#W.state.equipRequests, 0) T.eq(W.state.cursor, nil, "back in its bag slot")
        T.has(W.chatText(), "cannot be equipped right now") T.eq(f:IsShown(), true)
        W.state.clientRefuses = nil

        -- the server says no (the game shows its own message): nothing changed, the card is still there
        click()
        T.eq(#W.state.equipRequests, 1, "and when the game lets it, it goes") T.eq(W.chatText(), "")
        W.serverAnswers(false)
        T.eq(W.state.equipped[5], W.I.chest) T.eq(W.state.bags[0].items[1], W.I.better)
        T.eq(f:IsShown(), true, "not worn: still a better item waiting")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: a spell that waits for its target or the repair cursor - the right-click does not hand the item to them", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        W.state.spellTargeting = true                    -- Disenchant is waiting for an item
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(W.state.spellCastOn, nil, "the item was not touched") T.eq(#W.state.equipRequests, 0)
        T.has(W.chatText(), "cannot be equipped right now") T.eq(f:IsShown(), true)
        W.state.spellTargeting = false
        W.state.repairMode = true                        -- the merchant's repair cursor
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(W.state.repaired, nil) T.eq(#W.state.equipRequests, 0) T.has(W.chatText(), "cannot be equipped right now")
        W.state.repairMode = false
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 1)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: an item that binds when equipped - the game asks, EasyGear leaves the cursor alone until the answer", function()
        -- the game has three such questions (binds, binds and stays tradeable for a while, ends a refund)
        for _, kind in ipairs({ true, "tradeable", "refundable" }) do
            local W = world(function(w)
                w.I.bound = F.gear(w, 9121, "Binding Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, boe = kind })
            end)
            loot(W, 1, W.I.bound)
            local f = shown(W)[1]
            W.clearChat()
            f.__scripts.OnClick(f, "RightButton")
            T.ok(W.state.pendingBind, "the game asks whether it may bind the item (" .. tostring(kind) .. ")")
            T.ok(W.state.cursor, "and holds it on the cursor meanwhile - letting go would take the question back")
            T.eq(#W.state.equipRequests, 0) T.eq(W.chatText(), "", "nothing failed") T.eq(f:IsShown(), true)
            W.bindAnswer(true)
            T.eq(#W.state.equipRequests, 1)
            W.serverAnswers(true)
            T.eq(W.state.equipped[5], W.I.bound) T.eq(#shown(W), 0)
            T.eq(W.EG.lastError, nil)
        end

        -- the player says no: nothing is equipped, the card is still there, and a later right-click asks again
        local V = world(function(w)
            w.I.bound = F.gear(w, 9121, "Binding Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, boe = true })
        end)
        loot(V, 1, V.I.bound)
        local g = shown(V)[1]
        g.__scripts.OnClick(g, "RightButton")
        V.bindAnswer(false)
        T.eq(#V.state.equipRequests, 0) T.eq(V.state.equipped[5], V.I.chest) T.eq(g:IsShown(), true)
        V.advance(2)
        g.__scripts.OnClick(g, "RightButton")
        T.ok(V.state.pendingBind, "asked again")
        V.bindAnswer(false)
        -- a question once asked says nothing about the next attempt: an item the game does not take goes back
        V.state.clientRefuses = true
        V.advance(2)
        V.clearChat()
        g.__scripts.OnClick(g, "RightButton")
        T.eq(V.state.cursor, nil, "not left on the cursor because of the question before")
        T.has(V.chatText(), "cannot be equipped right now")
        T.eq(V.EG.lastError, nil)
    end)

    T.test("toast: a double click equips one item - the card that moves up under the mouse is not hit by the second click", function()
        local W = world()
        W.put(0, 1, W.I.better) W.put(0, 2, W.I.helm)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 2)
        local first = shown(W)[1]
        local firstLink = first.data.link
        first.__scripts.OnClick(first, "RightButton")
        T.eq(#W.state.equipRequests, 1)
        W.clearChat()
        first.__scripts.OnClick(first, "RightButton")    -- the second click of a double click, before the server answered
        T.eq(#W.state.equipRequests, 1, "nothing more") T.eq(W.chatText(), "", "and no complaint")
        W.serverAnswers(true)
        T.eq(#shown(W), 1, "the first card went, the other one took its place")
        local second = shown(W)[1]
        T.ok(second.data.link ~= firstLink)
        second.__scripts.OnClick(second, "RightButton")  -- ... or right after it
        T.eq(#W.state.equipRequests, 0, "the card that moved up is not equipped by accident")
        T.eq(second:IsShown(), true)
        W.advance(1.1)
        second.__scripts.OnClick(second, "RightButton")
        T.eq(#W.state.equipRequests, 1, "a second later a click means this card")
        T.eq(W.state.equipRequests[1].link, second.data.link)
        -- a refused attempt does not start the wait: the next click may try again at once
        local V = world()
        loot(V, 1, V.I.better)
        local g = shown(V)[1]
        V.state.lockdown = true
        g.__scripts.OnClick(g, "RightButton")
        V.state.lockdown = false
        g.__scripts.OnClick(g, "RightButton")
        T.eq(#V.state.equipRequests, 1)
    end)

    T.test("toast: the item is known by what it is, not by its link - a level-up rewrites the links in the bags and the card stays", function()
        local W = world()
        loot(W, 2, W.I.better)
        local f = shown(W)[1]
        local leveled = W.I.better:gsub("(item:%d+::::::::)60", "%161")
        T.ok(leveled ~= W.I.better, "the link carries the level of the character")
        T.eq(W.EG.Items.Key(leveled), W.EG.Items.Key(W.I.better), "the same piece")
        local enchanted = W.I.better:gsub("item:(%d+):", "item:%1:1234")
        T.ok(W.EG.Items.Key(enchanted) ~= W.EG.Items.Key(W.I.better), "an enchanted one is another piece")
        T.eq(W.EG.Items.Key(nil), nil) T.eq(W.EG.Items.Key("no link"), "no link")
        local respecced = W.I.better:gsub("(item:%d+::::::::60:)", "%171")
        T.ok(respecced ~= W.I.better) T.eq(W.EG.Items.Key(respecced), W.EG.Items.Key(W.I.better), "nor does the specialization in the link matter")
        T.eq(W.EG.Items.Key(W.I.better), "item:9101:::::::::::::", "the level is left out, the fields stay in their places")
        T.eq(W.EG.Items.Key(enchanted), "item:9101:1234::::::::::::", "everything else of the item text is kept")
        -- the character gains a level: the same piece in the same slot has another link now; no event of the bags yet
        W.put(0, 2, leveled)
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 1, "found all the same")
        T.eq(W.state.equipRequests[1].bagSlot, 2) T.eq(W.state.equipRequests[1].link, leveled)
        W.serverAnswers(false)
        -- the bags are looked at: the card is kept and follows the new link (its tooltip, the comparison)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 1, "not thrown out for a link that changed") T.eq(f.data.link, leveled)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: the card always names the slot a right-click leads to - also after something else was put on", function()
        local W = world(function(w)
            w.I.fine = F.gear(w, 9131, "Fine Ring", "INVTYPE_FINGER", 45, { STR = 25, HIT = 15 }, { typeText = "" })
        end)
        W.put(0, 1, W.I.ring) W.put(0, 2, W.I.fine)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 2)
        local card = {}
        for _, f in ipairs(shown(W)) do card[f.data.link] = f end
        T.has(card[W.I.ring].detail:GetText(), "Finger 2: Plain Ring") T.has(card[W.I.fine].detail:GetText(), "Finger 2: Plain Ring")
        card[W.I.ring].__scripts.OnClick(card[W.I.ring], "RightButton")
        T.eq(W.state.equipRequests[1].slot, 12)
        W.serverAnswers(true)
        T.eq(#shown(W), 1)
        local left = shown(W)[1]
        T.eq(left.data.link, W.I.fine)
        T.has(left.detail:GetText(), "Finger 1: Copper Band", "the weaker ring is the other one now - the card says so")
        T.hasnt(left.detail:GetText(), "Plain Ring")
        W.advance(2)
        left.__scripts.OnClick(left, "RightButton")
        T.eq(W.state.equipRequests[1].slot, 11, "and that is where the click leads")
        -- a card that waited its turn says the right thing when it comes up
        local V = world(function(w)
            w.I.fine = F.gear(w, 9131, "Fine Ring", "INVTYPE_FINGER", 45, { STR = 25, HIT = 15 }, { typeText = "" })
        end)
        V.put(0, 1, V.I.better) V.put(0, 2, V.I.helm) V.put(0, 3, V.I.legs)
        V.fire("BAG_UPDATE_DELAYED")
        V.put(0, 4, V.I.ring) V.put(0, 5, V.I.fine)                         -- two rings more: they have to wait
        V.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(V), 3) T.eq(#V.EG.Toast.queue, 2)
        V.equip(12, V.I.ring) V.state.bags[0].items[4] = V.I.ring2          -- Good Ring is put on from the bags
        V.fire("PLAYER_EQUIPMENT_CHANGED", 12, false) V.fire("BAG_UPDATE_DELAYED")
        T.eq(#V.EG.Toast.queue, 1) T.eq(V.EG.Toast.queue[1].link, V.I.fine)
        T.has(V.EG.Toast.queue[1].detail, "Finger 1: Copper Band", "the waiting card was brought up to date")
        T.eq(V.EG.lastError, nil)
    end)

    T.test("toast: weapons go where they belong - a two-hander into the main hand, a bow into the ranged slot", function()
        local W = world(function(w)
            w.I.great = F.gear(w, 9141, "Greatsword", "INVTYPE_2HWEAPON", 40, {}, { dps = 45 })
            w.I.bow = F.gear(w, 9142, "Bow", "INVTYPE_RANGED", 40, { STR = 10 }, { dps = 12 })
        end)
        loot(W, 1, W.I.great)
        T.eq(#shown(W), 1)
        local f = shown(W)[1]
        f.__scripts.OnClick(f, "RightButton")
        T.eq(W.state.equipRequests[1].slot, 16)
        W.serverAnswers(true)
        T.eq(W.state.equipped[16], W.I.great) T.eq(W.state.bags[0].items[1], W.I.sword, "the old sword lies in the bag")
        T.eq(#shown(W), 0, "and is no news")
        W.advance(120)
        loot(W, 2, W.I.bow)
        T.eq(#shown(W), 1, "a bow for the empty ranged slot")
        local g = shown(W)[1]
        g.__scripts.OnClick(g, "RightButton")
        T.eq(#W.state.equipRequests, 1) T.eq(W.state.equipRequests[1].slot, 18)
        W.serverAnswers(true)
        T.eq(W.state.equipped[18], W.I.bow) T.eq(#shown(W), 0)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: a card whose item is gone or no upgrade any more is closed by the right-click, with a word why", function()
        local W = world()
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        W.put(0, 1, nil)                                 -- sold or destroyed a moment ago; the bags have not been looked at since
        W.clearChat()
        f.__scripts.OnClick(f, "RightButton")
        T.eq(#W.state.equipRequests, 0) T.has(W.chatText(), "is no longer in your bags") T.has(W.chatText(), "Better Chestplate")
        T.eq(#shown(W), 0, "nothing left to point at")

        local V = world(function(w)
            w.I.super = F.gear(w, 9111, "Super Chestplate", "INVTYPE_CHEST", 90, { STR = 200, STA = 100 }, { armor = 900 })
        end)
        loot(V, 1, V.I.better)
        V.equip(5, V.I.super)                            -- something better is worn by now
        V.EG:InvalidateResults()
        local ok, why, pointless = V.EG.Toast.Equip(V.I.better)
        T.eq(ok, false) T.has(why, "is no upgrade any more") T.eq(pointless, true)
        T.eq(#V.state.equipRequests, 0) T.eq(V.state.cursor, nil)
        local g = shown(V)[1]
        V.clearChat()
        g.__scripts.OnClick(g, "RightButton")
        T.has(V.chatText(), "is no upgrade any more") T.eq(#shown(V), 0)
        T.eq(V.EG.lastError, nil)
    end)

    T.test("toast: cards follow what is worn - equipped by any way, a card's item is no news; the example stays", function()
        local W = world(function(w)
            w.I.super = F.gear(w, 9112, "Super Chestplate", "INVTYPE_CHEST", 90, { STR = 200, STA = 100 }, { armor = 900 })
        end)
        W.put(0, 1, W.I.better) W.put(0, 2, W.I.ring) W.put(0, 3, W.I.helm) W.put(0, 4, W.I.legs) W.put(0, 5, W.I.boots)
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 3) T.eq(#W.EG.Toast.queue, 2)
        -- the player equips the helm from the bags (it stands as a card) and the boots (they wait)
        local standing, waiting = {}, {}
        for _, f in ipairs(shown(W)) do standing[f.data.link] = true end
        for _, d in ipairs(W.EG.Toast.queue) do waiting[d.link] = true end
        local worn, later
        for _, link in ipairs({ W.I.better, W.I.ring, W.I.helm, W.I.legs, W.I.boots }) do
            if standing[link] and not worn then worn = link end
            if waiting[link] and not later then later = link end
        end
        local slotOf = { [W.I.better] = 5, [W.I.ring] = 12, [W.I.helm] = 1, [W.I.legs] = 7, [W.I.boots] = 8 }
        -- the player right-clicks it in the bags: the game swaps it with what is worn and tells of both
        local function wear(link)
            local items = W.state.bags[0].items
            for i = 1, 16 do
                if items[i] == link then items[i] = W.state.equipped[slotOf[link]] end
            end
            W.equip(slotOf[link], link)
            W.fire("PLAYER_EQUIPMENT_CHANGED", slotOf[link], false)
            W.fire("BAG_UPDATE_DELAYED")
        end
        wear(later)
        T.eq(#shown(W), 3) T.eq(#W.EG.Toast.queue, 1, "the waiting one that is worn now will not come")
        wear(worn)
        T.eq(#shown(W), 3, "its card went, the last waiting one took the place") T.eq(#W.EG.Toast.queue, 0)
        for _, f in ipairs(shown(W)) do
            T.ok(f.data.link ~= worn and f.data.link ~= later, "no card for what is worn")
        end
        -- one that is sold (it leaves the bags): its card goes as well
        local sold = shown(W)[1].data.link
        for i = 1, 16 do
            if W.state.bags[0].items[i] == sold then W.state.bags[0].items[i] = nil end
        end
        W.fire("BAG_UPDATE_DELAYED")
        T.eq(#shown(W), 2, "nothing left to point at")
        -- something better than a standing card's item is put on from elsewhere: no upgrade any more
        local V2 = world(function(w)
            w.I.super = F.gear(w, 9113, "Super Chestplate", "INVTYPE_CHEST", 90, { STR = 200, STA = 100 }, { armor = 900 })
        end)
        loot(V2, 1, V2.I.better)
        T.eq(#shown(V2), 1)
        V2.equip(5, V2.I.super) V2.fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
        T.eq(#shown(V2), 0, "at once, with the change of equipment")
        T.eq(V2.state.bags[0].items[1], V2.I.better, "although it still lies in the bags")
        T.eq(W.EG.lastError, nil)

        -- the example of /eg toast test shows something worn: it is no upgrade and stays all the same
        local V = world()
        V.slash("toast test")
        local sample = shown(V)[1]
        T.eq(sample.caption:GetText(), V.EG.L.TOAST_SAMPLE)
        V.equip(12, nil) V.fire("PLAYER_EQUIPMENT_CHANGED", 12, true) V.flush()
        T.eq(sample:IsShown(), true, "the example stays")
        T.eq(sample.detail:GetText(), V.EG.L.TOAST_SAMPLE_TEXT, "with its own words")
        V.clearChat()
        sample.__scripts.OnClick(sample, "RightButton")
        T.eq(#V.state.equipRequests, 0, "nothing to equip") T.eq(#shown(V), 0, "a right-click just closes the example")
        T.eq(V.chatText(), "", "without a word")

        -- a change that only the settings or the profile bring (no event of the game): the cards follow as well
        local S = world(function(w)
            w.I.super = F.gear(w, 9114, "Super Chestplate", "INVTYPE_CHEST", 90, { STR = 200, STA = 100 }, { armor = 900 })
        end)
        loot(S, 1, S.I.better)
        S.equip(5, S.I.super)
        S.EG:InvalidateAll()
        T.eq(#shown(S), 0, "no upgrade any more by the new state of things")

        -- before the bags were ever looked at, a card (of /eg toast test) is not thrown out for lack of knowledge
        local N = T.world(F.arms(), function(w)
            w.I = F.armsWarrior(w)
            w.I.better = F.gear(w, 9101, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35 })
            w.bag(0, 16, { w.I.better })
        end)
        N.slash("toast test")
        T.eq(#N.EG.Toast.shown, 1) T.eq(N.EG.Toast.shown[1].name:GetText(), "Better Chestplate")
        N.EG:InvalidateAll()
        T.eq(#N.EG.Toast.shown, 1, "still there") T.eq(N.EG.lastError, nil)

        -- the data of what is worn is away for a moment (the client dropped it): no verdict, so the card is kept
        local U = world()
        loot(U, 1, U.I.better)
        U.state.items[2001].uncached = true              -- the worn chest piece
        U.EG.Items.Wipe()
        U.EG:InvalidateAll() U.flush()
        T.eq(select(2, U.EG.Score.UpgradeState(U.I.better)), true, "the comparison waits for data")
        T.eq(#shown(U), 1, "not thrown out while nobody can tell")
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
        T.eq(saved.rel, "BOTTOMRIGHT", "the point of the screen it is measured from")

        W.clearChat() W.slash("toast reset")
        T.eq(W.env.EasyGearCharDB.toast, nil) T.eq(anchor:GetPoint(1), "TOP") T.eq(select(5, anchor:GetPoint(1)), -170)
        T.has(W.chatText(), "original place")

        -- a saved place is used at the next login
        local V = world(function(w) w.env.EasyGearCharDB = { toast = { point = "LEFT", x = 40, y = -20 } } end)
        loot(V, 1, V.I.better)
        local p, _, rp, x, y = V.env.EasyGearToastAnchor:GetPoint(1)
        T.eq(p, "LEFT") T.eq(rp, "LEFT") T.eq(x, 40) T.eq(y, -20)
        V.slash("reset")
        T.eq(V.env.EasyGearToastAnchor:GetPoint(1), "TOP", "/eg reset puts it back as well")
        -- the client may measure a moved frame from another point of the screen than the frame's own
        local U = world(function(w) w.env.EasyGearCharDB = { toast = { point = "TOP", rel = "CENTER", x = 12, y = 90 } } end)
        loot(U, 1, U.I.better)
        local up, _, urel, ux, uy = U.env.EasyGearToastAnchor:GetPoint(1)
        T.eq(up, "TOP") T.eq(urel, "CENTER") T.eq(ux, 12) T.eq(uy, 90)
    end)

    T.test("toast: while it is dragged the time stands; a toast that goes while dragged lets go of the place and remembers it", function()
        local W = world()
        loot(W, 1, W.I.better)
        loot(W, 2, W.I.ring)
        local f, anchor = shown(W)[1], W.env.EasyGearToastAnchor
        W.tick(0.1)                                      -- grabbed while it still fades in
        f.__scripts.OnDragStart(f)
        f.__scripts.OnLeave(f)                           -- a fast pull: the mouse is ahead of the toast
        W.tick(30)
        T.eq(f:IsShown(), true, "held while dragged") T.eq(f.__alpha, 1, "and fully visible, wherever its fading was")
        T.eq(#shown(W), 1, "the other one ran out meanwhile")
        anchor:ClearAllPoints() anchor:SetPoint("LEFT", W.env.UIParent, "LEFT", 55, 66)
        close(W, f)                                      -- closed in mid-drag: the client sends no OnDragStop for a hidden frame
        T.eq(f:IsShown(), false)
        T.eq(anchor.__moving, false, "the place no longer follows the mouse")
        T.eq(W.env.EasyGearCharDB.toast.point, "LEFT") T.eq(W.env.EasyGearCharDB.toast.x, 55, "and is remembered where it was dropped")
        -- the frame is used again: it does not think it is still dragged
        W.advance(120)
        loot(W, 3, W.I.better)
        local again = shown(W)[1]
        T.eq(again, f, "the same frame from the pool") T.eq(again.dragging, false)
        W.tick(16)
        T.eq(#shown(W), 0, "its time runs again")
        -- switched off in mid-drag: the same
        loot(W, 4, W.I.helm)
        local g = shown(W)[1]
        g.__scripts.OnDragStart(g)
        T.eq(anchor.__moving, true)
        W.slash("toast off") W.flush()
        T.eq(#shown(W), 0) T.eq(anchor.__moving, false)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("toast: a card comes to the front when it appears - above EasyGear's windows, even a clicked one; never into the strata of the game's dialogs", function()
        local W = world()
        W.EG.Window.SetItem(W.I.weak)
        local win = W.env.EasyGearWindow
        T.eq(win:GetFrameStrata(), "HIGH")
        T.eq(win:IsToplevel(), true, "a click brings a window to the front - whole, not in parts")
        local function top(f)
            local level = f:GetFrameLevel()
            for _, child in ipairs({ f:GetChildren() }) do level = math.max(level, top(child)) end
            return level
        end
        win:Raise()                                      -- the user clicks the window: the client raises it above all in HIGH
        loot(W, 1, W.I.better)
        local f = shown(W)[1]
        T.eq(f:GetFrameStrata(), "HIGH", "never over a dialog of the game (those are DIALOG)")
        T.ok(f:GetFrameLevel() > top(win), "the card is in front of the window and all its parts")
        T.ok(f.icon:GetFrameLevel() > f:GetFrameLevel(), "its own parts with it")
        win:Raise()                                      -- clicked again: the window covers the card ...
        T.ok(win:GetFrameLevel() > top(f))
        loot(W, 2, W.I.ring)
        local g = shown(W)[2]
        T.ok(g:GetFrameLevel() > top(win), "... and the next card is in front again")
        W.EG.ProfileWindow.Open()
        T.eq(W.env.EasyGearProfileWindow:IsToplevel(), true)
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
        close(W, f)

        W.EG:Set("showToast", false)                     -- an example also shows while announcements are off
        loot(W, 1, W.I.better)
        W.slash("toast test")
        T.eq(#shown(W), 1) T.eq(shown(W)[1].name:GetText(), "Better Chestplate")
        T.eq(shown(W)[1].caption:GetText(), W.EG.L.TOAST_TITLE)
        -- it looks like the real thing but is an example: a right-click closes it and equips nothing
        local example = shown(W)[1]
        example.__scripts.OnEnter(example)
        T.eq(W.env.GameTooltip:HasLine(W.EG.L.TOAST_HINT_SAMPLE), true, "the tooltip says so")
        T.eq(W.env.GameTooltip:HasLine(W.EG.L.TOAST_HINT), false)
        example.__scripts.OnLeave(example)
        example.__scripts.OnClick(example, "RightButton")
        T.eq(#W.state.equipRequests, 0) T.eq(W.state.cursor, nil) T.eq(#shown(W), 0)

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
                local kind = rnd(4)
                if kind == 1 then
                    close(W, f)
                elseif kind == 2 then
                    W.state.lockdown = rnd(4) == 1
                    f.__scripts.OnClick(f, "RightButton")        -- equip: the server answers at once, yes or no
                    W.state.lockdown = false
                    if W.state.equipRequests[1] then W.serverAnswers(rnd(3) ~= 1) end
                    T.eq(W.state.cursor, nil, "nothing left on the cursor, step " .. step)
                else
                    f.__scripts.OnClick(f, "LeftButton")
                end
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
            T.eq(#W.state.equipRequests, 0, "no request left open, step " .. step)
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
