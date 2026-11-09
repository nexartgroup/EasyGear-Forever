-- Group.lua and Classes.lua: group members, inspecting them, the verdict for other classes, the violet star
return function(T)
    local F = require("fixtures")

    local ids = 30000
    local function piece(W, loc, ilvl, stats, extra)
        ids = ids + 1
        return F.gear(W, ids, "Piece" .. ids, loc, ilvl, stats, extra)
    end

    -- nine worn pieces of one armor type: head, neck, shoulder, chest, waist, legs, feet, wrist, hands
    local WORN = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST",
                   [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST",
                   [10] = "INVTYPE_HAND" }
    local ORDER = { 1, 2, 3, 5, 6, 7, 8, 9, 10 }
    local function wornSet(W, sub, ilvl, stats, count)
        local gear = {}
        for n, slot in ipairs(ORDER) do
            if not count or n <= count then
                gear[slot] = piece(W, WORN[slot], ilvl, stats, { subclassID = (slot == 2) and 0 or sub })
            end
        end
        return gear
    end
    local CASTER = { INT = 10, SP = 10 }

    -- The player is the Arms warrior of the other tests (level 60). setup(W, G) adds the party before the game starts.
    local function world(setup, opts)
        local G
        local W = T.world(F.arms(opts), function(w)
            w.I = F.armsWarrior(w)
            G = w.installGroup()
            if setup then setup(w, G) end
        end)
        return W, G
    end
    local function star(b)
        return b.EasyGearArrow and b.EasyGearArrow:IsShown() and b.EasyGearArrow.__atlas == "tradeskills-star" or false
    end
    local function arrow(b)
        return b.EasyGearArrow and b.EasyGearArrow:IsShown() and b.EasyGearArrow.__atlas == "bags-greenarrow" or false
    end
    local function nobody(W) return #W.EG.Group.list end

    ------------------------------------------------------------------ members
    T.test("group: the party members are listed with class, level and name - the player is not one of them", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", level = 58 })
            g.add("party2", { name = "Eve", class = "MAGE" })
        end)
        local list = W.EG.Group.list
        T.eq(#list, 2)
        T.eq(list[1].name, "Bob") T.eq(list[1].class, "PRIEST") T.eq(list[1].level, 58) T.eq(list[1].unit, "party1")
        T.eq(list[2].name, "Eve") T.eq(list[2].class, "MAGE") T.eq(list[2].className, "Mage")
        G.remove("party2")
        G.rosterChanged() W.flush()
        T.eq(#W.EG.Group.list, 1, "Eve left")
        G.remove("party1")
        G.rosterChanged() W.flush()
        T.eq(nobody(W), 0, "nobody is left")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: a companion that is no player is not a member", function()
        local W = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST" })
            g.add("party2", { name = "Follower", class = "WARRIOR", npc = true })
        end)
        T.eq(#W.EG.Group.list, 1) T.eq(W.EG.Group.list[1].name, "Bob")
    end)

    T.test("group: not in a group - nothing to do, no timer keeps running", function()
        local W = T.world(F.ARMS, function(w) w.I = F.armsWarrior(w) w.installGroup() end)
        T.eq(nobody(W), 0)
        W.advance(60)
        T.eq(W.EG.Group.Wanted(), false)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: a raid counts only when the setting says so; the player's own raid token is skipped", function()
        local W, G = world(function(w, g)
            g.setRaid(true)
            g.add("raid1", { isPlayer = true })
            g.add("raid2", { name = "Bob", class = "PRIEST" })
            g.add("raid3", { name = "Eve", class = "MAGE" })
        end)
        T.eq(nobody(W), 0, "off by default: in a raid almost everything would be 'better for somebody'")
        W.EG:Set("groupRaid", true)
        W.flush()
        T.eq(nobody(W), 2) T.eq(W.EG.Group.list[1].name, "Bob") T.eq(W.EG.Group.list[2].name, "Eve")
        W.EG:Set("groupRaid", false)
        W.flush()
        T.eq(nobody(W), 0)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: members keep their data when the unit tokens shift", function()
        local gear
        local W, G = world(function(w, g)
            gear = wornSet(w, 1, 30, CASTER)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear, guid = "Player-1-BOB" })
            g.add("party2", { name = "Eve", class = "MAGE", guid = "Player-1-EVE" })
        end)
        W.advance(30)
        local bob = W.EG.Group.list[1]
        T.ok(W.EG.Group.HasData(bob))
        local requests = G.requests()
        -- Eve leaves: Bob moves from party1 to party1 (same), then Bob gets the token party2
        G.remove("party1") G.remove("party2")
        G.add("party2", { name = "Bob", class = "PRIEST", gear = gear, guid = "Player-1-BOB" })
        G.rosterChanged() W.advance(5)
        T.eq(#W.EG.Group.list, 1) T.eq(W.EG.Group.list[1].unit, "party2")
        T.ok(W.EG.Group.HasData(W.EG.Group.list[1]), "the data of the same guid stays")
        T.eq(G.requests(), requests, "no new request for a member who was just read")
    end)

    ------------------------------------------------------------------ inspecting
    T.test("group: members are inspected one after the other, at least 2.5 seconds apart, and their gear is read", function()
        local gear
        local W, G = world(function(w, g)
            gear = wornSet(w, 1, 30, CASTER)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            g.add("party2", { name = "Eve", class = "MAGE", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(G.requests("party1"), 1) T.eq(G.requests("party2"), 1)
        T.ok(G.notified[2].at - G.notified[1].at >= 2.5, "spaced out: the server drops requests when flooded")
        T.ok(G.notified[2].at - G.notified[1].at < 5, "and not slower than needed: an answer releases the line")
        local bob = W.EG.Group.list[1]
        T.ok(W.EG.Group.HasData(bob)) T.eq(bob.count, 9) T.eq(bob.complete, true)
        T.eq(bob.gear[5], gear[5]) T.eq(bob.gear[1], gear[1])
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: the member whose data are oldest is asked first", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Eve", class = "MAGE", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party3", { name = "Zed", class = "WARLOCK", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(G.requests(), 3)
        G.gearChanged("party3") G.gearChanged("party2") G.gearChanged("party1")      -- all three are due at once
        W.advance(20)
        T.eq(G.requests(), 6)
        T.eq(G.notified[4].unit, "party1", "the one read first is the first to be read again")
        T.eq(G.notified[5].unit, "party2") T.eq(G.notified[6].unit, "party3")
    end)

    T.test("group: nothing is requested in combat, with an inspect window open, out of range, offline or when switched off", function()
        -- prepare(w, g) runs before the game starts; the settings come in as saved variables
        local function requestsWith(prepare)
            local W, G = world(function(w, g)
                g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
                prepare(w, g)
            end)
            W.advance(60)
            return G.requests(), W, G
        end
        T.eq((requestsWith(function(_, g) g.combat = true end)), 0, "in combat")
        T.eq((requestsWith(function(_, g) g.lockdown = true end)), 0, "in a lockdown of the interface")
        T.eq((requestsWith(function(_, g) g.inspectFrameShown = true end)), 0, "while the player inspects somebody")
        T.eq((requestsWith(function(_, g) g.talentInspect = true end)), 0, "while the player looks at somebody's talents")
        T.eq((requestsWith(function(_, g) g.members.party1.inspectable = false end)), 0, "a unit the client does not let us inspect")
        T.eq((requestsWith(function(_, g) g.members.party1.distance = 40 end)), 0, "out of range")
        T.eq((requestsWith(function(_, g) g.members.party1.visible = false end)), 0, "not visible")
        T.eq((requestsWith(function(_, g) g.members.party1.connected = false end)), 0, "offline")
        T.eq((requestsWith(function(w) w.env.EasyGearDB = { groupInspect = false } end)), 0, "inspecting switched off")
        T.eq((requestsWith(function(w) w.env.EasyGearDB = { showGroupHints = false } end)), 0, "group hints switched off")
        T.eq((requestsWith(function() end)), 1, "and with nothing in the way it happens once")

        local _, W, G = requestsWith(function(_, g) g.combat = true end)
        G.combat = false
        W.advance(10)
        T.eq(G.requests(), 1, "the combat is over: the member is read")
        G.members.party1.distance = 100
        G.rosterChanged()
        local W2, G2 = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER), distance = 80 })
        end)
        W2.advance(30)
        T.eq(G2.requests(), 0)
        G2.members.party1.distance = 20
        W2.advance(10)
        T.eq(G2.requests(), 1, "he came close: read")
    end)

    T.test("group: a member who does not answer is asked again only after a growing pause", function()
        local W, G = world(function(w, g)
            g.answers = false
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(120)
        local n = G.requests()
        T.ok(n >= 2 and n <= 5, "a few tries, no flood: " .. n)
        local bob = W.EG.Group.list[1]
        T.ok(bob.tries >= 1 and bob.nextTry ~= nil, "the failures are counted")
        T.eq(W.EG.Group.HasData(bob), false)
        G.answers = true
        W.advance(400)
        T.ok(W.EG.Group.HasData(W.EG.Group.list[1]), "when he answers again he is read")
    end)

    T.test("group: an error in NotifyInspect is contained and does not stop the loop", function()
        local W, G = world(function(w, g)
            g.failNotify = true
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(40)
        T.eq(W.EG.lastError, nil, "pcall around the request")
        G.failNotify = false
        W.advance(400)
        T.ok(W.EG.Group.HasData(W.EG.Group.list[1]), "later he is read")
    end)

    T.test("group: the gear of a unit token is only attributed to the member the token still belongs to", function()
        local W, G = world(function(w, g)
            w.env.EasyGearDB = { groupInspect = false }
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER), guid = "Player-1-BOB" })
        end)
        W.advance(5)
        local bob = W.EG.Group.list[1]
        G.members.party1.guid = "Player-1-OTHER"             -- the token moved on to another player
        G.inspectedGUID = "Player-1-OTHER"
        T.eq(W.EG.Group.Read(bob), false)
        T.eq(W.EG.Group.HasData(bob), false, "nothing was taken over")
        G.members.party1.guid = "Player-1-BOB"
        G.inspectedGUID = "Player-1-BOB"
        T.eq(W.EG.Group.Read(bob), true) T.eq(bob.count, 9)
    end)

    T.test("group: an inspection started by hand is taken along - also when the addon does not inspect itself", function()
        local W, G = world(function(w, g)
            w.env.EasyGearDB = { groupInspect = false }
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(G.requests(), 0)
        T.eq(W.EG.Group.HasData(W.EG.Group.list[1]), false)
        G.inspectByHand("party1")
        W.flush()
        T.ok(W.EG.Group.HasData(W.EG.Group.list[1]))
        local stranger = G.add("target", { name = "Stranger", class = "ROGUE" })
        G.inspectByHand("target")                   -- somebody who is not in the group: ignored
        T.eq(#W.EG.Group.list, 1) T.ok(stranger)
        T.eq(W.EG.Group.list[1].count, 9, "Bob's data are not overwritten by the stranger's")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: a changed set of equipment reads the member again soon, a quiet one only after five minutes", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(G.requests(), 1)
        W.advance(200)
        T.eq(G.requests(), 1, "nothing changed")
        G.gearChanged("party1")
        W.advance(10)
        T.eq(G.requests(), 2, "UNIT_INVENTORY_CHANGED marks the member")
        G.gearChanged("player")                     -- the player's own change is not a member's
        G.gearChanged("target")
        W.advance(10)
        T.eq(G.requests(), 2)
        W.advance(320)
        T.eq(G.requests(), 3, "five minutes later he is read again")
    end)

    T.test("group: an incomplete read is repeated after 20 seconds, and empty slots do not count in the meantime", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER, 3) })
        end)
        W.advance(15)
        local bob = W.EG.Group.list[1]
        T.eq(bob.count, 3) T.eq(bob.complete, false)
        T.eq(G.requests(), 1)
        W.advance(30)
        T.ok(G.requests() >= 2, "read again")
    end)

    T.test("group: when the client does not hand out a link yet, the item number stands in", function()
        local gear
        local W, G = world(function(w, g)
            gear = wornSet(w, 1, 30, CASTER)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            g.unreadable[5] = true
        end)
        W.advance(30)
        local bob = W.EG.Group.list[1]
        T.eq(type(bob.gear[5]), "number", "the chest is only known by its number")
        T.eq(bob.gear[1], gear[1]) T.eq(bob.count, 9)
        T.ok(W.EG.Items.Get(bob.gear[5]), "and the number is enough to rate it")
    end)

    T.test("group: data that are secret to the addon are not used", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Eve", class = "MAGE", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(#W.EG.Group.list, 2)
        -- the client hides the class of a new member (restricted unit identity): he is skipped, nothing raises
        W.env.issecretvalue = function(v) return v == "WARLOCK" end
        G.add("party3", { name = "Zed", class = "WARLOCK" })
        W.EG.Group.Refresh()
        T.eq(#W.EG.Group.list, 2) T.eq(W.EG.Group.list[2].name, "Eve")
        -- a member we know keeps his class when a later answer is secret
        W.env.issecretvalue = function(v) return v == "MAGE" end
        W.EG.Group.Refresh()
        T.eq(#W.EG.Group.list, 3)
        W.env.issecretvalue = nil
        W.EG.Group.Refresh()
        T.eq(#W.EG.Group.list, 3)
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ class rules
    T.test("classes: armor types by class and level - plate wearers do not wear cloth, mail starts at 40", function()
        local W = world()
        local C = W.EG.Classes
        local function usable(class, level, item, worn)
            return C.Usable({ class = class, level = level }, item, worn)
        end
        local function armor(sub, loc) return { classID = 4, subclassID = sub, equipLoc = loc or "INVTYPE_CHEST", reqLevel = 0 } end
        T.eq(usable("WARRIOR", 60, armor(4)), true)
        T.eq(usable("WARRIOR", 39, armor(4)), true, "plate from level 40: one level short is still a candidate")
        T.eq(usable("WARRIOR", 38, armor(4)), false, "two levels short is not")
        local ok, why = usable("MAGE", 60, armor(4))
        T.eq(ok, false) T.eq(why, "type")
        T.eq(usable("WARRIOR", 60, armor(1)), false, "a plate wearer in cloth: no improvement")
        T.eq(usable("WARRIOR", 60, armor(2)), false)
        T.eq(usable("WARRIOR", 60, armor(1), armor(1)), true, "but cloth that is worn there stays comparable")
        T.eq(usable("WARRIOR", 39, armor(3)), true, "before 40 mail is the best a warrior wears")
        T.eq(usable("WARRIOR", 39, armor(1)), false)
        T.eq(usable("HUNTER", 39, armor(3)), true, "mail from 40: one level short") T.eq(usable("HUNTER", 38, armor(3)), false)
        T.eq(usable("HUNTER", 39, armor(2)), true, "and leather, the best he wears now, stays a candidate")
        T.eq(usable("HUNTER", 40, armor(3)), true) T.eq(usable("HUNTER", 40, armor(2)), false)
        T.eq(usable("HUNTER", 40, armor(2), armor(2)), true)
        T.eq(usable("SHAMAN", 40, armor(3)), true) T.eq(usable("SHAMAN", 20, armor(3)), false)
        T.eq(usable("PALADIN", 60, armor(4)), true) T.eq(usable("PALADIN", 60, armor(3)), false)
        T.eq(usable("ROGUE", 60, armor(2)), true) T.eq(usable("ROGUE", 60, armor(3)), false)
        T.eq(usable("DRUID", 60, armor(2)), true) T.eq(usable("DRUID", 60, armor(4)), false)
        for _, class in ipairs({ "PRIEST", "MAGE", "WARLOCK" }) do
            T.eq(usable(class, 60, armor(1)), true, class) T.eq(usable(class, 60, armor(2)), false, class)
        end
        for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
                               "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND" }) do
            T.eq(usable("WARRIOR", 60, armor(1, loc)), false, "cloth in " .. loc)
            T.eq(usable("WARRIOR", 60, armor(4, loc)), true, "plate in " .. loc)
            T.eq(usable("MAGE", 60, armor(1, loc)), true, "cloth in " .. loc .. " for a mage")
        end
        -- no type for rings, neck, trinkets and held items; cloaks are cloth but everybody wears them
        for _, loc in ipairs({ "INVTYPE_FINGER", "INVTYPE_NECK", "INVTYPE_TRINKET", "INVTYPE_HOLDABLE" }) do
            T.eq(usable("WARRIOR", 60, armor(0, loc)), true, loc) T.eq(usable("MAGE", 60, armor(0, loc)), true, loc)
        end
        T.eq(usable("WARRIOR", 60, armor(1, "INVTYPE_CLOAK")), true) T.eq(usable("MAGE", 60, armor(1, "INVTYPE_CLOAK")), true)
        -- shields and relics
        local shield = armor(6, "INVTYPE_SHIELD")
        for class, can in pairs({ WARRIOR = true, PALADIN = true, SHAMAN = true, ROGUE = false, PRIEST = false, MAGE = false,
                                  HUNTER = false, DRUID = false, WARLOCK = false }) do
            T.eq(usable(class, 60, shield), can, "shield " .. class)
        end
        T.eq(usable("PALADIN", 60, armor(7, "INVTYPE_RELIC")), true) T.eq(usable("SHAMAN", 60, armor(7, "INVTYPE_RELIC")), false)
        T.eq(usable("DRUID", 60, armor(8, "INVTYPE_RELIC")), true) T.eq(usable("SHAMAN", 60, armor(9, "INVTYPE_RELIC")), true)
        T.eq(usable("MAGE", 60, armor(9, "INVTYPE_RELIC")), false)
        T.eq(usable("DEATHKNIGHT", 60, armor(4)), false, "an unknown class wears nothing")
        T.eq(C.BestArmor("WARRIOR", 60), 4) T.eq(C.BestArmor("WARRIOR", 39), 3) T.eq(C.BestArmor("HUNTER", 40), 3)
        T.eq(C.BestArmor("MAGE", 1), 1) T.eq(C.BestArmor("NOBODY", 60), nil)
        T.eq(C.Known("MAGE"), true) T.eq(C.Known("NOBODY"), false) T.eq(C.Known(nil), false)
    end)

    T.test("classes: weapon types by class", function()
        local W = world()
        local C = W.EG.Classes
        local function weapon(sub) return { classID = 2, subclassID = sub, equipLoc = "INVTYPE_WEAPON", reqLevel = 0 } end
        local function can(class, sub) return (C.Usable({ class = class, level = 60 }, weapon(sub))) end
        local AXE, AXE2, BOW, GUN, MACE, MACE2, POLE, SWORD, SWORD2, STAFF, FIST, DAGGER, THROWN, XBOW, WAND =
            0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18, 19
        T.eq(can("MAGE", DAGGER), true) T.eq(can("MAGE", SWORD), true) T.eq(can("MAGE", SWORD2), false)
        T.eq(can("MAGE", WAND), true) T.eq(can("MAGE", MACE), false) T.eq(can("MAGE", STAFF), true)
        T.eq(can("PRIEST", MACE), true) T.eq(can("PRIEST", SWORD), false) T.eq(can("PRIEST", MACE2), false)
        T.eq(can("ROGUE", SWORD), true) T.eq(can("ROGUE", SWORD2), false) T.eq(can("ROGUE", FIST), true)
        T.eq(can("ROGUE", STAFF), false) T.eq(can("ROGUE", XBOW), true)
        T.eq(can("HUNTER", BOW), true) T.eq(can("HUNTER", GUN), true) T.eq(can("HUNTER", MACE), false)
        T.eq(can("HUNTER", SWORD2), true) T.eq(can("HUNTER", WAND), false)
        T.eq(can("DRUID", MACE2), true) T.eq(can("DRUID", SWORD), false) T.eq(can("DRUID", POLE), true)
        T.eq(can("SHAMAN", AXE2), true) T.eq(can("SHAMAN", SWORD), false) T.eq(can("SHAMAN", MACE2), true)
        T.eq(can("PALADIN", SWORD2), true) T.eq(can("PALADIN", DAGGER), false) T.eq(can("PALADIN", BOW), false)
        T.eq(can("WARRIOR", DAGGER), true) T.eq(can("WARRIOR", WAND), false) T.eq(can("WARRIOR", THROWN), true)
        T.eq(can("WARLOCK", SWORD), true) T.eq(can("WARLOCK", AXE), false)
    end)

    T.test("classes: the class line of the tooltip, in both genders, and the level", function()
        local W = world()
        local C = W.EG.Classes
        local item = { classID = 4, subclassID = 1, equipLoc = "INVTYPE_CHEST", reqLevel = 20, classesText = "Priest, Mage" }
        local ok, why = C.Usable({ class = "WARRIOR", level = 60 }, item)
        T.eq(ok, false) T.eq(why, "class")
        T.eq((C.Usable({ class = "MAGE", level = 60 }, item)), true)
        T.eq((C.Usable({ class = "PRIEST", level = 60, className = "Priest" }, item)), true)
        local need
        ok, why, need = C.Usable({ class = "MAGE", level = 19 }, item)
        T.eq(ok, true) T.eq(why, nil) T.eq(need, 20, "one level short: usable from level 20")
        ok, why, need = C.Usable({ class = "MAGE", level = 18 }, item)
        T.eq(ok, false) T.eq(why, "level") T.eq(need, nil)
        ok, why, need = C.Usable({ class = "MAGE", level = 20 }, item)
        T.eq(ok, true) T.eq(need, nil, "no level to wait for")
        -- a language with gendered class names: the list has the male form, the unit the female one
        W.env.LOCALIZED_CLASS_NAMES_FEMALE.PRIEST = "Priestess"
        item.classesText = "Priestess, Mage"
        T.eq((C.Usable({ class = "PRIEST", level = 60, className = "Priestess" }, item)), true)
        item.classesText = "Priest"
        T.eq((C.Usable({ class = "PRIEST", level = 60, className = "Priestess" }, item)), true, "male form in the list")
        W.env.LOCALIZED_CLASS_NAMES_FEMALE.PRIEST = "Heilerin"       -- a form that does not contain the male one
        item.classesText = "Heilerin"
        T.eq((C.Usable({ class = "PRIEST", level = 60 }, item)), true, "the female form from the client's table alone")
        -- without a table entry for the class the name of the unit itself has to do
        W.env.LOCALIZED_CLASS_NAMES_MALE.PRIEST = nil
        W.env.LOCALIZED_CLASS_NAMES_FEMALE.PRIEST = nil
        T.eq((C.Usable({ class = "PRIEST", level = 60, className = "Heilerin" }, item)), true, "the name the unit reports")
        -- without any name for the class the line cannot be checked
        T.eq((C.Usable({ class = "PRIEST", level = 60 }, item)), false)
        T.eq((C.Usable(nil, item)), false) T.eq((C.Usable({ class = "PRIEST" }, nil)), false)
    end)

    T.test("classes: an item that asks for one level more than the member has is still named - two more are not", function()
        local W = world()
        local C = W.EG.Classes
        T.eq(C.LEVEL_TOLERANCE, 1)
        local function check(class, level, item)
            local ok, why, need = C.Usable({ class = class, level = level }, item)
            return ok, why, need
        end
        local function piece2(sub, loc, req) return { classID = 4, subclassID = sub, equipLoc = loc or "INVTYPE_FINGER", reqLevel = req } end
        local ok, why, need = check("MAGE", 20, piece2(0, nil, 21))
        T.eq(ok, true) T.eq(why, nil) T.eq(need, 21)
        ok, why, need = check("MAGE", 20, piece2(0, nil, 22))
        T.eq(ok, false) T.eq(why, "level") T.eq(need, nil)
        ok, _, need = check("MAGE", 20, piece2(0, nil, 20))
        T.eq(ok, true) T.eq(need, nil)
        ok, _, need = check("MAGE", 20, piece2(0, nil, 1))
        T.eq(ok, true) T.eq(need, nil)
        -- the level of the armor type counts like the level of the item
        ok, _, need = check("WARRIOR", 39, piece2(4, "INVTYPE_CHEST", 35))
        T.eq(ok, true) T.eq(need, 40, "plate from level 40, whatever the item asks")
        ok, why = check("WARRIOR", 39, piece2(4, "INVTYPE_CHEST", 41))
        T.eq(ok, false) T.eq(why, "level", "the item itself asks too much")
        ok, _, need = check("HUNTER", 39, piece2(3, "INVTYPE_HEAD", 39))
        T.eq(ok, true) T.eq(need, 40)
        ok, why = check("HUNTER", 30, piece2(3, "INVTYPE_HEAD", 30))
        T.eq(ok, false) T.eq(why, "type", "ten levels short of mail")
        -- the level 39 warrior may be shown his next chestpiece (plate) and what he wears now (mail), but no cloth
        T.eq((check("WARRIOR", 39, piece2(3, "INVTYPE_CHEST", 30))), true)
        T.eq((check("WARRIOR", 39, piece2(1, "INVTYPE_CHEST", 30))), false)
        -- a shield or relic has no level of its own
        ok, _, need = check("PALADIN", 10, { classID = 4, subclassID = 6, equipLoc = "INVTYPE_SHIELD", reqLevel = 10 })
        T.eq(ok, true) T.eq(need, nil)
    end)

    T.test("items: the class line of an item is kept in its data", function()
        local W = world(function(w)
            w.I.line = piece(w, "INVTYPE_CHEST", 60, CASTER, { subclassID = 1, classes = "Priest, Mage" })
            w.I.free = piece(w, "INVTYPE_CHEST", 60, CASTER, { subclassID = 1 })
        end)
        T.eq(W.EG.Items.Get(W.I.line).classesText, "Priest, Mage")
        T.eq(W.EG.Items.Get(W.I.free).classesText, nil)
        T.eq(W.EG.Items.Get(W.I.line).usable, false, "red for the warrior: the player's own verdict is unchanged")
    end)

    ------------------------------------------------------------------ profiles of members
    T.test("group: the profile of a member follows his talents, else the class default, and the level", function()
        local W, G = world(function(w, g)
            local gear = wornSet(w, 1, 30, CASTER)
            g.add("party1", { name = "Pri", class = "PRIEST", tab = 3, gear = gear })
            g.add("party2", { name = "Pal", class = "PALADIN", gear = gear })
            g.add("party3", { name = "Mag", class = "MAGE", level = 40, tab = 1, gear = gear })
            g.add("party4", { name = "War", class = "WARRIOR", level = 40, tab = 3, gear = gear })
        end)
        W.advance(60)
        local function profile(i) return W.EG.Group.ProfileOf(W.EG.Group.list[i]) end
        T.eq(profile(1).spec.id, "PRIEST_SHADOW") T.eq(profile(1).source, "spec")
        T.eq(W.EG.Group.list[1].tab, 3)
        T.eq(profile(2).spec.id, "PALADIN_ALLROUND") T.eq(profile(2).source, "class")
        T.eq(profile(3).spec.id, "MAGE_LEVELING", "below the maximum level: the leveling profile") T.eq(profile(3).source, "spec")
        T.eq(profile(4).spec.id, "WARRIOR_PROT", "tank and healer trees keep their profile while leveling")
        T.near(profile(1).weights.HIT, 1.2) T.ok(profile(2).weights.STR, 'the paladin default is a melee profile')
        W.EG:Set("autoLeveling", false)
        T.eq(profile(3).spec.id, "MAGE_ARCANE", "the setting for the leveling profile applies to members, too")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: healer and tank trees keep their profile below the maximum level", function()
        local W = world(function(w, g)
            g.add("party1", { name = "Hea", class = "PRIEST", level = 40, tab = 2, gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Tan", class = "PALADIN", level = 40, tab = 2, gear = wornSet(w, 4, 30, CASTER) })
            g.add("party3", { name = "Dps", class = "PALADIN", level = 40, tab = 3, gear = wornSet(w, 4, 30, CASTER) })
        end)
        W.advance(40)
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[1]).spec.id, "PRIEST_HOLY")
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[2]).spec.id, "PALADIN_PROT")
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[3]).spec.id, "PALADIN_LEVELING")
    end)

    T.test("group: a member whose talents are unknown gets the leveling profile below the maximum level, else all-round", function()
        local W = world(function(w, g)
            g.add("party1", { name = "Low", class = "MAGE", level = 40, gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Max", class = "MAGE", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[1]).spec.id, "MAGE_LEVELING")
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[2]).spec.id, "MAGE_ALLROUND")
        W.EG:Set("autoLeveling", false)
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[1]).spec.id, "MAGE_LEVELING", "without talents the level decides")
    end)

    T.test("group: leveling profiles of hybrid classes use the variant of the member's tree", function()
        local W = world(function(w, g)
            g.add("party1", { name = "Sha", class = "SHAMAN", level = 40, tab = 1, gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Sha2", class = "SHAMAN", level = 40, tab = 2, gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        local ele, enh = W.EG.Group.ProfileOf(W.EG.Group.list[1]), W.EG.Group.ProfileOf(W.EG.Group.list[2])
        T.eq(ele.spec.id, "SHAMAN_LEVELING") T.eq(enh.spec.id, "SHAMAN_LEVELING")
        T.near(ele.weights.SP, 1.0, 1e-9, "elemental variant: spell power first")
        T.eq(enh.weights.AGI, 0.9)
        local own = W.EG.Profiles.WeightsForTab(W.EG.Specs.BY_ID.SHAMAN_LEVELING, nil)
        T.eq(own.AGI, 0.9) T.eq(W.EG.Profiles.WeightsForTab(nil, 1).SP, nil)
    end)

    T.test("group: the druid's cat and bear share a tree - the default is the cat", function()
        local W = world(function(w, g)
            g.add("party1", { name = "Dru", class = "DRUID", tab = 2, gear = wornSet(w, 2, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[1]).spec.id, "DRUID_CAT")
    end)

    ------------------------------------------------------------------ verdicts
    local function bobAndRobe(extra)
        local robe, gear
        local W, G = world(function(w, g)
            gear = wornSet(w, 1, 30, CASTER)
            gear[5] = piece(w, "INVTYPE_CHEST", 30, { INT = 10, SP = 40 }, { subclassID = 1 })
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
            w.bag(0, 16, { [1] = robe })
            if extra then extra(w, g, gear) end
        end)
        W.advance(30)
        return W, G, robe, gear
    end

    T.test("group: a worn item the client does not know yet - no answer is kept until it arrives", function()
        local robe
        local W = world(function(w, g)
            local gear = wornSet(w, 1, 30, CASTER)
            gear[5] = piece(w, "INVTYPE_CHEST", 30, { INT = 10, SP = 40 }, { subclassID = 1, uncached = true })
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
            w.bag(0, 16, { [1] = robe })
        end)
        W.advance(30)
        local list, waiting = W.EG.Group.Beneficiaries(robe)
        T.eq(#list, 0) T.eq(waiting, true, "the chest of Bob is still loading")
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), false)
        local chestID = W.EG.Items.IDFromLink(W.EG.Group.list[1].gear[5])
        W.state.items[chestID].uncached = nil
        W.fire("GET_ITEM_INFO_RECEIVED", chestID, true)
        W.advance(5)
        T.eq(#W.EG.Group.Beneficiaries(robe), 1, "now the verdict is there")
        T.eq(star(b), true, "and the symbol follows without being touched")
    end)

    T.test("group: better for a member and no upgrade for you - the violet star, in the corner of the arrow", function()
        local W, _, robe = bobAndRobe()
        T.eq(W.EG.Score.UpgradeState(robe), nil, "nothing for the warrior")
        local list = W.EG.Group.Beneficiaries(robe)
        T.eq(#list, 1) T.eq(list[1].member.name, "Bob") T.eq(list[1].slot, 5) T.eq(list[1].empty, false)
        T.ok(list[1].delta > 0 and list[1].percent > 50)
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true) T.eq(arrow(b), false)
        local tex = b.EasyGearArrow
        T.eq(tex.__desaturated, true) T.near(tex.__vertex[1], 0.75) T.near(tex.__vertex[2], 0.40) T.near(tex.__vertex[3], 1.0)
        T.eq((tex:GetPoint(1)), "TOPLEFT")
        T.eq(tex:GetWidth(), 18)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: an upgrade for you keeps the green arrow, the tooltip still names the member", function()
        local plate
        local W = world(function(w, g)
            g.add("party1", { name = "Pat", class = "PALADIN", gear = wornSet(w, 4, 30, { STR = 10, STA = 10 }) })
            plate = piece(w, "INVTYPE_CHEST", 60, { STR = 40, STA = 30 }, { subclassID = 4, armor = 600 })
        end)
        W.advance(30)
        T.eq(W.EG.Score.UpgradeState(plate), "UPGRADE")
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, plate)
        T.eq(arrow(b), true) T.eq(star(b), false)
        local tip = W.tooltipFor(b, plate)
        T.eq(tip:HasLine(W.EG.L.GROUP_BETTER), true) T.eq(tip:HasLine("Pat"), true)
        T.eq(tip:HasLine(W.EG.L.UPGRADE), true, "and the verdict for the player is there as before")
    end)

    T.test("group: nobody gains, or the item is not gear - no star, no lines", function()
        local W, _, robe = bobAndRobe(function(w)
            w.I.worse = piece(w, "INVTYPE_CHEST", 10, { INT = 1 }, { subclassID = 1 })
            w.I.potion = F.gear(w, 39001, "Potion", "", 1, {})
            w.I.gray = piece(w, "INVTYPE_CHEST", 90, { INT = 90, SP = 90 }, { subclassID = 1, quality = 0 })
        end)
        for _, link in ipairs({ W.I.worse, W.I.potion, W.I.gray }) do
            local b = W.bagButton(0, 2)
            W.env.SetItemButtonQuality(b, 3, link)
            T.eq(star(b), false)
            T.eq(W.tooltipFor(b, link):HasLine(W.EG.L.GROUP_BETTER), false)
        end
        T.eq(W.EG.Group.Beneficiaries(W.I.worse) ~= nil and #W.EG.Group.Beneficiaries(W.I.worse), 0)
        T.eq(W.EG.Group.Beneficiaries(W.I.potion), nil)
        T.eq(W.EG.Group.Beneficiaries(nil), nil)
        T.ok(robe)
    end)

    T.test("score: the level of the rated character decides the weight of the item level and of sockets", function()
        local W = world(function(w) w.I.socketed = piece(w, "INVTYPE_CHEST", 60, { STR = 10 }, { sockets = 1 }) end)
        local S = W.EG.Score
        local eff60, base = S.EffectiveIlvlWeight()
        local eff30 = S.EffectiveIlvlWeight(30)
        T.near(eff60, base) T.near(eff30, base / 2, 1e-9, "level 30 of 60")
        T.near((S.EffectiveIlvlWeight(90)), base, 1e-9, "never above the maximum")
        local weights = { STR = 1.0 }
        T.near(S.SocketPoints(weights, 30) * 2, S.SocketPoints(weights, 60), 1e-9)
        T.near(S.SocketPoints(weights), S.SocketPoints(weights, 60), 1e-9, "the player's level is the default")
        local item = W.EG.Items.Get(W.I.socketed)
        local rows60, at60 = S.Breakdown(item, 5, weights)
        local rows30, at30 = S.Breakdown(item, 5, weights, 30)
        T.ok(at30 < at60, "a lower level rates the same item lower")
        local function socketWeight(rows)
            for _, r in ipairs(rows) do if r.key == W.EG.Stats.SOCKET then return r.weight end end
        end
        T.near(socketWeight(rows30) * 2, socketWeight(rows60), 1e-9, "the empty socket is worth less at level 30, too")
        W.EG:Set("ilvlScaling", false)
        T.near((S.EffectiveIlvlWeight(30)), base, 1e-9, "without scaling the level does not matter")
    end)

    T.test("group: the level of the member scales the item level part of the verdict", function()
        -- two mages of the same tree with the same worn chest, one level 60, one level 30; the new chest differs only in its
        -- item level: the gain is 14 % at level 60 and 9 % at level 30; a bar at 12 % lets only the first through
        local W = world(function(w, g)
            local function mage(name, level)
                local gear = wornSet(w, 1, 30, CASTER)
                gear[5] = piece(w, "INVTYPE_CHEST", 30, { SP = 20 }, { subclassID = 1 })
                g.add(name == "High" and "party1" or "party2", { name = name, class = "MAGE", level = level, tab = 3, gear = gear })
            end
            mage("High", 60) mage("Low", 30)
            w.I.better = piece(w, "INVTYPE_CHEST", 40, { SP = 20 }, { subclassID = 1 })
        end)
        W.EG:Set("autoLeveling", false) W.EG:Set("minDeltaPercent", 12)
        W.advance(30)
        local list = W.EG.Group.Beneficiaries(W.I.better)
        T.eq(#list, 1) T.eq(list[1].member.name, "High")
        W.EG:Set("minDeltaPercent", 8)
        list = W.EG.Group.Beneficiaries(W.I.better)
        T.eq(#list, 2, "both pass a lower bar")
    end)

    T.test("group: the threshold is the one of the player but at least 3 percent", function()
        -- Bob's chest is worth 61 points (ilvl 30 -> 15, INT 10 -> 6, SP 40 -> 40)
        local W, _, _, gear = bobAndRobe(function(w)
            w.I.p1 = piece(w, "INVTYPE_CHEST", 30, { INT = 10, SP = 41 }, { subclassID = 1 })     -- +1.6 %
            w.I.p3 = piece(w, "INVTYPE_CHEST", 30, { INT = 10, SP = 43 }, { subclassID = 1 })     -- +4.9 %
        end)
        T.eq(#W.EG.Group.Beneficiaries(W.I.p1), 0, "below 3 %")
        T.eq(#W.EG.Group.Beneficiaries(W.I.p3), 1)
        W.EG:Set("minDeltaPercent", 6)
        T.eq(#W.EG.Group.Beneficiaries(W.I.p3), 0, "the player's own setting counts when it is higher")
        W.EG:Set("minDeltaPercent", 1)
        W.EG:Set("minDelta", 5)
        T.eq(#W.EG.Group.Beneficiaries(W.I.p3), 0, "and the absolute minimum")
        W.EG:Set("minDelta", 0)
        T.eq(#W.EG.Group.Beneficiaries(W.I.p3), 1)
        T.ok(gear)
    end)

    T.test("group: an empty slot counts only when the member's gear is read completely", function()
        local W, G = world(function(w, g)
            local full = wornSet(w, 1, 30, CASTER)
            full[9] = nil                                           -- no wrist piece, eight others
            g.add("party1", { name = "Bob", class = "PRIEST", gear = full })
            local poor = wornSet(w, 1, 30, CASTER, 4)               -- four pieces only: head, neck, shoulder, chest
            g.add("party2", { name = "Poor", class = "MAGE", gear = poor })
            w.I.bracer = piece(w, "INVTYPE_WRIST", 40, { INT = 20, SP = 20 }, { subclassID = 1 })
            w.I.belt = piece(w, "INVTYPE_WAIST", 40, { INT = 20, SP = 20 }, { subclassID = 1 })
        end)
        W.advance(40)
        local bob, poor = W.EG.Group.list[1], W.EG.Group.list[2]
        T.eq(bob.complete, true) T.eq(poor.complete, false)
        local list = W.EG.Group.Beneficiaries(W.I.bracer)
        T.eq(#list, 1) T.eq(list[1].member.name, "Bob") T.eq(list[1].empty, true) T.eq(list[1].percent, nil)
        T.eq(W.tooltipFor(W.bagButton(0, 1), W.I.bracer):HasLine(W.EG.L.NOTHING_EQUIPPED), true)
        local belt = W.EG.Group.Beneficiaries(W.I.belt)
        T.eq(#belt, 1, "the belt replaces Bob's belt and not the poor mage's missing one") T.eq(belt[1].member.name, "Bob")
        T.eq(belt[1].empty, false)
    end)

    T.test("group: of two rings the weaker is compared; a unique ring never goes next to its copy", function()
        local ringA, ringB, uniq
        local W = world(function(w, g)
            local gear = wornSet(w, 1, 30, CASTER)
            ringA = piece(w, "INVTYPE_FINGER", 30, { INT = 10 }, { subclassID = 0 })
            ringB = piece(w, "INVTYPE_FINGER", 30, { INT = 30 }, { subclassID = 0 })
            uniq = piece(w, "INVTYPE_FINGER", 30, { INT = 20, SP = 10 }, { subclassID = 0, unique = true })
            gear[11], gear[12] = ringA, uniq
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            w.I.mid = piece(w, "INVTYPE_FINGER", 30, { INT = 20 }, { subclassID = 0 })
            w.I.high = piece(w, "INVTYPE_FINGER", 50, { INT = 50, SP = 30 }, { subclassID = 0 })
        end)
        W.advance(30)
        local mid = W.EG.Group.Beneficiaries(W.I.mid)
        T.eq(#mid, 1) T.eq(mid[1].slot, 11, "better than the INT 10 ring, not than the unique one with spell power")
        T.eq(#W.EG.Group.Beneficiaries(uniq), 0, "the same unique ring: no gain in either slot")
        local high = W.EG.Group.Beneficiaries(W.I.high)
        T.eq(#high, 1) T.ok(high[1].slot == 11 or high[1].slot == 12)
        T.eq(high[1].slot, 11, "the one with the smaller loss: the weaker ring")
        T.ok(ringB)
    end)

    T.test("group: class, armor type and level decide who can be named", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Pri", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Mag", class = "MAGE", level = 40, gear = wornSet(w, 1, 30, CASTER) })
            g.add("party3", { name = "Lok", class = "WARLOCK", gear = wornSet(w, 1, 30, CASTER) })
            w.I.robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
            w.I.lvl45 = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1, minLevel = 45 })
            w.I.lvl41 = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1, minLevel = 41 })
            w.I.warlockOnly = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1, classes = "Warlock" })
            w.I.leather = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 2 })
        end)
        W.advance(60)
        local function names(link)
            local out = {}
            for _, e in ipairs(W.EG.Group.Beneficiaries(link) or {}) do out[#out + 1] = e.member.name end
            table.sort(out)
            return table.concat(out, ",")
        end
        T.eq(names(W.I.robe), "Lok,Mag,Pri")
        T.eq(names(W.I.lvl45), "Lok,Pri", "the level 40 mage is five levels short")
        T.eq(names(W.I.lvl41), "Lok,Mag,Pri", "one level short is still named ...")
        local entry
        for _, e in ipairs(W.EG.Group.Beneficiaries(W.I.lvl41)) do if e.member.name == "Mag" then entry = e end end
        T.eq(entry.needLevel, 41) T.eq(W.EG.Group.Beneficiaries(W.I.robe)[1].needLevel, nil)
        local tip = W.tooltipFor(W.bagButton(0, 1), W.I.lvl41)
        T.eq(tip:HasLine(string.format(W.EG.L.GROUP_AT_LEVEL, 41)), true, "... with the level he needs")
        T.eq(W.tooltipFor(W.bagButton(0, 1), W.I.robe):HasLine(string.format(W.EG.L.GROUP_AT_LEVEL, 41)), false)
        T.eq(names(W.I.warlockOnly), "Lok")
        T.eq(names(W.I.leather), "", "cloth wearers do not wear leather")
    end)

    -- one member, a few candidates; returns the names of the slots in which each candidate would gain
    local function weaponCase(class, gear, candidates, level)
        local W = world(function(w, g)
            g.add("party1", { name = "M", class = class, level = level, gear = gear(w) })
            w.C = {}
            for key, def in pairs(candidates) do
                w.C[key] = piece(w, def[1], def[2], def[3], def[4])
            end
        end)
        W.advance(30)
        local function slots(key)
            local out = {}
            for _, e in ipairs(W.EG.Group.Beneficiaries(W.C[key]) or {}) do out[#out + 1] = e.slot end
            return table.concat(out, ",")
        end
        return slots, W
    end

    T.test("group: weapons of a one-hander user - one-hand against one-hand, held item against held item", function()
        local slots = weaponCase("PRIEST", function(w)
            local g = wornSet(w, 1, 30, CASTER)
            g[16] = piece(w, "INVTYPE_WEAPON", 30, { SP = 20 }, { subclassID = 4, dps = 10 })
            g[17] = piece(w, "INVTYPE_HOLDABLE", 30, { INT = 10 }, { subclassID = 0 })
            return g
        end, {
            mace = { "INVTYPE_WEAPON", 60, { SP = 60 }, { subclassID = 4, dps = 30 } },
            staff = { "INVTYPE_2HWEAPON", 60, { SP = 90 }, { subclassID = 10, dps = 40 } },
            held = { "INVTYPE_HOLDABLE", 60, { INT = 40 }, { subclassID = 0 } },
            shield = { "INVTYPE_SHIELD", 60, { STA = 40 }, { subclassID = 6, armor = 4000 } },
            sword = { "INVTYPE_WEAPON", 60, { SP = 60 }, { subclassID = 7, dps = 30 } },
            mainhand = { "INVTYPE_WEAPONMAINHAND", 60, { SP = 60 }, { subclassID = 4, dps = 30 } },
            offhand = { "INVTYPE_WEAPONOFFHAND", 60, { SP = 60 }, { subclassID = 4, dps = 30 } },
        })
        T.eq(slots("mace"), "16", "a mace for the main hand; the held item in the off hand is no weapon")
        T.eq(slots("mainhand"), "16")
        T.eq(slots("staff"), "", "he wears a one-hander: no judgement on a change of style")
        T.eq(slots("held"), "17", "a held item against his held item")
        T.eq(slots("shield"), "", "he has no shield, and a priest cannot carry one")
        T.eq(slots("sword"), "", "a priest cannot use swords")
        T.eq(slots("offhand"), "", "his off hand holds no weapon")
    end)

    T.test("group: weapons of a two-hander user - two-hand against two-hand, no change of style", function()
        local slots = weaponCase("WARRIOR", function(w)
            local g = wornSet(w, 4, 30, { STR = 10, STA = 10 })
            g[16] = piece(w, "INVTYPE_2HWEAPON", 30, { STR = 20 }, { subclassID = 8, dps = 30 })
            return g
        end, {
            two = { "INVTYPE_2HWEAPON", 60, { STR = 60 }, { subclassID = 8, dps = 60 } },
            one = { "INVTYPE_WEAPON", 60, { STR = 60 }, { subclassID = 7, dps = 60 } },
            shield = { "INVTYPE_SHIELD", 60, { STA = 40 }, { subclassID = 6, armor = 4000 } },
            weak = { "INVTYPE_2HWEAPON", 20, { STR = 5 }, { subclassID = 8, dps = 10 } },
            wand = { "INVTYPE_RANGEDRIGHT", 60, { SP = 20 }, { subclassID = 19, dps = 40, classID = 2 } },
        })
        T.eq(slots("two"), "16") T.eq(slots("one"), "", "the warrior fights with a two-hander: no judgement on dual wielding")
        T.eq(slots("shield"), "", "and no shield next to a two-hander")
        T.eq(slots("weak"), "") T.eq(slots("wand"), "", "a warrior cannot use wands")
    end)

    T.test("group: a shield is compared with a shield, not with a held item", function()
        local slots = weaponCase("WARRIOR", function(w)
            local g = wornSet(w, 4, 30, { STR = 10, STA = 10 })
            g[16] = piece(w, "INVTYPE_WEAPON", 30, { STR = 20 }, { subclassID = 7, dps = 30 })
            g[17] = piece(w, "INVTYPE_HOLDABLE", 30, { STR = 5 }, { subclassID = 0 })
            return g
        end, {
            shield = { "INVTYPE_SHIELD", 60, { STA = 60, STR = 30 }, { subclassID = 6, armor = 4000 } },
            held = { "INVTYPE_HOLDABLE", 60, { STR = 40 }, { subclassID = 0 } },
            sword = { "INVTYPE_WEAPON", 60, { STR = 60 }, { subclassID = 7, dps = 60 } },
        })
        T.eq(slots("shield"), "", "he wears a held item: no judgement on giving it up for a shield")
        T.eq(slots("held"), "17")
        T.eq(slots("sword"), "16", "the off hand holds no weapon, so only the main hand is compared")
    end)

    T.test("group: the off hand of a dual wielder counts half - the gain decides the slot", function()
        local slots = weaponCase("ROGUE", function(w)
            local g = wornSet(w, 2, 30, { AGI = 10, STA = 10 })
            g[16] = piece(w, "INVTYPE_WEAPON", 30, { AGI = 10 }, { subclassID = 15, dps = 20 })
            g[17] = piece(w, "INVTYPE_WEAPON", 30, { AGI = 10 }, { subclassID = 15, dps = 12 })
            return g
        end, {
            big = { "INVTYPE_WEAPON", 60, { AGI = 10 }, { subclassID = 15, dps = 40 } },
            mid = { "INVTYPE_WEAPON", 60, { AGI = 10 }, { subclassID = 15, dps = 25 } },
            mace = { "INVTYPE_WEAPON", 60, { AGI = 10 }, { subclassID = 4, dps = 40 } },
            two = { "INVTYPE_2HWEAPON", 60, { AGI = 10 }, { subclassID = 8, dps = 60 } },
        })
        T.eq(slots("big"), "16", "40 against 20 is the bigger gain than half of 40 against half of 12")
        T.eq(slots("mid"), "17", "25 against 20 gains less than half of 25 against half of 12")
        T.eq(slots("mace"), "16", "rogues use one-hand maces")
        T.eq(slots("two"), "", "and no two-hander")
    end)

    T.test("group: the ranged slot - an empty one counts for a complete read, a bow is no relic", function()
        local W = world(function(w, g)
            local hunter = wornSet(w, 2, 30, { AGI = 10, STA = 10 })
            hunter[18] = piece(w, "INVTYPE_RANGED", 30, { AGI = 5 }, { subclassID = 2, dps = 20, classID = 2 })
            g.add("party1", { name = "Hun", class = "HUNTER", gear = hunter })
            g.add("party2", { name = "Pri", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party3", { name = "Poor", class = "MAGE", gear = wornSet(w, 1, 30, CASTER, 3) })
            w.I.gun = piece(w, "INVTYPE_RANGED", 60, { AGI = 40 }, { subclassID = 3, dps = 50, classID = 2 })
            w.I.wand = piece(w, "INVTYPE_RANGEDRIGHT", 60, { SP = 20 }, { subclassID = 19, dps = 40, classID = 2 })
        end)
        W.advance(40)
        local gun, wand = W.EG.Group.Beneficiaries(W.I.gun), W.EG.Group.Beneficiaries(W.I.wand)
        T.eq(#gun, 1) T.eq(gun[1].member.name, "Hun") T.eq(gun[1].slot, 18)
        T.eq(#wand, 1) T.eq(wand[1].member.name, "Pri") T.eq(wand[1].empty, true, "the priest has no wand")
        T.eq(W.EG.Group.list[3].complete, false, "and the poor mage's read says nothing about a wand he may lack")
    end)

    ------------------------------------------------------------------ where the star appears
    T.test("group: the star appears in bags, bank, loot and rolls - not at vendors, in quest rewards, mail or trade", function()
        local W, _, robe = bobAndRobe()
        W.state.rolls = { [9] = robe }
        local bank = W.bankButton(6, 4)
        bank.itemInfo = { hyperlink = robe, itemID = 1 }
        W.env.SetItemButtonQuality(bank, 3, 1)
        T.eq(star(bank), true, "bank")
        local loot = W.lootButton(1)
        W.env.SetItemButtonQuality(loot, 3, robe)
        T.eq(star(loot), true, "loot")
        local roll = { rollID = 9, IconFrame = W.env.CreateFrame("Frame") }
        W.env.GroupLootFrame_SetupItemDisplay(roll)
        T.eq(star(roll.IconFrame), true, "roll")
        local vendor = { ItemButton = W.namedButton("MerchantItem1ItemButton", 1) }
        W.env.MerchantFrameItem_UpdateQuality(vendor, robe, false)
        T.eq(star(vendor.ItemButton), false, "vendor")
        local mail = W.namedButton("OpenMailAttachmentButton1", 1)
        W.env.SetItemButtonQuality(mail, 3, robe)
        T.eq(star(mail), false, "mail")
        local trade = W.namedButton("TradeRecipientItem1ItemButton", 1)
        W.env.SetItemButtonQuality(trade, 3, robe)
        T.eq(star(trade), false, "trade")
        local quest = W.questRewards({ { link = robe }, { link = W.I.chest } })
        W.showRewards()
        T.eq(star(quest[1]), false, "quest reward")
        T.eq(W.EG.Group.State(robe, "char"), nil) T.eq(W.EG.Group.State(robe, "merchant"), nil)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: the settings switch the star off - the group, the bag markers, the item markers", function()
        local W, _, robe = bobAndRobe()
        local b, loot = W.bagButton(0, 1), W.lootButton(1)
        W.env.SetItemButtonQuality(b, 3, robe) W.env.SetItemButtonQuality(loot, 3, robe)
        T.eq(star(b), true) T.eq(star(loot), true)
        W.EG:Set("showBagIcons", false) W.flush()
        T.eq(star(b), false, "bag markers off") T.eq(star(loot), true, "loot markers are another setting")
        W.EG:Set("showBagIcons", true) W.EG:Set("showItemIcons", false) W.flush()
        T.eq(star(b), true) T.eq(star(loot), false, "item markers off")
        W.EG:Set("showItemIcons", true) W.EG:Set("showGroupHints", false) W.flush()
        T.eq(star(b), false) T.eq(star(loot), false)
        T.eq(W.tooltipFor(b, robe):HasLine(W.EG.L.GROUP_BETTER), false)
        T.eq(#W.EG.Group.list, 0, "the group is not even tracked")
        W.EG:Set("showGroupHints", true) W.advance(40)
        T.eq(#W.EG.Group.list, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true)
    end)

    T.test("group: the star follows what the members wear - a new piece, a left member, a changed profile", function()
        local W, G, robe, gear = bobAndRobe()
        local oldChest = gear[5]
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true)
        -- Bob puts the robe on (the item itself is the best he can have now)
        G.members.party1.gear[5] = robe
        G.gearChanged("party1")
        W.advance(40)
        T.eq(star(b), false, "he wears it now")
        -- he takes the old chest back
        G.members.party1.gear[5] = oldChest
        G.gearChanged("party1")
        W.advance(40)
        T.eq(star(b), true)
        -- he leaves the group
        G.remove("party1") G.rosterChanged() W.flush()
        T.eq(star(b), false)
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ bound items
    T.test("group: a bound item in a bag gets no star, unless its trade time is running", function()
        local W, _, robe = bobAndRobe()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true, "not bound")
        W.bind(0, 1, false) W.EG:InvalidateAll() W.flush()
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), false, "soulbound: it cannot be handed over")
        T.eq(W.EG.Group.Untradable(0, 1, robe), true)
        W.bind(0, 1, true) W.EG:InvalidateAll() W.flush()
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true, "bound but still tradable (the tooltip carries the trade time)")
        T.eq(W.EG.Group.Untradable(0, 1, robe), false)
        -- the tooltip names the member in any case; the base tooltip says what the item is bound to
        T.eq(W.tooltipFor(b, robe):HasLine("Bob"), true)
        T.eq(W.EG.Group.Untradable(nil, nil, robe), false) T.eq(W.EG.Group.Untradable(0, 99, robe), false)
    end)

    T.test("group: the bank asks for the bound state of its own slot", function()
        local W, _, robe = bobAndRobe()
        W.bag(6, 28, { [4] = robe })
        local bank = W.bankButton(6, 4)
        bank.itemInfo = { hyperlink = robe, itemID = 1 }
        W.env.SetItemButtonQuality(bank, 3, 1)
        T.eq(star(bank), true)
        W.bind(6, 4, false) W.EG:InvalidateAll() W.flush()
        W.env.SetItemButtonQuality(bank, 3, 1)
        T.eq(star(bank), false, "soulbound in the bank")
        local other = W.bankButton(6, 5)                     -- another slot of the same tab is not affected
        other.itemInfo = { hyperlink = robe, itemID = 1 }
        W.env.SetItemButtonQuality(other, 3, 1)
        T.eq(star(other), true)
    end)

    T.test("group: loot and rolls have no bound state to check", function()
        local W, _, robe = bobAndRobe()
        W.bind(0, 1, false)
        local loot = W.lootButton(1)
        W.env.SetItemButtonQuality(loot, 3, robe)
        T.eq(star(loot), true)
    end)

    ------------------------------------------------------------------ tooltip
    T.test("group: the tooltip names the members, the one with the biggest gain first, and sums up the rest", function()
        local W = world(function(w, g)
            local names = { "Ann", "Ben", "Cid", "Dan", "Eli", "Fay" }
            for i, name in ipairs(names) do
                local gear = wornSet(w, 1, 30, CASTER)
                gear[5] = piece(w, "INVTYPE_CHEST", 30, { INT = 10, SP = 10 + 5 * i }, { subclassID = 1 })   -- Ann has the weakest
                g.add("party" .. i, { name = name, class = (i % 2 == 0) and "MAGE" or "PRIEST", gear = gear })
            end
            w.I.robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
        end)
        T.eq(#W.EG.Group.list, 4, "a party has four players besides you")
        W.advance(60)
        local list = W.EG.Group.Beneficiaries(W.I.robe)
        T.eq(#list, 4)
        for i = 2, #list do T.ok(list[i - 1].percent >= list[i].percent, "sorted by gain") end
        T.eq(list[1].member.name, "Ann")
        local lines = W.EG.Group.TooltipLines(W.I.robe)
        T.eq(#lines, 5, "header and four members") T.eq(lines[1].left, W.EG.L.GROUP_BETTER)
        T.has(lines[2].left, "Ann") T.has(lines[2].left, "|cff") T.has(lines[2].right, "%")
        T.has(lines[2].left, W.EG.Group.ProfileOf(list[1].member).name, "and the profile he is rated with")
        local tip = W.tooltipFor(W.bagButton(0, 1), W.I.robe)
        T.eq(tip:HasLine("Ann"), true)
    end)

    T.test("group: more than four members in a raid are summed up", function()
        local W = world(function(w, g)
            g.setRaid(true)
            g.add("raid1", { isPlayer = true })
            for i = 2, 7 do
                g.add("raid" .. i, { name = "R" .. i, class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            end
            w.I.robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
            w.env.EasyGearDB = { groupRaid = true }
        end)
        W.advance(90)
        T.eq(#W.EG.Group.list, 6)
        local lines = W.EG.Group.TooltipLines(W.I.robe)
        T.eq(#lines, 6, "header, four members and the rest")
        T.eq(lines[6].left, string.format(W.EG.L.GROUP_MORE, 2))
    end)

    T.test("group: no group lines on the character window, in compare tooltips or for non-gear", function()
        local W, _, robe = bobAndRobe()
        local chest = W.namedButton("CharacterChestSlot", 5)
        W.equip(5, robe)
        T.eq(W.tooltipFor(chest, robe):HasLine(W.EG.L.GROUP_BETTER), false, "the character window shows only the score")
        T.eq(W.tooltipFor(W.bagButton(0, 1), robe):HasLine(W.EG.L.GROUP_BETTER), true)
        W.equip(5, W.I.chest)
        local potion = F.gear(W, 39002, "Potion", "", 1, {})
        T.eq(W.tooltipFor(W.bagButton(0, 2), potion):HasLine(W.EG.L.GROUP_BETTER), false)
        W.EG:Set("showTooltip", false)
        T.eq(W.tooltipFor(W.bagButton(0, 1), robe):HasLine(W.EG.L.GROUP_BETTER), false, "tooltip lines switched off")
    end)

    ------------------------------------------------------------------ commands and status
    T.test("group: /eg group lists the members and what is known about them", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", tab = 3, gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Far", class = "MAGE", distance = 60 })
            g.add("party3", { name = "Off", class = "ROGUE", connected = false })
        end)
        W.advance(30)
        W.clearChat()
        W.slash("group")
        local text = W.chatText()
        T.has(text, W.EG.L.OPT_SEC_GROUP) T.has(text, "Bob") T.has(text, "Far") T.has(text, "Off")
        T.has(text, "9 items")
        T.has(text, W.EG.L.GROUP_STATE_RANGE) T.has(text, W.EG.L.GROUP_STATE_DISCONNECTED)
        T.has(text, W.EG.L.GROUP_FROM_TALENTS) T.has(text, W.EG.L.GROUP_CLASS_DEFAULT)
        G.combat = true
        W.clearChat() W.slash("group")
        T.has(W.chatText(), W.EG.L.GROUP_STATE_BLOCKED, "in combat nobody is read now")
        W.EG:Set("groupInspect", false)
        W.clearChat() W.slash("group list")
        T.has(W.chatText(), W.EG.L.GROUP_STATE_OFF)
    end)

    T.test("group: /eg group on, off, raid, inspect and scan", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        W.slash("group off")
        T.eq(W.EG:Get("showGroupHints"), false) T.eq(#W.EG.Group.list, 0)
        W.clearChat() W.slash("group")
        T.has(W.chatText(), W.EG.L.GROUP_OFF)
        W.slash("group on")
        T.eq(W.EG:Get("showGroupHints"), true)
        W.slash("group aus") W.slash("group an")
        T.eq(W.EG:Get("showGroupHints"), true)
        W.slash("group raid")
        T.eq(W.EG:Get("groupRaid"), true)
        W.slash("group raid off")
        T.eq(W.EG:Get("groupRaid"), false)
        W.slash("group inspect off")
        T.eq(W.EG:Get("groupInspect"), false)
        W.slash("group inspect on")
        T.eq(W.EG:Get("groupInspect"), true)
        W.advance(20)
        local before = G.requests()
        W.clearChat() W.slash("group scan")
        T.has(W.chatText(), W.EG.L.GROUP_RESCAN)
        W.advance(10)
        T.eq(G.requests(), before + 1, "scan reads the member again at once")
        W.clearChat() W.slash("group nonsense")
        T.has(W.chatText(), W.EG.L.OPT_SEC_GROUP)
        W.clearChat() W.slash("gruppe")
        T.has(W.chatText(), W.EG.L.OPT_SEC_GROUP)
        W.clearChat() W.slash("help")
        T.has(W.chatText(), "/eg group")
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: /eg group in a raid says that its members are not checked", function()
        local W = world(function(w, g)
            g.setRaid(true) g.add("raid1", { isPlayer = true }) g.add("raid2", { name = "Bob", class = "PRIEST" })
        end)
        W.clearChat() W.slash("group")
        T.has(W.chatText(), W.EG.L.GROUP_RAID_OFF)
        local W2 = world()
        W2.clearChat() W2.slash("group")
        T.has(W2.chatText(), W2.EG.L.GROUP_NONE)
    end)

    T.test("group: /eg status tells how many members are read", function()
        local W = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Eve", class = "MAGE", distance = 99 })
        end)
        W.advance(30)
        W.clearChat() W.slash("status")
        T.has(W.chatText(), W.EG.L.OPT_GROUP .. ": " .. W.EG.L.SET_ON .. " (1 / 2)")
        W.EG:Set("groupInspect", false)
        W.clearChat() W.slash("status")
        T.has(W.chatText(), W.EG.L.OPT_GROUP_INSPECT .. ": " .. W.EG.L.SET_OFF)
        W.EG:Set("showGroupHints", false)
        W.clearChat() W.slash("status")
        T.has(W.chatText(), W.EG.L.OPT_GROUP .. ": " .. W.EG.L.SET_OFF)
    end)

    T.test("group: errors inside the group code are contained and reported once", function()
        local W, G, robe = bobAndRobe()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true)
        W.EG.Group.Beneficiaries = function() error("boom") end
        W.clearChat()
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(W.EG.lastError.label, "itembuttons") T.has(W.chatText(), "boom")
        W.clearChat()
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(W.chatText(), "", "reported once")
        T.ok(G)
    end)

    T.test("group: an inspection that the player or another addon started is not overtaken", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(30)
        T.eq(G.requests(), 1)
        G.add("party2", { name = "Eve", class = "MAGE", gear = wornSet(W, 1, 30, CASTER) })
        G.rosterChanged()
        W.env.NotifyInspect("party1")                       -- the player clicks "inspect" on Bob (not the addon)
        local before = G.requests()
        W.advance(5)
        T.eq(G.requests(), before, "the addon keeps out of the way for a few seconds")
        W.advance(5)
        T.eq(G.requests(), before + 1, "and then goes on with Eve")
        T.eq(G.notified[#G.notified].unit, "party2")
        T.eq(W.EG.lastError, nil)
    end)

    ------------------------------------------------------------------ findings of the review: no loops, no lost data
    T.test("group: members who wear little are asked again a few times, not for ever", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Low", class = "MAGE", level = 8, gear = wornSet(w, 1, 5, CASTER, 3) })
            g.add("party2", { name = "Naked", class = "ROGUE", level = 5, gear = {} })
        end)
        W.advance(700)
        T.ok(G.requests("party1") >= 3 and G.requests("party1") <= 6, "few: " .. G.requests("party1"))
        T.ok(G.requests("party2") >= 3 and G.requests("party2") <= 6, "few: " .. G.requests("party2"))
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: a reading that brings nothing new does not make everything be computed again", function()
        local changes = 0
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", tab = 3, gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.EG:Listen("GROUP", function() changes = changes + 1 end)
        W.advance(10)
        local first = changes
        W.advance(700)                                           -- two periodic readings of the same gear
        T.eq(changes, first, "nothing changed: nothing announced")
        T.ok(G.requests() >= 3, "the readings happened")
        G.members.party1.gear[5] = F.gear(W, 41000, "Other Chest", "INVTYPE_CHEST", 31, { INT = 12 }, { subclassID = 1 })
        G.gearChanged("party1") W.advance(60)
        T.eq(changes, first + 1, "other gear: announced once")
        G.members.party1.tab = 1 G.gearChanged("party1") W.advance(60)
        T.eq(changes, first + 2, "another talent tree: announced")
        G.members.party1.level = 61 G.gearChanged("party1") W.advance(60)
        T.eq(changes, first + 3, "a new level: announced")
    end)

    T.test("group: an event that comes right after a reading (the inspection causes it) does not start a loop", function()
        local W, G = world(function(w, g)
            g.echoEvent = true
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Eve", class = "MAGE", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(700)
        T.ok(G.requests("party1") <= 4, "periodic only: " .. G.requests("party1"))
        T.ok(G.requests("party2") <= 4, "periodic only: " .. G.requests("party2"))
    end)

    T.test("group: a member who keeps changing his equipment is read at most every 30 seconds", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(10)
        local before = G.requests()
        for _ = 1, 100 do                                        -- every 3 seconds for five minutes
            G.gearChanged("party1")
            W.advance(3)
        end
        local n = G.requests() - before
        T.ok(n >= 5 and n <= 11, "a request every 30 seconds or so: " .. n)
    end)

    T.test("group: /eg group scan reads at once, whatever the waiting times say", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        W.advance(12)
        local before = G.requests()
        G.gearChanged("party1") W.advance(8)
        T.eq(G.requests(), before, "a change soon after a reading waits for the cooldown")
        W.slash("group scan") W.advance(6)
        T.eq(G.requests(), before + 1, "but the player's command does not")
    end)

    T.test("group: an answer without any item - the client held somebody else's data - keeps the old reading", function()
        local robe
        local W, G = world(function(w, g)
            local gear = wornSet(w, 1, 30, CASTER)
            gear[5] = piece(w, "INVTYPE_CHEST", 30, { INT = 10, SP = 40 }, { subclassID = 1 })
            g.add("party1", { name = "Bob", class = "PRIEST", gear = gear })
            robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
            w.bag(0, 16, { [1] = robe })
        end)
        W.advance(30)
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), true)
        local bob = W.EG.Group.list[1]
        local stamp = bob.stamp
        G.staleReply = true
        G.gearChanged("party1") W.advance(40)
        T.ok(G.requests("party1") >= 2, "it was asked again")
        T.eq(W.EG.Group.HasData(bob), true, "and the empty answer did not wipe him") T.eq(bob.count, 9)
        T.eq(bob.stamp, stamp) T.eq(star(b), true, "the star stays")
        T.ok(bob.nextTry ~= nil and bob.tries >= 1, "he is asked again after a pause")
        G.staleReply = false
        W.advance(200)
        T.eq(bob.stamp > stamp, true, "and read properly later") T.eq(star(b), true)
    end)

    T.test("group: the talent tree is only taken from three different specialization numbers", function()
        local function tabWith(mode)
            local W = world(function(w, g)
                g.specs = mode
                g.add("party1", { name = "Bob", class = "PRIEST", tab = 3, gear = wornSet(w, 1, 30, CASTER) })
            end)
            W.advance(20)
            return W.EG.Group.list[1].tab, W
        end
        T.eq((tabWith(nil)), 3)
        local tab, W = tabWith("same")
        T.eq(tab, nil, "one number for all trees: no way to tell the tree")
        T.eq(W.EG.Group.ProfileOf(W.EG.Group.list[1]).source, "class", "so the class default rates him")
        T.eq(W.EG.Group.list[1].specID ~= nil, true)
        tab, W = tabWith("few")
        T.eq(tab, nil, "only the first tree known") T.eq(W.EG.lastError, nil)
    end)

    T.test("group: the level of a member follows UNIT_LEVEL without a new reading", function()
        local robe
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", level = 40, tab = 3, gear = wornSet(w, 1, 30, CASTER) })
            robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1, minLevel = 42 })
        end)
        W.advance(30)
        T.eq(#W.EG.Group.Beneficiaries(robe), 0, "two levels short")
        local requests = G.requests()
        G.members.party1.level = 41
        G.levelChanged("party1") W.advance(5)
        T.eq(W.EG.Group.list[1].level, 41)
        local list = W.EG.Group.Beneficiaries(robe)
        T.eq(#list, 1) T.eq(list[1].needLevel, 42, "one level short now")
        T.eq(G.requests(), requests, "no new reading was needed")
        G.levelChanged("target") G.levelChanged("party1") W.advance(5)
        T.eq(W.EG.lastError, nil)
    end)

    T.test("group: a roster entry whose class or level comes late is picked up a few seconds later", function()
        local W, G = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            g.add("party2", { name = "Late", class = "MAGE", level = 0 })
        end)
        T.eq(#W.EG.Group.list, 1, "the level is not known yet")
        G.members.party2.level = 60
        W.advance(4)
        T.eq(#W.EG.Group.list, 2, "the next look finds him")
        -- and the looking stops: a member that never delivers does not keep the timer busy for ever
        G.add("party3", { name = "Never", class = "MAGE", level = 0 })
        local calls = 0
        local refresh = W.EG.Group.Refresh
        W.EG.Group.Refresh = function(...) calls = calls + 1 return refresh(...) end
        W.EG.Group.Refresh()
        W.advance(120)
        T.ok(calls >= 3 and calls <= 8, "a handful of looks: " .. calls)
        T.eq(#W.EG.Group.list, 2, "he is not in the group")
        W.EG.Group.Refresh = refresh
    end)

    T.test("group: while your own verdict is still loading there is no star that turns into an arrow", function()
        local robe, plate
        local W = world(function(w, g)
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
            robe = piece(w, "INVTYPE_CHEST", 60, { INT = 30, SP = 80 }, { subclassID = 1 })
        end)
        W.advance(30)
        W.EG.Items.Wipe()
        W.state.items[2001].uncached = true                     -- the chest you wear is not in the client's memory
        W.EG:InvalidateAll()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(star(b), false, "your own answer is still missing")
        W.state.items[2001].uncached = nil
        W.fire("GET_ITEM_INFO_RECEIVED", 2001, true)
        W.advance(5)
        T.eq(star(b), true, "now it is clear that the robe is nothing for you")
        T.ok(plate == nil)
    end)

    T.test("group: the trade time of a bound item is looked at again after a minute", function()
        local W, _, robe = bobAndRobe()
        W.bind(0, 1, true)                                        -- still tradable
        T.eq(W.EG.Group.Untradable(0, 1, robe), false)
        W.state.bags[0].trade[1] = nil                            -- the trade time has run out
        W.advance(30)
        T.eq(W.EG.Group.Untradable(0, 1, robe), false, "a cached answer is good for a while")
        W.advance(40)
        T.eq(W.EG.Group.Untradable(0, 1, robe), true, "and not for longer than a minute")
    end)

    T.test("group: the tooltip of a bound item in your bag names nobody - elsewhere it does", function()
        local W, _, robe = bobAndRobe()
        local b = W.bagButton(0, 1)
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(W.tooltipFor(b, robe):HasLine("Bob"), true, "not bound")
        W.bind(0, 1, false) W.EG:InvalidateAll() W.flush()
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(W.tooltipFor(b, robe):HasLine("Bob"), false, "soulbound: it cannot be handed over")
        T.eq(W.tooltipFor(W.env.UIParent, robe):HasLine("Bob"), true, "a link in the chat has no slot to check")
        W.bind(0, 1, true) W.EG:InvalidateAll() W.flush()
        W.env.SetItemButtonQuality(b, 3, robe)
        T.eq(W.tooltipFor(b, robe):HasLine("Bob"), true, "bound but tradable")
        local bank = W.bankButton(6, 4)
        bank.itemInfo = { hyperlink = robe, itemID = 1 }
        W.bag(6, 28, { [4] = robe })
        W.bind(6, 4, false)
        W.env.SetItemButtonQuality(bank, 3, 1)
        T.eq(W.tooltipFor(bank, robe):HasLine("Bob"), false, "the bank, too")
    end)

    T.test("group: Group.Read tells whether anything changed", function()
        local W, G = world(function(w, g)
            w.env.EasyGearDB = { groupInspect = false }
            g.add("party1", { name = "Bob", class = "PRIEST", gear = wornSet(w, 1, 30, CASTER) })
        end)
        local bob = W.EG.Group.list[1]
        G.inspectedGUID = bob.guid
        local ok, changed = W.EG.Group.Read(bob)
        T.eq(ok, true) T.eq(changed, true, "the first reading is a change")
        ok, changed = W.EG.Group.Read(bob)
        T.eq(ok, true) T.eq(changed, false, "the same again is not")
        G.members.party1.gear[1] = nil
        ok, changed = W.EG.Group.Read(bob)
        T.eq(changed, true, "a piece less")
    end)
end
