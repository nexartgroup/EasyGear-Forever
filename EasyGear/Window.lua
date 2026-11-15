--[[---------------------------------------------------------------------------
    Window.lua - Vergleichsfenster (/eg, /eggui)

    Einen Gegenstand auf das Feld links ziehen, bei offenem Fenster mit Umschalt anklicken oder
    /eg <Link> eingeben. Links steht die volle Rechnung des Kandidaten (Attribut, Wert, Gewicht,
    Punkte), rechts die des angelegten Gegenstands; bei Ringen, Schmuck und Einhandwaffen schalten
    die Reiter zwischen beiden Plaetzen. Unten stehen Urteil und Hinweise.

    Aufbau aus dem eigenen Baukasten (UI.lua): Kopf mit Titel und Profil, zwei Karten (neues Item,
    angelegtes Item) mit Symbol, Wertung und Rechentabelle - hinter jeder Zeile ein Balken, der zeigt,
    wie viel sie zur Wertung beitraegt -, darunter das Urteil auf einem Streifen in seiner Farbe.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Window = {}
EG.Window = Window

local L = EG.L
local Items, Score, Profiles, UI = EG.Items, EG.Score, EG.Profiles, EG.UI

local ipairs, type, pcall, tostring = ipairs, type, pcall, tostring
local sformat = string.format
local mmax, mabs = math.max, math.abs

local WIDTH, HEIGHT = 644, 610
local ROWS = 15
local ROW_H = 18
local CARD_W, CARD_PAD = 304, 10
local HEAD_H = 118                       -- Karte: Abschnitt, Symbol, Name, Wertung und die Spaltentitel
-- Breite der vier Spalten einer Rechenzeile (zusammen die Innenbreite einer Karte: 284 Pixel)
local LABEL_W, VALUE_W, WEIGHT_W, POINTS_W = 136, 48, 44, 50
local GAP = 2
Window.ROW_WIDTH = CARD_W - 2 * CARD_PAD

local frame
local state = { link = nil, pick = 1 }

------------------------------------------------------------------------------
-- 01  Bausteine
------------------------------------------------------------------------------

-- Eine Karte (Kandidat oder Angelegtes): Abschnittstitel, Symbol, Name, Wertung und die Rechenzeilen
local function BuildColumn(parent, x, caption)
    local col = { rows = {} }

    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    card:SetSize(CARD_W, HEAD_H + ROWS * ROW_H + CARD_PAD)
    UI.Box(card, "card", "border")
    col.card = card

    col.caption = UI.Text(card, 10, "faint")
    col.caption:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -9)
    col.caption:SetText(caption)

    local btn = UI.Icon(card, 40)
    btn:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -26)
    btn.EasyGearPlain = true            -- deren Tooltip bekommt keine EasyGear-Zeilen (Tooltip.lua)
    col.button = btn

    col.name = UI.Text(card, 14, "text")
    col.name:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + 48, -27)
    col.name:SetWidth(CARD_W - CARD_PAD * 2 - 48)
    col.info = UI.Text(card, 11, "dim")
    col.info:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + 48, -47)
    col.info:SetWidth(CARD_W - CARD_PAD * 2 - 48)
    col.info:SetWordWrap(false)         -- eine Zeile: lange Namen duerfen die Rechnung darunter nicht ueberdecken
    -- die Wertung: links die Beschriftung, rechts gross die Zahl
    col.scoreCaption = UI.Text(card, 10, "faint")
    col.scoreCaption:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -80)
    col.scoreCaption:SetText(L.WIN_SCORE)
    col.score = UI.Text(card, 18, "accent")
    col.score:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -73)
    col.score:SetJustifyH("RIGHT")

    -- Spaltentitel ueber der Tabelle
    local headY = -(HEAD_H - 16)
    local function Head(text, offset, width, justify)
        local fs = UI.Text(card, 10, "faint")
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + offset, headY)
        fs:SetWidth(width)
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        fs:SetText(text)
        return fs
    end
    col.heads = {
        Head(L.COL_STAT, 0, LABEL_W, "LEFT"),
        Head(L.COL_VALUE, LABEL_W + GAP, VALUE_W, "RIGHT"),
        Head(L.COL_WEIGHT, LABEL_W + VALUE_W + 2 * GAP, WEIGHT_W, "RIGHT"),
        Head(L.COL_POINTS, LABEL_W + VALUE_W + WEIGHT_W + 3 * GAP, POINTS_W, "RIGHT"),
    }
    UI.Rule(card, "TOP", -(HEAD_H - 2))

    local y = -HEAD_H
    for i = 1, ROWS do
        local row = {}
        -- jede zweite Zeile dunkler; dahinter der Balken ihres Anteils an der Wertung
        if i % 2 == 0 then
            row.stripe = card:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetPoint("TOPLEFT", card, "TOPLEFT", 1, y)
            row.stripe:SetSize(CARD_W - 2, ROW_H)
            row.stripe:SetColorTexture(UI.Color("stripe"))
        end
        row.bar = card:CreateTexture(nil, "BORDER")
        row.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 1, y - 1)
        row.bar:SetSize(1, ROW_H - 2)
        row.bar:Hide()
        local function Cell(size, role, offset, width, justify)
            local fs = UI.Text(card, size, role)
            fs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + offset, y - 3)
            fs:SetWidth(width)
            fs:SetJustifyH(justify)
            fs:SetWordWrap(false)       -- eine Zeile: ein langer Name wird gekuerzt und ueberdeckt nicht die naechste Zeile
            return fs
        end
        row.label = Cell(12, "text", 0, LABEL_W, "LEFT")
        row.value = Cell(12, "text", LABEL_W + GAP, VALUE_W, "RIGHT")
        row.weight = Cell(11, "faint", LABEL_W + VALUE_W + 2 * GAP, WEIGHT_W, "RIGHT")
        row.points = Cell(12, "accent", LABEL_W + VALUE_W + WEIGHT_W + 3 * GAP, POINTS_W, "RIGHT")
        col.rows[i] = row
        y = y - ROW_H
    end
    return col
