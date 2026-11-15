--[[---------------------------------------------------------------------------
    ProfileWindow.lua - Profilvergleich (/egprofile)

    Links ein waehlbares Vergleichsprofil (Klasse und Profil), rechts das aktive Profil. Die Spalte
    "Wert" ist auf beiden Seiten gleich: es sind die Summen der angelegten Ausruestung. Verschieden
    sind Gewicht und Punkte. So sieht man, was die jetzige Ausruestung unter einem anderen Profil waere.

    Eigene Profile entstehen hier: Bearbeiten, dann "Als neues Profil speichern" (oder bei einem eigenen
    Profil "Ueberschreiben"). Aktivieren stellt das Profil fuer diesen Charakter ein, "Automatisch"
    kehrt zur Talenterkennung zurueck.

    Aufbau aus dem eigenen Baukasten (UI.lua): Kopf, zwei Karten mit Tabelle, Ergebniszeile, Knoepfe im Fuss.
    Von der Standard-Oberflaeche kommen nur das Aufklappmenue (MenuUtil) fuer Klasse und Profil und der
    allgemeine Eingabe- und Bestaetigungsdialog (StaticPopup).
-----------------------------------------------------------------------------]]

local _, EG = ...
local PW = {}
EG.ProfileWindow = PW

local L = EG.L
local Stats, Score, Profiles, Specs, Items, UI = EG.Stats, EG.Score, EG.Profiles, EG.Specs, EG.Items, EG.UI

local ipairs, pairs, type, tonumber, pcall = ipairs, pairs, type, tonumber, pcall
local sformat, sgsub = string.format, string.gsub

local WIDTH, HEIGHT = 748, 628
local PANEL_W = 356
local PANEL_H = 404
local MAX_ROWS = 18
local ROW_H = 15
local ROWS_TOP = 98                 -- Karte: Abschnitt, Name, Beschreibung und Spaltentitel stehen darueber

local frame
local state = {
    class = nil,        -- Klassenkennung des Vergleichsprofils
    id = nil,           -- Profil-ID des Vergleichsprofils
    edit = false,       -- Bearbeitungsmodus
    draft = nil,        -- Gewichte im Bearbeitungsmodus
    offset = 0,         -- erste sichtbare Zeile
}

------------------------------------------------------------------------------
-- 01  Bausteine
------------------------------------------------------------------------------

local function Text(parent, size, role, justify)
    local fs = UI.Text(parent, size, role)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function ClassName(token)
    local t = _G.LOCALIZED_CLASS_NAMES_MALE
    return (t and t[token]) or token
end

local FmtWeight = EG.FmtWeight

-- Eingabefeld: dunkle Mulde mit Rand in der Akzentfarbe
local function InputBox(eb, size)
    local fill = eb:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(eb)
    fill:SetColorTexture(0, 0, 0, 0.45)
    eb.edge = UI.Border(eb, "accent")
    UI.Font(eb, size)
    eb:SetTextColor(UI.Color("text"))
end

-- Eingabe- und Bestaetigungsdialoge der Standard-Oberflaeche; ohne sie wird sofort gehandelt
local function AskName(default, onAccept)
    if type(_G.StaticPopup_Show) ~= "function" then
        onAccept(default)
        return
    end
    local ok, dialog = pcall(_G.StaticPopup_Show, "GENERIC_INPUT_BOX", nil, nil, {
        text = L.P_NEW_PROMPT,
        acceptText = _G.ACCEPT,
        cancelText = _G.CANCEL,
        maxLetters = 32,
        callback = EG:Guard("profiles", onAccept),
    })
    if not ok then
        onAccept(default)
        return
    end
    if dialog and dialog.GetEditBox then
        local eb = dialog:GetEditBox()
        if eb then
            eb:SetText(default or "")
            eb:HighlightText()
        end
    end
end

--[[ text ist ein Formattext mit %s; arg1 kommt als text_arg1 hinein. Die Oberflaeche formatiert selbst
     (GENERIC_CONFIRMATION: SetFormattedText(text, text_arg1, text_arg2)) - ein frei gewaehlter Profilname mit
     einem Prozentzeichen darf deshalb nie vorab in den Text eingesetzt werden.                          ]]
local function AskConfirm(text, arg1, onAccept)
    if type(_G.StaticPopup_ShowCustomGenericConfirmation) == "function" then
        local ok = pcall(_G.StaticPopup_ShowCustomGenericConfirmation, {
            text = text, text_arg1 = arg1, callback = EG:Guard("profiles", onAccept), showAlert = true,
        })
        if ok then return end
    end
    onAccept()
