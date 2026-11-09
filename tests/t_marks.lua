-- Marks.lua / Contexts.lua: markers on item buttons, the way the Forever UI calls the hooks
return function(T)
    local F = require("fixtures")

    local function world(setup, opts)
        return T.world(F.arms(opts), function(W)
            W.I = F.armsWarrior(W)
            W.I.better = F.gear(W, 7001, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35 })
            W.I.weak = F.gear(W, 7002, "Weak Chestplate", "INVTYPE_CHEST", 10, { STR = 1 })
            W.I.late = F.gear(W, 7003, "Late Chestplate", "INVTYPE_CHEST", 90, { STR = 90 }, { minLevel = 65 })
            if setup then setup(W) end
        end)
    end
    local function arrow(b) return b.EasyGearArrow and b.EasyGearArrow:IsShown() or false end
    local function check(b) return b.EasyGearCheck and b.EasyGearCheck:IsShown() or false end

    T.test("marks: the hooks are installed and reported", function()
        local W = world()
        for _, name in ipairs({ "itembuttons", "merchant", "merchantstock", "rolls", "tooltip", "settings", "shiftclick" }) do
            T.eq(W.EG.hookStatus[name] and W.EG.hookStatus[name].ok, true, name)
        end
        T.eq(W.EG.hookStatus.quest, nil, "QuestInfo_ShowRewards is not hooked: its callers hold the function values")
    end)

    T.test("marks: bag button - arrow for an upgrade, nothing for the rest", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        T.eq(arrow(b), true)
        T.eq(b.EasyGearArrow:GetAtlas(), "bags-greenarrow")
        T.eq(b.EasyGearArrow.__desaturated, false)
        W.env.SetItemButtonQuality(b, 3, W.I.weak)
        T.eq(arrow(b), false, "the same button shows a worse item")
        W.env.SetItemButtonQuality(b, nil, nil)
        T.eq(arrow(b), false, "empty slot")
        T.eq(check(b), false)
    end)

    T.test("marks: an item that needs a higher level gets the yellow arrow", function()
        local W = world()
        local b = W.bagButton(0, 2)
        W.env.SetItemButtonQuality(b, 3, W.I.late)
        T.eq(arrow(b), true) T.eq(b.EasyGearArrow.__desaturated, true)
        local v = b.EasyGearArrow.__vertex
        T.near(v[1], 1.0) T.near(v[2], 0.82) T.near(v[3], 0.0)
    end)

    T.test("marks: a bag button without a link in the call finds it in the bag", function()
        local W = world(function(w) w.bag(0, 4, { [3] = w.I.better }) end)
        local b = W.bagButton(0, 3)
        W.env.SetItemButtonQuality(b, 3, nil)
        T.eq(arrow(b), true)
    end)

    T.test("marks: the Camelot bank passes an item id; the link comes from the slot data", function()
        local W = world()
        local b = W.bankButton(6, 4)
        b.itemInfo = { hyperlink = W.I.better, itemID = 7001 }
        W.env.SetItemButtonQuality(b, 3, 7001)
        T.eq(arrow(b), true)
        b.itemInfo = { itemID = 7002 }
        W.env.SetItemButtonQuality(b, 3, 7002)
        T.eq(arrow(b), false, "without a hyperlink the id alone (weaker) is used")
    end)

    T.test("marks: every item button has GetBagID, only container buttons are bag buttons", function()
        local W = world()
        local plain = W.namedButton("MerchantItem1ItemButton", 1)
        T.ok(plain.GetBagID, "ItemButtonMixin gives all item buttons GetBagID")
        W.env.SetItemButtonQuality(plain, 3, W.I.better)
        T.eq(arrow(plain), false, "not a bag button, not marked by the generic hook")
        T.eq(W.EG.Contexts.Classify(plain), false)
        T.eq(W.EG.Contexts.Classify(W.bagButton(0, 1)), "bag")
        T.eq(W.EG.Contexts.Classify(W.bankButton(6, 1)), "bank")
        T.eq(W.EG.Contexts.Classify(W.namedButton("CharacterFinger0Slot", 11)), "char")
        T.eq(W.EG.Contexts.Classify(W.namedButton("CharacterTrinket1Slot", 14)), "char")
        T.eq(W.EG.Contexts.Classify(W.namedButton("CharacterSecondaryHandSlot", 17)), "char")
        T.eq(W.EG.Contexts.Classify(W.namedButton("TradeRecipientItem3ItemButton", 3)), "trade")
        T.eq(W.EG.Contexts.Classify(W.namedButton("OpenMailAttachmentButton2", 2)), "mail")
        T.eq(W.EG.Contexts.Classify(W.lootButton(1)), "loot")
        T.eq(W.EG.Contexts.Classify("junk"), false)
    end)

    T.test("marks: vendor, loot, trade and mail buttons", function()
        local W = world()
        local frame = { ItemButton = W.namedButton("MerchantItem1ItemButton", 1) }
        W.env.MerchantFrameItem_UpdateQuality(frame, W.I.better, false)
        T.eq(arrow(frame.ItemButton), true)
        W.env.MerchantFrameItem_UpdateQuality(frame, nil, false)
        T.eq(arrow(frame.ItemButton), false, "sold out slot")

        local loot = W.lootButton(1)
        W.env.SetItemButtonQuality(loot, 3, W.I.better)
        T.eq(arrow(loot), true)

        local trade = W.namedButton("TradeRecipientItem1ItemButton", 1)
        W.env.SetItemButtonQuality(trade, 3, W.I.better)
        T.eq(arrow(trade), true)

        local mail = W.namedButton("OpenMailAttachmentButton1", 1)
        W.env.SetItemButtonQuality(mail, 3, 7001)
        T.eq(arrow(mail), true, "mail passes the item id")
    end)

    T.test("contexts: slot names come from a whitelist - bag, ammo and unknown slots are no equipment", function()
        local W = world()
        local C = W.EG.Contexts
        local expect = { Head = 1, Neck = 2, Shoulder = 3, Shirt = 4, Chest = 5, Waist = 6, Legs = 7, Feet = 8,
                         Wrist = 9, Hands = 10, Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14, Back = 15,
                         MainHand = 16, SecondaryHand = 17, Ranged = 18, Tabard = 19 }
        for name, slot in pairs(expect) do
            local kind, id = C.SlotOfName("Character" .. name .. "Slot")
            T.eq(kind, "Character", name) T.eq(id, slot, name)
            kind, id = C.SlotOfName("Inspect" .. name .. "Slot")
            T.eq(kind, "Inspect", name) T.eq(id, slot, name)
        end
        for _, name in ipairs({ "CharacterBag0Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "CharacterAmmoSlot",
                                "CharacterFooSlot", "CharacterSlot", "MyCharacterHeadSlot", "CharacterHeadSlotX", "" }) do
            T.eq(C.SlotOfName(name), nil, name)
        end
        T.eq(C.SlotOfName(nil), nil) T.eq(C.SlotOfName(5), nil) T.eq(C.SlotOfName({}), nil)
        T.eq(C.Classify(W.namedButton("CharacterBag0Slot", 20)), false, "the bag bar buttons are not character slots")
        T.eq(C.Classify(W.namedButton("CharacterAmmoSlot", 0)), false)
        T.eq(C.Classify(W.namedButton("InspectHeadSlot", 1)), false, "inspecting someone is not our own character window")
    end)

    T.test("marks: the mail attachment takes its link from the inbox, not from the bare item id", function()
        local W = world()
        W.env.InboxFrame = { openMailID = 4 }
        local asked = {}
        W.env.GetInboxItemLink = function(mailID, i)
            asked[#asked + 1] = mailID .. ":" .. i
            return W.I.better
        end
        local mail = W.namedButton("OpenMailAttachmentButton2", 2)
        W.env.SetItemButtonQuality(mail, 3, 7002)           -- Blizzard passes only the (weak) item id
        T.eq(arrow(mail), true, "the inbox link decides")
        T.eq(asked[1], "4:2")
        -- without an open mail or inbox function the id has to do
        W.env.GetInboxItemLink = nil
        W.env.SetItemButtonQuality(mail, 3, 7002)
        T.eq(arrow(mail), false, "weak id alone")
        W.env.GetInboxItemLink = function() return nil end
        W.env.SetItemButtonQuality(mail, 3, 7001)
        T.eq(arrow(mail), true, "an empty answer falls back to the id")
    end)

    T.test("marks: a loot roll asks GetLootRollItemLink first and the tooltip data second", function()
        local W = world()
        local calls = 0
        W.env.GetLootRollItemLink = function(rollID) calls = calls + 1 return rollID == 9 and W.I.better or nil end
        local frame = { rollID = 9, IconFrame = W.env.CreateFrame("Frame") }
        W.env.GroupLootFrame_SetupItemDisplay(frame)
        T.eq(arrow(frame.IconFrame), true) T.eq(calls, 1)
        W.state.rolls = { [11] = W.I.better }
        local second = { rollID = 11, IconFrame = W.env.CreateFrame("Frame") }
        W.env.GroupLootFrame_SetupItemDisplay(second)
        T.eq(arrow(second.IconFrame), true, "falls back to C_TooltipInfo.GetLootRollItem")
        W.env.GetLootRollItemLink = function() error("not available yet") end
        local third = { rollID = 11, IconFrame = W.env.CreateFrame("Frame") }
        W.env.GroupLootFrame_SetupItemDisplay(third)
        T.eq(arrow(third.IconFrame), true, "an error in the getter does not lose the roll")
    end)

    T.test("marks: the arrow moves to the right corner when the vendor shows the remaining stock", function()
        local W = world()
        local frame = { ItemButton = W.namedButton("MerchantItem2ItemButton", 2) }
        frame.ItemButton.Stock = W.env.CreateFrame("Frame")
        frame.ItemButton.Stock:Hide()
        W.env.MerchantFrameItem_UpdateQuality(frame, W.I.better, false)
        T.eq((frame.ItemButton.EasyGearArrow:GetPoint(1)), "TOPLEFT")
        frame.ItemButton.Stock:Show()
        W.env.MerchantFrameItem_UpdateQuality(frame, W.I.better, false)
        T.eq((frame.ItemButton.EasyGearArrow:GetPoint(1)), "TOPRIGHT", "the stock number sits at the left")
    end)

    T.test("marks: group loot rolls take the link from the tooltip data", function()
        local W = world(function(w) w.state.rolls = { [9] = w.I.better } end)
        local frame = { rollID = 9, IconFrame = W.env.CreateFrame("Frame") }
        W.env.GroupLootFrame_SetupItemDisplay(frame)
        T.eq(arrow(frame.IconFrame), true)
        local none = { rollID = 10, IconFrame = W.env.CreateFrame("Frame") }
        W.env.GroupLootFrame_SetupItemDisplay(none)
        T.eq(arrow(none.IconFrame), false)
    end)

    T.test("marks: character window hint appears when the bags hold something better", function()
        local W = world(function(w) w.bag(0, 8, { [1] = w.I.better }) end)
        local chest = W.namedButton("CharacterChestSlot", 5)
        local head = W.namedButton("CharacterHeadSlot", 1)
        W.env.SetItemButtonQuality(chest, 3, 2001)
        W.env.SetItemButtonQuality(head, 0, nil)
        T.eq(arrow(chest), true) T.eq(arrow(head), false)
        -- wear it: the hint goes away
        W.equip(5, W.I.better)
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        W.state.bags[0].items[1] = nil
        W.flush()
        T.eq(arrow(chest), false)
    end)

    T.test("marks: the character hint is stale-free at the moment the equipment changes", function()
        local W = world(function(w) w.bag(0, 8, { [1] = w.I.better }) end)
        local C = W.EG.Contexts
        T.ok(C.SlotHint(5), "something better for the chest is in the bags")
        W.equip(5, W.I.better)
        W.state.bags[0].items[1] = nil
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        T.eq(C.SlotHint(5), nil, "no timer needs to run first")
    end)

    T.test("marks: bag changes update the character window hint", function()
        local W = world()
        local chest = W.namedButton("CharacterChestSlot", 5)
        W.env.SetItemButtonQuality(chest, 3, 2001)
        T.eq(arrow(chest), false)
        W.put(0, 1, W.I.better)
        W.fire("BAG_UPDATE_DELAYED")
        W.flush()
        T.eq(arrow(chest), true)
    end)

    T.test("marks: settings switch the groups off and on", function()
        local W = world()
        local bag, loot, char = W.bagButton(0, 1), W.lootButton(1), W.namedButton("CharacterChestSlot", 5)
        W.put(0, 5, W.I.better)
        W.env.SetItemButtonQuality(bag, 3, W.I.better)
        W.env.SetItemButtonQuality(loot, 3, W.I.better)
        W.env.SetItemButtonQuality(char, 3, 2001)
        T.eq(arrow(bag) and arrow(loot) and arrow(char), true)
        W.EG:Set("showBagIcons", false) W.flush()
        T.eq(arrow(bag), false) T.eq(arrow(loot), true)
        W.EG:Set("showItemIcons", false) W.flush()
        T.eq(arrow(loot), false)
        W.EG:Set("showBagIcons", true) W.EG:Set("showItemIcons", true) W.flush()
        T.eq(arrow(bag), true) T.eq(arrow(loot), true) T.eq(arrow(char), true)
        W.EG:Set("showCharIcons", false) W.flush()
        T.eq(arrow(char), false, "only the character hint goes")
        T.eq(arrow(bag), true) T.eq(arrow(loot), true)
    end)

    T.test("marks: a profile change re-evaluates all marks", function()
        local W = world()
        local b = W.bagButton(0, 1)
        local ring = F.gear(W, 7010, "Tank Ring", "INVTYPE_FINGER", 20, { DEF = 60, STA = 30 }, { typeText = "" })
        W.env.SetItemButtonQuality(b, 3, ring)
        T.eq(arrow(b), false, "arms: 13 points against 14.5 in the weaker ring slot")
        W.EG.Profiles.SetActive("WARRIOR_PROT")
        W.flush()
        T.eq(arrow(b), true, "protection values defence and stamina")
        W.EG.Profiles.SetActive("AUTO")
        W.flush()
        T.eq(arrow(b), false)
    end)

    T.test("marks: an equipment change re-evaluates the marks", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        T.eq(arrow(b), true)
        W.equip(5, F.gear(W, 7011, "Best Chest", "INVTYPE_CHEST", 60, { STR = 60 }, { armor = 900 }))
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        W.flush()
        T.eq(arrow(b), false)
    end)

    T.test("marks: an item that arrives later gets its mark when the data is there", function()
        local W = world(function(w) w.I.slow = F.gear(w, 7012, "Slow", "INVTYPE_CHEST", 50, { STR = 50 }, { uncached = true }) end)
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.slow)
        T.eq(arrow(b), false)
        W.state.items[7012].uncached = nil
        W.fire("GET_ITEM_INFO_RECEIVED", 7012)
        W.flush()
        T.eq(arrow(b), true)
    end)

    T.test("marks: texture fallback when the atlas is unknown", function()
        local W = world(nil, { noAtlas = true })
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        T.eq(arrow(b), true)
        T.eq(b.EasyGearArrow:GetAtlas(), nil)
        T.ok(b.EasyGearArrow:GetTexture(), "file texture")
    end)

    T.test("marks: hidden buttons are skipped by the refresh, shown ones follow", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        b:Hide()
        W.EG:Set("showBagIcons", false) W.flush()
        T.eq(arrow(b), false, "marks of hidden buttons are cleared when their group goes off")
        W.EG:Set("showBagIcons", true) W.flush()
        T.eq(arrow(b), false, "hidden: no work")
        b:Show()
        W.EG:InvalidateAll() W.flush()
        T.eq(arrow(b), true)
    end)

    ------------------------------------------------------------------ quest rewards
    local function quest(W, links, counts)
        local choices = {}
        for i, l in ipairs(links) do choices[i] = { link = l, count = counts and counts[i] or 1 } end
        local buttons = W.questRewards(choices)
        W.showRewards()
        return buttons
    end

    T.test("quest: the best of several rewards gets the check mark", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7020, "Reward A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7021, "Reward B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        local b = quest(W, { W.I.a, W.I.b })
        T.eq(check(b[1]), false) T.eq(check(b[2]), true)
        T.eq(arrow(b[1]) and arrow(b[2]), true, "both are upgrades")
        local rec, kind = W.EG.Contexts.IsRecommended(b[2])
        T.eq(rec, true) T.eq(kind, "UPGRADE")
        T.eq(W.EG.Contexts.IsRecommended(b[1]), false)
    end)

    T.test("quest: the check mark sits at the icon of the wide reward button", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7040, "A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7041, "B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        local b = W.questRewards({ { link = W.I.a }, { link = W.I.b } })
        b[2].Icon = W.env.CreateFrame("Frame")
        W.showRewards()
        local _, rel = b[2].EasyGearCheck:GetPoint(1)
        T.eq(rel, b[2].Icon, "anchored to the icon")
        local point
        point, rel = b[1].EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPLEFT") T.eq(rel, b[1].icon, "the arrow follows the icon too (its top left corner)")
    end)

    T.test("quest: no upgrade among the choices - the most valuable one to sell is marked", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7022, "Junk A", "INVTYPE_CHEST", 5, { STR = 1 }, { sellPrice = 10 })
            w.I.b = F.gear(w, 7023, "Junk B", "INVTYPE_CHEST", 5, { STR = 1 }, { sellPrice = 30 })
        end)
        local b = quest(W, { W.I.a, W.I.b })
        T.eq(check(b[2]), true)
        local _, kind = W.EG.Contexts.IsRecommended(b[2])
        T.eq(kind, "VENDOR")
    end)

    T.test("quest: a single reward is not marked, the setting switches the mark off", function()
        local W = world(function(w) w.I.a = F.gear(w, 7024, "Only", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 }) end)
        local b = quest(W, { W.I.a })
        T.eq(check(b[1]), false)
        W = world(function(w)
            w.I.a = F.gear(w, 7025, "A", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
            w.I.b = F.gear(w, 7026, "B", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
        end)
        W.EG:Set("showQuestIcons", false)
        b = quest(W, { W.I.a, W.I.b })
        T.eq(check(b[1]) or check(b[2]), false)
        T.eq(arrow(b[1]), false, "quest arrows follow the quest setting too")
    end)

    T.test("quest: quest log mode passes item ids and still works", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7027, "A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7028, "B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        local choices = { { link = W.I.a }, { link = W.I.b } }
        local buttons = W.questRewards(choices, true)
        for i, b in ipairs(buttons) do W.env.SetItemButtonQuality(b, 3, 7026 + i) end
        W.flush()
        T.eq(check(buttons[2]), true)
    end)

    T.test("quest: a reward frame that is not shown gets no check mark", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7050, "A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7051, "B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        local b = W.questRewards({ { link = W.I.a }, { link = W.I.b } })
        W.env.QuestInfoFrame.rewardsFrame.IsVisible = function() return false end
        W.showRewards()
        T.eq(check(b[1]) or check(b[2]), false)
        W.env.QuestInfoFrame.rewardsFrame.IsVisible = function() return true end
        W.fire("GET_ITEM_INFO_RECEIVED", 7050, true)
        W.flush()
        T.eq(check(b[2]), true, "when the frame shows, the next refresh sets the mark")
    end)

    T.test("quest: choices the client marks unusable do not take part", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7029, "Big", "INVTYPE_CHEST", 90, { STR = 90 }, { armor = 900 })
            w.I.b = F.gear(w, 7030, "Small", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
        end)
        local b = W.questRewards({ { link = W.I.a, usable = false }, { link = W.I.b } })
        W.showRewards()
        T.eq(check(b[2]), true) T.eq(check(b[1]), false)
    end)

    T.test("quest: a new set of rewards clears the old choice", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7031, "A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7032, "B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        local choices = { { link = W.I.a }, { link = W.I.b } }
        local b = W.questRewards(choices)
        W.showRewards()
        T.eq(check(b[2]), true)
        -- the next quest offers the same two items in the other order
        choices[1].link, choices[2].link = W.I.b, W.I.a
        W.showRewards()
        T.eq(check(b[1]), true) T.eq(check(b[2]), false)
    end)

    T.test("quest: currency rewards pass a currency id and are never mistaken for items", function()
        local W = world(function(w)
            -- an item whose id equals a currency id and that would be a big upgrade
            w.I.trap = F.gear(w, 1792, "Trap Chest", "INVTYPE_CHEST", 90, { STR = 90 }, { armor = 900 })
        end)
        local b = W.namedButton("QuestInfoRewardsFrameQuestInfoItem1", 1)
        b.type, b.objectType, b.currencyInfo = "reward", "currency", { currencyID = 1792 }
        W.env.SetItemButtonQuality(b, 1, 1792)
        T.eq(arrow(b), false)
        -- the same button later shows an item reward in the quest log (stale objectType from before)
        W.env.SetItemButtonQuality(b, 3, 7001)
        T.eq(arrow(b), true, "item ids from the quest log are used as they are")
    end)

    ------------------------------------------------------------------ marker look: shape and color
    local RAID = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
    -- what a fresh texture shows once the addon has painted it for this kind
    local function paintOf(W, kind)
        local tex = W.env.CreateFrame("Frame"):CreateTexture()
        W.EG.Marks.Paint(tex, kind)
        return tex
    end
    local function vertex(tex) local v = tex.__vertex return v[1], v[2], v[3] end

    T.test("look: the defaults are the original look of every kind", function()
        local W = world()
        local expect = {
            UPGRADE = { atlas = "bags-greenarrow",       desat = false, r = 1,    g = 1,    b = 1 },
            LEVEL   = { atlas = "bags-greenarrow",       desat = true,  r = 1,    g = 0.82, b = 0 },
            GROUP   = { atlas = "tradeskills-star",      desat = true,  r = 0.75, g = 0.40, b = 1 },
            PICK    = { atlas = "common-icon-checkmark", desat = false, r = 0.25, g = 1,    b = 0.25 },
            SELL    = { atlas = "common-icon-checkmark", desat = false, r = 0.25, g = 1,    b = 0.25 },
        }
        for kind, e in pairs(expect) do
            local tex = paintOf(W, kind)
            T.eq(tex:GetAtlas(), e.atlas, kind) T.eq(tex.__desaturated, e.desat, kind)
            local r, g, b = vertex(tex)
            T.near(r, e.r, 1e-9, kind) T.near(g, e.g, 1e-9, kind) T.near(b, e.b, 1e-9, kind)
        end
        T.eq(#W.EG.Marks.KINDS, 5) T.eq(#W.EG.Marks.SHAPES, 11)
        local tex = paintOf(W, "no such kind")
        T.eq(tex:GetAtlas(), "bags-greenarrow", "an unknown kind is painted like an upgrade")
    end)

    T.test("look: another shape changes the picture; the color stays the kind's own, drawn from the grey picture", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        local tex = b.EasyGearArrow
        W.EG:Set("markUpgradeShape", "diamond") W.flush()
        T.eq(arrow(b), true)
        T.eq(tex:GetAtlas(), nil) T.eq(tex:GetTexture(), RAID .. "3")
        T.eq(tex.__desaturated, true)
        local r, g, bl = vertex(tex)
        T.near(r, 0x40 / 255, 1e-9) T.near(g, 1, 1e-9) T.near(bl, 0x40 / 255, 1e-9)
        local l, rr, t, bb = tex:GetTexCoord()
        T.eq(l, 0) T.eq(rr, 1) T.eq(t, 0) T.eq(bb, 1, "a file picture shows all of its texture")
        T.eq(tex:GetWidth(), 18) T.eq(tex:GetHeight(), 18)

        W.EG:Set("markUpgradeShape", "coin") W.flush()
        T.eq(tex:GetAtlas(), "bags-junkcoin") T.eq(tex:GetTexture(), nil)
        W.EG:Set("markUpgradeShape", "arrow") W.flush()
        T.eq(tex:GetAtlas(), "bags-greenarrow") T.eq(tex.__desaturated, false, "back to the original")
        T.near((select(1, vertex(tex))), 1, 1e-9)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("look: another color tints the grey picture; the color of the original keeps the original look", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        local tex = b.EasyGearArrow
        W.EG:Set("markUpgradeColor", "ff0000ff") W.flush()
        T.eq(tex:GetAtlas(), "bags-greenarrow", "same shape") T.eq(tex.__desaturated, true)
        local r, g, bl = vertex(tex)
        T.near(r, 0) T.near(g, 0) T.near(bl, 1)
        W.EG:Set("markUpgradeColor", "ffff8000") W.flush()
        r, g, bl = vertex(tex)
        T.near(r, 1) T.near(g, 128 / 255, 1e-9) T.near(bl, 0)
        for _, same in ipairs({ "ff40ff40", "FF40FF40", "#40ff40", "40FF40", "0040ff40" }) do
            W.EG:Set("markUpgradeColor", "ffff8000") W.flush()
            W.EG:Set("markUpgradeColor", same) W.flush()
            T.eq(tex.__desaturated, false, same .. " is the color of the original")
            r, g, bl = vertex(tex)
            T.eq(r, 1, same) T.eq(g, 1, same) T.eq(bl, 1, same)
        end
        T.eq(W.EG.lastError, nil)
    end)

    T.test("look: a color a hair away from the original counts as the original (the color field rounds)", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        local tex = b.EasyGearArrow
        for _, near in ipairs({ "ff41ff3f", "ff3effff", "ff42ff3e", "ff40ff40", "ff40ff42", "ff3e3e3e" }) do
            W.EG:Set("markUpgradeColor", "ff0000ff") W.flush()
            W.EG:Set("markUpgradeColor", near) W.flush()
            if near == "ff3e3e3e" then
                T.eq(tex.__desaturated, true, near .. " is far from the original in green and blue")
            elseif near == "ff3effff" then
                T.eq(tex.__desaturated, true, near .. " is far from the original in the blue channel")
            else
                T.eq(tex.__desaturated, false, near .. " is within two steps in every channel")
                T.eq(tex.__vertex[1], 1) T.eq(tex.__vertex[2], 1) T.eq(tex.__vertex[3], 1)
            end
        end
        for _, far in ipairs({ "ff43ff40", "ff40fc40", "ff40ff3d", "ff3dff40", "ff40ff44" }) do
            W.EG:Set("markUpgradeColor", far) W.flush()
            T.eq(tex.__desaturated, true, far .. " is three steps away in one channel")
        end
        W.EG:Set("markUpgradeShape", "star") W.EG:Set("markUpgradeColor", "ff40ff40") W.flush()
        T.eq(tex.__desaturated, true, "the original color of another shape is still a tinted shape")
        W.EG:Set("markUpgradeShape", "arrow") W.EG:Set("markLevelColor", "ffffd002") W.flush()
        local level = paintOf(W, "LEVEL")
        T.near(level.__vertex[2], 0.82, 1e-9, "the level arrow: within two steps of its own original too")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("look: a level arrow follows its own look", function()
        local W = world()
        local b = W.bagButton(0, 2)
        W.env.SetItemButtonQuality(b, 3, W.I.late)
        W.EG:Set("markLevelShape", "square") W.EG:Set("markLevelColor", "ff800000") W.flush()
        local tex = b.EasyGearArrow
        T.eq(arrow(b), true) T.eq(tex:GetTexture(), RAID .. "6") T.eq(tex.__desaturated, true)
        local r, g, bl = vertex(tex)
        T.near(r, 128 / 255, 1e-9) T.near(g, 0) T.near(bl, 0)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        T.eq(tex:GetAtlas(), "bags-greenarrow", "the next item is an upgrade for now: the arrow of that kind")
    end)

    T.test("look: values that do not exist count as the default and raise nothing", function()
        local W = world()
        for _, bad in ipairs({ "bogus", "", "STAR", " star", 5, true, false, {}, 0 / 0 }) do
            W.EG:Set("markGroupShape", bad)
            local tex = paintOf(W, "GROUP")
            T.eq(tex:GetAtlas(), "tradeskills-star", "shape " .. tostring(bad))
        end
        for _, bad in ipairs({ "zzz", "", "ff40ff4", "ff40ff40ff", "ff 40ff4", "gg0000", 5, true, false, {} }) do
            W.EG:Set("markGroupColor", bad)
            local tex = paintOf(W, "GROUP")
            local r, g, b = vertex(tex)
            T.eq(tex.__desaturated, true, "color " .. tostring(bad))
            T.near(r, 0.75, 1e-9, "the original color, not its rounded hex value") T.near(g, 0.40, 1e-9) T.near(b, 1, 1e-9)
        end
        W.EG:Set("markGroupShape", nil) W.EG:Set("markGroupColor", nil)
        T.eq(paintOf(W, "GROUP"):GetAtlas(), "tradeskills-star", "settings that are gone altogether")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("look: every kind has its own shape and color", function()
        local W = world()
        W.EG:Set("markGroupShape", "moon") W.EG:Set("markGroupColor", "ffff0000")
        W.EG:Set("markSellShape", "coin")
        local up, gr, pick, sell = paintOf(W, "UPGRADE"), paintOf(W, "GROUP"), paintOf(W, "PICK"), paintOf(W, "SELL")
        T.eq(up:GetAtlas(), "bags-greenarrow") T.eq(up.__desaturated, false)
        T.eq(gr:GetTexture(), RAID .. "5") T.near((select(1, vertex(gr))), 1) T.near((select(2, vertex(gr))), 0)
        T.eq(pick:GetAtlas(), "common-icon-checkmark") T.eq(pick.__desaturated, false)
        T.eq(sell:GetAtlas(), "bags-junkcoin") T.eq(sell.__desaturated, true)
        local r, g, b = vertex(sell)
        T.near(r, 0x40 / 255, 1e-9) T.near(g, 1) T.near(b, 0x40 / 255, 1e-9)
    end)

    T.test("look: without atlases every shape comes from its file; a single missing atlas only costs its own shape", function()
        local W = world(nil, { noAtlas = true })
        local FILES = {
            arrow = "Interface\\Buttons\\UI-CheckBox-Check", star = RAID .. "1", check = "Interface\\Buttons\\UI-CheckBox-Check",
            coin = "Interface\\MoneyFrame\\UI-GoldIcon", circle = RAID .. "2", diamond = RAID .. "3", triangle = RAID .. "4",
            moon = RAID .. "5", square = RAID .. "6", cross = RAID .. "7", skull = RAID .. "8",
        }
        local count = 0
        for _, shape in ipairs(W.EG.Marks.SHAPES) do
            W.EG:Set("markUpgradeShape", shape.id)
            local tex = paintOf(W, "UPGRADE")
            T.eq(tex:GetAtlas(), nil, shape.id) T.eq(tex:GetTexture(), shape.file, shape.id)
            T.eq(shape.file, FILES[shape.id], shape.id .. " has the file it should have")
            count = count + 1
        end
        T.eq(count, 11)
        local W2 = world(nil, { missingAtlas = { ["bags-junkcoin"] = true } })
        W2.EG:Set("markUpgradeShape", "coin")
        T.eq(paintOf(W2, "UPGRADE"):GetTexture(), "Interface\\MoneyFrame\\UI-GoldIcon")
        W2.EG:Set("markUpgradeShape", "star")
        T.eq(paintOf(W2, "UPGRADE"):GetAtlas(), "tradeskills-star")
        W2.EG:Set("markUpgradeShape", "skull")
        T.eq(paintOf(W2, "UPGRADE"):GetTexture(), RAID .. "8", "a shape that has only a file")
    end)

    T.test("look: the check mark follows the look of the upgrade pick and of the sell pick", function()
        local W = world(function(w)
            w.I.a = F.gear(w, 7050, "Reward A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7051, "Reward B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        W.EG:Set("markPickShape", "star") W.EG:Set("markPickColor", "ff3366ff")
        W.EG:Set("markSellShape", "coin") W.EG:Set("markSellColor", "ffffd100")
        local b = quest(W, { W.I.a, W.I.b })
        local tex = b[2].EasyGearCheck
        T.eq(check(b[2]), true)
        T.eq(select(2, W.EG.Contexts.IsRecommended(b[2])), "UPGRADE")
        T.eq(tex:GetAtlas(), "tradeskills-star") T.eq(tex.__desaturated, true)
        local r, g, bl = vertex(tex)
        T.near(r, 0x33 / 255, 1e-9) T.near(g, 0x66 / 255, 1e-9) T.near(bl, 1, 1e-9)
        T.eq(tex:GetWidth(), 20) T.eq(tex:GetHeight(), 20, "the check keeps its size whatever its shape")

        local V = world(function(w)
            w.I.a = F.gear(w, 7052, "Junk A", "INVTYPE_CHEST", 5, { STR = 1 }, { sellPrice = 10 })
            w.I.b = F.gear(w, 7053, "Junk B", "INVTYPE_CHEST", 5, { STR = 1 }, { sellPrice = 30 })
        end)
        V.EG:Set("markPickShape", "star") V.EG:Set("markSellShape", "coin") V.EG:Set("markSellColor", "ffffd100")
        local vb = quest(V, { V.I.a, V.I.b })
        T.eq(check(vb[2]), true) T.eq(select(2, V.EG.Contexts.IsRecommended(vb[2])), "VENDOR")
        tex = vb[2].EasyGearCheck
        T.eq(tex:GetAtlas(), "bags-junkcoin", "chosen for its price: the sell look")
        r, g, bl = vertex(tex)
        T.near(r, 1) T.near(g, 0xd1 / 255, 1e-9) T.near(bl, 0)
        -- the other pick keeps the original when only the sell look was changed
        local W2 = world(function(w)
            w.I.a = F.gear(w, 7054, "Reward A", "INVTYPE_CHEST", 36, { STR = 25 }, { armor = 400 })
            w.I.b = F.gear(w, 7055, "Reward B", "INVTYPE_CHEST", 40, { STR = 30 }, { armor = 500 })
        end)
        W2.EG:Set("markSellShape", "coin")
        local b2 = quest(W2, { W2.I.a, W2.I.b })
        T.eq(b2[2].EasyGearCheck:GetAtlas(), "common-icon-checkmark")
        T.eq(b2[2].EasyGearCheck.__desaturated, false)
    end)

    T.test("look: a change in the settings redraws the visible buttons at once, hidden ones when they show again", function()
        local W = world()
        local shown, hidden = W.bagButton(0, 1), W.bagButton(0, 2)
        W.env.SetItemButtonQuality(shown, 3, W.I.better)
        W.env.SetItemButtonQuality(hidden, 3, W.I.better)
        hidden:Hide()
        W.EG:Set("markUpgradeColor", "ff00ffff") W.flush()
        T.near((select(1, vertex(shown.EasyGearArrow))), 0)
        T.near((select(1, vertex(hidden.EasyGearArrow))), 1, 1e-9, "hidden: not redrawn yet")
        hidden:Show() W.env.SetItemButtonQuality(hidden, 3, W.I.better)
        T.near((select(1, vertex(hidden.EasyGearArrow))), 0, 1e-9, "drawn with the new look when it is set again")
    end)

    T.test("look: WriteChoice and SetChoice accept valid values only, ResetChoice restores the original", function()
        local W = world()
        local M, db = W.EG.Marks, W.env.EasyGearDB
        T.eq(M.WriteChoice("UPGRADE", "bogus"), false) T.eq(M.WriteChoice("NOPE", "star"), false)
        T.eq(M.WriteChoice("UPGRADE", nil, "xyz"), false) T.eq(M.WriteChoice(nil, "star"), false)
        T.eq(M.WriteChoice("UPGRADE", "star", "zzz"), false)
        T.eq(db.markUpgradeShape, "arrow", "a half valid call writes nothing") T.eq(db.markUpgradeColor, "ff40ff40")
        T.eq(M.WriteChoice("UPGRADE", "star", "#FF8800"), true)
        T.eq(db.markUpgradeShape, "star") T.eq(db.markUpgradeColor, "ffff8800", "stored in the form the color field uses")
        T.eq(M.WriteChoice("UPGRADE", "skull"), true) T.eq(db.markUpgradeColor, "ffff8800", "shape only: the color stays")
        T.eq(M.WriteChoice("UPGRADE", nil, "00ff00"), true) T.eq(db.markUpgradeShape, "skull", "color only: the shape stays")
        T.eq(M.WriteChoice("UPGRADE"), true, "nothing to change is fine")

        local calls = 0
        W.EG:Listen("INVALIDATED", function() calls = calls + 1 end)
        T.eq(M.SetChoice("GROUP", "bogus"), false) T.eq(calls, 0, "refused: nothing to redraw")
        T.eq(M.SetChoice("GROUP", "moon", "ff00ff"), true) T.eq(calls, 1, "one redraw for both values")

        M.ResetChoice("UPGRADE")
        T.eq(db.markUpgradeShape, "arrow") T.eq(db.markUpgradeColor, "ff40ff40") T.eq(db.markGroupShape, "moon", "the others stay")
        M.ResetChoice()
        T.eq(db.markGroupShape, "star") T.eq(db.markGroupColor, "ffbf66ff")
        for _, kind in ipairs(M.KINDS) do
            T.eq(db[kind.shapeKey], W.EG.DEFAULTS[kind.shapeKey], kind.id) T.eq(db[kind.colorKey], W.EG.DEFAULTS[kind.colorKey], kind.id)
        end
    end)

    T.test("look: colors are read as AARRGGBB or RRGGBB, with or without a hash", function()
        local W = world()
        local M = W.EG.Marks
        T.eq(M.NormalizeColor("ff8800"), "ffff8800") T.eq(M.NormalizeColor("#FF8800"), "ffff8800")
        T.eq(M.NormalizeColor("80ff8800"), "ffff8800", "the opacity does not count") T.eq(M.NormalizeColor("#80FF8800"), "ffff8800")
        T.eq(M.NormalizeColor("ffFF8800"), "ffff8800")
        for _, bad in ipairs({ "", "ff88", "ff88001", "ff8800001", "gg8800", "ff 800", "##ff8800", "ff8800 ", " ff8800" }) do
            T.eq(M.NormalizeColor(bad), nil, "'" .. bad .. "'")
        end
        T.eq(M.NormalizeColor(nil), nil) T.eq(M.NormalizeColor(123456), nil) T.eq(M.NormalizeColor({}), nil)
        local r, g, b = M.ColorRGB("ff8800")
        T.near(r, 1) T.near(g, 136 / 255, 1e-9) T.near(b, 0)
        T.eq(M.ColorRGB("nope"), nil)
    end)

    T.test("look: the defaults in the settings are valid, complete and the original look", function()
        local W = world()
        local M, defaults = W.EG.Marks, W.EG.DEFAULTS
        local seenShape, seenColor = {}, {}
        for _, kind in ipairs(M.KINDS) do
            T.ok(M.Shape(defaults[kind.shapeKey]), kind.id .. " default shape exists")
            T.eq(M.NormalizeColor(defaults[kind.colorKey]), defaults[kind.colorKey], kind.id .. " default color is in normal form")
            T.ok(not seenShape[kind.shapeKey] and not seenColor[kind.colorKey], "no key is used twice")
            seenShape[kind.shapeKey], seenColor[kind.colorKey] = true, true
            T.eq(M.Kind(kind.id), kind)
            local shape, color = M.Choice(kind.id)
            T.eq(shape, defaults[kind.shapeKey]) T.eq(color, defaults[kind.colorKey])
        end
        local ids = {}
        for _, shape in ipairs(M.SHAPES) do
            T.no(ids[shape.id], "shape " .. shape.id .. " is listed once") ids[shape.id] = true
            T.eq(M.Shape(shape.id), shape)
            T.ok(shape.file, shape.id .. " has a file for clients without the atlas")
        end
        T.eq(M.Kind("NOPE"), nil) T.eq(M.Shape("nope"), nil)
    end)

    T.test("look: the entries of the shape list show the picture and the name", function()
        local W = world()
        local M = W.EG.Marks
        T.eq(M.ShapeLabel(M.Shape("arrow")), "|A:bags-greenarrow:16:16|a Arrow")
        T.eq(M.ShapeLabel(M.Shape("circle")), "|T" .. RAID .. "2:16:16|t Circle")
        T.eq(M.ShapeLabel(M.Shape("skull"), 24), "|T" .. RAID .. "8:24:24|t Skull")
        local N = world(nil, { noAtlas = true })
        T.eq(N.EG.Marks.ShapeLabel(N.EG.Marks.Shape("arrow")), "|TInterface\\Buttons\\UI-CheckBox-Check:16:16|t Arrow")
    end)

    T.test("look: every kind and shape has a name in English and German, every kind a tip", function()
        local W = world()
        local env = { EasyGearLocales = {} }
        for _, code in ipairs({ "enUS", "deDE" }) do
            local chunk = assert(loadfile(T.dir .. "/Locales/" .. code .. ".lua"))
            setfenv(chunk, env) chunk()
        end
        for _, code in ipairs({ "enUS", "deDE" }) do
            local tbl = env.EasyGearLocales[code]
            for _, kind in ipairs(W.EG.Marks.KINDS) do
                T.ok(tbl[kind.name] and tbl[kind.name] ~= "", code .. " " .. kind.name)
                T.ok(tbl[kind.tip] and #tbl[kind.tip] > 20, code .. " " .. kind.tip)
            end
            for _, shape in ipairs(W.EG.Marks.SHAPES) do
                T.ok(tbl[shape.name] and tbl[shape.name] ~= "", code .. " " .. shape.name)
            end
        end
        T.eq(env.EasyGearLocales.deDE.SHAPE_CHECK, "Haken")
    end)
end
