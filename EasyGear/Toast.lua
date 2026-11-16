--[[---------------------------------------------------------------------------
    Toast.lua - Einblendung "besseres Item"

    Kommt ein Gegenstand neu in die Taschen (gepluendert, gewuerfelt, gekauft, als Questbelohnung, aus der Post,
    im Handel) und ist er besser als das Angelegte, erscheint fuer 15 Sekunden eine Karte in Form eines Items:

        | [Symbol mit Markierung]  BESSERES ITEM
        |                          Name des Gegenstands (in der Farbe seiner Qualitaet)
        |                          +37  (+83.1%)   Brust: Alte Brustplatte
        ============------         (eine Linie laeuft ab)

    Die Karte nimmt Farbe und Form der Markierung "Verbesserung" (Optionen). Unter der Maus bleibt sie stehen
    und zeigt den Tooltip; Klick oeffnet den Vergleich, Rechtsklick legt den Gegenstand an, Umschalt + Rechtsklick
    schliesst sie, Ziehen verschiebt den Platz aller Einblendungen. Hoechstens drei stehen zugleich, weitere warten.

    Anlegen: nur auf diesen Rechtsklick hin, und nur wenn es gerade geht (nicht im Kampf, nicht tot, kein Zauber
    wartet auf ein Ziel, der Gegenstand liegt noch in den Taschen und ist noch eine Verbesserung). Sonst sagt der
    Chat, warum nicht. Eine Karte, deren Gegenstand keine Verbesserung in den Taschen mehr ist - er wurde angelegt,
    hier oder in den Taschen, verkauft, oder etwas Besseres wird getragen -, verschwindet; die uebrigen zeigen
    stets den Platz, in den ein Rechtsklick jetzt fuehrt. Ein Gegenstand wird an seinem Schluessel wiedererkannt
    (Items.Key), nicht am Link: der aendert sich mit der Stufe des Charakters.

    Was als "neu" gilt: die Zahl der Faecher, die einen Gegenstand halten, ist seit dem letzten Blick in die
    Taschen gestiegen (BAG_UPDATE_DELAYED). Nicht neu ist, was beim Anmelden schon da war, was gerade abgelegt
    wurde (es war angelegt), was nur seinen Link wechselt (verzaubert) und was aus der offenen Bank kommt.

    Die Karten liegen in der Ebene der eigenen Fenster (HIGH) und werden beim Erscheinen nach vorn geholt: ueber
    die Fenster, auch ueber eines, das gerade angeklickt wurde - aber unter die Rueckfragen des Spiels (DIALOG).
    Eine Einblendung verdeckt nie einen Knopf einer Rueckfrage.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Toast = {}
EG.Toast = Toast

local L = EG.L
local Items, Score, Recommend, Marks, UI = EG.Items, EG.Score, EG.Recommend, EG.Marks, EG.UI

local ipairs, pairs, tonumber = ipairs, pairs, tonumber
local tremove, tconcat = table.remove, table.concat
local sformat = string.format
local mmax, mmin = math.max, math.min

local WIDTH, HEIGHT, GAP = 320, 64, 6
local MAX_SHOWN = 3                 -- so viele stehen zugleich
local MAX_QUEUE = 8                 -- so viele warten hoechstens; aeltere fallen weg
local FADE_IN, FADE_OUT = 0.25, 0.5 -- Sekunden Ein- und Ausblenden (Teil der Standzeit)
local QUIET = 5                     -- Sekunden nach Anmelden / Ladebildschirm: die Taschen fuellen sich noch
local REPEAT = 60                   -- derselbe Gegenstand nicht noch einmal innerhalb dieser Zeit
local PENDING = 15                  -- so lange wird auf fehlende Gegenstandsdaten gewartet
local EQUIP_GAP = 1                 -- Sekunden nach einem Anlegen, in denen Rechtsklicks nichts tun: ein Doppelklick
                                    -- traefe sonst die Karte, die inzwischen an die Stelle der ersten gerueckt ist
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
        GameTooltip:AddLine(self.data.sample and L.TOAST_HINT_SAMPLE or L.TOAST_HINT, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end
end

local function OnLeave(self)
    self.hover = false
    if GameTooltip then GameTooltip:Hide() end
end

--[[ Den Gegenstand anlegen - nur auf den Rechtsklick auf seine Karte hin, und nur wenn es gerade geht. Der Weg ist
     der des Ausruestungsmanagers des Spiels (EquipmentManager_EquipContainerItem): Mauszeiger leeren, den Gegenstand
     aus seinem Fach aufnehmen, pruefen, ob er in den Platz darf, auf den Platz legen. Was dort lag, legt das Spiel
     in das frei gewordene Fach; lehnt der Server ab, sagt es das Spiel.
     Bindet der Gegenstand beim Anlegen, fragt das Spiel nach und haelt ihn so lange am Mauszeiger (den zu leeren,
     braeche die Rueckfrage ab): seine Ereignisse EQUIP_BIND_*_CONFIRM kommen noch waehrend des Aufrufs.
     Rueckgabe: true - oder false, der Grund als Text, und ob die Karte damit hinfaellig ist.                     ]]
local bindAsked = false

function Toast.Equip(link)
    if InCombatLockdown() then return false, sformat(L.TOAST_EQUIP_COMBAT, link), false end
    if UnitIsDeadOrGhost("player") then return false, sformat(L.TOAST_EQUIP_DEAD, link), false end
    -- ein Zauber wartet auf sein Ziel (verzaubern, entzaubern), oder der Reparaturhammer ist gewaehlt: der Griff
    -- nach dem Gegenstand gaelte ihm
    if SpellIsTargeting() or InRepairMode() then return false, sformat(L.TOAST_EQUIP_FAILED, link), false end
    local bag, slot, current = Recommend.Find(link)
    if not bag then return false, sformat(L.TOAST_EQUIP_GONE, link), true end
    -- der Platz, in den er kaeme - nach dem Stand von jetzt
    local result = Score.Compare(current)
    if not (result and result.isUpgrade and result.candSlot) then return false, sformat(L.TOAST_EQUIP_STALE, link), true end
    local target = result.candSlot
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    -- nicht aufgenommen (gesperrt: er wird gerade bewegt), er darf nicht in den Platz, oder der Platz ist gesperrt
    if not CursorHasItem() or not C_PaperDollInfo.CursorCanGoInSlot(target) or IsInventoryItemLocked(target) then
        ClearCursor()                   -- zurueck in sein Fach
        return false, sformat(L.TOAST_EQUIP_FAILED, link), false
    end
    bindAsked = false
    PickupInventoryItem(target)
    -- Noch in der Hand, ohne dass das Spiel nach dem Binden fragt: es hat ihn nicht genommen - zurueck in sein Fach
    if CursorHasItem() and not bindAsked then
        ClearCursor()
        return false, sformat(L.TOAST_EQUIP_FAILED, link), false
    end
    return true
end

local function BindAsked() bindAsked = true end
EG:On("EQUIP_BIND_CONFIRM", BindAsked)
EG:On("EQUIP_BIND_TRADEABLE_CONFIRM", BindAsked)
EG:On("EQUIP_BIND_REFUNDABLE_CONFIRM", BindAsked)

local lastEquip = -EQUIP_GAP

local function OnClick(self, button)
    local data = self.data
    local link = data and data.link
    if button ~= "RightButton" then
        if link and EG.Window then EG.Window.SetItem(link) end
        return
    end
    -- Umschalt + Rechtsklick schliesst; ein Beispiel (/eg toast test) laesst sich nur schliessen
    if IsShiftKeyDown() or not link or data.sample then
        Release(self)
        return
    end
    if Now() - lastEquip < EQUIP_GAP then return end     -- der Klick davor ist noch unterwegs
    local ok, why, pointless = Toast.Equip(link)
    if ok then lastEquip = Now() else EG:Print(why) end
    -- angelegt verschwindet die Karte von selbst (Recheck): ihr Gegenstand liegt dann nicht mehr in den Taschen
    if pointless then Release(self) end
end

local function NewFrame()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
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
    f:Raise()               -- vor alles in ihrer Ebene, auch vor ein Fenster, das ein Klick nach vorn geholt hat
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

-- Die Einblendung fuer diesen Gegenstand zeigen (oder einreihen); sample: nur als Beispiel (/eg toast test).
-- Rueckgabe: wurde sie angenommen?
function Toast.Show(link, sample)
    local item = Items.Get(link)
    if not item then return false end
    local result = item.isGear and Score.Compare(item) or nil
    if not result then return false end
    -- der Link, wie er in den Taschen liegt (nicht der bereinigte der Gegenstandsdaten), und sein Schluessel: daran
    -- wird das Stueck wiedergefunden, auch wenn sein Link sich mit der Stufe des Charakters aendert
    Push({ link = link, key = Items.Key(link), name = item.name, texture = item.texture, quality = item.quality,
           detail = Detail(result), sample = sample })
    return true
end

-- Ein Beispiel zum Ansehen und Verschieben (/eg toast test): die beste Verbesserung in den Taschen, sonst etwas Angelegtes
function Toast.Test()
    local list = Recommend.Upgrades(false)
    if list[1] and Toast.Show(list[1].link, true) then return true end
    for slot = 1, 19 do
        local item = Items.Equipped(slot)
        if item then
            Push({ link = item.link, name = item.name, texture = item.texture, quality = item.quality,
                   caption = L.TOAST_SAMPLE, detail = L.TOAST_SAMPLE_TEXT, sample = true })
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
local byKey = {}        -- Schluessel (Items.Key) -> Link, wie er beim letzten Blick in den Taschen lag
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

--[[ Was steht und wartet, noch einmal pruefen: eine Karte, deren Gegenstand nicht mehr in den Taschen liegt (angelegt,
     verkauft, in die Bank gelegt) oder keine Verbesserung mehr ist (etwas Besseres wird getragen), verschwindet.
     Ein Beispiel bleibt; was noch laedt, auch. Der Link der Karte folgt dem in den Taschen.                       ]]
local function Stale(data)
    if data.sample then return false end
    local current = byKey[data.key]
    if not current then return true end
    data.link = current
    local state, loading = Score.UpgradeState(data.link)
    return not loading and state ~= "UPGRADE"
end

-- Was die Karte sagt, nach dem Stand von jetzt: der Platz, in den ein Rechtsklick fuehrt, und was dort ersetzt wird
local function Refresh(data)
    local result = not data.sample and Score.Compare(data.link) or nil
    if result then data.detail = Detail(result) end
end

local function Recheck()
    for i = #queue, 1, -1 do
        if Stale(queue[i]) then tremove(queue, i) else Refresh(queue[i]) end
    end
    for i = #shown, 1, -1 do
        local f = shown[i]
        if f and f.data then
            if Stale(f.data) then
                Release(f)
            else
                Refresh(f.data)
                f.detail:SetText(f.data.detail or "")
            end
        end
    end
end

local function OnBags()
    local now = Recommend.BagGear()
    local before, idsBefore, seen = counts, ids, wornSeen
    local worn = NoteWorn()             -- hebt seen auf den Stand von jetzt: seen[id] >= worn[id]
    counts, ids, wornSeen = now, ByID(now), worn
    byKey = {}
    for link in pairs(now) do byKey[Items.Key(link)] = link end
    if before and Toast.Enabled() and not bankOpen and Now() >= quietUntil then
        for link, n in pairs(now) do
            local id = Items.IDFromLink(link) or link
            -- neu in den Taschen, abzueglich dessen, was nur abgelegt wurde (ein zweites Stueck eines angelegten Rings zaehlt)
            local gained = (ids[id] or 0) - (idsBefore[id] or 0) - ((seen[id] or 0) - (worn[id] or 0))
            if n > (before[link] or 0) and gained > 0 then Consider(link) end
        end
    end
    Recheck()               -- was die Taschen verlassen hat, braucht keine Karte mehr
end

EG:On("BAG_UPDATE_DELAYED", OnBags)
EG:On("PLAYER_EQUIPMENT_CHANGED", function()
    -- auch was angelegt wird, ohne durch die Taschen zu gehen (aus der Bank, vom Haendler), gilt spaeter als abgelegt
    NoteWorn()
    Recheck()
end)
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

-- abgeschaltet: was steht, verschwindet; sonst gilt der neue Stand (Ausruestung, Profil, Einstellungen)
EG:Listen("INVALIDATED", function()
    if Toast.Enabled() then Recheck() else Toast.Clear() end
end)

EG:Listen("GUI_RESET", Toast.ResetPosition)
