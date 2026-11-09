-- Options.lua: settings page and addon compartment
return function(T)
    local F = require("fixtures")

    local function world(setup, opts)
        return T.world(F.arms(opts), function(W)
            W.I = F.armsWarrior(W)
            W.I.better = F.gear(W, 9001, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500 })
            if setup then setup(W) end
        end)
    end
    local function category(W) return W.state.settings[1] end

    T.test("options: one category with checkboxes, sliders, dropdowns, color fields and buttons", function()
        local W = world()
        local cat = category(W)
        T.ok(cat, "category registered") T.eq(cat.name, "EasyGear") T.eq(cat.registered, true)
        local kinds = {}
        for _, c in ipairs(cat.controls) do kinds[c.kind] = (kinds[c.kind] or 0) + 1 end
        T.eq(kinds.checkbox, 13) T.eq(kinds.slider, 2) T.eq(kinds.dropdown, 6, "the profile and a shape list for each of the 5 kinds")
        T.eq(kinds.swatch, 5, "a color field for each kind")
        local headers, buttons = 0, 0
        for _, init in ipairs(cat.initializers) do
            if init.kind == "header" then headers = headers + 1 end
            if init.kind == "button" then buttons = buttons + 1 end
        end
        T.eq(headers, 6) T.eq(buttons, 2, "reset the marker look, reset all settings")
        T.eq(W.EG.hookStatus.settings.ok, true)
    end)

    T.test("options: every control has a name and a tooltip from the language file", function()
        local W = world()
        for _, c in ipairs(category(W).controls) do
            if c.kind ~= "dropdown" or c.tooltip then
                T.ok(c.tooltip and c.tooltip ~= "", "tooltip of " .. tostring(c.setting.variable))
            end
            T.ok(W.EG:LocaleHas((c.setting.name and "x") and "TITLE" or "TITLE"))
            T.ok(not c.setting.name:match("^OPT_"), "name resolved: " .. c.setting.name)
        end
    end)

    T.test("options: the settings write into EasyGearDB and take effect immediately", function()
        local W = world()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        T.eq(b.EasyGearArrow:IsShown(), true)
        local s = W.state.settingByVariable.EasyGear_showBagIcons
        T.eq(s:GetValue(), true)
        s:SetValue(false)
        T.eq(W.env.EasyGearDB.showBagIcons, false)
        W.flush()
        T.eq(b.EasyGearArrow:IsShown(), false, "marker follows the setting")

        local slider = W.state.settingByVariable.EasyGear_ilvlWeight
        T.eq(slider:GetValue(), 0.5)
        local before = W.EG.Score.OfLink(W.I.chest)
        slider:SetValue(1.0)
        T.eq(W.EG:Get("ilvlWeight"), 1.0)
        T.near(W.EG.Score.OfLink(W.I.chest) - before, 15)
    end)

    T.test("options: the slider ranges and labels", function()
        local W = world()
        local sliders = {}
        for _, c in ipairs(category(W).controls) do if c.kind == "slider" then sliders[#sliders + 1] = c end end
        T.eq(sliders[1].options.minValue, 0) T.eq(sliders[1].options.maxValue, 2) T.near(sliders[1].options.steps, 40)
        T.eq(sliders[1].options.formatter(0.55), "0.55")
        T.eq(sliders[2].options.formatter(1), "1.0 %")
    end)

    T.test("options: the profile dropdown lists automatic plus every profile and sets the character profile", function()
        local W = world()
        local dd
        for _, c in ipairs(category(W).controls) do if c.kind == "dropdown" then dd = c end end
        local opts = dd.getOptions()
        T.eq(opts[1].value, "AUTO") T.has(opts[1].label, "Automatic")
        T.eq(#opts, 1 + 5 + 2)
        T.eq(dd.setting:GetValue(), "AUTO")
        dd.setting:SetValue("WARRIOR_FURY")
        T.eq(W.EG.Profiles.ActiveID(), "WARRIOR_FURY")
        W.state.settingsOpen = true
        W.EG.Profiles.SetActive("AUTO")
        T.ok((W.state.settingByVariable.EasyGear_PROFILE.notified or 0) >= 1, "the page is told when the profile changes elsewhere")
    end)

    T.test("options: the reset button asks first, resets the settings and keeps own profiles", function()
        local W = world()
        local reset
        for _, init in ipairs(category(W).initializers) do if init.kind == "button" then reset = init end end
        W.EG:Set("tooltipDiff", false)
        local id = W.EG.Profiles.CreateCustom("Keep Me", "WARRIOR_ARMS")
        reset.onClick()
        local dlg = W.state.popups[#W.state.popups]
        T.eq(dlg.which, "GENERIC_CONFIRMATION")
        T.eq(W.env.EasyGearDB.tooltipDiff, false, "nothing happens before confirming")
        dlg.data.callback()
        T.eq(W.env.EasyGearDB.tooltipDiff, true)
        T.ok(W.EG.Profiles.Get(id), "own profiles survive a reset")
    end)

    T.test("options: Open goes to the category", function()
        local W = world()
        T.eq(W.EG.Options.Open(), true)
        T.eq(W.state.opened[#W.state.opened], category(W):GetID())
    end)

    T.test("options: the addon compartment functions", function()
        local W = world()
        local env = W.env
        env.EasyGear_OnAddonCompartmentClick("EasyGear", "LeftButton")
        T.eq(W.EG.Window.IsShown(), true)
        env.EasyGear_OnAddonCompartmentClick("EasyGear", "LeftButton")
        T.eq(W.EG.Window.IsShown(), false, "toggles")
        env.EasyGear_OnAddonCompartmentClick("EasyGear", "RightButton")
        T.eq(#W.state.opened, 1)
        local owner = W.env.CreateFrame("Frame")
        env.EasyGear_OnAddonCompartmentEnter("EasyGear", owner)
        local tip = env.GameTooltip
        T.eq(tip:GetOwner(), owner)
        T.has(tip:Dump(), "EasyGear 4.0.0-test") T.has(tip:Dump(), "Left click") T.has(tip:Dump(), "Profile: Arms")
        env.EasyGear_OnAddonCompartmentLeave()
        T.eq(tip.__shown, false)
    end)

    T.test("options: the TOC names exist as functions", function()
        local toc = io.open(T.dir .. "/EasyGear.toc"):read("*a")
        local W = world()
        for field, fname in toc:gmatch("## (AddonCompartmentFunc[%w]*):%s*([%w_]+)") do
            T.eq(type(W.env[fname]), "function", field)
        end
        T.has(toc, "## SavedVariables: EasyGearDB")
        T.has(toc, "## SavedVariablesPerCharacter: EasyGearCharDB")
    end)

    T.test("options: without a settings interface the addon still starts and says so", function()
        local W = world(nil, { noSettings = true })
        T.eq(W.EG.hookStatus.settings.ok, false)
        W.clearChat()
        T.eq(W.EG.Options.Open(), false)
        T.has(W.chatText(), "settings page is not available")
    end)

    T.test("options: only values that changed elsewhere reach an open page - without a loop or a click for every setting", function()
        local W = world()
        W.state.settingsOpen = true
        local s = W.state.settingByVariable
        local function told()
            local names = {}
            for var, st in pairs(s) do if (st.notified or 0) > 0 then names[#names + 1] = var .. "=" .. st.notified end end
            table.sort(names)
            return table.concat(names, " ")
        end
        local calls = 0
        W.EG:Listen("INVALIDATED", function() calls = calls + 1 end)

        W.slash("ilvl 0.9")
        T.eq(calls, 1, "one invalidation - the notification of the page started no second one")
        T.eq(told(), "EasyGear_ilvlWeight=1", "only the changed setting is told (a checkbox would click)")
        T.eq(s.EasyGear_ilvlWeight:GetValue(), 0.9)

        -- a change on the page itself tells nobody: the control shows it already
        calls = 0
        s.EasyGear_showBagIcons:SetValue(false)
        T.eq(calls, 1)
        T.eq(W.env.EasyGearDB.showBagIcons, false)
        T.eq(told(), "EasyGear_ilvlWeight=1", "no one was told about the page's own change")
        W.slash("icons on")
        T.eq(told(), "EasyGear_ilvlWeight=1 EasyGear_showBagIcons=1", "but a chat command is")

        -- the reset tells exactly those that differ from what the page shows
        W.slash("tooltip off")
        W.slash("reset")
        T.eq(s.EasyGear_showTooltip:GetValue(), true) T.eq(s.EasyGear_ilvlWeight:GetValue(), 0.5)
        T.eq(s.EasyGear_showTooltip.notified, 2, "off by command, back by reset") T.eq(s.EasyGear_ilvlWeight.notified, 2)
        T.eq(s.EasyGear_showBagIcons.notified, 1, "already back on: the reset did not touch it")
        T.eq(s.EasyGear_tooltipDiff.notified, nil, "unchanged settings stay untouched")
    end)

    T.test("options: the profile follows changes made elsewhere, not the page's own choice", function()
        local W = world()
        W.state.settingsOpen = true
        local p = W.state.settingByVariable.EasyGear_PROFILE
        p:SetValue("WARRIOR_FURY")
        T.eq(W.EG.Profiles.ActiveID(), "WARRIOR_FURY") T.eq(p.notified, nil, "own choice")
        W.slash("profile warrior_prot")
        T.eq(p.notified, 1) T.eq(p:GetValue(), "WARRIOR_PROT")
        W.slash("profile warrior_prot")
        T.eq(p.notified, 1, "nothing changed, nobody is told")
    end)

    T.test("options: a control that adjusts the value (a slider snapping to its step) is taken over and evaluated", function()
        local W = world()
        W.state.settingsOpen = true
        local slider = W.state.settingByVariable.EasyGear_ilvlWeight
        slider:SetValueChangedCallback(function(setting, v)
            local snapped = math.floor(v / 0.05 + 0.5) * 0.05
            if math.abs(snapped - v) > 1e-9 then setting:SetValue(snapped) end
        end)
        local calls = 0
        W.EG:Listen("INVALIDATED", function() calls = calls + 1 end)
        W.slash("ilvl 0.73")
        T.near(W.EG:Get("ilvlWeight"), 0.75, 1e-9, "the control's value stands")
        T.eq(calls, 2, "evaluated once more with the adjusted value")
        -- ilvl 30 x 0.75 + 20 STR x 1 + 20 STA x 0.1 + 300 armor x 0.025 = 22.5 + 20 + 2 + 7.5
        T.near(W.EG.Score.OfLink(W.I.chest), 52, 1e-9)
    end)

    T.test("options: the slider ranges are the ranges of the chat commands", function()
        local W = world()
        local ranges = W.EG.RANGES
        local sliders = {}
        for _, c in ipairs(category(W).controls) do if c.kind == "slider" then sliders[#sliders + 1] = c end end
        T.eq(sliders[1].options.minValue, ranges.ilvlWeight[1]) T.eq(sliders[1].options.maxValue, ranges.ilvlWeight[2])
        T.eq(sliders[2].options.minValue, ranges.minDeltaPercent[1]) T.eq(sliders[2].options.maxValue, ranges.minDeltaPercent[2])
        for _, cmd in ipairs({ { "ilvl", "ilvlWeight" }, { "mindeltapct", "minDeltaPercent" } }) do
            local hi = ranges[cmd[2]][2]
            W.slash(cmd[1] .. " " .. hi)
            T.eq(W.EG:Get(cmd[2]), hi, cmd[1] .. " accepts the slider maximum")
            W.slash(cmd[1] .. " " .. (hi + 0.5))
            T.eq(W.EG:Get(cmd[2]), hi, cmd[1] .. " refuses more than the slider can show")
        end
    end)

    T.test("options: a closed settings window is not bothered", function()
        local W = world()
        W.state.settingsOpen = false
        W.slash("ilvl 0.9")
        W.slash("tooltip off")
        for var, st in pairs(W.state.settingByVariable) do T.eq(st.notified or 0, 0, var) end
    end)

    ------------------------------------------------------------------ marker look
    local RAID = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
    local function control(W, key)
        for _, c in ipairs(category(W).controls) do
            if c.setting.variable == "EasyGear_" .. key then return c end
        end
    end

    T.test("options: a section for the marker look sits after the group, a shape list and a color field for every kind", function()
        local W = world()
        local L, M = W.EG.L, W.EG.Marks
        local headers = {}
        for i, init in ipairs(category(W).initializers) do
            if init.kind == "header" then headers[#headers + 1] = { name = init.name, at = i } end
        end
        local names = {}
        for _, h in ipairs(headers) do names[#names + 1] = h.name end
        T.eq(table.concat(names, "|"), "Markers|Group|Marker look|Tooltip|Scoring|Profile")

        -- between the header of the look and the next one: shape, color, shape, color ... and the reset button
        local run = {}
        for i = headers[3].at + 1, headers[4].at - 1 do run[#run + 1] = category(W).initializers[i] end
        T.eq(#run, 11)
        for i, kind in ipairs(M.KINDS) do
            local shape, color = run[2 * i - 1], run[2 * i]
            T.eq(shape.kind, "dropdown", kind.id) T.eq(shape.setting.variable, "EasyGear_" .. kind.shapeKey)
            T.eq(color.kind, "swatch", kind.id) T.eq(color.setting.variable, "EasyGear_" .. kind.colorKey)
            T.eq(shape.setting.name, L[kind.name] .. ": shape") T.eq(color.setting.name, L[kind.name] .. ": color")
            T.eq(shape.tooltip, L[kind.tip]) T.eq(color.tooltip, L[kind.tip])
            T.ok(#shape.tooltip > 20 and shape.tooltip ~= kind.tip, "the tip is a text")
            T.eq(shape.setting.default, W.EG.DEFAULTS[kind.shapeKey]) T.eq(color.setting.default, W.EG.DEFAULTS[kind.colorKey])
            T.eq(shape.setting.vtype, "string") T.eq(color.setting.vtype, "string")
        end
        T.eq(run[11].kind, "button") T.eq(run[11].text, "Reset marker look") T.eq(run[11].name, "Reset marker look")
        T.ok(run[11].tooltip and #run[11].tooltip > 20)
        T.eq(W.EG.hookStatus.settings.ok, true)
    end)

    T.test("options: the shape list offers every shape with its picture and its name", function()
        local W = world()
        local M = W.EG.Marks
        local opts = control(W, "markGroupShape").getOptions()
        T.eq(#opts, #M.SHAPES)
        for i, shape in ipairs(M.SHAPES) do
            T.eq(opts[i].value, shape.id) T.eq(opts[i].label, M.ShapeLabel(shape))
        end
        T.eq(opts[1].label, "|A:bags-greenarrow:16:16|a Arrow")
        T.eq(opts[5].label, "|T" .. RAID .. "2:16:16|t Circle")
        T.eq(control(W, "markGroupShape").setting:GetValue(), "star", "the list shows the current shape")
    end)

    T.test("options: choosing a shape or a color on the page changes the marks and is stored in the form the color field uses", function()
        local W = world()
        W.state.settingsOpen = true
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, W.I.better)
        local shape, color = W.state.settingByVariable.EasyGear_markUpgradeShape, W.state.settingByVariable.EasyGear_markUpgradeColor
        T.eq(shape:GetValue(), "arrow") T.eq(color:GetValue(), "ff40ff40")

        shape:SetValue("diamond") W.flush()
        T.eq(W.env.EasyGearDB.markUpgradeShape, "diamond")
        T.eq(b.EasyGearArrow:GetTexture(), RAID .. "3", "the marker follows at once")
        color:SetValue("80FF8800") W.flush()
        T.eq(color:GetValue(), "ffff8800", "the page reads back the normal form") T.eq(W.env.EasyGearDB.markUpgradeColor, "ffff8800")
        T.near(b.EasyGearArrow.__vertex[2], 136 / 255, 1e-9)
        T.eq(shape.notified, nil, "the page's own choices are not told back") T.eq(color.notified, nil)

        shape:SetValue("not a shape") W.flush()
        T.eq(shape:GetValue(), "diamond", "a value the settings refuse does not arrive")
        color:SetValue("not a color") W.flush()
        T.eq(color:GetValue(), "ffff8800")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("options: a stored value that does not exist never reaches the page", function()
        local W = world(function(w) w.env.EasyGearDB = { markUpgradeShape = "nope", markUpgradeColor = "bogus", markGroupColor = 12, markGroupShape = {} } end)
        local s = W.state.settingByVariable
        T.eq(s.EasyGear_markUpgradeShape:GetValue(), "arrow") T.eq(s.EasyGear_markUpgradeColor:GetValue(), "ff40ff40")
        T.eq(s.EasyGear_markGroupShape:GetValue(), "star") T.eq(s.EasyGear_markGroupColor:GetValue(), "ffbf66ff")
        for _, kind in ipairs(W.EG.Marks.KINDS) do
            T.eq(#s["EasyGear_" .. kind.colorKey]:GetValue(), 8, "the color field needs exactly eight digits")
        end
        W.state.settingsOpen = true
        W.EG:InvalidateAll()
        for var, st in pairs(s) do T.eq(st.notified or 0, 0, var .. " is not stale") end
    end)

    T.test("options: a look changed elsewhere reaches an open page - only the rows that changed", function()
        local W = world()
        W.state.settingsOpen = true
        local s = W.state.settingByVariable
        W.slash("marker group diamond ff8800")
        T.eq(s.EasyGear_markGroupShape.notified, 1) T.eq(s.EasyGear_markGroupColor.notified, 1)
        T.eq(s.EasyGear_markGroupShape:GetValue(), "diamond") T.eq(s.EasyGear_markGroupColor:GetValue(), "ffff8800")
        T.eq(s.EasyGear_markUpgradeShape.notified, nil) T.eq(s.EasyGear_markLevelColor.notified, nil)
        W.slash("marker group diamond")
        T.eq(s.EasyGear_markGroupShape.notified, 1, "nothing changed, nobody is told")
        W.slash("marker group 112233")
        T.eq(s.EasyGear_markGroupShape.notified, 1) T.eq(s.EasyGear_markGroupColor.notified, 2, "only the color changed")
        W.slash("reset")
        T.eq(s.EasyGear_markGroupShape.notified, 2) T.eq(s.EasyGear_markGroupColor.notified, 3)
        T.eq(s.EasyGear_markGroupShape:GetValue(), "star")
    end)

    T.test("options: the reset button of the look resets the look and nothing else", function()
        local W = world()
        local btn
        for _, init in ipairs(category(W).initializers) do
            if init.kind == "button" and not btn then btn = init end
        end
        T.eq(btn.name, "Reset marker look")
        W.state.settingsOpen = true
        W.EG:Set("tooltipDiff", false)
        W.slash("marker group moon ff0000") W.slash("marker sell skull 0000ff")
        local shape = W.state.settingByVariable.EasyGear_markGroupShape
        T.eq(shape.notified, 1) T.eq(shape:GetValue(), "moon")
        W.clearChat()
        btn.onClick()
        local db = W.env.EasyGearDB
        T.eq(db.markGroupShape, "star") T.eq(db.markGroupColor, "ffbf66ff") T.eq(db.markSellShape, "check") T.eq(db.markSellColor, "ff40ff40")
        T.eq(db.tooltipDiff, false, "the other settings are left alone")
        T.has(W.chatText(), "Marker look reset to the original.")
        T.eq(shape:GetValue(), "star") T.eq(shape.notified, 2, "the open page shows it")
        T.eq(W.state.settingByVariable.EasyGear_markUpgradeShape.notified, nil, "and only what changed")
    end)

    T.test("options: the settings reset also restores the look", function()
        local W = world()
        W.slash("marker group moon ff0000")
        W.slash("reset")
        T.eq(W.env.EasyGearDB.markGroupShape, "star") T.eq(W.env.EasyGearDB.markGroupColor, "ffbf66ff")
    end)

    T.test("options: without the color field of the interface the shape lists stay and the page still builds", function()
        local W = world(nil, { noColorSwatch = true })
        local kinds = {}
        for _, c in ipairs(category(W).controls) do kinds[c.kind] = (kinds[c.kind] or 0) + 1 end
        T.eq(kinds.swatch, nil) T.eq(kinds.dropdown, 6)
        T.eq(W.EG.hookStatus.settings.ok, true)
        W.slash("marker group moon")
        T.eq(W.env.EasyGearDB.markGroupShape, "moon", "and the chat command remains")
    end)
end
