-- Random gear, profiles and levels: nothing may raise, and the invariants of the comparison must hold
return function(T)
    local F = require("fixtures")

    -- small deterministic generator (the tests must be repeatable). Park-Miller: the products stay below 2^53, so
    -- the arithmetic is exact (a 31-bit LCG with a 2^30 multiplier is not, and its low bits degenerate).
    local seed = (tonumber(os.getenv("FUZZ_SEED")) or 12345) % 2147483646 + 1
    local RUNS = tonumber(os.getenv("FUZZ_RUNS")) or 12
    local function rnd(n)
        seed = (seed * 16807) % 2147483647
        return seed % n + 1
    end
    local function pick(list) return list[rnd(#list)] end

    local LOCS = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
                   "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET",
                   "INVTYPE_CLOAK", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
                   "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_BODY",
                   "INVTYPE_TABARD" }
    local SLOT_OF = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
                      INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
                      INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
                      INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17,
                      INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 18 }
    local STATS = { "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "CRIT", "HIT", "HASTE", "EXP", "ARP", "DEF", "DODGE", "PARRY", "MP5" }
    local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

    local nextId = 100000
    local function randomItem(W)
        nextId = nextId + 1
        local loc = pick(LOCS)
        local stats = {}
        for _ = 1, rnd(5) do stats[pick(STATS)] = rnd(60) end
        local extra = { armor = (rnd(3) == 1) and rnd(800) or nil, sockets = (rnd(4) == 1) and rnd(2) or nil,
                        minLevel = (rnd(3) == 1) and rnd(70) or 0, unique = (rnd(10) == 1) and true or nil,
                        badType = (rnd(8) == 1) and true or nil, sellPrice = rnd(5000) }
        if loc:find("WEAPON") or loc == "INVTYPE_RANGED" then extra.dps = rnd(400) / 10 end
        return F.gear(W, nextId, "Item" .. nextId, loc, rnd(120), stats, extra), loc
    end

    T.test("fuzz: random characters and gear never raise and keep the invariants", function()
        local checked = 0
        for run = 1, RUNS do
            local class = pick(CLASSES)
            local level = pick({ 10, 30, 59, 60 })
            local pts = { rnd(41) - 1, rnd(41) - 1, rnd(41) - 1 }
            local W = T.world({ class = class, level = level, talents = { mode = "specinfo", points = pts } }, function(w)
                -- random worn set
                for slot = 1, 18 do
                    if rnd(3) > 1 then
                        local link, loc = randomItem(w)
                        local fits = SLOT_OF[loc]
                        if fits then w.equip(fits == 11 and (rnd(2) == 1 and 11 or 12) or fits, link) end
                    end
                end
            end)
            for _, spec in ipairs(W.EG.Profiles.List(class)) do
                if rnd(3) == 1 then W.EG.Profiles.SetActive(spec.id) end
                for _ = 1, 12 do
                    local link = randomItem(W)
                    local ok, r = pcall(W.EG.Score.Compare, link, true)
                    T.ok(ok, "Compare raised: " .. tostring(r))
                    if r then
                        checked = checked + 1
                        T.ok(r.score == r.score and r.score > -1e9 and r.score < 1e9, "finite score")
                        if not r.noCompare then
                            T.near(r.delta, r.score - r.targetScore, 1e-9, "delta = score - worn score")
                            if r.isUpgrade then
                                T.ok(r.usable and not r.levelTooLow and r.delta > 0 and r.delta >= r.threshold, "upgrade invariants")
                            end
                            T.ok(r.target, "a target slot")
                        end
                        local sum = 0
                        for _, row in ipairs(r.breakdown or {}) do sum = sum + row.points end
                        if r.breakdown then T.near(sum, r.score, 1e-6, "breakdown adds up to the score") end
                        local state = W.EG.Score.UpgradeState(link)
                        T.ok(state == nil or state == "UPGRADE" or state == "LEVEL")
                        local tip = W.tooltipFor(W.bagButton(0, 1), link)
                        T.ok(tip.__shown)
                    end
                end
                W.EG.Slash.PrintUpgrades()
            end
            T.eq(W.EG.lastError, nil, "no internal error in run " .. run .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
        end
        T.ok(checked > 40 * RUNS, "enough comparisons: " .. checked)
    end)

    --[[ A random walk through everything that happens in a session. The caches are warmed first, then one event
         happens, and right after it (no timer has run) every cached answer must equal the answer computed from
         scratch - a stale cache would show as a difference. Nothing may raise on the way.                    ]]
    T.test("fuzz: after random events the cached answers equal fresh ones", function()
        local RUNS_STATE = math.max(4, math.floor(RUNS / 2))
        local COMMANDS = { "ilvl 0.7", "ilvl 0.5", "mindelta 3", "mindelta 0", "mindeltapct 5", "mindeltapct 1", "autolevel off",
                           "autolevel on", "enchants off", "enchants on", "ilvlscale off", "ilvlscale on", "socket 3",
                           "socket auto", "tooltip off", "tooltip on", "icons", "frobnicate", "upgrades", "status",
                           "profile list", "ilvl abc", "scale 9", "parse item:100001" }
        local checks = 0
        for run = 1, RUNS_STATE do
            local class = pick(CLASSES)
            local W = T.world({ class = class, level = pick({ 30, 60 }),
                                talents = { mode = "specinfo", points = { rnd(41) - 1, rnd(41) - 1, rnd(41) - 1 } } })
            local pool, locs = {}, {}
            for i = 1, 10 do pool[i], locs[i] = randomItem(W) end
            local S, C = W.EG.Score, W.EG.Contexts

            --[[ Everything the session may have cached, read as the displays would read it right after the event, and
                 compared with the same answers computed from scratch (hints and totals bypass their caches).    ]]
            local function verify()
                local sample, cached = { pick(pool), pick(pool), pick(pool) }, {}
                for i, link in ipairs(sample) do cached[i] = { S.Compare(link), S.UpgradeState(link) } end
                local cachedHints = {}
                for slot = 1, 19 do
                    local h = C.SlotHint(slot)
                    cachedHints[slot] = h and h.delta
                end
                local cachedTotals = S.EquippedTotals()

                W.EG:InvalidateAll()
                checks = checks + 1

                local freshTotals = S.EquippedTotals(true)
                for _, key in ipairs({ "COUNT", "ILVL", "DPS", "RDPS", "SOCKET" }) do
                    T.near(cachedTotals[key], freshTotals[key], 1e-9, "stale total " .. key .. ", run " .. run)
                end
                local freshHints = W.EG.Recommend.SlotHints()
                for slot = 1, 19 do
                    T.eq(cachedHints[slot], freshHints[slot] and freshHints[slot].delta, "stale hint for slot " .. slot .. ", run " .. run)
                end
                for i, link in ipairs(sample) do
                    local r1, s1 = cached[i][1], cached[i][2]
                    local r2, s2 = S.Compare(link), S.UpgradeState(link)
                    T.eq(r1 == nil, r2 == nil, "availability, run " .. run)
                    if r1 and r2 then
                        T.eq(r1.delta == nil, r2.delta == nil, "delta present, run " .. run)     -- shirts and tabards have none
                        if r1.delta and r2.delta then T.near(r1.delta, r2.delta, 1e-9, "stale delta, run " .. run) end
                        T.eq(r1.isUpgrade, r2.isUpgrade, "stale verdict, run " .. run)
                        T.eq(r1.target and r1.target.slotID, r2.target and r2.target.slotID, "stale target, run " .. run)
                    end
                    T.eq(s1, s2, "stale state, run " .. run)
                end
            end

            for _ = 1, 40 do
                -- warm every cache
                for _, link in ipairs(pool) do S.Compare(link) S.UpgradeState(link) end
                for slot = 1, 19 do C.SlotHint(slot) end
                S.EquippedTotals()

                local action = rnd(11)
                local flush = false
                if action == 1 then
                    local i = rnd(#pool)
                    local slot = SLOT_OF[locs[i]]
                    if slot then W.equip(slot, pool[i]) W.fire("PLAYER_EQUIPMENT_CHANGED", slot) end
                elseif action == 2 then
                    local slot = rnd(18)
                    W.equip(slot, nil)
                    W.fire("PLAYER_EQUIPMENT_CHANGED", slot)
                elseif action == 3 then                          -- an enchant: new link in the same slot, no slot event
                    local link, loc = randomItem(W)
                    local slot = SLOT_OF[loc]
                    if slot then W.equip(slot, link) W.fire("UNIT_INVENTORY_CHANGED", "player") end
                elseif action == 4 then
                    W.put(0, rnd(8), pick(pool))
                    W.fire("BAG_UPDATE_DELAYED")
                elseif action == 5 then
                    W.fire("GET_ITEM_INFO_RECEIVED", 100000 + rnd(40), rnd(2) == 1)
                elseif action == 6 then
                    W.tooltipFor(W.bagButton(0, 1), pick(pool))
                    W.tooltipFor(W.namedButton("CharacterChestSlot", 5), pick(pool))
                    local shop = W.env.ShoppingTooltip1
                    shop:SetOwner(W.env.GameTooltip, "ANCHOR_NONE")
                    W.env.__showItem(shop, pick(pool))
                elseif action == 7 then
                    W.EG.Window.SetItem(pick({ pick(pool), 100000 + rnd(40), "item:" .. (100000 + rnd(40)), "junk", 0 }))
                    W.EG.Window.Refresh()
                elseif action == 8 then
                    W.slash(pick(COMMANDS))
                elseif action == 9 then
                    W.flush()
                elseif action == 10 then
                    W.setLevel(pick({ 30, 45, 60 }))
                    flush = true                                  -- the profile follows the level after a short delay
                else
                    local specs = W.EG.Profiles.List(class)
                    W.EG.Profiles.SetActive(rnd(3) == 1 and "AUTO" or pick(specs).id)
                end
                if flush then W.flush() end

                T.eq(W.EG.lastError, nil, "no internal error, run " .. run .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
                verify()
            end
        end
        T.ok(checks >= 40 * RUNS_STATE, "enough checks: " .. checks)
    end)

    -- the events that can change a verdict, as one step of a random walk (the walk flushes the timers afterwards)
    local function randomEvent(W, pool, locs, class)
        local action = rnd(8)
        if action == 1 then
            local i = rnd(#pool)
            local slot = SLOT_OF[locs[i]]
            if slot then W.equip(slot, pool[i]) W.fire("PLAYER_EQUIPMENT_CHANGED", slot) end
        elseif action == 2 then
            local slot = rnd(18)
            W.equip(slot, nil)
            W.fire("PLAYER_EQUIPMENT_CHANGED", slot)
        elseif action == 3 then
            local link, loc = randomItem(W)
            local slot = SLOT_OF[loc]
            if slot then W.equip(slot, link) W.fire("UNIT_INVENTORY_CHANGED", "player") end
        elseif action == 4 then
            W.setLevel(pick({ 30, 45, 60 }))
        elseif action == 5 then
            W.EG.Profiles.SetActive(rnd(3) == 1 and "AUTO" or pick(W.EG.Profiles.List(class)).id)
        elseif action == 6 then
            W.slash(pick({ "ilvl 0.7", "ilvl 0.5", "mindelta 3", "mindelta 0", "enchants off", "enchants on", "autolevel off", "autolevel on" }))
        elseif action == 7 then
            W.EG:Set("showBagIcons", rnd(3) ~= 1)
        else
            W.fire("GET_ITEM_INFO_RECEIVED", 100000 + rnd(40), rnd(2) == 1)
        end
    end

    --[[ Baganator redraws a button only when it is told to. Whenever an event changes what the arrow of any button
         should say, EasyGear must have asked for a redraw; after the redraw the widgets show the verdicts.        ]]
    T.test("fuzz: Baganator is asked to redraw whenever a verdict changed, and its widgets follow the verdicts", function()
        local RUNS_B = math.max(3, math.floor(RUNS / 3))
        local walks = 0
        for run = 1, RUNS_B do
            local class = pick(CLASSES)
            local Bm
            local W = T.world({ class = class, level = pick({ 30, 60 }),
                                talents = { mode = "specinfo", points = { rnd(41) - 1, rnd(41) - 1, rnd(41) - 1 } } },
                              function(w) Bm = w.installBaganator() end)
            local pool, locs, buttons = {}, {}, {}
            for i = 1, 10 do pool[i], locs[i] = randomItem(W) end
            for i = 1, 5 do
                buttons[i] = Bm.button()
                Bm.update(buttons[i], pool[i])
            end
            local function verdicts()
                local out = {}
                for i, b in ipairs(buttons) do
                    local link = b.BGR and b.BGR.itemLink
                    local state = (link and W.EG:Get("showBagIcons") ~= false) and W.EG.Score.UpgradeState(link) or nil
                    out[i] = state or false
                end
                return out
            end
            for step = 1, 30 do
                local before, asked = verdicts(), #Bm.refreshes
                randomEvent(W, pool, locs, class)
                W.flush()
                local after = verdicts()
                local changed = false
                for i = 1, #buttons do if before[i] ~= after[i] then changed = true end end
                if changed then T.ok(#Bm.refreshes > asked, "a verdict changed but Baganator was not asked (run " .. run .. ", step " .. step .. ")") end
                if #Bm.refreshes > asked then                       -- what Baganator does on a request
                    for _, b in ipairs(buttons) do Bm.update(b, b.BGR.itemLink) end
                end
                for i, b in ipairs(buttons) do
                    T.eq(b.cornerPlugins.easygear:IsShown(), after[i] ~= false, "widget " .. i .. " follows its verdict (run " .. run .. ")")
                end
                local b = pick(buttons)                              -- a new item arrives in one of the buttons (or none)
                local arrived = pick(pool)
                if rnd(4) == 1 then arrived = nil end
                Bm.update(b, arrived)
                walks = walks + 1
                T.eq(W.EG.lastError, nil, "no internal error: " .. tostring(W.EG.lastError and W.EG.lastError.err))
            end
        end
        T.ok(walks >= 30 * RUNS_B)
    end)

    --[[ EllesmereUI's slots and list rows are filled and emptied by their owner without any notice to EasyGear except
         the quality and the texture calls; the owner also resizes and raises its buttons. The arrows must follow the
         items that are really in the slots, be half as high as the icon below (8 to 16 pixels) and sit on a frame
         that stays above the layer they hang on.                                                                      ]]
    T.test("fuzz: EllesmereUI's bag slots and list rows show the verdict of their item and nothing when emptied", function()
        local RUNS_E = math.max(3, math.floor(RUNS / 3))
        for run = 1, RUNS_E do
            local class = pick(CLASSES)
            local Em
            local W = T.world({ class = class, level = pick({ 30, 60 }),
                                talents = { mode = "specinfo", points = { rnd(41) - 1, rnd(41) - 1, rnd(41) - 1 } } },
                              function(w) Em = w.installEllesmere() end)
            local pool, locs, slots = {}, {}, {}
            for i = 1, 10 do pool[i], locs[i] = randomItem(W) end
            for i = 1, 6 do slots[i] = { button = Em.slot(0, i, i > 3) } end          -- three grid slots, three list rows
            for step = 1, 30 do
                local rec = pick(slots)                                  -- a slot is refilled or emptied
                rec.link = pick(pool)
                if rnd(4) == 1 then rec.link = nil end
                local overlay = rec.button._textOverlay
                if rnd(3) == 1 then overlay:SetHeight(pick({ 0, 10, 16, 17, 20, 24, 31, 32, 37, 48 })) end   -- resized ...
                if rnd(3) == 1 then overlay:SetFrameLevel(rnd(200)) end                                        -- ... or raised
                Em.render(rec.button, rec.link)
                rec.height = overlay:GetHeight()
                randomEvent(W, pool, locs, class)
                W.flush()                                                -- the marks refresh after the debounce
                for i, r in ipairs(slots) do
                    local expected = false
                    if r.link and W.EG:Get("showBagIcons") ~= false then expected = W.EG.Score.UpgradeState(r.link) ~= nil end
                    local shown = r.button.EasyGearArrow and r.button.EasyGearArrow:IsShown() or false
                    T.eq(shown, expected, "slot " .. i .. " (run " .. run .. ", step " .. step .. ")")
                    if shown then
                        local want = 16
                        if r.height and r.height > 0 then want = math.max(8, math.min(16, math.floor(r.height * 0.5))) end
                        T.eq(r.button.EasyGearArrow:GetWidth(), want, "size of the arrow in slot " .. i .. " (run " .. run .. ")")
                        T.eq(r.button.EasyGearHost:GetFrameLevel(), r.button._textOverlay:GetFrameLevel() + 8,
                             "level of the frame with the marks in slot " .. i .. " (run " .. run .. ")")
                    end
                end
                T.eq(W.EG.lastError, nil, "no internal error: " .. tostring(W.EG.lastError and W.EG.lastError.err))
            end
        end
    end)

    --[[ The vendor window: a standard row (square button, the icon is the button's own) and a row in EllesmereUI's list
         view (the button covers the row, the icon is the SlotTexture of the row). The stock text comes before the
         quality in the standard window and after it in the list view. In every order, the arrow must show the verdict
         at the corner of the right icon - the other corner while the stock text is shown.                         ]]
    T.test("fuzz: vendor rows show the verdict at the icon, giving way to the stock text in either call order", function()
        local RUNS_V = math.max(3, math.floor(RUNS / 3))
        for run = 1, RUNS_V do
            local class = pick(CLASSES)
            local W = T.world({ class = class, level = pick({ 30, 60 }),
                                talents = { mode = "specinfo", points = { rnd(41) - 1, rnd(41) - 1, rnd(41) - 1 } } })
            local pool, locs, rows = {}, {}, {}
            for i = 1, 10 do pool[i], locs[i] = randomItem(W) end
            for i = 1, 6 do
                local frame = W.env.CreateFrame("Frame")
                frame.SlotTexture = frame:CreateTexture(nil, "BACKGROUND")
                frame.ItemButton = W.namedButton("MerchantItem" .. i .. "ItemButton", i)
                local wide = i > 3
                if wide then frame.ItemButton:SetSize(pick({ 200, 300, 450 }), pick({ 20, 24, 32 }))
                else frame.ItemButton:SetSize(37, 37) end
                frame.ItemButton.Stock = W.env.CreateFrame("Frame", nil, frame.ItemButton)
                frame.ItemButton.Stock:Hide()
                rows[i] = { frame = frame, wide = wide, stock = 0 }
            end
            for step = 1, 40 do
                local r = pick(rows)
                local link, stock = pick(pool), pick({ 0, 0, 1, 5, 20 })
                if rnd(5) == 1 then link = nil end
                if rnd(2) == 1 then                                      -- the standard window: stock first, then quality
                    W.env.SetItemButtonStock(r.frame.ItemButton, stock)
                    W.env.MerchantFrameItem_UpdateQuality(r.frame, link, false)
                else                                                     -- EllesmereUI's list: quality first, then stock
                    W.env.MerchantFrameItem_UpdateQuality(r.frame, link, false)
                    W.env.SetItemButtonStock(r.frame.ItemButton, stock)
                end
                r.link, r.stock = link, stock
                if rnd(3) == 1 then randomEvent(W, pool, locs, class) W.flush() end
                for i, row in ipairs(rows) do
                    local b = row.frame.ItemButton
                    local expected = false
                    if row.link and W.EG:Get("showItemIcons") ~= false then expected = W.EG.Score.UpgradeState(row.link) ~= nil end
                    local shown = b.EasyGearArrow and b.EasyGearArrow:IsShown() or false
                    T.eq(shown, expected, "row " .. i .. " (run " .. run .. ", step " .. step .. ")")
                    if shown then
                        local point, rel = b.EasyGearArrow:GetPoint(1)
                        T.eq(point, row.stock > 0 and "TOPRIGHT" or "TOPLEFT", "corner of row " .. i .. " (run " .. run .. ")")
                        T.eq(rel, row.wide and row.frame.SlotTexture or (b.Icon or b.icon), "icon of row " .. i .. " (run " .. run .. ")")
                    end
                end
                T.eq(W.EG.lastError, nil, "no internal error: " .. tostring(W.EG.lastError and W.EG.lastError.err))
            end
        end
    end)

    T.test("fuzz: a copy of the worn item in a single-slot position never gains", function()
        local W = T.world(F.arms(), function(w) w.I = F.armsWarrior(w) end)
        local r = W.EG.Score.Compare(W.I.chest)
        T.near(r.delta, 0, 1e-9)
        T.eq(r.isUpgrade, false)
        -- for a ring or trinket the second slot decides: a copy would fill the empty one
        r = W.EG.Score.Compare(W.I.trinket)
        T.eq(r.target.empty, true) T.near(r.delta, r.score)
    end)

    T.test("fuzz: every profile of every class resolves and scores a plain item", function()
        for _, class in ipairs(CLASSES) do
            local W = T.world({ class = class, level = 60, talents = { mode = "specinfo", points = { 20, 10, 5 } } })
            local link = F.gear(W, 200000 + #class, "Plain", "INVTYPE_CHEST", 50, { STR = 20, INT = 20, SP = 20 }, { armor = 300 })
            for _, spec in ipairs(W.EG.Profiles.List(class)) do
                T.eq(W.EG.Profiles.SetActive(spec.id), true)
                local s = W.EG.Score.OfLink(link)
                T.ok(s and s > 0, class .. " " .. spec.id)
            end
        end
    end)

    --[[ A group changes all the time: members join, leave, change gear, walk away, die; the player fights, opens the inspect
         window, changes settings and gear. After every step the verdicts of the group must be the ones computed from
         scratch, every named member must be in the group and really gain, and every request must have been made with
         manners (not in combat, not with an inspect window open, only in range, 2.5 seconds apart).           ]]
    local WEAPON_SUBS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18, 19 }
    T.test("fuzz: group verdicts stay right while members, gear, settings and time change at random", function()
        local RUNS_G = math.max(3, math.floor(RUNS / 3))
        local requestsChecked = 0
        for run = 1, RUNS_G do
            local class = pick(CLASSES)
            local G, pool, locs = nil, {}, {}
            local function groupItem(w)
                nextId = nextId + 1
                local loc = pick(LOCS)
                local stats = {}
                for _ = 1, rnd(5) do stats[pick(STATS)] = rnd(60) end
                local weapon = loc:find("WEAPON") or loc == "INVTYPE_RANGED"
                local extra = { armor = (rnd(3) == 1) and rnd(800) or nil, minLevel = (rnd(4) == 1) and rnd(60) or 0,
                                unique = (rnd(12) == 1) and true or nil, quality = pick({ 0, 1, 2, 3, 4, 4 }),
                                subclassID = weapon and pick(WEAPON_SUBS) or pick({ 0, 1, 1, 2, 2, 3, 4, 4, 6, 7 }),
                                classes = (rnd(10) == 1) and pick({ "Priest, Mage", "Warrior", "Rogue, Druid" }) or nil }
                if weapon then extra.dps = rnd(400) / 10 end
                return F.gear(w, nextId, "Item" .. nextId, loc, rnd(120), stats, extra), loc
            end
            local function itemForSlot(slot)
                local fits = {}
                for i, loc in ipairs(locs) do
                    if SLOT_OF[loc] == slot or (slot == 12 and SLOT_OF[loc] == 11) or (slot == 14 and SLOT_OF[loc] == 13) then
                        fits[#fits + 1] = pool[i]
                    end
                end
                if #fits == 0 then return nil end
                return pick(fits)
            end
            local W = T.world({ class = class, level = pick({ 30, 60 }),
                                talents = { mode = "specinfo", points = { rnd(41) - 1, rnd(41) - 1, rnd(41) - 1 } } },
                              function(w)
                G = w.installGroup()
                for i = 1, 30 do pool[i], locs[i] = groupItem(w) end
                for i = 1, rnd(4) do
                    local gear = {}
                    for _, slot in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
                        if rnd(4) > 1 then gear[slot] = itemForSlot(slot) end
                    end
                    G.add("party" .. i, { name = "M" .. i, class = pick(CLASSES), level = pick({ 20, 40, 60 }),
                                          tab = (rnd(3) == 1) and nil or rnd(3), gear = gear, distance = pick({ 5, 5, 5, 50 }) })
                end
            end)
            local function sample()
                local out = {}
                for _ = 1, 6 do out[#out + 1] = pick(pool) end
                return out
            end
            local function names(list)
                local out = {}
                for _, e in ipairs(list or {}) do out[#out + 1] = e.member.guid .. ":" .. e.slot .. ":" .. string.format("%.6f", e.delta) end
                return table.concat(out, ";")
            end

            for step = 1, 25 do
                local action = rnd(13)
                local members = {}
                for unit in pairs(G.members) do members[#members + 1] = unit end
                table.sort(members)
                local unit = #members > 0 and pick(members) or nil
                if action == 1 then
                    W.advance(rnd(10))
                elseif action == 2 and unit then
                    local slot = pick({ 1, 3, 5, 7, 11, 13, 15, 16, 17, 18 })
                    G.members[unit].gear[slot] = itemForSlot(slot)
                    G.gearChanged(unit)
                elseif action == 3 and unit then
                    G.remove(unit) G.rosterChanged()
                elseif action == 4 and #members < 4 then
                    local free = "party" .. rnd(4)
                    if not G.members[free] then
                        G.add(free, { name = "N" .. step, class = pick(CLASSES), level = pick({ 20, 40, 60 }),
                                      tab = (rnd(3) == 1) and nil or rnd(3), gear = { [5] = itemForSlot(5), [1] = itemForSlot(1) } })
                        G.rosterChanged()
                    end
                elseif action == 5 then
                    if rnd(2) == 1 then G.combat = not G.combat else G.lockdown = not G.lockdown end
                elseif action == 6 then
                    if rnd(2) == 1 then G.inspectFrameShown = not G.inspectFrameShown else G.talentInspect = not G.talentInspect end
                elseif action == 7 and unit then
                    local m = G.members[unit]
                    m.distance = (m.distance > 28) and 5 or 50
                    if rnd(5) == 1 then m.connected = not m.connected end
                elseif action == 8 then
                    local key = pick({ "minDelta", "minDeltaPercent", "groupInspect", "showGroupHints", "groupRaid", "includeEnchants" })
                    if key == "minDelta" then W.EG:Set(key, pick({ 0, 5, 20 }))
                    elseif key == "minDeltaPercent" then W.EG:Set(key, pick({ 0, 1, 5, 10 }))
                    else W.EG:Set(key, rnd(3) ~= 1) end
                elseif action == 9 then
                    local slot = pick({ 5, 11, 13, 16 })
                    W.equip(slot, itemForSlot(slot))
                    W.fire("PLAYER_EQUIPMENT_CHANGED", slot)
                elseif action == 10 then
                    W.setLevel(pick({ 30, 45, 60 }))
                elseif action == 11 and unit then
                    G.inspectByHand(unit)
                elseif action == 12 then
                    -- the look of the marks, valid or not
                    local kind = pick(W.EG.Marks.KINDS)
                    local shapes = { "arrow", "star", "check", "coin", "circle", "diamond", "triangle", "moon", "square", "cross",
                                     "skull", "bogus", "", 7, false }
                    local colors = { "ff40ff40", "ff000000", "ffffffff", "ff123456", "80ff8800", "#abcdef", "nope", "", 12, true }
                    if rnd(2) == 1 then W.EG:Set(kind.shapeKey, pick(shapes)) else W.EG:Set(kind.colorKey, pick(colors)) end
                else
                    for _, key in ipairs(sample()) do W.tooltipFor(W.bagButton(0, 1), key) end
                end
                W.flush()
                for _, kind in ipairs(W.EG.Marks.KINDS) do
                    local tex = W.env.CreateFrame("Frame"):CreateTexture()
                    W.EG.Marks.Paint(tex, kind.id)
                    T.ok(tex:GetAtlas() or tex:GetTexture(), "a picture for every kind, whatever the settings say")
                    T.eq(type(tex.__desaturated), "boolean")
                    for i = 1, 3 do T.ok(tex.__vertex[i] >= 0 and tex.__vertex[i] <= 1, "a color between 0 and 1") end
                end

                T.eq(W.EG.lastError, nil, "no internal error, run " .. run .. ", step " .. step .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
                local Gp = W.EG.Group
                for _, link in ipairs(sample()) do
                    local cached = Gp.Beneficiaries(link)
                    local before = names(cached)
                    W.EG:InvalidateComparisons()                         -- drop everything that is cached ...
                    local fresh = Gp.Beneficiaries(link)                 -- ... and compute it from scratch
                    T.eq(names(fresh), before, "stale verdict (run " .. run .. ", step " .. step .. ")")
                    local inGroup = {}
                    for _, m in ipairs(Gp.list) do inGroup[m] = true end
                    local itemData = W.EG.Items.Get(link)
                    for _, e in ipairs(fresh or {}) do
                        T.ok(inGroup[e.member], "only members of the group are named")
                        T.ok((itemData.reqLevel or 0) <= e.member.level + 1, "at most one level too high for the member")
                        T.ok(e.delta > 0, "a gain")
                        T.ok(e.percent == nil or e.percent >= 3 - 1e-6, "at least three percent: " .. tostring(e.percent))
                        T.ok(e.slot >= 1 and e.slot <= 18)
                    end
                    local state = Gp.State(link, "loot")
                    T.eq(state, (fresh and #fresh > 0) and "GROUP" or nil, "state and list agree")
                    if not Gp.Enabled() then T.eq(fresh, nil, "nothing when the hints are off") end
                end
            end

            local last = nil
            for _, r in ipairs(G.notified) do
                T.eq(r.combat, false, "no request in combat") T.eq(r.lockdown, false, "no request in a lockdown")
                T.eq(r.frame, false, "no request with an inspect window open") T.eq(r.talents, false)
                T.ok(r.distance and r.distance <= 28, "only in range")
                T.eq(r.connected, true) T.eq(r.visible, true)
                if last then T.ok(r.at - last >= 2.5 - 1e-9, "requests are spaced out: " .. (r.at - last)) end
                last = r.at
                requestsChecked = requestsChecked + 1
            end
        end
        T.ok(requestsChecked > 0, "the walk made requests")
    end)
end