end

------------------------------------------------------------------------------
-- 02  Zeilen
------------------------------------------------------------------------------

local function Selected()
    return state.id and Profiles.Get(state.id) or nil
end

-- Schluessel der Zeilen: feste Reihenfolge, damit beide Seiten fluchten
local function RowKeys(wL, wR)
    local keys, seen = { "ILVL" }, { ILVL = true }
    for _, k in ipairs(Stats.ORDER) do
        keys[#keys + 1] = k
        seen[k] = true
    end
    -- eigene Gewichte auf rohe ITEM_MOD-Namen
    for _, w in ipairs({ wL or {}, wR or {} }) do
        for k, v in pairs(w) do
            if not seen[k] and k ~= Stats.DPS and k ~= Stats.RDPS and k ~= Stats.SOCKET and v and v ~= 0 then
                seen[k] = true
                keys[#keys + 1] = k
            end
        end
    end
    keys[#keys + 1] = Stats.DPS
    keys[#keys + 1] = Stats.RDPS
    keys[#keys + 1] = Stats.SOCKET
    return keys
end

local function ValueOf(totals, key)
    if key == "ILVL" then return totals.ILVL or 0 end
    if key == Stats.DPS then return totals.DPS or 0 end
    if key == Stats.RDPS then return totals.RDPS or 0 end
    if key == Stats.SOCKET then return totals.SOCKET or 0 end
    return (totals.stats and totals.stats[key]) or 0
end

local function WeightOf(key, w)
    if key == "ILVL" then return (Score.EffectiveIlvlWeight()) end
    if key == Stats.DPS then return Score.HandWeight(w, "MELEE") end
    if key == Stats.RDPS then return Score.HandWeight(w, "RANGED") end
    if key == Stats.SOCKET then return Score.SocketPoints(w) end
    return w[key] or 0
end

--[[ Gemeinsame Zeilenliste beider Seiten.
     Rueckgabe: rows, Summe links, Summe rechts
     Zeile: { key, label, value, wa, pa, wb, pb, fixed }                                              ]]
function PW.BuildRows(totals, wL, wR, edit, rawDraft)
    local rows = {}
    local ta, tb = 0, 0
    for _, key in ipairs(RowKeys(wL, wR)) do
        local wa, wb = WeightOf(key, wL), WeightOf(key, wR)
        local value = ValueOf(totals, key)
        local fixed = (key == "ILVL" or key == Stats.SOCKET)
        local show = edit and not fixed or (wa ~= 0 or wb ~= 0)
        if key == Stats.SOCKET and (totals.SOCKET or 0) == 0 then show = false end
        if show then
            local label = (key == "ILVL") and L.BASE_ILVL or Stats.Label(key)
            local pa, pb = value * wa, value * wb
            rows[#rows + 1] = {
                key = key, label = label, value = value, wa = wa, pa = pa, wb = wb, pb = pb, fixed = fixed,
                raw = rawDraft and rawDraft[key] or nil,
            }
            ta, tb = ta + pa, tb + pb
        elseif fixed then
            -- feste Zeilen zaehlen auch dann, wenn sie nicht erscheinen
            ta, tb = ta + value * wa, tb + value * wb
        end
    end
    return rows, ta, tb
end

------------------------------------------------------------------------------
-- 03  Eine Seite
------------------------------------------------------------------------------

local function BuildSide(parent, editable)
    local side = {}

    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(PANEL_W, PANEL_H)
    UI.Box(p, "card", "border")
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", EG:Guard("profiles", function(_, delta) PW.Scroll(delta > 0 and -3 or 3) end))
    side.panel = p

    side.caption = Text(p, 10, "faint")
    side.caption:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -9)

    side.title = Text(p, 15, "text")
    side.title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -24)
    side.title:SetSize(PANEL_W - 20, 18)

    side.desc = Text(p, 11, "dim")
    side.desc:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -45)
    side.desc:SetSize(PANEL_W - 20, 26)
    side.desc:SetJustifyV("TOP")

    -- Spaltentitel
    local hy = -(ROWS_TOP - 16)
    local function Head(text, point, x, justify)
        local fs = Text(p, 10, "faint", justify)
        fs:SetPoint(point, p, (point == "TOPRIGHT" and x < 0) and "TOPRIGHT" or "TOPLEFT", x, hy)
        fs:SetText(text)
        return fs
    end
    Head(L.COL_STAT, "TOPLEFT", 10, "LEFT")
    Head(L.COL_VALUE, "TOPRIGHT", 222, "RIGHT")
    Head(L.COL_WEIGHT, "TOPRIGHT", 288, "RIGHT")
    Head(L.COL_POINTS, "TOPRIGHT", -10, "RIGHT")
    UI.Rule(p, "TOP", -(ROWS_TOP - 2))

    side.rows = {}
    for i = 1, MAX_ROWS do
        local y = -ROWS_TOP - (i - 1) * ROW_H
        local row = {}

        if i % 2 == 0 then
            row.stripe = p:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetPoint("TOPLEFT", p, "TOPLEFT", 1, y)
            row.stripe:SetSize(PANEL_W - 2, ROW_H)
            row.stripe:SetColorTexture(UI.Color("stripe"))
        end

        row.label = Text(p, 12, "text")
        row.label:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y)
        row.label:SetSize(150, ROW_H)
        row.label:SetWordWrap(false)

        row.value = Text(p, 12, "text", "RIGHT")
        row.value:SetPoint("TOPRIGHT", p, "TOPLEFT", 222, y)
        row.value:SetHeight(ROW_H)

        row.weight = Text(p, 11, "faint", "RIGHT")
        row.weight:SetPoint("TOPRIGHT", p, "TOPLEFT", 288, y)
        row.weight:SetHeight(ROW_H)

        row.points = Text(p, 12, "text", "RIGHT")
        row.points:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, y)
        row.points:SetHeight(ROW_H)

        if editable then
            local eb = CreateFrame("EditBox", nil, p)
            eb:SetSize(54, ROW_H)
            eb:SetPoint("TOPRIGHT", p, "TOPLEFT", 292, y)
            eb:SetAutoFocus(false)
            eb:SetFontObject("GameFontHighlightSmall")
            eb:SetJustifyH("RIGHT")
            eb:SetMaxLetters(7)
            eb:SetTextInsets(3, 4, 0, 0)
            InputBox(eb, 11)
            eb:SetScript("OnEscapePressed", EG:Guard("profiles", function(s) s:ClearFocus() end))
            eb:SetScript("OnEnterPressed", EG:Guard("profiles", function(s) s:ClearFocus() end))
            eb:SetScript("OnTabPressed", EG:Guard("profiles", function(s) s:ClearFocus() end))
            eb:SetScript("OnEditFocusLost", EG:Guard("profiles", function(s) PW.ApplyEdit(s.statKey, s:GetText()) end))
            eb:Hide()
            row.edit = eb
        end
        side.rows[i] = row
    end

    local ty = -ROWS_TOP - MAX_ROWS * ROW_H - 6
    UI.Rule(p, "TOP", ty + 3)

    side.totalLabel = Text(p, 10, "faint")
    side.totalLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 10, ty - 8)
    side.totalLabel:SetText(L.P_GEAR_SCORE)

    side.totalValue = Text(p, 16, "accent", "RIGHT")
    side.totalValue:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, ty - 4)
    return side
