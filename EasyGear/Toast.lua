--[[---------------------------------------------------------------------------
    Toast.lua - Einblendung "besseres Item"

    Kommt ein Gegenstand neu in die Taschen (gepluendert, gewuerfelt, gekauft, als Questbelohnung, aus der Post,
    im Handel) und ist er besser als das Angelegte, erscheint fuer 15 Sekunden eine Karte in Form eines Items:

        | [Symbol mit Markierung]  BESSERES ITEM
        |                          Name des Gegenstands (in der Farbe seiner Qualitaet)
        |                          +37  (+83.1%)   Brust: Alte Brustplatte
        ============------         (eine Linie laeuft ab)

    Die Karte nimmt Farbe und Form der Markierung "Verbesserung" (Optionen). Unter der Maus bleibt sie stehen
    und zeigt den Tooltip; Klick oeffnet den Vergleich, Rechtsklick schliesst sie, Ziehen verschiebt den Platz
    aller Einblendungen. Hoechstens drei stehen zugleich, weitere warten.

    Was als "neu" gilt: die Zahl der Faecher, die einen Gegenstand halten, ist seit dem letzten Blick in die
    Taschen gestiegen (BAG_UPDATE_DELAYED). Nicht neu ist, was beim Anmelden schon da war, was gerade abgelegt
    wurde (es war angelegt), was nur seinen Link wechselt (verzaubert) und was aus der offenen Bank kommt.
    EasyGear legt nichts an: die Einblendung weist nur hin.

    Die Karten liegen in der Ebene der eigenen Fenster (HIGH), dort weit oben: ueber den Fenstern, aber unter
    den Rueckfragen des Spiels (DIALOG) - eine Einblendung verdeckt nie einen Knopf einer Rueckfrage.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Toast = {}
EG.Toast = Toast

local L = EG.L
local Items, Score, Recommend, Marks, UI = EG.Items, EG.Score, EG.Recommend, EG.Marks, EG.UI

local ipairs, pairs, tonumber = ipairs, pairs, tonumber
local tremove, tconcat = table.remove, table.concat
local mmax, mmin = math.max, math.min

local WIDTH, HEIGHT, GAP = 320, 64, 6
local LEVEL = 200                   -- Rahmenebene der Karten in "HIGH": ueber Fenstern, die niemand nach vorn geholt hat
local MAX_SHOWN = 3                 -- so viele stehen zugleich
local MAX_QUEUE = 8                 -- so viele warten hoechstens; aeltere fallen weg
local FADE_IN, FADE_OUT = 0.25, 0.5 -- Sekunden Ein- und Ausblenden (Teil der Standzeit)
local QUIET = 5                     -- Sekunden nach Anmelden / Ladebildschirm: die Taschen fuellen sich noch
local REPEAT = 60                   -- derselbe Gegenstand nicht noch einmal innerhalb dieser Zeit
local PENDING = 15                  -- so lange wird auf fehlende Gegenstandsdaten gewartet
local DEFAULT_POS = { point = "TOP", x = 0, y = -170 }

local function Now() return GetTime and GetTime() or 0 end

------------------------------------------------------------------------------
-- 01  Einstellungen
------------------------------------------------------------------------------

function Toast.Enabled()
    return EG:Get("showToast") ~= false
end

-- Standzeit in Sekunden (Einstellung toastSeconds, im Bereich von EG.RANGES)
function Toast.Seconds()
    local range = EG.RANGES.toastSeconds
    local v = tonumber(EG:Get("toastSeconds")) or EG.DEFAULTS.toastSeconds
    return mmax(range[1], mmin(range[2], v))
end

------------------------------------------------------------------------------
-- 02  Karten
------------------------------------------------------------------------------

local anchor
local pool, shown, queue = {}, {}, {}
Toast.shown, Toast.queue = shown, queue

-- Nach dem Verschieben haelt das Spiel den Rahmen an einem Punkt des Bildschirms fest: Punkt, Bezugspunkt, Abstand
local function SavePosition()
    if not (anchor and EG.cdb) then return end
    local point, _, rel, x, y = anchor:GetPoint(1)
    EG.cdb.toast = { point = point, rel = rel, x = x, y = y }
end

local function Place()
    local pos = EG.cdb and EG.cdb.toast or DEFAULT_POS
    local point = pos.point or DEFAULT_POS.point
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, pos.rel or point, pos.x or 0, pos.y or 0)
end

-- Das Ziehen beenden und den Platz merken. Verschwindet eine Karte, waehrend sie gezogen wird, meldet das Spiel
-- kein OnDragStop mehr: darum auch beim Schliessen.
local function StopDrag(f)
    if not f.dragging then return end
    f.dragging = false
    anchor:StopMovingOrSizing()
    SavePosition()
end

-- Der Platz der Einblendungen: ein unsichtbarer Rahmen, an dem die Karten haengen und der sich verschieben laesst
local function Anchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "EasyGearToastAnchor", UIParent)
    anchor:SetSize(WIDTH, HEIGHT)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    Place()
    return anchor
