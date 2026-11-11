--[[---------------------------------------------------------------------------
    DialogueUI.lua - Anbindung an Dialogue UI (Raenore, Peterodox)

    Dialogue UI ersetzt die Quest- und Gespraechsfenster der Standard-Oberflaeche und zeichnet alles selbst:
    Belohnungsknoepfe mit eigenen Symbolen (Aufwertungspfeil nach Gegenstandsstufe, hoechster Verkaufspreis) und einen
    eigenen Tooltip (kein GameTooltip) mit einem Vergleich, den die Umschalttaste ein- und ausblendet. Die Haken von
    EasyGear auf die Standard-Oberflaeche (Tooltip.lua, Contexts.lua) greifen dort deshalb nicht. Diese Datei haengt
    EasyGear an Schnittstellen, die Dialogue UI selbst anbietet oder fuer sein Pawn benutzt, ohne etwas an Dialogue UI
    zu aendern, und malt mit dessen Schriften, Farben und Abstaenden:

      Tooltip     Ein Block unter dem Vergleich von Dialogue UI und ueber dessen Umschalt-Hinweis - dort, wo Dialogue UI
                  auch die Werte von Pawn einsetzt:
                      EasyGear                         Wertung: 5.4        (Gold, wie "Ersetze ...")
                      VERBESSERUNG                     +0.5 (+9.2%)         (Gruen / Rot von Dialogue UI)
                          +1 Beweglichkeit                                  (eingerueckt, nur bei eingeblendetem Vergleich)
                      Besser fuer die Gruppe: ...
                  Bei ausgeblendetem Vergleich bleibt es bei Wertung und Urteil - der Tooltip von Dialogue UI soll
                  knapp bleiben. Schnittstelle: DialogueUIAPI.AddItemTooltipProcessorExternal (oeffentlich) und
                  tooltip.ProcessItemExternal (der Platz fuer Pawn; EasyGear haengt sich dahinter, die Zeilen eines
                  vorhandenen Pawn bleiben erhalten und stehen davor).
      Belohnungen Die beste Wahl unter mehreren Belohnungen bekommt den Haken von EasyGear (Form und Farbe wie in den
                  Optionen gewaehlt) an der oberen rechten Ecke des Symbols, die Dialogue UI frei laesst. Ein Gegenstand,
                  den EasyGear fuer eine Verbesserung haelt, bekommt den Aufwertungspfeil von Dialogue UI selbst
                  (ShowUpgradeIcon: sein Bild, seine Bewegung, sein Platz) - hat Dialogue UI keinen gezeigt.

    Alles ist abgesichert: fehlt eine der Schnittstellen, meldet /eg status, welche, und das Uebrige laeuft weiter.
-----------------------------------------------------------------------------]]

local _, EG = ...
local DUI = {}
EG.DialogueUI = DUI

local L = EG.L
local Items, Score, Recommend, Marks, Tooltip = EG.Items, EG.Score, EG.Recommend, EG.Marks, EG.Tooltip

local type, pcall, ipairs, pairs, next, tostring, tonumber = type, pcall, ipairs, pairs, next, tostring, tonumber
local tconcat = table.concat

local ADDON = "DialogueUI"
local TICK = 0.25                        -- Sekunden zwischen zwei Durchlaeufen ueber die Belohnungsknoepfe

------------------------------------------------------------------------------
-- 01  Aussehen: die Farben und Masse von Dialogue UI (Code/Tooltip/Tooltip_Private.lua, Tooltip_Base.lua)
------------------------------------------------------------------------------

local GOLD = { 1.00, 0.82, 0.00 }        -- Ueberschriften ("Ersetze ...")
local WHITE = { 1, 1, 1 }
-- Rolle einer Zeile (siehe Tooltip.BuildLines) -> Farbe in Dialogue UI
local PALETTE = {
    title = GOLD, warn = GOLD, text = WHITE,
    good = { 0.098, 1.000, 0.098 },      -- "|cff19ff19": der Zuwachs der Gegenstandsstufe
    bad = { 1.000, 0.125, 0.125 },       -- die rote Warnung bei verschiedenen Gegenstandsarten
    muted = { 0.50, 0.50, 0.50 },        -- der Umschalt-Hinweis
}
local INDENT = 12                        -- TOOLTIP_PADDING: so weit rueckt Dialogue UI die Werte eines Vergleichs ein
local SIZE_BODY = 2                      -- Schriftgroesse "Medium" (1 = gross, 3 = klein)

-- Jede Zeile von EasyGear nennt, was ihre Farbe bedeutet (role, rightRole); die Farbe dazu ist die von Dialogue UI
local function ColorOf(role)
    return PALETTE[role] or WHITE
end

