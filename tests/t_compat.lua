-- Compat.lua and the protection of the marks: Baganator and EllesmereUI (models of their interfaces, see wow_mock.lua)
return function(T)
    local F = require("fixtures")

    -- flags: baganator = true | { broken = true } | { noWidgetAPI = true }, ellesmere = true | { noBags = true }
    local function world(flags)
        flags = flags or {}
        local models = {}
        local W = T.world(F.ARMS, function(w)
            w.I = F.armsWarrior(w)
            w.I.better = F.gear(w, 11001, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35 })
            w.I.weak = F.gear(w, 11002, "Weak Chestplate", "INVTYPE_CHEST", 10, { STR = 1 })
            w.I.late = F.gear(w, 11003, "Late Chestplate", "INVTYPE_CHEST", 90, { STR = 90 }, { minLevel = 65 })
            w.I.potion = F.gear(w, 11004, "Potion", "", 1, {})
            if flags.baganator then models.B = w.installBaganator(type(flags.baganator) == "table" and flags.baganator or nil) end
            if flags.ellesmere then models.E = w.installEllesmere(type(flags.ellesmere) == "table" and flags.ellesmere or nil) end
        end)
        return W, models.B, models.E
    end
    local function arrow(b) return b.EasyGearArrow and b.EasyGearArrow:IsShown() or false end

    ------------------------------------------------------------------ Baganator
    T.test("baganator: the arrow is registered as a corner widget (top right) and as an upgrade source", function()
        local W, B = world({ baganator = true })
        local w = B.widgets.easygear
        T.ok(w, "corner widget registered")
        T.eq(w.label, W.EG.L.COMPAT_WIDGET) T.eq(w.isFast, false, "Baganator budgets the work itself")
        T.eq(B.corners.easygear, "top_right", "the corner that is empty in Baganator's default layout")
        T.ok(B.plugins.easygear and B.plugins.easygear.label == "EasyGear", "upgrade source registered")
        T.eq(B.upgradePlugin, "easygear", "selected when nothing else is")
        T.eq(W.EG.hookStatus.baganator.ok, true)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("baganator: the widget shows the green arrow for an upgrade, the yellow one for a level, nothing otherwise", function()
        local W, B = world({ baganator = true })
        local b = B.button()
        local widget = b.cornerPlugins.easygear
        T.ok(widget, "onInit built the widget") T.eq(widget:GetObjectType(), "Texture")
        T.eq(widget.__atlas, "bags-greenarrow") T.eq(widget:GetWidth(), 15)

        T.eq(B.update(b, W.I.better), "easygear") T.eq(widget:IsShown(), true) T.eq(widget.__desaturated, false)
        T.eq(B.update(b, W.I.weak), nil) T.eq(widget:IsShown(), false, "a weaker item")
        T.eq(B.update(b, W.I.late), "easygear") T.eq(widget.__desaturated, true, "yellow: the level does not reach yet")
        T.near(widget.__vertex[1], 1.0) T.near(widget.__vertex[3], 0)
        T.eq(B.update(b, W.I.better), "easygear") T.eq(widget.__desaturated, false, "the next item is green again")
        T.eq(B.update(b, W.I.potion), nil, "not gear")
        T.eq(B.update(b, nil), nil, "empty slot")
        T.eq(b.__pending, false)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("baganator: an item that is not loaded yet answers 'not yet', then the arrow follows", function()
        local W, B = world({ baganator = true })
        local b = B.button()
        local slow = F.gear(W, 11005, "Slow Chestplate", "INVTYPE_CHEST", 60, { STR = 60 }, { uncached = true })
        T.eq(B.update(b, slow), nil) T.eq(b.__pending, true, "nil is what makes Baganator ask again")
        W.state.items[11005].uncached = nil
        T.eq(B.update(b, slow), "easygear") T.eq(b.__pending, false)
    end)

    T.test("baganator: the setting for bag markers switches the widget and the source off", function()
        local W, B = world({ baganator = true })
        local b = B.button()
        W.EG:Set("showBagIcons", false)
        T.eq(B.update(b, W.I.better), nil)
        T.eq(B.isUpgrade(W.I.better), false)
        W.EG:Set("showBagIcons", true)
        T.eq(B.update(b, W.I.better), "easygear") T.eq(B.isUpgrade(W.I.better), true)
    end)

    T.test("baganator: its buttons get no marks of their own from the hooks of the interface", function()
        local W, B = world({ baganator = true })
        local b = B.button()
        B.update(b, W.I.better)                            -- Baganator sets the quality through the method of the button ...
        T.eq(b.EasyGearArrow, nil) T.eq(b.EasyGearHost, nil) T.eq(W.EG.Marks.registry[b], nil)
        W.env.SetItemButtonQuality(b, 3, W.I.better)         -- ... but if the global function ever reaches such a button
        T.eq(b.EasyGearArrow, nil) T.eq(W.EG.Marks.registry[b], nil)
        -- a Baganator button before its first update (no details yet) is recognised by its corner machinery
        local fresh = B.button()
        fresh.BGR = nil
        W.env.SetItemButtonQuality(fresh, 3, W.I.better)
        T.eq(fresh.EasyGearArrow, nil)
        -- an old registration is dropped
        local other = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(other, 3, W.I.better)
        T.eq(arrow(other), true, "a button of the interface is marked")
        other.widgetContainer = W.env.CreateFrame("Frame", nil, other)      -- ... until Baganator takes it over
        W.env.SetItemButtonQuality(other, 3, W.I.better)
        T.eq(arrow(other), false)
        -- each of the three signs of Baganator is enough on its own
        for _, sign in ipairs({ "BGR", "cornerPlugins", "widgetContainer" }) do
            local single = W.bagButton(0, 2)
            single[sign] = (sign == "widgetContainer") and W.env.CreateFrame("Frame", nil, single) or {}
            W.env.SetItemButtonQuality(single, 3, W.I.better)
            T.eq(single.EasyGearArrow, nil, sign)
        end
    end)

    T.test("baganator: the upgrade source answers yes, no and 'not yet'", function()
        local W, B = world({ baganator = true })
        T.eq(B.isUpgrade(W.I.better), true)
        T.eq(B.isUpgrade(W.I.weak), false) T.eq(B.isUpgrade(W.I.late), false, "a level that does not reach is no upgrade yet")
        T.eq(B.isUpgrade(W.I.potion), false) T.eq(B.isUpgrade(nil), false)
        local slow = F.gear(W, 11006, "Slow Chestplate", "INVTYPE_CHEST", 60, { STR = 60 }, { uncached = true })
        local yes, raw = B.isUpgrade(slow)
        T.eq(yes, false) T.eq(raw, nil, "nil: the item information is not there yet")
    end)

    T.test("baganator: Baganator is asked to redraw after gear, profile and level changes and when items arrive", function()
        local W, B = world({ baganator = true })
        T.eq(#B.refreshes, 0)
        W.equip(5, W.I.better)
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        W.flush()
        T.ok(#B.refreshes >= 1, "after an equipment change")
        T.eq(B.refreshes[#B.refreshes][1], "item_widgets") T.eq(B.refreshes[#B.refreshes][2], "searches")
        W.EG.Profiles.SetActive("WARRIOR_PROT")
        local n = #B.refreshes - 1
        W.EG.Profiles.SetActive("WARRIOR_ARMS")
        W.flush()
        T.ok(#B.refreshes > n, "after a profile change") n = #B.refreshes
        W.setLevel(59)
        W.flush()
        T.ok(#B.refreshes > n, "after a level up") n = #B.refreshes
        W.fire("GET_ITEM_INFO_RECEIVED", 11001, true)
        W.flush()
        T.ok(#B.refreshes > n, "when item information arrives")
    end)

    T.test("baganator: a burst of changes becomes one request, and none while neither widget nor source is used", function()
        local W, B = world({ baganator = true })
        for _ = 1, 5 do W.EG:InvalidateAll() end
        W.flush()
        T.eq(#B.refreshes, 1, "debounced")
        B.corners.easygear = nil                             -- the user took the arrow out of the corners ...
        B.upgradePlugin = "pawn"                             -- ... and chose another upgrade source
        W.EG:InvalidateAll()
        W.flush()
        T.eq(#B.refreshes, 1, "no work for a feature that is not used")
        B.upgradePlugin = "easygear"                         -- the source is used again (and the widget not)
        W.EG:InvalidateAll()
        W.flush()
        T.eq(#B.refreshes, 2) T.eq(B.refreshes[2][1], "item_widgets") T.eq(B.refreshes[2][2], "searches")
        B.corners.easygear = "top_right"                     -- only the widget is used: no search to redo
        B.upgradePlugin = "pawn"
        W.EG:InvalidateAll()
        W.flush()
        T.eq(#B.refreshes, 3) T.eq(B.refreshes[3][1], "item_widgets") T.eq(B.refreshes[3][2], nil)
    end)

    T.test("baganator: an error inside EasyGear never reaches Baganator", function()
        local W, B = world({ baganator = true })
        local b = B.button()
        W.EG.Score.UpgradeState = function() error("boom") end
        W.clearChat()
        local ok = pcall(B.update, b, W.I.better)
        T.eq(ok, true, "the update of Baganator's button went through")
        T.eq(b.cornerPlugins.easygear:IsShown(), false)
        T.eq(W.EG.lastError.label, "baganator") T.has(W.chatText(), "boom")
        T.eq(B.isUpgrade(W.I.better), false, "and the source answers no")
        W.clearChat()
        pcall(B.update, b, W.I.better)
        T.eq(W.chatText(), "", "the message is printed once")
    end)

    T.test("baganator: not installed - nothing registers, nothing is reported", function()
        local W = world()
        T.eq(W.env.Baganator, nil) T.eq(W.EG.hookStatus.baganator, nil) T.eq(W.EG.lastError, nil)
        local lines = table.concat(W.EG.Compat.StatusLines(), "\n")
        T.has(lines, "Baganator: not installed") T.has(lines, "EllesmereUI: not installed")
    end)

    T.test("baganator: an interface that does not fit is reported, not fatal", function()
        local W = world({ baganator = { noWidgetAPI = true } })
        T.eq(W.EG.hookStatus.baganator.ok, false)
        T.has(table.concat(W.EG.Compat.StatusLines(), "\n"), "Baganator: found, but its interface is not usable")
        T.has(W.chatText(), W.EG.L.HOOKS_FAILED)
        W = world({ baganator = { broken = true } })
        T.eq(W.EG.hookStatus.baganator.ok, false) T.eq(W.EG.lastError, nil)
        T.has(W.EG.hookStatus.baganator.note, "assertion failed")
    end)

    T.test("baganator: without Syndicator it does not start - nothing is registered, and the status says why", function()
        local W, B = world({ baganator = { noSyndicator = true } })
        T.ok(B.B.API.RegisterCornerWidget, "its interface is there")
        T.eq(B.widgets.easygear, nil) T.eq(B.plugins.easygear, nil) T.eq(B.corners.easygear, nil)
        T.eq(W.EG.hookStatus.baganator.ok, false) T.has(W.EG.hookStatus.baganator.note, "Syndicator")
        T.has(table.concat(W.EG.Compat.StatusLines(), "\n"), "Baganator: found, but its interface is not usable (Syndicator)")
        T.has(W.chatText(), W.EG.L.HOOKS_FAILED)
        W.EG:InvalidateAll() W.flush()
        T.eq(#B.refreshes, 0, "no requests to a Baganator that does not run")
        T.eq(W.EG.lastError, nil)
        -- with Syndicator everything is as usual
        W = world({ baganator = true })
        T.eq(W.EG.hookStatus.baganator.ok, true)
    end)

    T.test("baganator: the status lists what is connected", function()
        local W = world({ baganator = true })
        T.has(table.concat(W.EG.Compat.StatusLines(), "\n"), "Baganator: arrow registered as a corner widget")
        W.clearChat()
        W.slash("status")
        T.has(W.chatText(), "Baganator: arrow registered") T.has(W.chatText(), "EllesmereUI: not installed")
    end)

    ------------------------------------------------------------------ EllesmereUI
    T.test("ellesmere: the arrow is painted through the overlay interface of its Bags module, at the top right", function()
        local W, _, E = world({ ellesmere = true })
        T.ok(E.bags.itemOverlayIcons.EasyGear, "painter registered") T.eq(W.EG.hookStatus.ellesmere.ok, true)
        local b = E.slot(0, 3)
        E.render(b, W.I.better)
        T.eq(arrow(b), true)
        local point, rel = b.EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPRIGHT", "the item level sits at the top left") T.eq(rel, b._textOverlay, "the layer above the icon")
        T.eq(b.EasyGearArrow:GetWidth(), 16)
        T.eq(W.EG.Marks.registry[b].ctx, "bag")
        E.render(b, W.I.weak)
        T.eq(arrow(b), false)
        E.render(b, W.I.late)
        T.eq(arrow(b), true) T.eq(b.EasyGearArrow.__desaturated, true, "yellow for a level")
        T.eq(W.EG.lastError, nil) T.eq(#E.overlayErrors, 0)
    end)

    T.test("ellesmere: the arrow is half as high as the icon under it, between 8 and 16 pixels", function()
        local W, _, E = world({ ellesmere = true })
        local function sizeFor(height, asRow)
            local b = E.slot(0, 1, asRow)
            if height ~= "model" then b._textOverlay:SetHeight(height) end
            E.render(b, W.I.better)
            return b.EasyGearArrow:GetWidth(), b.EasyGearArrow:GetHeight()
        end
        T.eq(sizeFor("model"), 16, "a regular grid slot (37 pixels)")
        T.eq(sizeFor(32), 16) T.eq(sizeFor(31), 15) T.eq(sizeFor(28), 14)
        T.eq(sizeFor("model", true), 10, "the 20 pixel icon of a list row")
        T.eq(sizeFor(17), 8) T.eq(sizeFor(12), 8, "never smaller than 8") T.eq(sizeFor(1), 8)
        T.eq(sizeFor(200), 16, "never larger than 16")
        T.eq(sizeFor(0), 16, "the height is not known yet - the full size")
        T.eq(sizeFor(nil), 16)
        local w, h = sizeFor(24)
        T.eq(w, 12) T.eq(h, 12, "square")
        -- the size follows the slot when the player resizes the bag slots: the next paint uses the new one
        local b = E.slot(0, 2)
        E.render(b, W.I.better)
        T.eq(b.EasyGearArrow:GetWidth(), 16)
        b._textOverlay:SetSize(22, 22)
        E.render(b, W.I.better)
        T.eq(b.EasyGearArrow:GetWidth(), 11)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("ellesmere: the rows of the list view get the arrow at the top right of their icon", function()
        local W, _, E = world({ ellesmere = true })
        local row = E.slot(0, 1, true)
        T.eq(row.ItemLevelText, nil, "a row has no item level text") T.ok(row._lvIcon, "but a row icon")
        T.eq(W.EG.Compat.HostOf(row), "ellesmere")
        E.render(row, W.I.better)
        T.eq(arrow(row), true)
        local point, rel = row.EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPRIGHT") T.eq(rel, row._textOverlay, "the layer over the row icon")
        T.eq(row.EasyGearArrow:GetWidth(), 10)
        W.env.SetItemButtonQuality(row, 3, W.I.late)         -- the interface's own hook leaves the row alone
        T.eq(row.EasyGearArrow.__desaturated, false, "the painter's green arrow is untouched")
        E.render(row, nil)
        T.eq(arrow(row), false)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("ellesmere: the frame with the marks follows the frame levels the bags give their buttons later", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        b._textOverlay:SetFrameLevel(12)
        E.render(b, W.I.better)
        T.eq(b.EasyGearHost:GetFrameLevel(), 20, "overlay + 8")
        b._textOverlay:SetFrameLevel(112)                    -- the window is raised: the levels of its buttons are set anew
        E.render(b, W.I.better)
        T.eq(b.EasyGearHost:GetFrameLevel(), 120, "back above the overlay")
        b._textOverlay:SetFrameLevel(30)
        W.EG:InvalidateAll() W.flush()                       -- a refresh without a paint of the bags does the same
        T.eq(b.EasyGearHost:GetFrameLevel(), 38)
        T.eq(arrow(b), true)
        -- one more owner: a button of the interface keeps its own frame at the right level above the button
        local plain = W.bagButton(0, 5)
        plain:SetFrameLevel(10)
        W.env.SetItemButtonQuality(plain, 3, W.I.better)
        T.eq(plain.EasyGearHost:GetFrameLevel(), 18)
        plain:SetFrameLevel(60)
        W.env.SetItemButtonQuality(plain, 3, W.I.better)
        T.eq(plain.EasyGearHost:GetFrameLevel(), 68)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("ellesmere: an emptied slot loses the arrow (the painter runs for empty slots too), a refilled one gets it", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        E.render(b, W.I.better)
        T.eq(arrow(b), true)
        E.render(b, nil)
        T.eq(arrow(b), false)
        W.EG:InvalidateAll() W.flush()
        T.eq(arrow(b), false, "a refresh does not bring a stale mark back")
        E.render(b, W.I.better)
        T.eq(arrow(b), true)
    end)

    T.test("ellesmere: the marks follow gear, profile and setting changes without the bags drawing again", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        E.render(b, W.I.better)
        T.eq(arrow(b), true)
        W.equip(5, W.I.better)                               -- wearing it: no longer an upgrade
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        W.flush()
        T.eq(arrow(b), false)
        W.equip(5, nil)
        W.fire("PLAYER_EQUIPMENT_CHANGED", 5)
        W.flush()
        T.eq(arrow(b), true)
        W.EG:Set("showBagIcons", false)
        W.flush()
        T.eq(arrow(b), false)
    end)

    T.test("ellesmere: the window skin fades textures of a button, the marks sit on a frame of their own", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        E.render(b, W.I.better)
        T.ok(b.EasyGearHost, "own frame") T.eq(b.EasyGearArrow:GetParent(), b.EasyGearHost)
        T.eq(b.EasyGearHost:GetParent(), b._textOverlay, "hangs on the layer the module gives to third parties")
        T.ok(b.EasyGearHost:GetFrameLevel() > b._textOverlay:GetFrameLevel())
        b:CreateTexture(nil, "BACKGROUND")                   -- a texture of the button's own, faded by the skin
        E.fade(b) E.fade(b._textOverlay)
        T.eq(b.EasyGearArrow:GetAlpha(), 1) T.eq(arrow(b), true)
        -- the same holds for the buttons of the interface that the skin restyles (vendor, loot, mail, quest rewards, ...)
        local mail = W.namedButton("OpenMailAttachmentButton1", 1)
        W.env.SetItemButtonQuality(mail, 3, W.I.better)
        E.fade(mail)
        T.eq(mail.EasyGearArrow:GetAlpha(), 1) T.eq(arrow(mail), true)
        local quest = W.questRewards({ { link = W.I.better }, { link = W.I.weak } })
        W.showRewards()
        E.fade(quest[1]) E.fade(quest[2])
        T.eq(arrow(quest[1]), true) T.eq(quest[1].EasyGearArrow:GetAlpha(), 1)
    end)

    T.test("ellesmere: a fallback arrow on the button itself repairs the alpha the skin took away", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        local create = W.env.CreateFrame
        W.env.CreateFrame = function(kind, name, parent, template)
            if kind == "Frame" and parent == b._textOverlay then error("forbidden owner") end
            return create(kind, name, parent, template)
        end
        E.render(b, W.I.better)                              -- no frame can be made: the textures sit on the button
        T.eq(b.EasyGearHost, nil) T.eq(arrow(b), true)
        E.fade(b)
        T.eq(b.EasyGearArrow:GetAlpha(), 0, "the skin got it")
        W.env.CreateFrame = create
        W.EG:InvalidateAll() W.flush()
        T.eq(b.EasyGearArrow:GetAlpha(), 1, "the next refresh paints it again")
    end)

    T.test("ellesmere: its buttons are left to the painter - the hooks of the interface do not mark them a second time", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)         -- if the interface ever calls the global function for them
        T.eq(b.EasyGearArrow, nil) T.eq(W.EG.Marks.registry[b], nil)
        E.render(b, W.I.better)
        T.eq(arrow(b), true)
        W.env.SetItemButtonQuality(b, 3, W.I.weak)           -- still no second marker, and the painter's one is untouched
        T.eq(arrow(b), true)
        T.eq(W.EG.Compat.HostOf(b), "ellesmere")
    end)

    T.test("ellesmere: an error inside the painter is contained and reported once", function()
        local W, _, E = world({ ellesmere = true })
        local b = E.slot(0, 1)
        W.EG.Marks.Set = function() error("boom") end
        W.clearChat()
        E.render(b, W.I.better)
        T.eq(#E.overlayErrors, 0, "EasyGear's painter caught it itself")
        T.eq(W.EG.lastError.label, "ellesmere") T.has(W.chatText(), "boom")
    end)

    T.test("ellesmere: bags without the overlay interface, and EllesmereUI without its Bags module, are reported", function()
        local W = world({ ellesmere = { noOverlayAPI = true } })
        T.eq(W.EG.hookStatus.ellesmere.ok, false)
        T.has(table.concat(W.EG.Compat.StatusLines(), "\n"), "without its overlay interface")
        W = world({ ellesmere = { noBags = true } })
        T.eq(W.EG.hookStatus.ellesmere, nil)
        T.has(table.concat(W.EG.Compat.StatusLines(), "\n"), "Bags module: not loaded")
    end)

    T.test("ellesmere: buttons of the interface and of other bag addons keep the standard place", function()
        local W = world({ ellesmere = true })
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        local point = b.EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPLEFT") T.eq(b.EasyGearArrow:GetWidth(), 18)
        -- the text overlay of EllesmereUI alone does not make a button its own - it needs the item level text of a grid
        -- slot or the row icon of a list row besides
        local half = W.bagButton(0, 2)
        half._textOverlay = W.env.CreateFrame("Frame", nil, half)
        W.env.SetItemButtonQuality(half, 3, W.I.better)
        T.eq((half.EasyGearArrow:GetPoint(1)), "TOPLEFT")
        T.eq(W.EG.Compat.HostOf(half), nil) T.eq(W.EG.Compat.HostOf("junk"), nil) T.eq(W.EG.Compat.HostOf(nil), nil)
        local onlyText = W.bagButton(0, 3)
        onlyText.ItemLevelText = onlyText:CreateFontString(nil, "OVERLAY")
        T.eq(W.EG.Compat.HostOf(onlyText), nil, "an item level text alone")
        local onlyRow = W.bagButton(0, 4)
        onlyRow._lvIcon = onlyRow:CreateTexture(nil, "ARTWORK")
        T.eq(W.EG.Compat.HostOf(onlyRow), nil, "a row icon alone")
        half._lvIcon = half:CreateTexture(nil, "ARTWORK")
        T.eq(W.EG.Compat.HostOf(half), "ellesmere", "overlay and row icon")
    end)

    ------------------------------------------------------------------ EllesmereUI vendor list ("Show As List")
    --[[ In the list view of its vendor window EllesmereUI sizes the item button to the whole row and uses the SlotTexture of
         the row as the icon (the button shows no picture). The standard window has a square button with the slot
         background behind it. EllesmereUI sets the stock text of its rows AFTER the quality; the standard window before. ]]
    local function vendorRow(W, width, height, name)
        local frame = W.env.CreateFrame("Frame")
        frame.SlotTexture = frame:CreateTexture(nil, "BACKGROUND")
        frame.ItemButton = W.namedButton(name or "EUI_MerchantItem1ItemButton", 1)
        frame.ItemButton:SetSize(width, height)
        frame.ItemButton.Stock = W.env.CreateFrame("Frame", nil, frame.ItemButton)
        frame.ItemButton.Stock:Hide()
        return frame
    end

    T.test("ellesmere vendor list: the arrow sits at the corner of the row icon, not at the end of the whole row", function()
        local W = world({ ellesmere = true })
        local row = vendorRow(W, 300, 32)
        W.env.MerchantFrameItem_UpdateQuality(row, W.I.better, false)
        local btn = row.ItemButton
        T.eq(arrow(btn), true)
        local point, rel = btn.EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPLEFT") T.eq(rel, row.SlotTexture, "the row icon is the SlotTexture")
        T.eq(btn.EasyGearArrow:GetWidth(), 18)
        -- the stock text sits at the same corner: the arrow goes to the other corner OF THE ICON
        btn.Stock:Show()
        W.env.MerchantFrameItem_UpdateQuality(row, W.I.better, false)
        point, rel = btn.EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPRIGHT") T.eq(rel, row.SlotTexture)
        -- a worse item, a sold out row
        W.env.MerchantFrameItem_UpdateQuality(row, W.I.weak, false)
        T.eq(arrow(btn), false)
        W.env.MerchantFrameItem_UpdateQuality(row, nil, false)
        T.eq(arrow(btn), false)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("ellesmere vendor list: the stock text arrives after the quality - the arrow gives way when it appears", function()
        local W = world({ ellesmere = true })
        local row = vendorRow(W, 300, 32)
        local btn = row.ItemButton
        W.env.MerchantFrameItem_UpdateQuality(row, W.I.better, false)       -- EllesmereUI: quality first ...
        T.eq((btn.EasyGearArrow:GetPoint(1)), "TOPLEFT", "no stock text yet")
        W.env.SetItemButtonStock(btn, 5)                                    -- ... then the stock
        T.eq((btn.EasyGearArrow:GetPoint(1)), "TOPRIGHT", "the number is at the top left now")
        T.eq(arrow(btn), true)
        W.env.MerchantFrameItem_UpdateQuality(row, W.I.better, false)       -- the next row use: the number is still there ...
        W.env.SetItemButtonStock(btn, 0)                                    -- ... until the stock is gone
        T.eq((btn.EasyGearArrow:GetPoint(1)), "TOPLEFT", "and the arrow is back at the corner")
        -- the row changes to another item whose stock text is shown
        W.env.MerchantFrameItem_UpdateQuality(row, W.I.weak, false)
        W.env.SetItemButtonStock(btn, 3)
        T.eq(arrow(btn), false, "a worse item gets no arrow, however the stock changes")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("ellesmere vendor list: the standard vendor window keeps the arrow at the icon of its square button", function()
        local W = world({ ellesmere = true })
        local std = vendorRow(W, 37, 37, "MerchantItem1ItemButton")          -- SlotTexture is only the background there
        W.env.MerchantFrameItem_UpdateQuality(std, W.I.better, false)
        local point, rel = std.ItemButton.EasyGearArrow:GetPoint(1)
        T.eq(point, "TOPLEFT")
        T.ok(rel ~= std.SlotTexture, "not the background behind the button")
        T.eq(rel, std.ItemButton.Icon or std.ItemButton.icon or std.ItemButton)
        -- not wide enough to be a row: 1.5 times the height is the limit
        local almost = vendorRow(W, 55, 37, "MerchantItem3ItemButton")
        W.env.MerchantFrameItem_UpdateQuality(almost, W.I.better, false)
        T.ok(select(2, almost.ItemButton.EasyGearArrow:GetPoint(1)) ~= almost.SlotTexture)
        local wide = vendorRow(W, 56, 37, "MerchantItem4ItemButton")
        W.env.MerchantFrameItem_UpdateQuality(wide, W.I.better, false)
        T.eq(select(2, wide.ItemButton.EasyGearArrow:GetPoint(1)), wide.SlotTexture)
        -- the same button can change its mode: the next use decides
        W.env.MerchantFrameItem_UpdateQuality(wide, W.I.better, false)
        wide.ItemButton:SetSize(37, 37)
        W.env.MerchantFrameItem_UpdateQuality(wide, W.I.better, false)
        T.ok(select(2, wide.ItemButton.EasyGearArrow:GetPoint(1)) ~= wide.SlotTexture)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("ellesmere vendor list: frames without a usable row icon, and stock calls for unmarked buttons, are harmless", function()
        local W = world({ ellesmere = true })
        for _, junk in ipairs({ "text", 5, true, {} }) do
            local row = vendorRow(W, 300, 32)
            row.SlotTexture = junk                           -- no region at all
            W.env.MerchantFrameItem_UpdateQuality(row, W.I.better, false)
            T.eq(arrow(row.ItemButton), true, tostring(junk))
            T.ok(select(2, row.ItemButton.EasyGearArrow:GetPoint(1)) ~= junk)
        end
        local bare = { ItemButton = W.namedButton("MerchantItem7ItemButton", 7) }      -- no SlotTexture at all
        bare.ItemButton:SetSize(300, 32)
        W.env.MerchantFrameItem_UpdateQuality(bare, W.I.better, false)
        T.eq(arrow(bare.ItemButton), true)
        local unsized = vendorRow(W, 300, 32)
        unsized.ItemButton:SetSize(nil, nil)
        W.env.MerchantFrameItem_UpdateQuality(unsized, W.I.better, false)
        T.eq(arrow(unsized.ItemButton), true, "a button whose size is not known yet counts as a regular one")
        local zero = vendorRow(W, 300, 0)
        W.env.MerchantFrameItem_UpdateQuality(zero, W.I.better, false)
        T.eq(arrow(zero.ItemButton), true)
        T.ok(select(2, zero.ItemButton.EasyGearArrow:GetPoint(1)) ~= zero.SlotTexture, "no height, no row")
        -- the stock hook only touches buttons that carry a mark
        local unmarked = W.namedButton("MerchantItem9ItemButton", 9)
        unmarked.Stock = W.env.CreateFrame("Frame", nil, unmarked)
        W.env.SetItemButtonStock(unmarked, 4)
        T.eq(W.EG.Marks.registry[unmarked], nil) T.eq(unmarked.EasyGearArrow, nil)
        W.env.SetItemButtonStock(nil, 4)
        T.eq(W.EG.lastError, nil)
        T.eq(W.EG.hookStatus.merchantstock.ok, true)
    end)

    T.test("ellesmere: the status says what was found", function()
        local W = world({ ellesmere = true })
        local lines = table.concat(W.EG.Compat.StatusLines(), "\n")
        T.has(lines, "EllesmereUI: found") T.has(lines, "Bags module: arrow through its overlay interface")
    end)

    T.test("compat: both together - Baganator's buttons use its widget, EllesmereUI's buttons the arrow at the top right", function()
        local W, B, E = world({ baganator = true, ellesmere = true })
        local bag = B.button()
        T.eq(B.update(bag, W.I.better), "easygear") T.eq(bag.EasyGearArrow, nil)
        local slot = E.slot(1, 2)
        E.render(slot, W.I.better)
        T.eq(arrow(slot), true) T.eq(slot.cornerPlugins, nil)
        T.eq(W.EG.lastError, nil)
    end)
end