end

-- which = "a" (links) oder "b" (rechts)
local function FillSide(side, rows, total, which, offset, editable)
    for i = 1, MAX_ROWS do
        local r = side.rows[i]
        r.label:SetText("")
        r.value:SetText("")
        r.weight:SetText("")
        r.points:SetText("")
        if r.edit then r.edit:Hide() end
    end

    for i = 1, MAX_ROWS do
        local data = rows[i + offset]
        local r = side.rows[i]
        if data then
            local w = (which == "a") and data.wa or data.wb
            local pt = (which == "a") and data.pa or data.pb
            local other = (which == "a") and data.pb or data.pa

            r.label:SetText(data.label or "?")
            local isDps = (data.key == Stats.DPS or data.key == Stats.RDPS)
            r.value:SetText(isDps and sformat("%.1f", data.value) or EG.FmtScore(data.value))

            if editable and r.edit and not data.fixed then
                r.edit.statKey = data.key
                local shown = data.raw
                if shown == nil then shown = 0 end
                r.edit:SetText(shown ~= 0 and FmtWeight(shown) or "")
                r.edit:Show()
                r.weight:SetText("")
            else
                r.weight:SetText("x" .. FmtWeight(w))
            end

            r.points:SetText(EG.FmtScore(pt))
            -- mehr Punkte als auf der anderen Seite: gruen; weniger: rot
            local role = (pt > other + 0.001) and "good" or ((pt < other - 0.001) and "bad" or "dim")
            UI.Paint(r.points, role)
            r.points.role = role
        end
    end

    side.totalValue:SetText(EG.FmtScore(total))
    UI.Paint(side.totalValue, "accent")