end

local function Layout()
    for i, f in ipairs(shown) do
        f:ClearAllPoints()
        f:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (HEIGHT + GAP))
    end
end

local Display

local function Release(f)
    StopDrag(f)
    for i = #shown, 1, -1 do
        if shown[i] == f then tremove(shown, i) end
    end
    f:Hide()
    f.data, f.hover = nil, false
    pool[#pool + 1] = f
    if queue[1] and #shown < MAX_SHOWN then Display(tremove(queue, 1)) end
    Layout()
end

-- Standzeit: einblenden, stehen, ausblenden; die Linie unten laeuft ab. Unter der Maus und beim Ziehen steht die Zeit.
local function OnUpdate(self, elapsed)
    if not (self.hover or self.dragging) then self.age = self.age + elapsed end
    local total = self.seconds
    if self.age >= total then
        Release(self)
        return
    end
    local alpha = 1
    if self.age < FADE_IN then
        alpha = self.age / FADE_IN
    elseif self.age > total - FADE_OUT then
        alpha = (total - self.age) / FADE_OUT
    end
    if self.hover or self.dragging then alpha = 1 end
    self:SetAlpha(alpha)
    self.timer:SetWidth(mmax(1, (WIDTH - 2) * (1 - self.age / total)))
end

local function OnEnter(self)
    self.hover = true
    self:SetAlpha(1)
    local link = self.data and self.data.link
    if link and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(L.TOAST_HINT, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end
end

local function OnLeave(self)
    self.hover = false
    if GameTooltip then GameTooltip:Hide() end
end

local function OnClick(self, button)
    local link = self.data and self.data.link
    if button == "RightButton" then
        Release(self)
    elseif link and EG.Window then
        EG.Window.SetItem(link)
    end
end

local function NewFrame()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(LEVEL)
    UI.Box(f, "bg", "border")

    f.bar = f:CreateTexture(nil, "ARTWORK")              -- links: ein Balken in der Farbe der Markierung
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.bar:SetWidth(3)

    f.icon = UI.Icon(f, 44, "Frame")
    f.icon:SetPoint("LEFT", f, "LEFT", 12, 1)
    f.mark = f.icon:CreateTexture(nil, "OVERLAY")
    f.mark:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -4, 4)

    local left = 12 + 44 + 10
    f.caption = UI.Text(f, 10, "good")
    f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", left, -9)
    f.name = UI.Text(f, 14, "text")
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", left, -23)
    f.name:SetWidth(WIDTH - left - 10)
    f.name:SetWordWrap(false)
    f.detail = UI.Text(f, 11, "dim")
    f.detail:SetPoint("TOPLEFT", f, "TOPLEFT", left, -43)
    f.detail:SetWidth(WIDTH - left - 10)
    f.detail:SetWordWrap(false)

    f.timer = f:CreateTexture(nil, "ARTWORK")            -- unten: die Linie, die ablaeuft
    f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    f.timer:SetSize(WIDTH - 2, 2)

    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnUpdate", EG:Guard("toast", OnUpdate))
    f:SetScript("OnEnter", EG:Guard("toast", OnEnter))
    f:SetScript("OnLeave", EG:Guard("toast", OnLeave))
    f:SetScript("OnClick", EG:Guard("toast", OnClick))
    f:SetScript("OnDragStart", EG:Guard("toast", function(self)
        self.dragging = true
        anchor:StartMoving()
    end))
    f:SetScript("OnDragStop", EG:Guard("toast", StopDrag))
    f:Hide()
    return f
end

-- data: { link, name, texture, quality, caption, detail }
Display = function(data)
    Anchor()
    local f = tremove(pool) or NewFrame()
    f.data = data
    f.age, f.seconds, f.hover = 0, Toast.Seconds(), false

    -- Farbe und Form der Markierung "Verbesserung", wie in den Optionen gewaehlt
    local r, g, b = Marks.Tint("UPGRADE")
    Marks.Style(f.mark, "UPGRADE", 20)
    f.bar:SetColorTexture(r, g, b, 1)
    f.timer:SetColorTexture(r, g, b, 0.9)
    f.caption:SetTextColor(r, g, b, 1)
    f.caption:SetText(data.caption or L.TOAST_TITLE)

    local qr, qg, qb = EG.Window.QualityColor(data.quality)
    f.icon:SetItem(data.texture, qr, qg, qb)
    f.name:SetText(data.name or "?")
    f.name:SetTextColor(qr, qg, qb)
    f.detail:SetText(data.detail or "")

    f:SetAlpha(0)
    f:Show()
    shown[#shown + 1] = f
    Layout()
    return f
end

local function Push(data)
    if #shown < MAX_SHOWN then return Display(data) end
    queue[#queue + 1] = data
    while #queue > MAX_QUEUE do tremove(queue, 1) end
    return nil
end

-- Alle Einblendungen schliessen (abgeschaltet, zurueckgesetzt)
function Toast.Clear()
    for i = #queue, 1, -1 do queue[i] = nil end
    while shown[1] do Release(shown[1]) end
end

------------------------------------------------------------------------------
-- 03  Inhalt
------------------------------------------------------------------------------

-- Zweite Zeile: der Zugewinn in Gruen, dahinter der Platz und was dort ersetzt wird
local function Detail(result)
    local C = EG.COLOR
    local gain = EG.FmtSigned(result.delta or 0)
    if result.percent then gain = gain .. "  (" .. EG.FmtPct(result.percent) .. ")" end
    local names = {}
    for _, r in ipairs(result.replaced or {}) do
        if r.item and r.item.name then names[#names + 1] = r.item.name end
    end
    local what = (#names > 0) and tconcat(names, " + ") or L.NOTHING_EQUIPPED
    -- der Platz, in den er kaeme (bei Ringen der bessere von beiden); bei einem Zweihaender beide Plaetze
    local slot = (not result.combined and result.candSlot) and Score.SlotName(result.candSlot) or (result.slotName or "")
    return C.good .. gain .. C.reset .. "   " .. slot .. ": " .. what
end

-- Die Einblendung fuer diesen Gegenstand zeigen (oder einreihen). Rueckgabe: wurde sie angenommen?
function Toast.Show(link)
    local item = Items.Get(link)
    if not item then return false end
    local result = item.isGear and Score.Compare(item) or nil
    if not result then return false end
    Push({ link = item.link or link, name = item.name, texture = item.texture, quality = item.quality,
           detail = Detail(result) })
    return true
end

-- Ein Beispiel zum Ansehen und Verschieben (/eg toast test): die beste Verbesserung in den Taschen, sonst etwas Angelegtes
function Toast.Test()
    local list = Recommend.Upgrades(false)
    if list[1] and Toast.Show(list[1].link) then return true end
    for slot = 1, 19 do
        local item = Items.Equipped(slot)
        if item then
            Push({ link = item.link, name = item.name, texture = item.texture, quality = item.quality,
                   caption = L.TOAST_SAMPLE, detail = L.TOAST_SAMPLE_TEXT })
            return true
        end
    end
    return false
end

function Toast.ResetPosition()
    if EG.cdb then EG.cdb.toast = nil end
    if anchor then Place() end
end

------------------------------------------------------------------------------
-- 04  Erkennen, was neu ist
------------------------------------------------------------------------------

local counts            -- Link -> Zahl der Faecher beim letzten Blick (nil: noch nie geschaut)
local ids = {}          -- Gegenstandsnummer -> Zahl der Faecher beim letzten Blick
local wornSeen = {}     -- Gegenstandsnummer -> wie oft seit dem letzten Blick hoechstens angelegt
local pending = {}      -- Link -> bis wann auf seine Daten gewartet wird
local lastShown = {}    -- Link -> wann zuletzt eingeblendet
local quietUntil = 0
local bankOpen = false

-- Gegenstandsnummer -> wie oft gerade angelegt (zwei gleiche Ringe: 2)
local function Worn()
    local out = {}
    for slot = 1, 19 do
        local link = Items.EquippedLink(slot)
        if link then
            local id = Items.IDFromLink(link) or link
            out[id] = (out[id] or 0) + 1
        end
    end
    return out
end

--[[ Merken, was angelegt ist oder war. Gezaehlt wird nach Gegenstandsnummer, nicht nach Link: der Link eines
     angelegten Gegenstands aendert sich mit der Stufe des Charakters und beim Verzaubern, die Nummer nicht.
     Zwischen zwei Blicken in die Taschen zaehlt der hoechste Stand - was davon nicht mehr angelegt ist und in
     den Taschen auftaucht, wurde abgelegt. Rueckgabe: der Stand von eben.                                      ]]
local function NoteWorn()
    local now = Worn()
    for id, n in pairs(now) do
        if n > (wornSeen[id] or 0) then wornSeen[id] = n end
    end
    return now
end

local function ByID(byLink)
    local out = {}
    for link, n in pairs(byLink) do
        local id = Items.IDFromLink(link) or link
        out[id] = (out[id] or 0) + n
    end
    return out
end

-- Ein neuer Gegenstand: ist er eine Verbesserung, wird er eingeblendet; fehlen seine Daten, kommt er spaeter wieder dran
local function Consider(link)
    local state, loading = Score.UpgradeState(link)
    if loading then
        pending[link] = pending[link] or (Now() + PENDING)
        return
    end
    pending[link] = nil
    if state ~= "UPGRADE" then return end
    local now = Now()
    if lastShown[link] and now - lastShown[link] < REPEAT then return end
    if Toast.Show(link) then lastShown[link] = now end
end

local function OnBags()
    local now = Recommend.BagGear()
    local before, idsBefore, seen = counts, ids, wornSeen
    local worn = NoteWorn()             -- hebt seen auf den Stand von jetzt: seen[id] >= worn[id]
    counts, ids, wornSeen = now, ByID(now), worn
    if not before or not Toast.Enabled() or bankOpen or Now() < quietUntil then return end
    for link, n in pairs(now) do
        local id = Items.IDFromLink(link) or link
        -- neu in den Taschen, abzueglich dessen, was nur abgelegt wurde (ein zweites Stueck eines angelegten Rings zaehlt)
        local gained = (ids[id] or 0) - (idsBefore[id] or 0) - ((seen[id] or 0) - (worn[id] or 0))
        if n > (before[link] or 0) and gained > 0 then Consider(link) end
    end
end

EG:On("BAG_UPDATE_DELAYED", OnBags)
-- auch was angelegt wird, ohne durch die Taschen zu gehen (aus der Bank, vom Haendler), gilt spaeter als abgelegt
EG:On("PLAYER_EQUIPMENT_CHANGED", NoteWorn)
EG:On("PLAYER_ENTERING_WORLD", function() quietUntil = Now() + QUIET end)
EG:On("BANKFRAME_OPENED", function() bankOpen = true end)
EG:On("BANKFRAME_CLOSED", function() bankOpen = false end)

EG:Listen("ITEMS_LOADED", function()
    local now = Now()
    local due = {}
    for link, untilTime in pairs(pending) do
        if now > untilTime then pending[link] = nil else due[#due + 1] = link end
    end
    for _, link in ipairs(due) do Consider(link) end
end)

-- abgeschaltet: was steht, verschwindet
EG:Listen("INVALIDATED", function()
    if not Toast.Enabled() and (shown[1] or queue[1]) then Toast.Clear() end
end)

EG:Listen("GUI_RESET", Toast.ResetPosition)