-- Eine Zeile in den Tooltip von Dialogue UI schreiben: links, und rechts daneben, wenn sie einen zweiten Text hat
local function AddLine(tooltip, ln)
    local c = ColorOf(ln.role)
    local fontString = tooltip:AddLeftLine(ln.left, c[1], c[2], c[3], ln.wrap and true or false, nil, SIZE_BODY,
        ln.indent and INDENT or nil)
    if ln.right and fontString then
        local rc = ColorOf(ln.rightRole)
        tooltip:AddRightLine(ln.right, rc[1], rc[2], rc[3], false, nil, SIZE_BODY)
    end
end

------------------------------------------------------------------------------
-- 02  Tooltip
------------------------------------------------------------------------------

local state = { found = false, problems = {}, tooltip = nil, wrapper = nil, checked = false, broken = false }

-- Die Anbindung als Ganzes laesst sich in den Optionen abschalten; der Tooltip folgt ausserdem dem Schalter der Tooltips
local function Active()
    return EG:Get("showDialogueUI") ~= false
end

local function Enabled()
    return Active() and EG:Get("showTooltip") ~= false
end

--[[ Die Methoden, mit denen EasyGear in den Tooltip von Dialogue UI schreibt. Den Tooltip erzeugt Dialogue UI erst beim
     ersten Gegenstand; beim ersten Aufruf des Verarbeiters wird geprueft, ob er sie hat. Fehlt eine (eine andere Fassung
     von Dialogue UI), nennt /eg status sie, und EasyGear schreibt nicht in diesen Tooltip.                           ]]
local TOOLTIP_METHODS = { "AddLeftLine", "AddRightLine", "AddBlankLine" }