end

------------------------------------------------------------------------------
-- 04  Auswahl
------------------------------------------------------------------------------

local function SpecAfterClassChange(class)
    local active = Profiles.ActiveSpec()
    for _, s in ipairs(Profiles.List(class)) do
        if not active or s.id ~= active.id then return s end
    end
    return Profiles.List(class)[1]
end

function PW.SetClass(class)
    state.class = class
    local spec = SpecAfterClassChange(class)
    state.id = spec and spec.id or nil
    state.edit, state.draft, state.offset = false, nil, 0
    PW.Rebuild()
end

function PW.SelectProfile(id)
    local spec = Profiles.Get(id)
    if not spec then return end
    state.id = id
    state.edit, state.draft, state.offset = false, nil, 0
    PW.Rebuild()
end

-- Menues neu aufbauen (Profilliste kann sich geaendert haben) und neu zeichnen
function PW.Rebuild()
    if not frame then return end
    PW.Refresh()
end

local function ClassMenu(_, root)
    local mine = Profiles.PlayerClass()
    local function IsSel(token) return state.class == token end
    local function Pick(token) PW.SetClass(token) end
    root:CreateRadio(L.P_MYCLASS .. " (" .. ClassName(mine) .. ")", IsSel, Pick, mine)
    for _, token in ipairs(Specs.CLASS_ORDER) do
        if token ~= mine then root:CreateRadio(ClassName(token), IsSel, Pick, token) end
    end
end

local function ProfileMenu(_, root)
    local function IsSel(id) return state.id == id end
    local function Pick(id) PW.SelectProfile(id) end
    if root.SetScrollMode then root:SetScrollMode(320) end
    for _, spec in ipairs(Profiles.List(state.class or Profiles.PlayerClass())) do
        local name = Profiles.Name(spec)
        if spec.custom then name = "* " .. name end
        root:CreateRadio(name, IsSel, Pick, spec.id)
    end
end

--[[ Auswahlknopf: flach wie die uebrigen, rechts ein kleines Dreieck. Ein Klick oeffnet das Aufklappmenue der
     Standard-Oberflaeche (MenuUtil.CreateContextMenu) mit den Eintraegen aus generator; fehlt es, springt jeder
     Klick zum naechsten Eintrag (Rechtsklick: zum vorigen). Den Text setzt PW.Refresh.                       ]]
local function MakeSelector(parent, width, generator, cycle)
    local b = UI.Button(parent, "", width, 24)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.label:SetWidth(width - 30)
    for i = 0, 3 do                 -- das Dreieck: vier Linien, jede zwei Pixel kuerzer
        local line = b:CreateTexture(nil, "ARTWORK")
        line:SetSize(7 - 2 * i, 1)
        line:SetPoint("TOP", b, "RIGHT", -13, 2 - i)
        line:SetColorTexture(UI.Color("dim"))
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", EG:Guard("profiles", function(self, button)
        local menu = _G.MenuUtil
        if type(menu) == "table" and type(menu.CreateContextMenu) == "function" then
            menu.CreateContextMenu(self, generator)
        else
            cycle(button == "RightButton" and -1 or 1)
        end
    end))
    return b
end

local function Cycle(list, current, step)
    local idx = 1
    for i, v in ipairs(list) do
        if v == current then idx = i break end
    end
    idx = idx + step
    if idx < 1 then idx = #list end
    if idx > #list then idx = 1 end
    return list[idx]
end

------------------------------------------------------------------------------
-- 05  Bearbeiten
------------------------------------------------------------------------------

local function StartDraft()
    local spec = Selected()
    state.draft = spec and Profiles.RawWeights(spec) or {}
end

function PW.ApplyEdit(statKey, text)
    if not (state.edit and state.draft and statKey) then return end
    local clean = EG.Trim(sgsub(text or "", ",", "."))
    local v = tonumber(clean)
    if clean == "" or v == 0 then
        state.draft[statKey] = nil                      -- leer oder 0: kein Gewicht
    elseif v and v == v and v ~= math.huge and v ~= -math.huge then
        state.draft[statKey] = v
    end                                                 -- sonst bleibt der alte Wert stehen
    PW.Refresh()