end

-- Der Wert einer Zeile. Was Verzauberung und Steine dazu beitragen, steht in Gruen dahinter: "1+1" (Basis + Verzauberung)
local function ValueText(data)
    local v = data.value or 0
    if data.key == "DPS" or data.key == "RDPS" then return sformat("%.1f", v) end
    local extra = data.extra
    if extra and extra > 0 and extra <= v then
        local own = v - extra
        return (own > 0 and EG.FmtScore(own) or "") .. EG.COLOR.good .. "+" .. EG.FmtScore(extra) .. EG.COLOR.reset
    end
    return EG.FmtScore(v)
end

local function FillRows(col, breakdown)
    local n = breakdown and #breakdown or 0
    -- der groesste Beitrag fuellt die ganze Zeile, die uebrigen im Verhaeltnis dazu
    local top = 0
    for i = 1, n do top = mmax(top, mabs(breakdown[i].points or 0)) end
    for i = 1, ROWS do
        local row, data = col.rows[i], breakdown and breakdown[i]
        local share = 0
        if data and i <= ROWS then
            row.label:SetText(data.label or "?")
            row.value:SetText(ValueText(data))
            row.weight:SetText("x" .. EG.FmtWeight(data.weight))
            row.points:SetText(EG.FmtScore(data.points or 0))
            if top > 0 then share = mabs(data.points or 0) / top end
        else
            row.label:SetText("") row.value:SetText("") row.weight:SetText("") row.points:SetText("")
        end
        row.share = share
        if share > 0 then
            row.bar:SetWidth(mmax(1, (CARD_W - 2) * share))
            row.bar:SetColorTexture(UI.Color("accent", 0.16))
            row.bar:Show()
        else
            row.bar:Hide()
        end
    end
    if n > ROWS then
        local row = col.rows[ROWS]
        row.label:SetText("...")
        row.value:SetText("") row.weight:SetText("") row.points:SetText("")
        row.share = 0
        row.bar:Hide()
    end
end

local function QualityColor(quality)
    local r, g, b = 1, 1, 1
    if C_Item and C_Item.GetItemQualityColor then
        local ok, rr, gg, bb = pcall(C_Item.GetItemQualityColor, quality or 1)
        if ok and rr then r, g, b = rr, gg, bb end
    end
    return r, g, b