local function CheckTooltip(tooltip)
    state.checked = true
    local missing = {}
    for _, name in ipairs(TOOLTIP_METHODS) do
        if type(tooltip[name]) ~= "function" then missing[#missing + 1] = "tooltip:" .. name end
    end
    if #missing == 0 then return true end
    state.broken = true
    for _, name in ipairs(missing) do state.problems[#state.problems + 1] = name end
    EG:HookResult("dialogueui", false, tconcat(state.problems, ", "))
    return false
end

-- Zeigt Dialogue UI den Vergleich mit dem Angelegten? (Umschalt, gespeichert in DialogueUI_DB)
local function Expanded()
    local db = _G.DialogueUI_DB
    return type(db) == "table" and db.TooltipShowItemComparison == true
end

-- Die empfohlene Questbelohnung: der Knopf, der den Tooltip besitzt, traegt den Haken (siehe Abschnitt 03)
local function PickOf(owner)
    local data = type(owner) == "table" and Marks.registry[owner] or nil
    if data and data.best then return { pick = data.bestKind or "UPGRADE" } end
    return nil
end

--[[ Den Block von EasyGear an das Ende des Tooltips setzen. Rueckgabe: wurde etwas gesetzt?
     Knapp (Vergleich aus): Wertung, Urteil und die Empfehlung. Mit Vergleich: dazu Platz, Attribute, Hinweise und die
     Gruppenhinweise.                                                                                               ]]
local function AddBlock(tooltip, link, owner)
    if not Enabled() or not link then return false end
    local expanded = Expanded()
    local content = Tooltip.Compose(Items.Get(link), "FULL", PickOf(owner), expanded)
    if not content then return false end

    local any = false
    for _, ln in ipairs(content.lines) do
        if expanded or not ln.detail then
            if not any then
                tooltip:AddBlankLine()
                any = true
            end
            AddLine(tooltip, ln)
        end
    end
    if content.group then                      -- Compose liefert sie nur bei eingeblendetem Vergleich
        tooltip:AddBlankLine()
        any = true
        for _, ln in ipairs(content.group) do AddLine(tooltip, ln) end
    end
    return any
end

-- EasyGear haengt sich hinter das, was schon an tooltip.ProcessItemExternal haengt (Pawn setzt dort seine Zeilen). Ersetzt
-- spaeter jemand die Funktion (ein Pawn, das erst jetzt geladen wird), haengt sich EasyGear von neuem an: ob die eigene noch
-- dort steht, zeigt der Vergleich mit state.wrapper.
local function Wrap(tooltip)
    local original = tooltip.ProcessItemExternal
    local function wrapper(self, itemLink)
        if type(original) == "function" then original(self, itemLink) end
        EG:Try("dialogueui", AddBlock, self, itemLink, self.owner)
    end
    tooltip.ProcessItemExternal = wrapper
    state.wrapper, state.tooltip = wrapper, tooltip
end

local function IsWrapped(tooltip)
    return state.wrapper ~= nil and tooltip.ProcessItemExternal == state.wrapper
end

--[[ Dialogue UI ruft jeden Verarbeiter, wenn sein Tooltip einen Gegenstand zeigt (DialogueUIAPI.AddItemTooltipProcessorExternal),
     aber erst im naechsten Bild - nach dem Umschalt-Hinweis, der die letzte Zeile sein soll. Beim ersten Mal haengt sich
     EasyGear deshalb an tooltip.ProcessItemExternal (das ruft Dialogue UI mitten im Aufbau, vor dem Hinweis) und laesst den
     Tooltip einmal neu bauen. Ausruestung setzt von da an der Haken, alles andere (ein Verbrauchsgegenstand, der die beste
     Wahl ist) setzt dieser Verarbeiter selbst ans Ende.                                                              ]]
local function OnSetItem(tooltip, _, itemLink)
    if type(tooltip) ~= "table" then return false end
    if not state.checked and not CheckTooltip(tooltip) then return false end
    if state.broken then return false end
    if not IsWrapped(tooltip)
       and type(tooltip.ProcessItemExternal) == "function" and type(tooltip.ReprocessInfo) == "function" then
        Wrap(tooltip)
        if Enabled() and tooltip.IsShown and tooltip:IsShown() then tooltip:ReprocessInfo() end
        return false
    end
    local item = Enabled() and itemLink and Items.Get(itemLink) or nil
    if item and item.isGear and IsWrapped(tooltip) then return false end      -- der Haken hat den Block gesetzt
    return AddBlock(tooltip, itemLink, tooltip.owner)
end

local function Processor(tooltip, itemID, itemLink)
    local ok, changed = EG:Try("dialogueui", OnSetItem, tooltip, itemID, itemLink)
    return ok and changed == true
end

-- Daten, die erst spaeter ankommen (ein Gegenstand wird geladen, eine Einstellung aendert sich): der offene Tooltip
-- baut sich neu, damit der Block erscheint oder verschwindet
local function RefreshTooltip()
    local tooltip = state.tooltip
    if tooltip and tooltip.IsShown and tooltip:IsShown() and type(tooltip.ReprocessInfo) == "function" then
        tooltip:ReprocessInfo()
    end
end

------------------------------------------------------------------------------
-- 03  Belohnungsknoepfe
------------------------------------------------------------------------------

local known = setmetatable({}, { __mode = "k" })        -- Knopf -> { key } : Knoepfe, die EasyGear hier markiert hat
local dirty = true                                      -- Ergebnisse veraltet: beim naechsten Durchlauf neu bewerten

local function RewardLink(kind, index)
    local getter = _G.GetQuestItemLink
    if type(getter) ~= "function" or not index then return nil end
    local ok, link = pcall(getter, kind, index)
    if ok and type(link) == "string" and link ~= "" then return link end
    return nil
end

-- Anzahl und "verwendbar" laut Client, wie sie Dialogue UI selbst liest (GetQuestItemInfo)
local function RewardInfo(kind, index)
    local getter = _G.GetQuestItemInfo
    if type(getter) ~= "function" then return 1, nil end
    local res = { pcall(getter, kind, index) }
    if not res[1] then return 1, nil end
    -- res = ok, Name, Textur, Anzahl, Qualitaet, verwendbar
    return tonumber(res[4]) or 1, res[6]
end

local function ClearAll()
    for button in pairs(known) do
        known[button] = nil
        Marks.Clear(button)
    end
    dirty = true
end

-- Der Haken gehoert zu den Markierungen der Questbelohnungen (eigener Schalter), nicht zu denen des Tooltips
local function MarksEnabled()
    return Active() and Marks.Enabled("quest")
end

local function ActiveButtons(dialog)
    local list = {}
    local pool = dialog.itemButtonPool
    if type(pool) ~= "table" or type(pool.ProcessActiveObjects) ~= "function" then return list end
    pool:ProcessActiveObjects(function(button)
        if type(button) == "table" and button.objectType == "item" and (button.type == "choice" or button.type == "reward") then
            list[#list + 1] = button
        end
    end)
    return list
end

--[[ Ein Durchlauf: Knoepfe anmelden, die beste Wahl bestimmen, Haken und Pfeile setzen. Dialogue UI baut die Belohnungen
     fuer jede Quest neu und benutzt die Knoepfe wieder; EasyGear erkennt am Gegenstand, ob ein Knopf neu belegt ist. ]]
local function Update(dialog)
    local buttons = ActiveButtons(dialog)
    if not MarksEnabled() then
        if next(known) then ClearAll() end
        return
    end

    local entries, choiceButtons = {}, {}
    for _, button in ipairs(buttons) do
        local link = RewardLink(button.type, button.index)
        local count, usable = RewardInfo(button.type, button.index)
        local key = tostring(button.type) .. ":" .. tostring(button.index) .. ":" .. tostring(link) .. ":" .. tostring(count)
            .. ":" .. tostring(usable)
        local entry = known[button]
        if not entry or entry.key ~= key then
            -- neu belegt (oder die Antwort des Clients hat sich geaendert): was dort vorher stand, ist vorbei
            known[button] = { key = key, usable = usable }
            if button.type == "choice" then Marks.Set(button, nil, { ctx = "quest" }) end      -- nur der Haken, kein eigener Pfeil
            dirty = true
        end
        if button.type == "choice" and link then
            entries[#entries + 1] = { index = button.index, link = link, count = count, apiUsable = usable }
            choiceButtons[button.index] = button
        end
    end

    if dirty then
        -- die beste Wahl (nur bei mehreren Belohnungen zur Auswahl)
        local best, kind
        if #entries >= 2 then best, kind = Recommend.BestReward(entries) end
        for idx, button in pairs(choiceButtons) do Marks.SetBest(button, best ~= nil and idx == best, kind) end

        -- der Aufwertungspfeil von Dialogue UI fuer jede Verbesserung, die EasyGear erkennt; fehlen noch Gegenstandsdaten,
        -- gilt der Durchlauf als nicht abgeschlossen
        local pending = false
        for _, button in ipairs(buttons) do
            local link = RewardLink(button.type, button.index)
            if link and known[button].usable ~= false
               and type(button.ShowUpgradeIcon) == "function" and type(button.DoesButtonHaveMarker) == "function"
               and not button:DoesButtonHaveMarker("upgrade") then
                local verdict, loading = Score.UpgradeState(link)
                if loading then pending = true end
                if verdict == "UPGRADE" then
                    button:ShowUpgradeIcon(type(dialog.IsChoosingReward) == "function" and dialog:IsChoosingReward() or false)
                end
            end
        end
        dirty = pending
    end
end

local function StartDriver(dialog)
    local driver = CreateFrame("Frame", nil, dialog)
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < TICK then return end
        elapsed = 0
        EG:Try("dialogueui", Update, dialog)
    end)
    driver:SetScript("OnShow", function() elapsed = TICK end)
    driver:SetScript("OnHide", function() ClearAll() end)
    -- Dialogue UI raeumt bei jedem Wechsel der Quest alle Knoepfe weg und belegt sie neu: nichts soll stehen bleiben
    if type(dialog.ReleaseAllObjects) == "function" and hooksecurefunc then
        pcall(hooksecurefunc, dialog, "ReleaseAllObjects", function() EG:Try("dialogueui", ClearAll) end)
    end
    DUI.driver = driver
end

local function MarkDirty()
    dirty = true
end

------------------------------------------------------------------------------
-- 04  Anmeldung und Auskunft
------------------------------------------------------------------------------

local function IsLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON) and true or false
end

function DUI.Register()
    if state.registered then return true end
    if not IsLoaded() then return false end
    state.found = true
    state.problems = {}

    local api = _G.DialogueUIAPI
    if type(api) == "table" and type(api.AddItemTooltipProcessorExternal) == "function" then
        local ok, err = pcall(api.AddItemTooltipProcessorExternal, Processor)
        if not ok then state.problems[#state.problems + 1] = "AddItemTooltipProcessorExternal: " .. tostring(err) end
    else
        state.problems[#state.problems + 1] = "DialogueUIAPI.AddItemTooltipProcessorExternal"
    end

    local dialog = _G.DUIQuestFrame
    if type(dialog) == "table" and type(dialog.itemButtonPool) == "table"
       and type(dialog.itemButtonPool.ProcessActiveObjects) == "function" then
        local ok, err = pcall(StartDriver, dialog)
        if not ok then state.problems[#state.problems + 1] = "DUIQuestFrame: " .. tostring(err) end
    else
        state.problems[#state.problems + 1] = "DUIQuestFrame.itemButtonPool"
    end

    state.registered = true
    EG:HookResult("dialogueui", #state.problems == 0, #state.problems > 0 and tconcat(state.problems, ", ") or nil)
    EG:Listen("INVALIDATED", function()
        MarkDirty()
        EG:Debounce("dialogueuiTooltip", 0.1, function() EG:Try("dialogueui", RefreshTooltip) end)
    end)
    EG:Listen("ITEMS_LOADED", function()
        MarkDirty()
        EG:Debounce("dialogueuiTooltip", 0.1, function() EG:Try("dialogueui", RefreshTooltip) end)
    end)
    return #state.problems == 0
end

-- Zeile fuer /eg status
function DUI.StatusLine()
    if not state.found then return "Dialogue UI: " .. L.COMPAT_NOT_FOUND end
    if #state.problems > 0 then return "Dialogue UI: " .. L.DUI_PROBLEM .. " (" .. tconcat(state.problems, ", ") .. ")" end
    return "Dialogue UI: " .. L.DUI_OK
end

EG:OnLogin("dialogueui", function() DUI.Register() end)