end

local function Announce(spec)
    EG:Print(sformat(L.SET_PROFILE, Profiles.Name(spec)))
end

function PW.SaveOver()
    local spec = Selected()
    if not (state.edit and state.draft and spec and spec.custom) then
        EG:Print(EG.COLOR.warn .. L.P_ONLY_CUSTOM .. EG.COLOR.reset)
        return
    end
    Profiles.SetCustomWeights(spec.id, state.draft)
    local newName = frame and frame.nameBox and EG.Trim(frame.nameBox:GetText()) or ""
    if newName ~= "" then Profiles.RenameCustom(spec.id, newName) end
    state.edit, state.draft = false, nil
    Announce(Profiles.Get(spec.id))
    PW.Rebuild()
end

function PW.SaveAsNew(name)
    local spec = Selected()
    local weights = state.draft
    if not weights then weights = spec and Profiles.RawWeights(spec) or {} end

    local id = Profiles.CreateCustom(name, spec and spec.id, state.class)
    if not id then return end
    Profiles.SetCustomWeights(id, weights)

    state.id = id
    state.edit, state.draft = false, nil
    Announce(Profiles.Get(id))
    PW.Rebuild()
end

function PW.Delete()
    local spec = Selected()
    if not (spec and spec.custom) then return end
    local id = spec.id
    AskConfirm(L.P_DELETE_PROMPT, Profiles.Name(spec), function()
        Profiles.DeleteCustom(id)
        state.edit, state.draft = false, nil
        state.id = nil
        PW.SetClass(state.class or Profiles.PlayerClass())
    end)
end

function PW.Activate()
    local spec = Selected()
    if not spec then return end
    if Profiles.SetActive(spec.id) then Announce(spec) end
    PW.Refresh()
end

function PW.UseAuto()
    if Profiles.SetActive("AUTO") then
        EG:Print(sformat(L.SET_PROFILE, Profiles.Resolve().name))
    end
    PW.Refresh()
end

function PW.ToggleEdit()
    state.edit = not state.edit
    state.offset = 0
    if state.edit then StartDraft() else state.draft = nil end
    PW.Refresh()
end

-- Das Mausrad verschiebt den Ausschnitt; Refresh haelt ihn innerhalb der Zeilenliste
function PW.Scroll(delta)
    state.offset = (state.offset or 0) + delta
    PW.Refresh()
end

------------------------------------------------------------------------------
-- 06  Darstellung
------------------------------------------------------------------------------

local function ItemLine(wL, wR)
    local link = EG.Window and EG.Window.Link and EG.Window.Link()
    if not link then return nil end
    local item = Items.Get(link)
    if not item then return nil end
    local _, a = Score.Breakdown(item, nil, wL)
    local _, b = Score.Breakdown(item, nil, wR)
    return sformat("%s: %s / %s", L.P_ITEM_LINE, EG.FmtScore(a), EG.FmtScore(b))
end

