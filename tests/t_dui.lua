-- DialogueUI.lua: EasyGear inside Dialogue UI (a model of it, see Mock.installDialogueUI, built after its source)
return function(T)
    local F = require("fixtures")

    -- Arms warrior with a good and a poor chest piece, a gem to sell, and a Dialogue UI model (options: see the mock)
    local function world(duiOptions, setup, flags)
        flags = flags or {}
        local W = T.world(F.arms(flags.world), function(w)
            w.I = F.armsWarrior(w)
            w.I.better = F.gear(w, 7001, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35 })
            w.I.weak = F.gear(w, 7002, "Weak Chestplate", "INVTYPE_CHEST", 10, { STR = 1 })
            w.I.good = F.gear(w, 7004, "Good Ring", "INVTYPE_FINGER", 40, { STR = 20, HIT = 15 }, { typeText = "" })
            w.I.gem = F.gear(w, 7003, "Shiny Gem", "", 1, {}, { sellPrice = 900 })
            w.I.pebble = F.gear(w, 7005, "Pebble", "", 1, {}, { sellPrice = 100 })
            if duiOptions then w.D = w.installDialogueUI(duiOptions) end
            if setup then setup(w) end
        end)
        return W, W.D
    end
    local function checkOf(b) return b.EasyGearCheck end
    local function checked(b) return b.EasyGearCheck ~= nil and b.EasyGearCheck:IsShown() end
    local function count(list, text)
        local n = 0
        for _, line in ipairs(list) do if line:find(text, 1, true) then n = n + 1 end end
        return n
    end
    local function index(list, text)
        for i, line in ipairs(list) do if line:find(text, 1, true) then return i end end
    end
    local function hoverText(W, D, button)
        D.hover(button)
        return D.lines()
    end

    ------------------------------------------------------------------ registration and status
    T.test("dui: found, the processor is registered once and /eg status says so", function()
        local W, D = world({})
        T.eq(W.EG.hookStatus.dialogueui.ok, true)
        local n = 0
        for _ in pairs(D.processors) do n = n + 1 end
        T.eq(n, 1, "one processor for the item tooltip of Dialogue UI")
        local function drivers()
            local c = 0
            for _, f in ipairs(W.state.frames) do if f.__parent == D.frame and f.__scripts.OnUpdate then c = c + 1 end end
            return c
        end
        T.eq(drivers(), 1, "one driver on the quest frame")
        T.eq(W.EG.DialogueUI.Register(), true) T.eq(W.EG.DialogueUI.Register(), true, "a second call changes nothing")
        n = 0
        for _ in pairs(D.processors) do n = n + 1 end
        T.eq(n, 1) T.eq(drivers(), 1, "and starts no second driver")
        W.clearChat() W.slash("status")
        T.has(W.chatText(), "Dialogue UI: found - score and verdict in its tooltips")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: without Dialogue UI nothing is registered and the status says so", function()
        local W = world(nil)
        T.eq(W.EG.hookStatus.dialogueui, nil)
        W.clearChat() W.slash("status")
        T.has(W.chatText(), "Dialogue UI: not installed")
        T.eq(W.EG.DialogueUI.Register(), false)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a Dialogue UI without the tooltip interface or without its quest frame is named in the status, the rest works", function()
        local W, D = world({ noProcessorAPI = true })
        T.eq(W.EG.hookStatus.dialogueui.ok, false) T.has(W.EG.hookStatus.dialogueui.note, "DialogueUIAPI.AddItemTooltipProcessorExternal")
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        T.eq(checked(b[1]), true, "the reward marks do not need the tooltip interface")
        W.clearChat() W.slash("status")
        T.has(W.chatText(), "Dialogue UI: found, but part of its interface is missing (DialogueUIAPI.AddItemTooltipProcessorExternal)")

        T.eq(W.EG.lastError, nil)
        for _, missing in ipairs({ "noQuestFrame", "noItemButtonPool" }) do
            local V, E = world({ [missing] = true })
            T.eq(V.EG.hookStatus.dialogueui.ok, false, missing) T.has(V.EG.hookStatus.dialogueui.note, "DUIQuestFrame.itemButtonPool", missing)
            local n = 0
            for _ in pairs(E.processors) do n = n + 1 end
            T.eq(n, 1, missing .. ": the tooltip lines do not need the quest frame")
            V.clearChat() V.slash("status")
            T.has(V.chatText(), "Dialogue UI: found, but part of its interface is missing (DUIQuestFrame.itemButtonPool)", missing)
            T.eq(V.EG.lastError, nil, missing)
        end
    end)

    ------------------------------------------------------------------ the tooltip
    T.test("dui: the block stands below the comparison and Pawn's lines and above the Shift hint, in Dialogue UI's colors", function()
        local W, D = world({ pawn = true })
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        local lines = hoverText(W, D, b[1])
        local pawn, head, verdict, hint = index(lines, "Pawn:"), index(lines, "EasyGear |"), index(lines, "UPGRADE |"), index(lines, "Show Comparison")
        T.ok(pawn and head and verdict and hint, D.text())
        T.ok(pawn < head and head < verdict and verdict < hint, "Pawn, then EasyGear, then the hint: " .. D.text())
        T.eq(lines[#lines], "Show Comparison", "the Shift hint stays the last line")
        T.eq(lines[head - 1], "", "a small gap in front of the block")
        T.eq(count(lines, "EasyGear |"), 1, "exactly one block")

        local row = D.row("EasyGear")
        T.eq(row.left.r, 1) T.near(row.left.g, 0.82) T.eq(row.left.b, 0, "the heading in the gold of Dialogue UI")
        T.eq(row.left.size, 2, "the size of its text") T.eq(row.right.text, "Score: 81.5")
        T.eq(row.right.r, 1) T.eq(row.right.g, 1) T.eq(row.right.b, 1, "the score itself in white")
        local v = D.row("UPGRADE")
        T.near(v.left.r, 0.098) T.eq(v.left.g, 1) T.near(v.left.b, 0.098, 1e-9, "its green")
        T.near(v.right.r, 0.098) T.eq(v.right.text, "+37  (+83.1%)")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the first tooltip is built twice (the block needs its place before the hint), every later one once", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        D.hover(b[1])
        T.eq(D.builds, 2, "built, then built again with the block")
        T.eq(count(D.lines(), "EasyGear |"), 1)
        T.eq(D.relayouts, 0, "the second build laid the tooltip out: the processor has nothing to announce")
        D.leave(b[1]) D.hover(b[1])
        T.eq(D.builds, 3, "from now on once per display")
        D.leave(b[1]) D.hover(b[2])
        T.eq(D.builds, 4) T.eq(count(D.lines(), "EasyGear |"), 1)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: with the comparison hidden the block is short, with it shown it has the slot, the attributes and the notes", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        local short = hoverText(W, D, b[1])
        T.eq(count(short, "Chest | 44.5"), 0) T.eq(count(short, "Strength"), 1, "only Dialogue UI's own stat line")
        T.ok(index(short, "UPGRADE |"))

        W.env.DialogueUI_DB.TooltipShowItemComparison = true
        local long = hoverText(W, D, b[1])
        T.ok(index(long, "Replaces:") < index(long, "EasyGear |"), "below the comparison of Dialogue UI")
        T.eq(count(long, "Chest | 44.5"), 1, "the slot and what it holds")
        T.eq(count(long, "+20 Critical Strike"), 2, "the attribute differences, below Dialogue UI's own stat lines")
        local _, at = D.row("+10 Strength")
        T.ok(at, "a difference line of EasyGear") T.eq(D.tooltip.rows[at].left.indent, 12, "indented like the deltas of Dialogue UI")
        T.near(D.tooltip.rows[at].left.r, 0.098)
        T.eq(long[#long], "Hide Comparison")

        W.EG:Set("tooltipDiff", false)
        T.eq(count(hoverText(W, D, b[1]), "+10 Strength"), 0, "the setting for the differences holds here too")
        W.EG:Set("showTooltipStats", false)
        T.eq(count(hoverText(W, D, b[1]), "Chest | 44.5"), 0, "and the one for the slot line")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the verdicts have their meaning in the colors of Dialogue UI - red, gold, green - and the reason is wrapped and grey", function()
        local W, D = world({}, function(w)
            w.I.robe = F.gear(w, 7020, "Robe", "INVTYPE_CHEST", 90, { INT = 100 }, { badType = true, typeText = "Cloth" })
            w.I.late = F.gear(w, 7021, "Late Chestplate", "INVTYPE_CHEST", 90, { STR = 100 }, { minLevel = 65 })
        end)
        local b = D.showQuest({ choices = { W.I.weak, W.I.robe, W.I.late, W.I.good } })
        D.tick(0.3)
        local RED = { 1, 0.125, 0.125 }
        local function sameColor(fs, c, msg)
            T.near(fs.r, c[1], 1e-9, msg) T.near(fs.g, c[2], 1e-9, msg) T.near(fs.b, c[3], 1e-9, msg)
        end

        hoverText(W, D, b[1])                                  -- a worse item
        local v = D.row("NO UPGRADE")
        T.ok(v, D.text()) sameColor(v.left, RED, "NO UPGRADE") sameColor(v.right, RED, "its negative difference")

        hoverText(W, D, b[2])                                  -- nobody of your class can use it
        v = D.row("NOT USABLE")
        T.ok(v, D.text()) sameColor(v.left, RED, "NOT USABLE") T.eq(v.right, nil, "no difference for what cannot be used")
        local reason, at = D.row("Not usable by your class")
        T.ok(reason, D.text()) T.eq(reason.left.wrap, true, "long reasons wrap") sameColor(reason.left, { 0.5, 0.5, 0.5 }, "the grey of its hint")
        T.eq(at, select(2, D.row("NOT USABLE")) + 1, "right below the verdict")

        hoverText(W, D, b[3])                                  -- better, but the level does not reach yet
        v = D.row("UPGRADE from level 65")
        T.ok(v, D.text()) sameColor(v.left, { 1, 0.82, 0 }, "the gold of Dialogue UI for what needs attention")

        W.equip(12, nil) W.fire("PLAYER_EQUIPMENT_CHANGED", 12) W.flush()
        hoverText(W, D, b[4])                                  -- the second finger slot is empty now
        v = D.row("UPGRADE (slot empty)")
        T.ok(v, D.text()) sameColor(v.left, { 0.098, 1, 0.098 }, "green")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the best of several rewards says so in its tooltip, the others do not", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.weak, W.I.better } })
        D.tick(0.3)
        T.eq(count(hoverText(W, D, b[2]), "EasyGear: best choice (largest upgrade)"), 1)
        local r = D.row("EasyGear: best choice")
        T.near(r.left.r, 0.098) T.eq(r.left.g, 1)
        T.eq(count(hoverText(W, D, b[1]), "best choice"), 0)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a reward that is no gear but the best one to sell gets its line at the end (Dialogue UI has no hook for it)", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.pebble, W.I.gem } })
        D.tick(0.3)
        T.eq(checked(b[2]), true) T.eq(checked(b[1]), false)
        local lines = hoverText(W, D, b[2])
        T.eq(lines[#lines], "EasyGear: best choice (highest vendor price)", D.text())
        T.eq(count(lines, "EasyGear"), 1)
        T.eq(D.relayouts, 1, "the processor changed the tooltip: Dialogue UI lays it out again")
        T.eq(count(hoverText(W, D, b[1]), "EasyGear"), 0, "the other one has nothing to say")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: Pawn's lines stay where Pawn put them, in front of EasyGear's", function()
        local W, D = world({ pawn = true })
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        local lines = hoverText(W, D, b[1])
        T.eq(count(lines, "Pawn: 12% upgrade"), 1) T.ok(index(lines, "Pawn:") < index(lines, "EasyGear |"))
        W.env.DialogueUI_DB.TooltipShowItemComparison = true
        lines = hoverText(W, D, b[1])
        T.eq(count(lines, "Pawn: 12% upgrade"), 1, "once, however often the tooltip is built")
    end)

    T.test("dui: a Dialogue UI that cannot rebuild its tooltip (or has no place for Pawn) gets the block at the end", function()
        for _, missing in ipairs({ "noReprocess", "noProcessItemExternal" }) do
            local W, D = world({ [missing] = true })
            local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
            D.tick(0.3)
            local lines = hoverText(W, D, b[1])
            T.eq(count(lines, "EasyGear |"), 1, missing .. ": " .. D.text())
            T.eq(lines[#lines], "UPGRADE | +37  (+83.1%)", missing .. ": after the hint, at the end")
            T.eq(D.relayouts, 1, missing .. ": and Dialogue UI is told to lay the tooltip out again")
            T.eq(count(hoverText(W, D, b[1]), "EasyGear |"), 1, "and still once the second time")
            T.eq(W.EG.lastError, nil, missing)
        end
    end)

    T.test("dui: switched off by its setting, or by the tooltip setting, there is no block; switched on again it comes back", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        T.eq(count(hoverText(W, D, b[1]), "EasyGear |"), 1)
        W.slash("dui off") W.flush()
        T.eq(count(D.lines(), "EasyGear"), 0, "the open tooltip builds itself again without the block")
        T.eq(count(hoverText(W, D, b[2]), "EasyGear"), 0)
        D.leave(b[2])
        W.slash("dui on") W.slash("dui off") W.flush()
        T.eq(D.tooltip:IsShown(), false, "a tooltip that is closed stays closed when a setting changes")
        W.slash("dui on") W.flush()
        T.eq(count(hoverText(W, D, b[1]), "EasyGear |"), 1, "and with it again")
        W.EG:Set("showTooltip", false) W.flush()
        T.eq(count(D.lines(), "EasyGear"), 0, "the setting for the tooltips takes the open one back, too")
        T.eq(count(hoverText(W, D, b[1]), "EasyGear"), 0, "the tooltip setting turns the block off, not the marks")
        T.eq(checked(b[1]), true)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a tooltip that closed before the processor ran is not opened again", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        b[1].__scripts.OnEnter(b[1])              -- the tooltip is built; the processors come one frame later ...
        b[1].__scripts.OnLeave(b[1])              -- ... and by then the mouse is gone
        W.advance(0)
        T.eq(D.tooltip:IsShown(), false)
        D.hover(b[1])                             -- the first rebuild was skipped: the next display does it
        T.eq(count(D.lines(), "EasyGear |"), 1, D.text())
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: an item whose data arrives later gets its block as soon as it is there", function()
        local notYet = {}
        local W, D = world({}, function(w)
            w.I.slow = F.gear(w, 7010, "Slow Chestplate", "INVTYPE_CHEST", 60, { STR = 60 }, { armor = 700 })
            -- the tooltip of Dialogue UI has the item, the item info of the client does not (yet)
            local original = w.env.C_Item.GetItemInfo
            w.env.C_Item.GetItemInfo = function(link)
                local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
                if id and notYet[id] then return nil end
                return original(link)
            end
            notYet[7010] = true
        end)
        local b = D.showQuest({ choices = { W.I.slow, W.I.weak } })
        D.tick(0.3)
        D.hover(b[1])
        T.ok(D.tooltip:IsShown(), "the tooltip of Dialogue UI is there ...")
        T.eq(count(D.lines(), "EasyGear"), 0, "... without EasyGear's block: the data is missing")
        notYet[7010] = nil
        W.fire("GET_ITEM_INFO_RECEIVED", 7010, true)
        W.flush()
        T.eq(count(D.lines(), "EasyGear |"), 1, "the open tooltip builds itself again: " .. D.text())
        T.eq(D.lines()[#D.lines()], "Show Comparison", "the hint is still the last line")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a reward judged on incomplete data is judged again when the data is complete (ITEMS_LOADED)", function()
        local W, D = world({}, function(w)
            w.I.enchanted = F.gear(w, 7040, "Enchanted Chestplate", "INVTYPE_CHEST", 10, { STR = 5 },
                { lines = { { type = T.Mock.LINE.ItemEnchantmentPermanent, leftText = "Enchanted: +150 Strength", leftColor = T.Mock.COLOR.green } } })
            w.state.items[7040].noTooltip = true           -- its tooltip data is not there yet: only the base values count
        end)
        local b = D.showQuest({ choices = { W.I.enchanted, W.I.weak }, choosing = true })
        D.tick(0.3)
        T.eq(#D.upgrades, 0, "judged on the base values alone: no upgrade")
        W.state.items[7040].noTooltip = nil
        W.flush()                                          -- the refresh that Items scheduled for the missing data
        D.tick(0.3)
        T.eq(#D.upgrades, 1, "with the enchant it is one: Dialogue UI's arrow") T.eq(D.upgrades[1].button, b[1])
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a reward whose data is still missing is asked again at every pass until it is there, with or without a message", function()
        local notYet = {}
        local W, D = world({}, function(w)
            w.I.slow = F.gear(w, 7050, "Slow Chestplate", "INVTYPE_CHEST", 60, { STR = 60 }, { armor = 700 })
            local original = w.env.C_Item.GetItemInfo
            w.env.C_Item.GetItemInfo = function(link)
                local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
                if id and notYet[id] then return nil end
                return original(link)
            end
            notYet[7050] = true
        end)
        local b = D.showQuest({ choices = { W.I.slow, W.I.weak } })
        D.tick(0.3)
        T.eq(#D.upgrades, 0, "not loaded")
        D.tick(0.3)
        T.eq(#D.upgrades, 0)
        notYet[7050] = nil                                 -- the data is there now; nobody announced it
        D.tick(0.3)
        T.eq(#D.upgrades, 1, "found at the next pass") T.eq(D.upgrades[1].button, b[1])
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the arrow follows the client's word on usability, like Dialogue UI itself", function()
        local W, D = world({})
        local spec = { choices = { { link = W.I.better, usable = false }, W.I.weak }, rewards = { { link = W.I.good, usable = false } }, choosing = true }
        local b = D.showQuest(spec)
        D.tick(0.3)
        T.eq(#D.upgrades, 0, "the client says: not usable - no arrow, although the tooltip's red lines do not say so")
        spec.choices[1].usable = true                      -- the answer changes (data arrives): now it is judged
        spec.rewards[1].usable = true
        D.tick(0.3)
        T.eq(#D.upgrades, 2, "the chest and the ring") T.eq(D.upgrades[1].button, b[1]) T.eq(D.upgrades[2].button, b[3])
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a Pawn that loads later and replaces the hook is chained again - its lines and the block, once each", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        D.hover(b[1])
        T.eq(count(D.lines(), "EasyGear |"), 1)
        D.leave(b[1])
        D.tooltip.ProcessItemExternal = function(self)       -- Pawn arrives and sets its own function
            self:AddBlankLine()
            self:AddLeftLine("Pawn: late", 1, 1, 1)
        end
        local lines = hoverText(W, D, b[1])
        T.eq(count(lines, "Pawn: late"), 1, D.text()) T.eq(count(lines, "EasyGear |"), 1, D.text())
        T.ok(index(lines, "Pawn: late") < index(lines, "EasyGear |"), "Pawn's lines first")
        T.eq(lines[#lines], "Show Comparison")
        lines = hoverText(W, D, b[1])
        T.eq(count(lines, "Pawn: late"), 1) T.eq(count(lines, "EasyGear |"), 1, "and stays so")
        T.eq(D.builds, 5, "the first display: 2 builds, the late Pawn: 2 builds more, the next display: 1")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the group lines come with the comparison, below the verdict", function()
        local W, D = world({}, function(w)
            local G = w.installGroup()
            local gear = {}
            local locs = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
                           [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND" }
            for slot, loc in pairs(locs) do
                gear[slot] = F.gear(w, 40000 + slot, "Cloth" .. slot, loc, 30, { INT = 10, SP = 10 }, { subclassID = slot == 2 and 0 or 1 })
            end
            G.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            w.I.robe = F.gear(w, 40100, "Robe", "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
        end)
        W.advance(30)
        local b = D.showQuest({ choices = { W.I.robe, W.I.weak } })
        D.tick(0.3)
        T.eq(count(hoverText(W, D, b[1]), "Better for the group"), 0, "not in the short tooltip")
        W.env.DialogueUI_DB.TooltipShowItemComparison = true
        local lines = hoverText(W, D, b[1])
        T.ok(index(lines, "Better for the group:"), D.text())
        T.ok(index(lines, "Bob") and index(lines, "Better for the group:") > index(lines, "NO UPGRADE"), D.text())
        T.eq(lines[index(lines, "Better for the group:") - 1], "", "a gap in front of the group lines")
        local head = D.row("Better for the group:")
        T.eq(head.left.r, 1) T.near(head.left.g, 0.82, 1e-9, "the heading in gold")
        local at
        for i, r in ipairs(D.tooltip.rows) do
            if r.left and r.left.text:find("Bob", 1, true) then at = i end
        end
        T.ok(at, "a line for the member")
        T.eq(D.tooltip.rows[at].left.indent, 12, "indented") T.near(D.tooltip.rows[at].right.r, 0.098, 1e-9, "the gain in green")
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ the reward buttons
    T.test("dui: the best of several rewards gets the check mark at the top right of its icon, in the look chosen in the options", function()
        local W, D = world({})
        W.EG:Set("markPickShape", "star") W.EG:Set("markPickColor", "ff3366ff")
        local b = D.showQuest({ choices = { W.I.weak, W.I.better }, choosing = true })
        T.eq(checked(b[2]), false, "nothing before the first pass of the driver")
        D.tick(0.1)
        T.eq(checked(b[2]), false, "the pass comes every quarter second")
        D.tick(0.2)
        T.eq(checked(b[2]), true) T.eq(checked(b[1]), false)
        local tex = checkOf(b[2])
        local point, rel = tex:GetPoint(1)
        T.eq(point, "TOPRIGHT") T.eq(rel, b[2].Icon, "at the icon, where Dialogue UI keeps its own marks off")
        T.eq(tex:GetAtlas(), "tradeskills-star") T.near(tex.__vertex[1], 0x33 / 255, 1e-9)
        T.eq(tex:GetWidth(), 20)
        T.eq(b[2].EasyGearArrow, nil, "no arrow of EasyGear's own: Dialogue UI has its arrow")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: one reward alone is nothing to choose from - no check mark; the reward to sell gets the sell look", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better } })
        D.tick(0.3)
        T.eq(checked(b[1]), false)
        W.EG:Set("markSellShape", "coin")
        local c = D.showQuest({ choices = { W.I.pebble, W.I.gem } })
        D.tick(0.3)
        T.eq(checked(c[2]), true) T.eq(checkOf(c[2]):GetAtlas(), "bags-junkcoin", "chosen for its vendor price")
    end)

    T.test("dui: without the release call the buttons are recognised by what they hold - the old mark is gone by the next pass", function()
        local W, D = world({ noReleaseAllObjects = true })
        T.eq(W.EG.hookStatus.dialogueui.ok, true, "the call is a convenience, not a requirement")
        local b = D.showQuest({ choices = { W.I.weak, W.I.better }, choosing = true })
        D.tick(0.3)
        T.eq(checked(b[2]), true)
        local c = D.showQuest({ choices = { W.I.better, W.I.weak }, choosing = true })     -- the same buttons, the other way round
        D.tick(0.3)
        T.eq(checked(c[1]), true, "the new best choice") T.eq(checked(c[2]), false, "and the old mark is gone")
        T.eq(#D.upgrades, 1, "the new quest got its arrows: the chest")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: when the answer of the client for a reward changes (usable), the best choice is worked out again", function()
        local W, D = world({}, function(w) w.I.cheap = F.gear(w, 7030, "Cheap Chestplate", "INVTYPE_CHEST", 10, { STR = 1 }, { sellPrice = 50 }) end)
        W.EG:Set("markSellShape", "coin")
        local spec = { choices = { { link = W.I.better }, { link = W.I.cheap } }, choosing = true }
        local b = D.showQuest(spec)
        D.tick(0.3)
        T.eq(checked(b[1]), true) T.eq(checked(b[2]), false)
        spec.choices[1].usable = false               -- the client now says that this one cannot be used
        D.tick(0.3)
        T.eq(checked(b[1]), false) T.eq(checked(b[2]), true, "so the other one is the best to take")
        T.eq(checkOf(b[2]):GetAtlas(), "bags-junkcoin")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: when the stack size of a reward changes, the best one to sell is worked out again", function()
        local W, D = world({})
        local spec = { choices = { { link = W.I.gem }, { link = W.I.pebble } } }
        local b = D.showQuest(spec)
        D.tick(0.3)
        T.eq(checked(b[1]), true) T.eq(checked(b[2]), false, "900 against 100")
        spec.choices[2].count = 10                         -- ten of the cheap ones: 1000
        D.tick(0.3)
        T.eq(checked(b[1]), false) T.eq(checked(b[2]), true)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: a currency reward is no item - it shares the type name and the numbers with the item rewards, and gets nothing", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.weak, W.I.better }, rewards = { W.I.good }, currencies = 2, choosing = true })
        D.tick(0.3)
        T.eq(b[4].objectType, "currency") T.eq(b[5].objectType, "currency")
        T.eq(#D.upgrades, 2, "the chest and the ring - the currency button with index 1 is not the first reward")
        for _, u in ipairs(D.upgrades) do T.ok(u.button ~= b[4] and u.button ~= b[5], "no arrow on a currency") end
        T.eq(b[4].EasyGearCheck, nil) T.eq(W.EG.Marks.registry[b[4]], nil, "not registered at all")
        T.eq(checked(b[2]), true)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the check mark follows a change of equipment - what was the best upgrade may be a vendor item now", function()
        local W, D = world({}, function(w)
            w.I.cheap = F.gear(w, 7030, "Cheap Chestplate", "INVTYPE_CHEST", 10, { STR = 1 }, { sellPrice = 50 })
            w.I.super = F.gear(w, 7031, "Super Chestplate", "INVTYPE_CHEST", 90, { STR = 200, STA = 100 }, { armor = 900 })
        end)
        W.EG:Set("markSellShape", "coin")
        local b = D.showQuest({ choices = { W.I.better, W.I.cheap } })
        D.tick(0.3)
        T.eq(checked(b[1]), true) T.ok(checkOf(b[1]):GetAtlas() ~= "bags-junkcoin", "chosen as an upgrade")
        W.equip(5, W.I.super) W.fire("PLAYER_EQUIPMENT_CHANGED", 5) W.flush()
        D.tick(0.3)
        T.eq(checked(b[1]), false, "no upgrade any more")
        T.eq(checked(b[2]), true) T.eq(checkOf(b[2]):GetAtlas(), "bags-junkcoin", "the best to sell, now")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the next quest starts clean - nothing stays on a button that Dialogue UI uses again", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.weak, W.I.better } })
        D.tick(0.3)
        T.eq(checked(b[2]), true)
        local c = D.showQuest({ choices = { W.I.better, W.I.weak } })     -- the buttons come from the pool, in the other order
        T.ok((c[1] == b[1] and c[2] == b[2]) or (c[1] == b[2] and c[2] == b[1]), "the same button objects")
        T.eq(checked(c[1]) or checked(c[2]), false, "gone at once, before the next pass: Dialogue UI released everything")
        D.tick(0.3)
        T.eq(checked(c[1]), true) T.eq(checked(c[2]), false, "and now the other one")
        D.hide()
        T.eq(checked(c[1]), false, "closing the window clears it too")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: an upgrade that Dialogue UI did not mark gets Dialogue UI's own arrow, once, with its movement while choosing", function()
        local W, D = world({}, function(w)
            w.I.robe = F.gear(w, 7020, "Robe", "INVTYPE_CHEST", 90, { INT = 100 }, { badType = true, typeText = "Cloth" })
            w.I.late = F.gear(w, 7021, "Late Chestplate", "INVTYPE_CHEST", 90, { STR = 100 }, { minLevel = 65 })
        end)
        local b = D.showQuest({ choices = { W.I.better, W.I.weak, W.I.robe, W.I.late }, rewards = { W.I.good }, choosing = true })
        D.tick(0.3)
        T.eq(#D.upgrades, 2, "the chest and the ring (an empty finger slot): the others are worse, unusable, or a level away")
        T.eq(D.upgrades[1].animation, true, "it flies up while the player is choosing")
        D.tick(0.5) W.flush() W.EG:InvalidateAll() D.tick(0.3)
        T.eq(#D.upgrades, 2, "never twice")
        T.eq(b[2].markers, nil, "nothing for the weak one") T.eq(b[3].markers, nil, "nor for the unusable one") T.eq(b[4].markers, nil, "nor for the one a level away")
        W.EG:Set("showQuestIcons", false) W.flush()
        local c = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        T.eq(#D.upgrades, 0, "no arrows while the quest marks are off") T.eq(checked(c[1]), false)
    end)

    T.test("dui: an arrow that Dialogue UI showed itself is left alone (it decides by item level, EasyGear by your weights)", function()
        local native = {}
        local W, D = world({ nativeArrow = native })
        native[W.I.better] = true                    -- Dialogue UI marks the chest (by item level) ...
        native[W.I.weak] = true                      -- ... and, wrongly by your weights, the weak one
        local asked = {}
        local original = W.EG.Score.UpgradeState
        W.EG.Score.UpgradeState = function(link, ...) asked[link] = true return original(link, ...) end
        local b = D.showQuest({ choices = { W.I.better, W.I.weak }, rewards = { W.I.good }, choosing = true })
        T.eq(#D.upgrades, 2, "its own arrows, set while it built the buttons")
        D.tick(0.3)
        T.eq(asked[W.I.better], nil) T.eq(asked[W.I.weak], nil) T.eq(asked[W.I.good], true, "EasyGear does not second-guess a button that has its arrow")
        T.eq(#D.upgrades, 3, "EasyGear adds the arrow only where Dialogue UI showed none: the ring (an empty slot)")
        T.eq(D.upgrades[3].button, b[3])
        T.eq(b[2].markers.upgrade, true, "and takes none away: that arrow is Dialogue UI's decision")
        T.eq(b[2].EasyGearArrow, nil, "no arrow of EasyGear's own on the weak one")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("dui: the marks follow the switches (Dialogue UI, quest marks) and the window: closed they are gone, shown again they are back at once", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.weak, W.I.better } })
        D.tick(0.3)
        T.eq(checked(b[2]), true)
        W.slash("dui off") D.tick(0.3)
        T.eq(checked(b[2]), false, "the switch of Dialogue UI")
        W.slash("dui on") D.tick(0.3)
        T.eq(checked(b[2]), true)
        W.slash("quest off") D.tick(0.3)
        T.eq(checked(b[2]), false, "the quest marks of EasyGear are one switch for both windows")
        W.slash("quest on") D.tick(0.3)
        T.eq(checked(b[2]), true)

        D.hide()
        T.eq(checked(b[2]), false, "the window closes: nothing is left on the buttons")
        D.tick(5)
        T.eq(checked(b[2]), false, "and nothing runs while it is closed")
        D.show()
        D.tick(0.01)
        T.eq(checked(b[2]), true, "shown again (the same quest): the first pass comes at once, not after a quarter second")
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ settings, options, commands
    T.test("dui: the page of settings has the switch, /eg dui toggles it", function()
        local W = world({})
        local found
        for _, c in ipairs(W.state.settings[1].controls) do
            if c.setting.variable == "EasyGear_showDialogueUI" then found = c end
        end
        T.ok(found, "a checkbox") T.eq(found.kind, "checkbox") T.has(found.setting.name, "Dialogue UI")
        T.ok(found.tooltip and #found.tooltip > 30)
        T.eq(W.EG:Get("showDialogueUI"), true)
        W.clearChat() W.slash("dui off")
        T.eq(W.EG:Get("showDialogueUI"), false) T.has(W.chatText(), "Dialogue UI")
        W.slash("dui")
        T.eq(W.EG:Get("showDialogueUI"), true, "without an argument it toggles")
        W.clearChat() W.slash("help")
        T.has(W.chatText(), "/eg dui [on|off]", "listed in the help")
    end)

    T.test("dui: a failure inside EasyGear never reaches Dialogue UI - neither in the processor nor in the hook inside its own tooltip code", function()
        local W, D = world({})
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        D.hover(b[1])                               -- the hook is in place from here on, and Dialogue UI calls it itself
        T.eq(count(D.lines(), "EasyGear |"), 1)
        D.leave(b[1])
        W.EG.Tooltip.Compose = function() error("boom") end
        D.hover(b[1])                               -- an error in the hook would stop Dialogue UI's own build: the model has no pcall
        T.eq(D.tooltip:IsShown(), true) T.eq(count(D.lines(), "EasyGear"), 0) T.eq(D.lines()[#D.lines()], "Show Comparison")
        T.ok(W.EG.lastError and tostring(W.EG.lastError.err):find("boom", 1, true), "reported for /eg status")
        D.tooltip:Hide()
        local processors = {}
        for p in pairs(D.processors) do processors[#processors + 1] = p end
        T.eq(processors[1](D.tooltip, 7001, W.I.better), false, "the processor answers false instead of raising")
        W.EG.lastError = nil
        T.eq(processors[1](nil, 7001, W.I.better), false) T.eq(processors[1]("tooltip", 7001, nil), false)
        T.eq(W.EG.lastError, nil, "what is no tooltip is not an error either")
    end)

    T.test("dui: a tooltip without one of the methods EasyGear writes with is named in the status, and left alone", function()
        for _, name in ipairs({ "AddLeftLine", "AddRightLine", "AddBlankLine" }) do
            local W, D = world({ missingMethods = { [name] = true } })
            local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
            D.tick(0.3)
            T.eq(W.EG.hookStatus.dialogueui.ok, true, name .. ": nothing is known before the first tooltip")
            local lines = hoverText(W, D, b[1])
            T.eq(count(lines, "EasyGear"), 0, name) T.eq(D.builds, 1, name .. ": no rebuild for a block that is not written")
            T.eq(W.EG.hookStatus.dialogueui.ok, false, name) T.eq(W.EG.hookStatus.dialogueui.note, "tooltip:" .. name)
            T.eq(count(hoverText(W, D, b[2]), "EasyGear"), 0, name .. ": and it stays that way")
            W.clearChat() W.slash("status")
            T.has(W.chatText(), "Dialogue UI: found, but part of its interface is missing (tooltip:" .. name .. ")")
            T.eq(checked(b[1]), true, name .. ": the marks on the reward buttons do not need the tooltip")
            T.eq(W.EG.lastError, nil, name)
        end
    end)

    T.test("dui: switched off from the start, EasyGear does not touch the tooltip - one build, no block", function()
        local W, D = world({})
        W.slash("dui off")
        local b = D.showQuest({ choices = { W.I.better, W.I.weak } })
        D.tick(0.3)
        D.hover(b[1])
        T.eq(D.builds, 1) T.eq(count(D.lines(), "EasyGear"), 0) T.eq(checked(b[1]), false)
        W.slash("dui on") W.flush()
        T.eq(count(D.lines(), "EasyGear |"), 1, "switched on, the open tooltip gets its block")
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ random walk
    T.test("dui: random quests, settings and hovers keep the invariants", function()
        local seed = (tonumber(os.getenv("FUZZ_SEED")) or 12345) % 2147483646 + 1
        local function rnd(n) seed = (seed * 16807) % 2147483647 return seed % n + 1 end
        local W, D = world({ pawn = true }, function(w)
            w.I.list = {}
            for i = 1, 6 do
                w.I.list[#w.I.list + 1] = F.gear(w, 7100 + i, "Chest" .. i, "INVTYPE_CHEST", rnd(80), { STR = rnd(40), STA = rnd(40) }, { armor = rnd(600) })
            end
            w.I.list[#w.I.list + 1] = w.I.gem
            w.I.list[#w.I.list + 1] = w.I.pebble
            w.I.list[#w.I.list + 1] = w.I.good
        end)
        local buttons = {}
        for step = 1, 60 do
            local action = rnd(8)
            if action == 1 or action == 2 then
                local choices, rewards = {}, {}
                for _ = 1, rnd(4) do choices[#choices + 1] = W.I.list[rnd(#W.I.list)] end
                for _ = 1, rnd(2) - 1 do rewards[#rewards + 1] = W.I.list[rnd(#W.I.list)] end
                buttons = D.showQuest({ choices = choices, rewards = rewards, choosing = rnd(2) == 1 })
            elseif action == 3 then
                D.tick(0.05 * rnd(8))
            elseif action == 4 and #buttons > 0 then
                local bt = buttons[rnd(#buttons)]
                D.hover(bt)
                local lines = D.lines()
                local item = W.EG.Items.Get(W.env.GetQuestItemLink(bt.type, bt.index))
                local wanted = (item and item.isGear and W.EG:Get("showDialogueUI") ~= false and W.EG:Get("showTooltip") ~= false) and 1 or 0
                T.eq(count(lines, "EasyGear |"), wanted, "one block for gear, none otherwise: " .. D.text())
                if D.tooltip.hasHotkey then
                    T.ok(lines[#lines] == "Show Comparison" or lines[#lines] == "Hide Comparison", "the hint stays last: " .. D.text())
                end
                T.eq(count(lines, "Pawn: 12% upgrade"), item and item.isGear and 1 or 0, "Pawn's lines once")
                T.ok(count(lines, "EasyGear: ") <= 1, "one pick line at most: " .. D.text())
            elseif action == 5 then
                W.env.DialogueUI_DB.TooltipShowItemComparison = not W.env.DialogueUI_DB.TooltipShowItemComparison
            elseif action == 6 then
                W.EG:Set(({ "showDialogueUI", "showTooltip", "showQuestIcons", "tooltipDiff" })[rnd(4)], rnd(3) ~= 1)
            elseif action == 7 then
                D.hide() D.show()
            else
                W.flush()
            end
            D.tick(0.3)
            local shown, shownIndex = 0, nil
            for _, bt in ipairs(buttons) do if checked(bt) then shown = shown + 1 shownIndex = bt.index end end
            T.ok(shown <= 1, "at most one best choice on screen, step " .. step)
            -- what it has to be: the best of the choices by the rules of the quest window (computed from the client's data)
            local entries = {}
            for _, bt in ipairs(buttons) do
                if bt.type == "choice" then
                    entries[#entries + 1] = { index = bt.index, link = W.env.GetQuestItemLink("choice", bt.index), count = 1, apiUsable = true }
                end
            end
            local marksOn = W.EG:Get("showDialogueUI") ~= false and W.EG:Get("showQuestIcons") ~= false
            if marksOn and #entries >= 2 then
                T.eq(shownIndex, (W.EG.Recommend.BestReward(entries)), "the check mark sits on the best choice, step " .. step)
            else
                T.eq(shown, 0, "no check mark with nothing to choose from or with the marks off, step " .. step)
            end
            T.eq(W.EG.lastError, nil, "no internal error, step " .. step .. ": " .. tostring(W.EG.lastError and W.EG.lastError.err))
        end
    end)
end