end
Window.QualityColor = QualityColor

local function ShowItem(col, item, extraInfo)
    local btn = col.button
    col.name:SetWordWrap(item == nil)   -- ein Gegenstandsname bleibt einzeilig, die Hinweise darunter duerfen umbrechen
    if item then
        local r, g, b = QualityColor(item.quality)
        btn:SetItem(item.texture, r, g, b)
        col.name:SetText(item.name or "?")
        col.name:SetTextColor(r, g, b)
        col.info:SetText(extraInfo or "")
    else
        btn:SetItem(nil)
        col.name:SetText(L.NOTHING_EQUIPPED)
        UI.Paint(col.name, "dim")
        col.info:SetText(extraInfo or "")
    end
    btn.link = item and item.link or nil
end

------------------------------------------------------------------------------
-- 02  Inhalt
------------------------------------------------------------------------------

-- Stufe, Platz und Art eines Gegenstands als eine Zeile; skip = ein Name, der schon davor steht und nicht noch einmal
-- erscheinen soll ("Brust - Gegenstandsstufe 10 - Brust - Leder")
local function ItemInfo(item, skip)
    local parts = { L.ILVL .. " " .. tostring(item.ilvl or 0) }
    if item.slotText and item.slotText ~= "" and item.slotText ~= skip then parts[#parts + 1] = item.slotText end
    if item.typeText and item.typeText ~= "" then parts[#parts + 1] = item.typeText end
    return table.concat(parts, " - ")
end

function Window.Refresh()
    if not frame or not frame:IsShown() then return end

    UI.Refresh(frame)
    frame.profileText:SetText(L.PROFILE .. ": " .. Profiles.Resolve().name)

    local item, why
    if state.link then item, why = Items.Get(state.link) end
    local result, resultWhy
    if item then result, resultWhy = Score.Compare(item, true) end

    -- Kein Gegenstand, oder Daten (auch die des angelegten Gegenstuecks) fehlen noch
    if not (item and result) then
        ShowItem(frame.cand, nil)
        local hint = L.DROP_HINT
        if state.link then
            hint = (why == "invalid" or resultWhy == "invalid") and L.INVALID_ITEM or L.ITEM_LOADING
        end
        frame.cand.name:SetText(hint)             -- gedaempft, wie es ShowItem fuer ein leeres Feld setzt
        frame.cand.score:SetText("")
        FillRows(frame.cand, nil)
        ShowItem(frame.eq, nil)
        frame.eq.name:SetText("")
        frame.eq.score:SetText("")
        FillRows(frame.eq, nil)
        frame.verdict:SetText("")
        frame.notes:SetText("")
        frame.verdictBar:SetColorTexture(UI.Color("line"))
        frame.tab1:Hide() frame.tab2:Hide()
        return
    end

    ShowItem(frame.cand, item, ItemInfo(item))
    frame.cand.score:SetText(EG.FmtScore(result.score or 0))
    FillRows(frame.cand, result.breakdown)

    -- Rechte Seite: der angelegte Gegenstand des gewaehlten Platzes
    local entries = result.equipped or {}
    if #entries > 1 and not result.combined then
        frame.tab1:Show() frame.tab2:Show()
        frame.tab1:SetText(Score.SlotName(entries[1].slotID))
        frame.tab2:SetText(Score.SlotName(entries[2].slotID))
        if state.pick > #entries then state.pick = 1 end
        frame.tab1:SetSelected(state.pick == 1)
        frame.tab2:SetSelected(state.pick == 2)
    else
        frame.tab1:Hide() frame.tab2:Hide()
        state.pick = 1
    end
    local entry = entries[state.pick]

    if entry and entry.item then
        local slotName = Score.SlotName(entry.slotID)
        ShowItem(frame.eq, entry.item, slotName .. " - " .. ItemInfo(entry.item, slotName))
        frame.eq.score:SetText(EG.FmtScore(result.combined and result.targetScore or entry.score or 0))
        FillRows(frame.eq, entry.breakdown)
    elseif entry then
        ShowItem(frame.eq, nil, Score.SlotName(entry.slotID))
        frame.eq.score:SetText("0")
        FillRows(frame.eq, nil)
    else
        ShowItem(frame.eq, nil)
        frame.eq.score:SetText("")
        FillRows(frame.eq, nil)
    end

    -- Urteil: der Text und der Streifen links davon tragen dieselbe Farbe
    local text, role
    if result.noCompare then
        text, role = L.R_NOCOMPARE, "dim"
    elseif not result.usable then
        text, role = L.NOT_USABLE .. " - " .. (result.reason or ""), "bad"
    elseif result.levelTooLow and result.wouldUpgrade then
        text, role = sformat(L.UPGRADE_AT_LEVEL, item.reqLevel or 0), "warn"
    elseif result.isUpgrade then
        text, role = L.UPGRADE, "good"
    else
        text, role = L.NO_UPGRADE, "bad"
    end
    if not result.noCompare and result.usable and result.delta then
        text = text .. "   " .. EG.FmtSigned(result.delta)
        if result.percent then text = text .. "  (" .. EG.FmtPct(result.percent) .. ")" end
    end
    frame.verdict:SetText(text)
    UI.Paint(frame.verdict, role)
    frame.verdict.role = role
    frame.verdictBar:SetColorTexture(UI.Color(role))

    local notes = {}
    if result.reason and result.usable and not result.noCompare then notes[#notes + 1] = result.reason end
    for _, n in ipairs(result.notes or {}) do notes[#notes + 1] = n end
    frame.notes:SetText(table.concat(notes, "\n"))
end

-- Gegenstandsnummer oder Gegenstandslink? (Umschalt-Klick liefert auch Zauber-, Quest- und andere Links)
function Window.IsItemRef(v)
    if type(v) == "number" then return v > 0 end
    return type(v) == "string" and string.find(v, "item:", 1, true) ~= nil
end

function Window.SetItem(link)
    if not Window.IsItemRef(link) then return false end
    state.link, state.pick = link, 1
    Window.Open()
    Window.Refresh()
    return true
end

function Window.Clear()
    state.link, state.pick = nil, 1
    Window.Refresh()
end

function Window.Link() return state.link end

------------------------------------------------------------------------------
-- 03  Aufbau
------------------------------------------------------------------------------

local function SavePosition()
    if not (frame and EG.cdb) then return end
    local point, _, _, x, y = frame:GetPoint(1)
    EG.cdb.gui = EG.cdb.gui or {}
    EG.cdb.gui.point, EG.cdb.gui.x, EG.cdb.gui.y = point, x, y
end

local function ReceiveCursorItem()
    if not GetCursorInfo then return end
    local kind, id, link = GetCursorInfo()
    if kind == "item" then
        if ClearCursor then ClearCursor() end
        Window.SetItem(link or id)
    end
end

local function Build()
    if frame then return frame end

    frame = UI.Window("EasyGearWindow", WIDTH, HEIGHT, "EasyGear")
    frame.subtitle:SetText(L.WIN_SUB)
    frame:SetScript("OnDragStart", EG:Guard("window", function(self) self:StartMoving() end))
    frame:SetScript("OnDragStop", EG:Guard("window", function(self) self:StopMovingOrSizing() SavePosition() end))

    local gui = EG.cdb and EG.cdb.gui or {}
    frame:SetPoint(gui.point or "CENTER", UIParent, gui.point or "CENTER", gui.x or 0, gui.y or 0)
    frame:SetScale(gui.scale or 1)

    local body = frame.body
    frame.holder = body

    -- im Kopf rechts: das Profil, nach dem gerechnet wird
    frame.profileText = UI.Text(frame, 12, "dim")
    frame.profileText:SetPoint("RIGHT", frame.close, "LEFT", -12, 0)
    frame.profileText:SetJustifyH("RIGHT")

    frame.cand = BuildColumn(body, 0, L.WIN_NEW)
    frame.eq = BuildColumn(body, CARD_W + UI.PAD, L.WIN_WORN)
    frame.cand.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.cand.button:SetScript("OnReceiveDrag", EG:Guard("window", ReceiveCursorItem))
    frame.cand.button:SetScript("OnClick", EG:Guard("window", function(_, button)
        if button == "RightButton" then Window.Clear() else ReceiveCursorItem() end
    end))
    frame.cand.name:SetText(L.DROP_HINT)

    for _, col in ipairs({ frame.cand, frame.eq }) do
        local b = col.button
        b:SetScript("OnEnter", EG:Guard("window", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end))
        b:SetScript("OnLeave", EG:Guard("window", function() GameTooltip:Hide() end))
    end

    -- Reiter fuer die beiden Plaetze (Ringe, Schmuck, Einhandwaffen): oben rechts in der Karte des Angelegten
    local eqCard = frame.eq.card
    frame.tab2 = UI.Tab(eqCard, "", EG:Guard("window", function() state.pick = 2 Window.Refresh() end))
    frame.tab2:SetPoint("TOPRIGHT", eqCard, "TOPRIGHT", -CARD_PAD, -2)
    frame.tab1 = UI.Tab(eqCard, "", EG:Guard("window", function() state.pick = 1 Window.Refresh() end))
    frame.tab1:SetPoint("TOPRIGHT", frame.tab2, "TOPLEFT", -4, 0)
    frame.tab1:Hide() frame.tab2:Hide()

    -- Urteil: ein Streifen unter den Karten, links ein Balken in der Farbe des Urteils
    local box = CreateFrame("Frame", nil, body)
    box:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    box:SetHeight(86)
    UI.Box(box, "card", "border")
    frame.verdictBox = box
    frame.verdictBar = box:CreateTexture(nil, "ARTWORK")
    frame.verdictBar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    frame.verdictBar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    frame.verdictBar:SetWidth(3)
    frame.verdictBar:SetColorTexture(UI.Color("line"))
    frame.verdictCaption = UI.Text(box, 10, "faint")
    frame.verdictCaption:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -9)
    frame.verdictCaption:SetText(L.WIN_VERDICT)
    frame.verdict = UI.Text(box, 16, "text")
    frame.verdict:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -24)
    frame.verdict:SetWidth(WIDTH - 2 * UI.PAD - 28)
    frame.verdict:SetWordWrap(false)
    frame.notes = UI.Text(box, 11, "dim")
    frame.notes:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -46)
    frame.notes:SetWidth(WIDTH - 2 * UI.PAD - 28)
    frame.notes:SetJustifyV("TOP")

    -- Schaltflaechen im Fuss
    frame.btnClear = UI.FooterButton(frame, L.BTN_CLEAR, 120, EG:Guard("window", function() Window.Clear() end))
    frame.btnChat = UI.FooterButton(frame, L.BTN_CHAT, 150, EG:Guard("window", function()
        if state.link and EG.Slash then EG.Slash.PrintReport(state.link) end
    end))
    frame.btnProfiles = UI.FooterButton(frame, L.BTN_PROFILES, 120, EG:Guard("window", function()
        if EG.ProfileWindow then EG.ProfileWindow.Toggle() end
    end))

    frame:SetScript("OnShow", EG:Guard("window", function() Window.Refresh() end))
    return frame
end

function Window.Open()
    Build()
    if not frame:IsShown() then frame:Show() end
end

function Window.Toggle()
    Build()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function Window.IsShown() return frame ~= nil and frame:IsShown() end

------------------------------------------------------------------------------
-- 04  Anbindung
------------------------------------------------------------------------------

-- Umschalt + Klick auf einen Gegenstand holt ihn in das offene Fenster
EG:OnLoad("window", function()
    if hooksecurefunc and type(_G.HandleModifiedItemClick) == "function" then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if frame and frame:IsShown() and IsShiftKeyDown and IsShiftKeyDown() and Window.IsItemRef(link) then
                EG:Try("window", Window.SetItem, link)
            end
        end)
        EG:HookResult("shiftclick", true)
    else
        EG:HookResult("shiftclick", false, "HandleModifiedItemClick fehlt")
    end
end)

EG:Listen("INVALIDATED", function() Window.Refresh() end)
EG:Listen("REFRESH", function() Window.Refresh() end)

EG:Listen("GUI_SCALE", function()
    if frame then frame:SetScale((EG.cdb and EG.cdb.gui and EG.cdb.gui.scale) or 1) end
end)

EG:Listen("GUI_RESET", function()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(1)
end)