function PW.Refresh()
    if not frame or not frame:IsShown() then return end
    if not EG.db or not EG.cdb then return end

    state.class = state.class or Profiles.PlayerClass()
    local active = Profiles.Resolve()

    if not (state.id and Profiles.Get(state.id)) then
        local spec = SpecAfterClassChange(state.class)
        state.id = spec and spec.id or nil
    end
    local spec = Selected()
    local edit = (state.edit and state.draft) and true or false

    -- Gewichte beider Seiten
    local wR = active.weights
    local wL
    if edit then
        wL = Profiles.DeriveWeights(state.draft, spec)
    else
        wL = spec and Profiles.WeightsFor(spec) or {}
    end

    local totals = Score.EquippedTotals()
    local rows, totalL, totalR = PW.BuildRows(totals, wL, wR, edit, edit and state.draft or nil)
    local maxOffset = #rows - MAX_ROWS
    if maxOffset < 0 then maxOffset = 0 end
    if state.offset > maxOffset then state.offset = maxOffset end
    if state.offset < 0 then state.offset = 0 end

    -- rechts: das aktive Profil
    frame.right.title:SetText(active.name or "-")
    frame.right.desc:SetText(Profiles.Desc(active.spec))
    FillSide(frame.right, rows, totalR, "b", state.offset, false)

    -- links: das Vergleichsprofil
    if edit then
        frame.nameBox:SetShown(spec and spec.custom or false)
        if spec and spec.custom and frame.nameBox:GetText() == "" then
            frame.nameBox:SetText(Profiles.Name(spec))
        end
        frame.left.title:SetText((spec and spec.custom) and "" or Profiles.Name(spec))
        frame.left.desc:SetText(L.P_EDIT_HINT)
    else
        frame.nameBox:Hide()
        frame.nameBox:SetText("")
        frame.left.title:SetText(spec and Profiles.Name(spec) or "-")
        frame.left.desc:SetText(spec and Profiles.Desc(spec) or "")
    end
    FillSide(frame.left, rows, totalL, "a", state.offset, edit)

    -- Ergebnis
    local isActive = (spec and active.spec and spec.id == active.spec.id and not edit) and true or false
    local delta = totalL - totalR
    local C = EG.COLOR
    frame.caveat:SetText(isActive and "" or L.P_CAVEAT)

    if (totals.COUNT or 0) == 0 then
        frame.verdict:SetText(C.warn .. L.P_NOGEAR .. C.reset)
        frame.note:SetText("")
        frame.caveat:SetText("")
    elseif isActive then
        frame.verdict:SetText(C.grey .. L.P_IS_ACTIVE .. C.reset)
        frame.note:SetText(sformat("%s: %s  (%s)", L.P_GEAR, EG.FmtScore(totalR), sformat(L.P_ITEMS, totals.COUNT or 0)))
    else
        local col = (delta > 0) and C.good or ((delta < 0) and C.bad or C.grey)
        local sign = (delta > 0) and "+" or ""
        frame.verdict:SetText(sformat("%s %s %s     %s: %s%s%s",
            EG.FmtScore(totalR), C.grey .. "->" .. C.reset, EG.FmtScore(totalL),
            L.DIFFERENCE, col, sign .. EG.FmtScore(delta), C.reset))
        local msg = (delta > 0) and L.P_BETTER or ((delta < 0) and L.P_WORSE or L.P_SAME)
        local itemLine = ItemLine(wL, wR)
        if itemLine then msg = msg .. "   |   " .. itemLine end
        frame.note:SetText(msg)
    end

    -- Knoepfe
    frame.btnEdit:SetText(edit and L.BTN_CANCEL or L.P_EDIT)
    frame.btnActivate:SetEnabled(spec ~= nil and not isActive and not edit)
    frame.btnAuto:SetEnabled(not active.auto)
    frame.btnSave:SetEnabled(edit and spec ~= nil and spec.custom == true)
    frame.btnSaveNew:SetEnabled(spec ~= nil)
    frame.btnDelete:SetEnabled(spec ~= nil and spec.custom == true and not edit)

    frame.profDD:SetText(spec and ((spec.custom and "* " or "") .. Profiles.Name(spec)) or "-")
    frame.classDD:SetText(ClassName(state.class))
    UI.Refresh(frame)
end

------------------------------------------------------------------------------
-- 07  Aufbau
------------------------------------------------------------------------------

local function SavePosition()
    if not (frame and EG.cdb) then return end
    local point, _, _, x, y = frame:GetPoint(1)
    EG.cdb.profileGui = EG.cdb.profileGui or {}
    EG.cdb.profileGui.point, EG.cdb.profileGui.x, EG.cdb.profileGui.y = point, x, y
end

