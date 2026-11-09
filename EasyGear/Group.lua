--[[---------------------------------------------------------------------------
    Group.lua - Gegenstaende, die fuer Gruppenmitglieder besser sind

    Ein Gegenstand, der fuer dich selbst keine Verbesserung ist, aber fuer jemanden in der Gruppe besser waere
    als das, was er traegt, bekommt einen violetten Stern; der Tooltip nennt, fuer wen (Group.TooltipLines).

    Woher die Daten kommen
      * Mitglieder: die Gruppe (vier Mitspieler); mit der Einstellung groupRaid auch der Schlachtzug.
      * Ausruestung: Untersuchen, wie es das Untersuchen-Fenster der Oberflaeche selbst tut (CanInspect,
        NotifyInspect, Ereignis INSPECT_READY, danach GetInventoryItemLink(unit, platz)). Das Addon fragt hoechstens
        alle 2.5 Sekunden nach, nie im Kampf, nie bei offenem Untersuchen-Fenster und nur Mitglieder in Reichweite;
        jede Untersuchung, die der Spieler oder ein anderes Addon ausloest, wird ebenfalls mitgenommen. Der Stand
        eines Mitglieds wird nach fuenf Minuten, bei einem Wechsel seiner Ausruestung (UNIT_INVENTORY_CHANGED) oder
        wenn er unvollstaendig war, neu gelesen. Aus der Reichweite oder offline bleibt der letzte Stand stehen.
      * Skillung: C_SpecializationInfo.GetInspectSpecialization, auf den Talentbaum der Klasse zurueckgefuehrt
        (GetSpecializationInfoForClassID). Gelingt das nicht, gilt der Klassenstandard: das Allround-Profil der
        Klasse, unter der Hoechststufe das Leveln-Profil.

    Wie bewertet wird
      * Mit dem Profil des Mitglieds, seiner Stufe und seiner getragenen Ausruestung; die Schwellen sind die des
        Spielers (Mindestvorsprung), mindestens aber MIN_PERCENT Prozent: die Gewichte sind Schaetzwerte.
      * Verwendbarkeit: Classes.Usable (Klassenzeile des Tooltips, Ruestungs- und Waffenart, Stufe). Genannt wird nur,
        wer den Gegenstand tragen kann oder dafuer hoechstens eine Stufe zu niedrig ist; der Tooltip sagt dann "ab Stufe N".
      * Waffen werden nur mit gleichartigen Waffen verglichen (Einhand mit Einhand, Zweihand mit Zweihand, Schild mit
        Schild): ob ein Mitglied die Haltung wechseln sollte, entscheidet das Addon nicht.
      * Ein leerer Platz zaehlt nur, wenn der Stand des Mitglieds vollstaendig ist (MIN_COMPLETE belegte Plaetze).

    Wo der Stern erscheint: Taschen, Bank, Beute und Wuerfelfenster. Gebundene Gegenstaende in Taschen und Bank nur,
    solange sie noch tauschbar sind (Tauschfrist im Tooltip): was man nicht abgeben kann, bekommt keinen Stern.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Group = {}
EG.Group = Group

local L = EG.L
local Items, Score, Profiles, Specs, Classes = EG.Items, EG.Score, EG.Profiles, EG.Specs, EG.Classes

local pairs, ipairs, type, tostring, tonumber, pcall = pairs, ipairs, type, tostring, tonumber, pcall
local sformat, tconcat, tsort = string.format, table.concat, table.sort
local mmax, mmin, floor = math.max, math.min, math.floor

-- Plaetze, die gelesen werden (ohne Hemd und Wappenrock)
local SCAN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local LOOP_INTERVAL = 1             -- Sekunden zwischen zwei Durchlaeufen des Zeitgebers
local INSPECT_INTERVAL = 2.5        -- Sekunden zwischen zwei Anfragen (der Server verwirft Anfragen, wenn man ihn flutet)
local REPLY_TIMEOUT = 6             -- Sekunden, nach denen eine Anfrage als unbeantwortet gilt
local REFRESH_AGE = 300             -- Sekunden, nach denen die Ausruestung eines Mitglieds neu gelesen wird
local RETRY_AGE = 20                -- Sekunden bis zur Wiederholung, wenn der letzte Stand unvollstaendig war
local BACKOFF = { 10, 30, 60, 120 } -- Wartezeit nach erfolglosen Anfragen
local MIN_COMPLETE = 8              -- so viele belegte Plaetze, damit ein leerer Platz als wirklich leer gilt
local FOREIGN_PAUSE = 6             -- Sekunden Ruhe nach einer Untersuchung, die nicht von uns stammt
local MIN_PERCENT = 3               -- Mindestvorsprung in Prozent fuer einen Gruppenhinweis
local MAX_TOOLTIP = 4               -- so viele Mitglieder nennt der Tooltip

-- Wo der Stern erscheinen darf
local CONTEXTS = { bag = true, bank = true, loot = true, roll = true }
local PURPLE = { 0.75, 0.40, 1.00 }
local GREY, GREEN, WHITE, YELLOW = { 0.62, 0.62, 0.62 }, { 0.25, 1.00, 0.25 }, { 1.00, 1.00, 1.00 }, { 1.00, 0.82, 0.00 }

local ONEHAND_MAIN = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local ONEHAND_OFF = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local RANGED_LOCS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true }

local known = {}                    -- GUID -> Mitglied (nur die aktuelle Gruppe)
Group.list = {}                     -- die Mitglieder in der Reihenfolge der Gruppe

-- Zwischenspeicher, die bei jeder Aenderung von Einstellungen, Profil oder Ausruestung des Spielers verfallen
local verdictCache, scoreCache, tradeCache = {}, {}, {}
EG:RegisterCache(verdictCache)
EG:RegisterCache(scoreCache)
EG:RegisterCache(tradeCache)

local function Now() return GetTime and GetTime() or 0 end

-- Einheitendaten koennen "geheim" sein (Beschraenkungen der Oberflaeche); damit laesst sich nicht rechnen
local function Plain(v)
    if v == nil then return nil end
    local secret = _G.issecretvalue
    if type(secret) == "function" and secret(v) then return nil end
    return v
end

function Group.Enabled()
    return EG:Get("showGroupHints") ~= false
end

------------------------------------------------------------------------------
-- 01  Mitglieder
------------------------------------------------------------------------------

local function RosterUnits()
    local units = {}
    if not (IsInGroup and IsInGroup()) then return units end
    if IsInRaid and IsInRaid() then
        if not EG:Get("groupRaid") then return units end
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function UpdateIdentity(m)
    local unit = m.unit
    local name = Plain((UnitName(unit)))
    if type(name) == "string" and name ~= "" then m.name = name end
    m.name = m.name or "?"

    local className, class, classID = UnitClass(unit)
    class = Plain(class)
    if type(class) == "string" and class ~= m.class then m.class = class m.profile = nil end
    className = Plain(className)
    if type(className) == "string" then m.className = className end
    classID = Plain(classID)
    if type(classID) == "number" then m.classID = classID end

    local level = Plain(UnitLevel(unit))
    if type(level) == "number" and level > 0 and level ~= m.level then m.level = level m.profile = nil end
end

local function WipeCaches()
    for _, cache in ipairs({ verdictCache, scoreCache, tradeCache }) do
        for k in pairs(cache) do cache[k] = nil end
    end
    for _, m in pairs(known) do m.profile = nil end
end

--[[ Die Mitglieder neu bestimmen. Wer schon bekannt ist (gleiche GUID), behaelt seinen Stand - die Einheitenkennung
     (party2, raid7) kann sich bei jeder Aenderung der Gruppe verschieben.                                        ]]
function Group.Refresh()
    local list, seen = {}, {}
    if Group.Enabled() then
        for _, unit in ipairs(RosterUnits()) do
            local ok, exists = pcall(UnitExists, unit)
            if ok and exists and not UnitIsUnit(unit, "player") and (not UnitIsPlayer or UnitIsPlayer(unit)) then
                local guid = Plain(UnitGUID(unit))
                if type(guid) == "string" then
                    local m = known[guid]
                    if not m then
                        m = { guid = guid, gear = {}, count = 0 }
                        known[guid] = m
                    end
                    m.unit = unit
                    pcall(UpdateIdentity, m)
                    if m.class and m.level then
                        list[#list + 1] = m
                        seen[guid] = true
                    end
                end
            end
        end
    end
    for guid in pairs(known) do
        if not seen[guid] then known[guid] = nil end
    end
    Group.list = list
    return list
end

-- Haben wir etwas von diesem Mitglied gelesen?
function Group.HasData(m)
    return type(m) == "table" and m.stamp ~= nil and m.count > 0
end

------------------------------------------------------------------------------
-- 02  Untersuchen
------------------------------------------------------------------------------

local pending = nil                 -- { guid, at }: eine Anfrage ist unterwegs
local lastRequest = -1000
local foreignAt = nil               -- Zeitpunkt der letzten Untersuchung, die der Spieler oder ein anderes Addon angestossen hat
local ownRequest = false            -- gerade ruft das Addon NotifyInspect selbst auf

-- Den Talentbaum (1..3) des untersuchten Spielers; nil, wenn die Oberflaeche ihn nicht herausgibt
local function ReadSpec(unit, classID)
    local SI = C_SpecializationInfo
    if not (SI and SI.GetInspectSpecialization) then return nil end
    local ok, specID = pcall(SI.GetInspectSpecialization, unit)
    specID = ok and Plain(specID) or nil
    if type(specID) ~= "number" or specID <= 0 then return nil end
    if type(GetSpecializationInfoForClassID) == "function" and classID then
        for i = 1, 3 do
            local good, id = pcall(GetSpecializationInfoForClassID, classID, i)
            if good and id == specID then return i, specID end
        end
    end
    return nil, specID
end

--[[ Die Ausruestung des gerade untersuchten Mitglieds lesen. Der Link kommt nicht immer sofort (der Client kennt den
     Gegenstand vielleicht noch nicht): dann steht die Gegenstandsnummer da, damit der Platz nicht leer aussieht.      ]]
function Group.Read(m)
    local unit = m.unit
    if not unit or Plain(UnitGUID(unit)) ~= m.guid then return false end

    local gear, count = {}, 0
    for _, slot in ipairs(SCAN_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if type(link) ~= "string" or link == "" then
            link = nil
            local id = GetInventoryItemID and GetInventoryItemID(unit, slot)
            if type(id) == "number" and id > 0 then link = id end
        end
        if link then
            gear[slot] = link
            count = count + 1
        end
    end

    pcall(UpdateIdentity, m)
    m.gear, m.count = gear, count
    m.complete = count >= MIN_COMPLETE
    m.stamp = Now()
    m.dirty, m.tries, m.nextTry = false, 0, nil
    m.tab, m.specID = ReadSpec(unit, m.classID)
    m.profile = nil
    return true
end

local function Backoff(tries)
    return BACKOFF[mmin(tries, #BACKOFF)]
end

local function NeedsScan(m, now)
    if m.nextTry and now < m.nextTry then return false end
    if not m.stamp or m.dirty then return true end
    if not m.complete and now - m.stamp > RETRY_AGE then return true end
    return now - m.stamp > REFRESH_AGE
end

-- Ist das Mitglied zum Untersuchen erreichbar?
local function InRange(m)
    local unit = m.unit
    if not unit then return false end
    if UnitIsConnected and not UnitIsConnected(unit) then return false end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    if CanInspect and not CanInspect(unit) then return false end
    if CheckInteractDistance and not CheckInteractDistance(unit, 1) then return false end
    return true
end

-- Darf das Addon jetzt untersuchen?  Nicht im Kampf und nicht, solange der Spieler selbst jemanden untersucht.
function Group.CanScanNow()
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false, "combat" end
    local frame = _G.InspectFrame
    if type(frame) == "table" and frame.IsShown and frame:IsShown() then return false, "inspect" end
    local talents = _G.PlayerSpellsFrame
    if type(talents) == "table" and talents.IsInspecting and talents:IsInspecting() then return false, "inspect" end
    -- Das Untersuchen-Fenster oeffnet sich erst, wenn die Antwort da ist: eine Anfrage des Spielers (oder eines anderen
    -- Addons) darf in dieser Zeit nicht von einer eigenen ueberholt werden
    if foreignAt and Now() - foreignAt < FOREIGN_PAUSE then return false, "inspect" end
    return true
end

local function Request(m, now)
    ownRequest = true
    local ok = pcall(NotifyInspect, m.unit)
    ownRequest = false
    if not ok then
        m.tries = (m.tries or 0) + 1
        m.nextTry = now + Backoff(m.tries)
        return false
    end
    pending = { guid = m.guid, at = now }
    lastRequest = now
    return true
end

--[[ Ein Schritt des Zeitgebers: hoechstens eine Anfrage, an das Mitglied, dessen Stand am aeltesten ist (wer noch nie
     gelesen wurde, zuerst).                                                                                     ]]
function Group.Step()
    local now = Now()
    if pending then
        if now - pending.at < REPLY_TIMEOUT then return end
        local m = known[pending.guid]
        if m then
            m.tries = (m.tries or 0) + 1
            m.nextTry = now + Backoff(m.tries)
        end
        pending = nil
    end
    if EG:Get("groupInspect") == false then return end
    if now - lastRequest < INSPECT_INTERVAL then return end
    if not Group.CanScanNow() then return end

    local best
    for _, m in ipairs(Group.list) do
        if NeedsScan(m, now) then
            local ok, near = pcall(InRange, m)
            if ok and near and (not best or (m.stamp or -1) < (best.stamp or -1)) then best = m end
        end
    end
    if best then Request(best, now) end
end

-- Alle Mitglieder beim naechsten Durchlauf neu lesen (/eg group scan)
function Group.Rescan()
    for _, m in ipairs(Group.list) do
        m.dirty, m.nextTry, m.tries = true, nil, 0
    end
    lastRequest = -1000
    Group.Start()
end

function Group.Wanted()
    return Group.Enabled() and #Group.list > 0
end

local running = false
local function Loop()
    if not Group.Wanted() then
        running = false
        return
    end
    EG:Try("group", Group.Step)
    EG:After(LOOP_INTERVAL, Loop)
end

function Group.Start()
    if running or not Group.Wanted() then return end
    running = true
    EG:After(LOOP_INTERVAL, Loop)
end

-- Stand der Mitglieder hat sich geaendert: berechnete Hinweise verwerfen, Anzeigen auffrischen
function Group.Changed()
    WipeCaches()
    EG:Fire("GROUP")            -- Compat.lua: Baganator soll seine Eckenelemente neu auswerten
    EG:Fire("REFRESH")          -- Marks.lua: die Symbole auffrischen
end

------------------------------------------------------------------------------
-- 03  Profil des Mitglieds
------------------------------------------------------------------------------

local ONEHAND_ANY = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true }

local function WornLoc(m, slot)
    local link = m.gear[slot]
    if not link then return nil end
    local info = C_Item and C_Item.GetItemInfoInstant
    if not info then return nil end
    local ok, _, _, _, equipLoc = pcall(info, link)
    return ok and equipLoc or nil
end

-- Mehrere Profile im selben Baum (Druide Katze/Baer): die getragenen Waffen des Mitglieds entscheiden, sonst die Standardwahl
local function PickTabSpec(list, tab, m)
    local candidates, default = {}, nil
    for _, spec in ipairs(list) do
        if spec.tab == tab then
            candidates[#candidates + 1] = spec
            if spec.auto and not default then default = spec end
        end
    end
    if #candidates == 0 then return nil end
    default = default or candidates[1]
    if #candidates == 1 then return default end

    local mh, oh = WornLoc(m, 16), WornLoc(m, 17)
    local style
    if mh == "INVTYPE_2HWEAPON" then
        style = "2H"
    elseif oh and ONEHAND_ANY[oh] then
        style = "DW"
    end
    if style then
        for _, spec in ipairs(candidates) do
            if spec.hands == style then return spec end
        end
    end
    return default
end

--[[ Das Profil eines Mitglieds: das seines Talentbaums, wenn der bekannt ist; sonst der Klassenstandard. Unter der
     Hoechststufe gilt das Leveln-Profil (wie beim Spieler, Einstellung autoLeveling), ausser bei Tank- und Heilbaeumen.
     Rueckgabe: { spec, weights, name, source = "spec" | "class", sig }                                              ]]
function Group.ProfileOf(m)
    if m.profile then return m.profile end
    local list = Specs.CLASS[m.class]
    if not list then return nil end

    local maxLevel = Profiles.MaxLevel()
    local level = m.level or maxLevel
    local leveling = Profiles.Get(Profiles.ClassProfileID(m.class, "LEVELING")) or Profiles.Get("LEVELING")
    local allround = Profiles.Get(Profiles.ClassProfileID(m.class, "ALLROUND")) or leveling

    local spec, source
    if m.tab then
        spec, source = PickTabSpec(list, m.tab, m) or list[1], "spec"
        if EG:Get("autoLeveling") and level < maxLevel and leveling and spec
           and spec.role ~= "TANK" and spec.role ~= "HEAL" then
            spec = leveling
        end
    else
        spec, source = (level < maxLevel) and leveling or allround, "class"
    end
    if not spec then return nil end

    local db = EG.db or EG.DEFAULTS
    m.profile = {
        spec = spec, source = source, name = Profiles.Name(spec),
        weights = Profiles.WeightsForTab(spec, m.tab),
        sig = tconcat({
            tostring(m.class), tostring(spec.id), tostring(level), tostring(m.tab),
            tostring(db.ilvlWeight), tostring(db.ilvlScaling), tostring(db.socketValue), tostring(db.includeEnchants),
            tostring(spec.rev or 0),
        }, ":"),
    }
    return m.profile
end

------------------------------------------------------------------------------
-- 04  Vergleich
------------------------------------------------------------------------------

local function ScoreFor(m, profile, item, slot)
    local key = profile.sig .. "|" .. tostring(item.link) .. "|" .. slot
    local hit = scoreCache[key]
    if hit then return hit end
    local _, total = Score.Breakdown(item, slot, profile.weights, m.level)
    scoreCache[key] = total
    return total
end

-- Gegenstand im Platz des Mitglieds. Rueckgabe: Gegenstand | nil, Zustand "ok" | "empty" | "loading" | "invalid"
local function Worn(m, slot)
    local link = m.gear[slot]
    if not link then return nil, "empty" end
    local item, why = Items.Get(link)
    if item then return item, "ok" end
    return nil, (why == "loading") and "loading" or "invalid"
end

--[[ Mit welchen getragenen Gegenstaenden wird verglichen?  Rueckgabe: Liste { slot, item (nil = leerer Platz) }, loading
     Waffen nur gegen gleichartige: das Addon rechnet nicht aus, ob ein Mitglied die Haltung wechseln sollte.       ]]
local function Targets(m, item)
    local loc = item.equipLoc
    local out, loading = {}, false

    local function Worn2(slot)
        local it, state = Worn(m, slot)
        if state == "loading" then loading = true end
        return it, state
    end
    local function Add(slot, it) out[#out + 1] = { slot = slot, item = it } end

    if loc == "INVTYPE_2HWEAPON" then
        local mh = Worn2(16)
        if mh and mh.equipLoc == "INVTYPE_2HWEAPON" then Add(16, mh) end
    elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
        local mh = Worn2(16)
        if mh and ONEHAND_MAIN[mh.equipLoc] then Add(16, mh) end
        if loc == "INVTYPE_WEAPON" then
            local oh = Worn2(17)
            if oh and ONEHAND_OFF[oh.equipLoc] then Add(17, oh) end
        end
    elseif loc == "INVTYPE_WEAPONOFFHAND" then
        local oh = Worn2(17)
        if oh and ONEHAND_OFF[oh.equipLoc] then Add(17, oh) end
    elseif loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE" then
        local oh = Worn2(17)
        if oh and oh.equipLoc == loc then Add(17, oh) end
    elseif RANGED_LOCS[loc] then
        local r, state = Worn2(18)
        if r then Add(18, r)
        elseif state == "empty" and m.complete then Add(18, nil) end
    else
        for _, slot in ipairs(Score.EQUIP_LOC_SLOTS[loc] or {}) do
            local it, state = Worn2(slot)
            if it then Add(slot, it)
            elseif state == "empty" and m.complete then Add(slot, nil) end
        end
    end
    return out, loading
end

--[[ Waere der Gegenstand fuer dieses Mitglied besser als das, was es traegt?
     Rueckgabe: Eintrag { member, delta, percent, slot, empty, score, targetScore, target, needLevel } | nil, Grund
     (needLevel: die Stufe, ab der das Mitglied den Gegenstand tragen kann, wenn sie noch aussteht)
     Gruende: "gear" kein Ausruestungsgegenstand, "data" Stand fehlt, "loading" Daten fehlen noch, "usable" nicht
     verwendbar, "none" nichts Vergleichbares getragen, "lower" nicht besser                                       ]]
function Group.Compare(m, item)
    if not (item and item.isGear) or (item.quality or 1) < 1 then return nil, "gear" end
    if not Group.HasData(m) then return nil, "data" end
    local profile = Group.ProfileOf(m)
    if not profile then return nil, "data" end

    local targets, loading = Targets(m, item)
    if loading then return nil, "loading" end

    -- ein einzigartiger Gegenstand ersetzt sein angelegtes Exemplar, er kommt nicht daneben
    if item.unique then
        for _, t in ipairs(targets) do
            if t.item and t.item.id == item.id then targets = { t } break end
        end
    end

    local best
    for _, t in ipairs(targets) do
        local usable, _, needLevel = Classes.Usable(m, item, t.item)
        if usable then
            local cs = ScoreFor(m, profile, item, t.slot)
            local es = t.item and ScoreFor(m, profile, t.item, t.slot) or 0
            local d = cs - es
            if not best or d > best.d + 1e-9 or (d > best.d - 1e-9 and es < best.es) then
                best = { slot = t.slot, target = t.item, cs = cs, es = es, d = d, needLevel = needLevel }
            end
        end
    end
    if not best then
        if #targets == 0 then return nil, "none" end
        return nil, "usable"
    end

    local minDelta = tonumber(EG:Get("minDelta")) or 0
    local pct = mmax(tonumber(EG:Get("minDeltaPercent")) or 0, MIN_PERCENT)
    local threshold = mmax(minDelta, (best.es > 0) and (best.es * pct / 100) or 0)
    if not (best.d > 0 and best.d >= threshold) then return nil, "lower" end

    return {
        member = m, delta = best.d, slot = best.slot, target = best.target, empty = best.target == nil,
        score = best.cs, targetScore = best.es, needLevel = best.needLevel,
        percent = (best.es > 0) and (best.d / best.es * 100) or nil,
    }
end

--[[ Alle Mitglieder, fuer die der Gegenstand besser waere, der groesste Zugewinn zuerst.
     Rueckgabe: Liste (kann leer sein) | nil; zweiter Wert: true, wenn Daten noch fehlen und eine spaetere Frage sich lohnt ]]
function Group.Beneficiaries(link)
    if not link or not Group.Enabled() or #Group.list == 0 then return nil end
    local hit = verdictCache[link]
    if hit then return hit end

    local item, why = Items.Get(link)
    if not item then return nil, why == "loading" end
    if not item.isGear then return nil end

    local out, pendingData = {}, false
    for _, m in ipairs(Group.list) do
        if Group.HasData(m) then
            local entry, reason = Group.Compare(m, item)
            if entry then out[#out + 1] = entry
            elseif reason == "loading" then pendingData = true end
        end
    end
    tsort(out, function(a, b)
        local pa, pb = a.percent or math.huge, b.percent or math.huge
        if pa ~= pb then return pa > pb end
        return (a.member.name or "") < (b.member.name or "")
    end)
    if not pendingData then verdictCache[link] = out end
    return out, pendingData
end

------------------------------------------------------------------------------
-- 05  Tauschbarkeit
------------------------------------------------------------------------------

-- Hat der gebundene Gegenstand noch eine Tauschfrist? (Zeile "Du kannst diesen Gegenstand ... tauschen" im Tooltip)
local function InTradeWindow(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem and Enum and Enum.TooltipDataLineType) then return false end
    local want = Enum.TooltipDataLineType.TradeTimeRemaining
    if not want then return false end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not (ok and type(data) == "table" and type(data.lines) == "table") then return false end
    for _, line in ipairs(data.lines) do
        if line.type == want then return true end
    end
    return false
end

--[[ Laesst sich der Gegenstand in diesem Fach nicht mehr abgeben?  Ein gebundener Gegenstand ohne Tauschfrist gehoert
     dem Spieler allein. Wo das Fach unbekannt ist (Beute, Wuerfeln), gibt es nichts zu pruefen.                    ]]
function Group.Untradable(bag, slot, link)
    if type(bag) ~= "number" or type(slot) ~= "number" or not (C_Container and C_Container.GetContainerItemInfo) then
        return false
    end
    local key = bag .. ":" .. slot .. ":" .. tostring(link)
    local hit = tradeCache[key]
    if hit ~= nil then return hit end

    local result = false
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" and info.isBound then
        result = not InTradeWindow(bag, slot)
    end
    tradeCache[key] = result
    return result
end

------------------------------------------------------------------------------
-- 06  Anzeige
------------------------------------------------------------------------------

--[[ Zustand fuer die Markierung eines Gegenstandssymbols: "GROUP" oder nil. Zweiter Wert: Daten fehlen noch.
     ctx: Art des Knopfes (Marks), bag/slot: das Fach, wenn bekannt                                          ]]
function Group.State(link, ctx, bag, slot)
    if not CONTEXTS[ctx] then return nil end
    local list, waiting = Group.Beneficiaries(link)
    if not (list and #list > 0) then return nil, waiting end
    if (ctx == "bag" or ctx == "bank") and Group.Untradable(bag, slot, link) then return nil end
    return "GROUP"
end

local function ClassColored(class, text)
    local colors = _G.RAID_CLASS_COLORS
    local c = type(colors) == "table" and colors[class] or nil
    if type(c) == "table" and c.r and c.g and c.b then
        return sformat("|cff%02x%02x%02x%s|r", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5), text)
    end
    return text
end

-- Name und Profil eines Mitglieds fuer Tooltip und Bericht: "Bob (Waffen)"
function Group.Who(m)
    local profile = Group.ProfileOf(m)
    local text = ClassColored(m.class, m.name or "?")
    if profile then text = text .. " (" .. profile.name .. ")" end
    return text
end

--[[ Zeilen fuer den Gegenstands-Tooltip (siehe Tooltip.BuildLines): Kopfzeile, dann je Mitglied Name, Profil und
     Zugewinn in Prozent; mehr als MAX_TOOLTIP werden zusammengefasst.                                        ]]
function Group.TooltipLines(link)
    local list = Group.Beneficiaries(link)
    if not (list and #list > 0) then return nil end
    local lines = { { left = L.GROUP_BETTER, color = PURPLE } }
    for i = 1, mmin(#list, MAX_TOOLTIP) do
        local e = list[i]
        local right = e.empty and L.NOTHING_EQUIPPED or EG.FmtPct(e.percent or 0)
        if e.needLevel then right = right .. "  " .. sformat(L.GROUP_AT_LEVEL, e.needLevel) end
        lines[#lines + 1] = { left = Group.Who(e.member), right = right, color = WHITE, rightColor = e.needLevel and YELLOW or GREEN }
    end
    if #list > MAX_TOOLTIP then
        lines[#lines + 1] = { left = sformat(L.GROUP_MORE, #list - MAX_TOOLTIP), color = GREY }
    end
    return lines
end

------------------------------------------------------------------------------
-- 07  Bericht (/eg group, /eg status)
------------------------------------------------------------------------------

--[[ Was ist mit diesem Mitglied?  Rueckgabe: Schluessel, Zahl
       "scanned", Alter in Sekunden   gelesen
       "disconnected" | "range" | "waiting" | "blocked" | "off"  (noch) nicht gelesen und warum                     ]]
function Group.MemberStatus(m)
    local now = Now()
    if m.stamp and m.count > 0 then return "scanned", floor(now - m.stamp) end
    if EG:Get("groupInspect") == false then return "off" end
    if UnitIsConnected and not UnitIsConnected(m.unit) then return "disconnected" end
    if not Group.CanScanNow() then return "blocked" end
    local ok, near = pcall(InRange, m)
    if not (ok and near) then return "range" end
    return "waiting"
end

function Group.StatusLines()
    local C = EG.COLOR
    if not Group.Enabled() then return { L.OPT_GROUP .. ": " .. L.SET_OFF } end
    local read = 0
    for _, m in ipairs(Group.list) do
        if Group.HasData(m) then read = read + 1 end
    end
    return { sformat("%s: %s (%d / %d)", L.OPT_GROUP, L.SET_ON, read, #Group.list)
        .. ((EG:Get("groupInspect") == false) and ("  " .. C.warn .. L.OPT_GROUP_INSPECT .. ": " .. L.SET_OFF .. C.reset) or "") }
end

local function StateText(state)
    if state == "disconnected" then return L.GROUP_STATE_DISCONNECTED end
    if state == "range" then return L.GROUP_STATE_RANGE end
    if state == "waiting" then return L.GROUP_STATE_WAITING end
    if state == "blocked" then return L.GROUP_STATE_BLOCKED end
    return L.GROUP_STATE_OFF
end

-- Eine Zeile je Mitglied fuer /eg group
function Group.ReportLines()
    local C = EG.COLOR
    local lines = {}
    if not Group.Enabled() then
        lines[1] = C.warn .. L.GROUP_OFF .. C.reset
        return lines
    end
    if #Group.list == 0 then
        lines[1] = (IsInRaid and IsInRaid() and not EG:Get("groupRaid")) and L.GROUP_RAID_OFF or L.GROUP_NONE
        return lines
    end
    for _, m in ipairs(Group.list) do
        local profile = Group.ProfileOf(m)
        local state, age = Group.MemberStatus(m)
        local text
        if state == "scanned" then
            text = sformat(L.GROUP_SCANNED, age, m.count)
        else
            text = C.grey .. StateText(state) .. C.reset
        end
        lines[#lines + 1] = sformat("  %s  %s%s%s  %s", Group.Who(m), C.grey,
            profile and (m.tab and L.GROUP_FROM_TALENTS or L.GROUP_CLASS_DEFAULT) or "?", C.reset, text)
    end
    return lines
end

------------------------------------------------------------------------------
-- 08  Ereignisse
------------------------------------------------------------------------------

EG:On("INSPECT_READY", function(_, guid)
    if not Group.Enabled() then return end
    local m = type(guid) == "string" and known[guid] or nil
    if not m then return end
    if pending and pending.guid == guid then pending = nil end
    if Group.Read(m) then EG:Debounce("groupChanged", 0.5, Group.Changed) end
end)

EG:On("UNIT_INVENTORY_CHANGED", function(_, unit)
    if type(unit) ~= "string" or unit == "player" then return end
    for _, m in ipairs(Group.list) do
        if m.unit == unit then m.dirty = true end
    end
end)

local function RosterChanged()
    EG:Debounce("groupRoster", 0.5, function()
        Group.Refresh()
        Group.Changed()
        Group.Start()
    end)
end
EG:On("GROUP_ROSTER_UPDATE", RosterChanged)
EG:On("PLAYER_ENTERING_WORLD", RosterChanged)

-- Einstellungen und Profile aendern, wie bewertet wird (die Profile der Mitglieder werden neu gebildet) und, mit den
-- Schaltern "Hinweise" und "Schlachtzug", wer ueberhaupt zaehlt
local rosterSig
EG:Listen("INVALIDATED", function()
    for _, m in pairs(known) do m.profile = nil end
    local sig = tostring(Group.Enabled()) .. ":" .. tostring(EG:Get("groupRaid"))
    if sig ~= rosterSig then
        rosterSig = sig
        Group.Refresh()
        Group.Start()
    end
end)

-- Jede Untersuchung, die nicht von uns kommt (Untersuchen-Fenster, Zielfenster, andere Addons), merken wir uns
EG:OnLoad("group", function()
    if type(_G.NotifyInspect) == "function" and hooksecurefunc then
        hooksecurefunc("NotifyInspect", function()
            if not ownRequest then foreignAt = Now() end
        end)
    end
end)

EG:OnLogin("group", function()
    Group.Refresh()
    Group.Start()
end)