local function Build()
    if frame then return frame end

    frame = UI.Window("EasyGearProfileWindow", WIDTH, HEIGHT, "EasyGear")
    frame.subtitle:SetText(L.P_SUB)
    frame:SetScript("OnDragStart", EG:Guard("profiles", function(self) self:StartMoving() end))
    frame:SetScript("OnDragStop", EG:Guard("profiles", function(self) self:StopMovingOrSizing() SavePosition() end))

    local g = EG.cdb and EG.cdb.profileGui or {}
    frame:ClearAllPoints()
    frame:SetPoint(g.point or "CENTER", UIParent, g.point or "CENTER", g.x or 0, g.y or 0)
    frame:SetScale((EG.cdb and EG.cdb.gui and EG.cdb.gui.scale) or 1)

    local body = frame.body

    -- Auswahl ueber den Karten: Klasse und Profil des Vergleichsprofils
    local classes = Specs.CLASS_ORDER
    frame.classDD = MakeSelector(body, 150, ClassMenu, function(step)
        PW.SetClass(Cycle(classes, state.class, step))
    end)
    frame.classDD:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)

    frame.profDD = MakeSelector(body, 198, ProfileMenu, function(step)
        local ids = {}
        for _, s in ipairs(Profiles.List(state.class or Profiles.PlayerClass())) do ids[#ids + 1] = s.id end
        PW.SelectProfile(Cycle(ids, state.id, step))
    end)
    frame.profDD:SetPoint("LEFT", frame.classDD, "RIGHT", 8, 0)

    -- Seiten
    frame.left = BuildSide(body, true)
    frame.left.panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -32)
    frame.left.caption:SetText(L.P_CANDIDATE)

    frame.right = BuildSide(body, false)
    frame.right.panel:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -32)
    frame.right.caption:SetText(L.P_ACTIVEPROF)

    -- Name eines eigenen Profils (Bearbeiten)
    local nameBox = CreateFrame("EditBox", nil, frame.left.panel)
    nameBox:SetSize(220, 20)
    nameBox:SetPoint("TOPLEFT", frame.left.panel, "TOPLEFT", 10, -23)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("GameFontNormal")
    nameBox:SetMaxLetters(32)
    nameBox:SetTextInsets(4, 4, 0, 0)
    InputBox(nameBox, 13)
    nameBox:SetScript("OnEscapePressed", EG:Guard("profiles", function(s) s:ClearFocus() end))
    nameBox:SetScript("OnEnterPressed", EG:Guard("profiles", function(s) s:ClearFocus() end))
    nameBox:Hide()
    frame.nameBox = nameBox

    -- Ergebnis unter den Seiten
    frame.verdict = Text(body, 15, "text", "CENTER")
    frame.verdict:SetPoint("BOTTOM", body, "BOTTOM", 0, 40)
    frame.verdict:SetWidth(WIDTH - 40)
    frame.note = Text(body, 12, "dim", "CENTER")
    frame.note:SetPoint("BOTTOM", body, "BOTTOM", 0, 22)
    frame.note:SetWidth(WIDTH - 40)
    frame.caveat = Text(body, 11, "faint", "CENTER")
    frame.caveat:SetPoint("BOTTOM", body, "BOTTOM", 0, 4)
    frame.caveat:SetWidth(WIDTH - 40)

    -- Schaltflaechen im Fuss
    local function Btn(text, width, onClick)
        return UI.FooterButton(frame, text, width, EG:Guard("profiles", onClick))
    end
    frame.btnActivate = Btn(L.P_ACTIVATE, 104, PW.Activate)
    frame.btnAuto = Btn(L.P_AUTO, 104, PW.UseAuto)
    frame.btnEdit = Btn(L.P_EDIT, 100, PW.ToggleEdit)
    frame.btnSave = Btn(L.P_OVERWRITE, 104, PW.SaveOver)
    frame.btnSaveNew = Btn(L.P_SAVE_NEW, 170, function()
        local spec = Selected()
        AskName(spec and (Profiles.Name(spec) .. " 2") or "", function(name) PW.SaveAsNew(name) end)
    end)
    frame.btnDelete = Btn(L.P_DELETE, 90, PW.Delete)

    frame:SetScript("OnShow", EG:Guard("profiles", function()
        state.class = state.class or Profiles.PlayerClass()
        PW.Rebuild()
    end))
    return frame
end

------------------------------------------------------------------------------
-- 08  Steuerung
------------------------------------------------------------------------------

function PW.Open()
    Build()
    if not frame:IsShown() then frame:Show() end
end

function PW.Toggle()
    Build()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function PW.IsShown() return frame ~= nil and frame:IsShown() end

-- Vergleichsprofil von aussen waehlen (/egprofile <id>)
function PW.Select(id)
    local spec = Profiles.Get(id)
    if not spec then return false end
    state.class = (spec.class and spec.class ~= "ANY") and spec.class or (state.class or Profiles.PlayerClass())
    PW.Open()
    PW.SelectProfile(id)
    return true
end

EG:Listen("INVALIDATED", function() PW.Refresh() end)
EG:Listen("REFRESH", function() PW.Refresh() end)

EG:Listen("GUI_SCALE", function()
    if frame then frame:SetScale((EG.cdb and EG.cdb.gui and EG.cdb.gui.scale) or 1) end
end)

EG:Listen("GUI_RESET", function()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(1)
end)
