--[[---------------------------------------------------------------------------
    Feed.lua - Anbindung an den Loot Feed von EllesmereUI (Forever Essentials)

    Der Loot Feed zeigt, was der Spieler gerade bekommt, als kurzlebige Zeilen: Symbol, Name, zweite Zeile
    (Gegenstandsstufe), rechts der Preis. EasyGear kennzeichnet darin, was besser ist als das Angelegte:

        [Markierung in der Ecke des Symbols]   die Zeile in der Farbe der Markierung getoent
        Name des Gegenstands                                                        Preis
        ilvl: 12   +83.1%          <- der Zugewinn, hinter der zweiten Zeile (ohne sie: hinter dem Namen)

    Verbesserung: Pfeil und Zugewinn; Verbesserung erst mit hoeherer Stufe: gelber Pfeil und die Stufe; besser fuer
    ein Gruppenmitglied: violetter Stern. Form und Farbe sind die der Optionen (Aussehen der Markierungen).
    Gekennzeichnet wird nur, was der Spieler selbst bekommt (Zeilen "item:..."), nicht was andere erwuerfeln.

    Der Loot Feed bietet anderen Addons keine Schnittstelle; seine Zeilen sind namenlose Rahmen. EasyGear findet sie
    ueber den Rahmen des Feeds - EllesmereUI fuehrt ihn im Entsperrmodus unter dem Schluessel "EUI_LootFeed"
    (EllesmereUI._unlockRegisteredElements) - und erkennt eine Zeile an ihrem Aufbau (icon, badge, name, sub, value).
    Jede Zeile wird einmal angenommen: von da an meldet ein Haken auf badge:SetText jede neue Belegung (der Feed
    setzt beim Fuellen diesen Text als letzten; Name, zweite Zeile und Preis stehen dann schon). Der Text steht
    hinter dem Text des Feeds, wenn er in dessen Platz passt - der reicht bis vor den Preis; passt er nicht, bleibt
    er weg (Markierung und Toenung bleiben). Markierung und Text liegen auf einer eigenen Schicht ueber der Zeile
    (ueber deren Rand), die Toenung in der Zeile selbst. Alles sind Kinder der Zeile und blendet mit ihr aus.

    Nach Zeilen gesucht wird, wenn etwas gepluendert wurde, wenn Daten eintreffen, kurz nachdem der Feed eine
    bekannte Zeile neu gefuellt hat (daneben kann eine neue entstanden sein) und, solange Umschalt gehalten wird,
    viermal je Sekunde: mit Umschalt und Mausrad blaettert der Feed in seinem Verlauf und baut dafuer Zeilen,
    ohne dass ein Ereignis davon erzaehlt.

    Gelesen aus EllesmereUIForeverEssentials_LootFeed.lua (9.8.6). Fehlt etwas davon, sagt /eg status es.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Feed = {}
EG.Feed = Feed

local L = EG.L
local Score, Marks = EG.Score, EG.Marks

local type, pcall, ipairs = type, pcall, ipairs
local sformat, ssub = string.format, string.sub
local mmax, mmin = math.max, math.min

local ELEMENT = "EUI_LootFeed"      -- Schluessel des Loot Feeds im Entsperrmodus von EllesmereUI
local TINT_ALPHA = 0.16             -- so stark toent die Farbe der Markierung die Zeile
local MARK_MIN, MARK_MAX = 12, 20   -- Groesse der Markierung auf dem Symbol (60 % des Symbols, in diesen Grenzen)
local GAP = 8                       -- Abstand des eigenen Textes zum Text des Feeds davor
local WATCH = 0.25                  -- Sekunden zwischen zwei Blicken auf den Feed, solange Umschalt gehalten wird
local LEVEL = 3                     -- so weit liegt die eigene Schicht ueber der Zeile (deren Rand liegt 1 darueber)

local rows = setmetatable({}, { __mode = "k" })     -- Zeile -> true: Zeilen, an denen EasyGear haengt
local adopted = 0

------------------------------------------------------------------------------
-- 01  Den Feed finden
------------------------------------------------------------------------------

-- Der Loot Feed gehoert zu den Markierungen bei Beute (Haendler, Beute, Wuerfeln, ...)
function Feed.Enabled()
    return Marks.Enabled("loot")
end

--[[ Der Rahmen des Feeds und, wenn es ihn nicht gibt, warum: "absent" (kein EllesmereUI oder kein Loot Feed darin),
     "off" (in EllesmereUI abgeschaltet: dann baut es keinen Rahmen).                                               ]]
local function Anchor()
    local eui = _G.EllesmereUI
    local registry = type(eui) == "table" and eui._unlockRegisteredElements or nil
    local element = type(registry) == "table" and registry[ELEMENT] or nil
    if type(element) ~= "table" or type(element.getFrame) ~= "function" then return nil, "absent" end
    local ok, frame = pcall(element.getFrame)
    if ok and type(frame) == "table" and type(frame.GetChildren) == "function" then return frame end
    return nil, "off"
end

-- Eine Zeile des Feeds, erkannt an ihrem Aufbau (NewRow in EllesmereUIForeverEssentials_LootFeed.lua)
local function IsRow(f)
    return type(f) == "table"
       and type(f.icon) == "table" and type(f.icon.SetTexture) == "function"
       and type(f.badge) == "table" and type(f.badge.SetText) == "function"
       and type(f.name) == "table" and type(f.sub) == "table" and type(f.value) == "table"
       and type(f.CreateTexture) == "function" and type(f.GetFrameLevel) == "function"
end

--[[ Der Gegenstand einer Zeile - nur wenn der Spieler ihn selbst bekommen hat. Der Feed nennt solche Zeilen
     "item:<Link>"; was andere erwuerfelt haben ("roll:..."), traegt auch einen Link, ist aber nicht zu haben.
     Im Verlauf (Umschalt + Mausrad) heissen die Zeilen "history:<n>", der urspruengliche Name steht im Eintrag. ]]
local function ItemLink(row)
    local data = row.data
    if type(data) ~= "table" or type(data.link) ~= "string" then return nil end
    local key = row.key
    if row.history then key = data.key end
    if type(key) ~= "string" or ssub(key, 1, 5) ~= "item:" then return nil end
    return data.link
end

------------------------------------------------------------------------------
-- 02  Eine Zeile kennzeichnen
------------------------------------------------------------------------------

local function Hide(row)
    if row.EasyGearMark then row.EasyGearMark:Hide() end
    if row.EasyGearTint then row.EasyGearTint:Hide() end
    if row.EasyGearText then row.EasyGearText:Hide() end
end

-- Der Text: der Zugewinn, die Stufe, oder dass es der Gruppe nuetzt
local function Label(state, link)
    if state == "GROUP" then return L.FEED_GROUP end
    local result = Score.Compare(link)
    if not result then return "" end
    if state == "LEVEL" then return sformat(L.FEED_LEVEL, (result.item and result.item.reqLevel) or 0) end
    if result.percent then return EG.FmtPct(result.percent) end
    return EG.FmtSigned(result.delta or 0)
end

-- Die Schrift der zweiten Zeile des Feeds uebernehmen (seine Schrift, seine Groesse)
local function MatchFont(fs, like)
    if type(like.GetFont) ~= "function" then return end
    local ok, file, size, flags = pcall(like.GetFont, like)
    if ok and type(file) == "string" and type(size) == "number" then pcall(fs.SetFont, fs, file, size, flags or "") end
end

local function Shown(region)
    return type(region.IsShown) ~= "function" or region:IsShown() and true or false
end

-- Ein Mass erfragen: GetHeight (Symbol und Zeile haben feste Groessen), GetWidth (der Platz eines Textes),
-- GetStringWidth (so breit steht er, hoechstens sein Platz), GetUnboundedStringWidth (so breit waere er ungekuerzt)
local function Measure(region, method)
    local v = type(region[method]) == "function" and region[method](region) or 0
    return type(v) == "number" and v or 0
end

--[[ Die eigene Schicht einer Zeile: ein Rahmen ueber der Zeile fuer Markierung und Text. Der Rand der Zeile ist
     ein Kindrahmen eine Ebene ueber ihr (PP.CreateBorder, r.lootBorder) - direkt in der Zeile laegen sie darunter. ]]
local function Layer(row)
    local layer = row.EasyGearLayer
    if not layer then
        layer = CreateFrame("Frame", nil, row)
        layer:SetAllPoints(row)
        row.EasyGearLayer = layer
    end
    layer:SetFrameLevel(row:GetFrameLevel() + LEVEL)
    return layer
end

--[[ Den Text setzen: hinter den Text der zweiten Zeile des Feeds, ohne sie hinter den Namen. Deren Platz reicht
     bis vor den Preis. Passt der eigene Text nicht mehr hinein (ein schmaler Feed, ein langer Name), bleibt er weg:
     so liegt er nie auf dem Preis. Rueckgabe: steht er?                                                         ]]
local function PlaceText(row, text)
    local line = Shown(row.sub) and row.sub or row.name
    local used = Measure(line, "GetStringWidth")
    text:ClearAllPoints()
    -- ohne Punkte ist der eigene Text so breit wie sein Inhalt
    local need = Measure(text, text.GetUnboundedStringWidth and "GetUnboundedStringWidth" or "GetStringWidth")
    if Measure(line, "GetWidth") - used - GAP < need then return false end
    if line == row.sub then
        text:SetPoint("TOPLEFT", line, "TOPLEFT", used + GAP, 0)
    else
        text:SetPoint("LEFT", line, "LEFT", used + GAP, 0)
    end
    return true
end

local function Paint(row)
    local link = ItemLink(row)
    local state, loading
    if link and Feed.Enabled() then
        state, loading = Score.UpgradeState(link)
        -- keine Verbesserung fuer dich: vielleicht fuer ein Gruppenmitglied (wie am Beutefenster)
        if state == nil and not loading and EG.Group then state = EG.Group.State(link, "loot") end
    end
    if not state then
        Hide(row)
        return
    end

    local layer = Layer(row)
    local icon = row.icon
    local mark = row.EasyGearMark
    if not mark then
        mark = layer:CreateTexture(nil, "OVERLAY")
        row.EasyGearMark = mark
    end
    -- 60 % des Symbols, mindestens lesbar, nie hoeher als die Zeile
    local side = Measure(icon, "GetHeight")
    local size = mmax(MARK_MIN, mmin(MARK_MAX, side * 0.6))
    local height = Measure(row, "GetHeight")
    if height > 0 then size = mmin(size, height) end
    Marks.Style(mark, state, size)
    mark:ClearAllPoints()
    if size + 1 <= side then
        -- in der Ecke des Symbols, nicht darueber hinaus: bei Kacheln und Kaesten ist das Symbol so gross wie die Zeile
        mark:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    else
        -- ein winziges Symbol (niedrige Zeilen): die Markierung liegt mittig darauf und bleibt so in der Zeile
        mark:SetPoint("CENTER", icon, "CENTER", 0, 0)
    end
    mark:Show()

    local r, g, b = Marks.Tint(state)
    local tint = row.EasyGearTint
    if not tint then
        tint = row:CreateTexture(nil, "BORDER")
        tint:SetAllPoints(row)
        row.EasyGearTint = tint
    end
    tint:SetColorTexture(r, g, b, TINT_ALPHA)
    tint:Show()

    local text = row.EasyGearText
    if not text then
        text = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.EasyGearText = text
    end
    -- Kacheln (Icon Tray) zeigen keinen Namen: dort steht nur die Markierung
    if Shown(row.name) then
        MatchFont(text, row.sub)
        text:SetText(Label(state, link))
        text:SetTextColor(r, g, b, 1)
        text:SetShown(PlaceText(row, text))
    else
        text:Hide()
    end
end

------------------------------------------------------------------------------
-- 03  Zeilen annehmen und nachziehen
------------------------------------------------------------------------------

local Soon

local function Adopt(row)
    rows[row] = true
    adopted = adopted + 1
    -- der Feed setzt beim Fuellen (Fill) diesen Text als letzten: Name, zweite Zeile und Preis stehen dann schon.
    -- Gleich danach noch ein Blick auf alle Zeilen: neben dieser kann der Feed eine neue gebaut haben.
    pcall(hooksecurefunc, row.badge, "SetText", function()
        EG:Try("feed", Paint, row)
        Soon()
    end)
end

-- Die Zeilen des Feeds durchgehen: neue annehmen, alle sichtbaren neu kennzeichnen
function Feed.Scan()
    local anchor = Anchor()
    if not anchor then return 0 end
    local seen = 0
    for _, child in ipairs({ anchor:GetChildren() }) do
        if IsRow(child) then
            seen = seen + 1
            if not rows[child] then Adopt(child) end
            if type(child.IsShown) ~= "function" or child:IsShown() then Paint(child) end
        end
    end
    return seen
end

-- Gleich nachsehen: nach dem Feed, der dasselbe Ereignis im selben Bild verarbeitet. Eine Zeile, deren Gegenstand der
-- Feed erst laden musste, erscheint spaeter - dann meldet sich REFRESH (die Daten sind auch fuer EasyGear eingetroffen).
Soon = function()
    EG:Debounce("feedScan", 0.05, function() EG:Try("feed", Feed.Scan) end)
end

--[[ Solange Umschalt gehalten wird, blaettert das Mausrad im Verlauf des Feeds; die Zeilen dafuer baut er, ohne dass
     ein Ereignis es meldet. In dieser Zeit regelmaessig nachsehen - nur mit einem Feed, und nur bis losgelassen wird. ]]
local watching = false
local function Watch()
    if not (IsShiftKeyDown() and Feed.Enabled() and Anchor()) then
        watching = false
        return
    end
    EG:Try("feed", Feed.Scan)
    EG:After(WATCH, Watch)
end

-- Zeile fuer /eg status (nur mit EllesmereUI)
function Feed.StatusLine()
    if type(_G.EllesmereUI) ~= "table" then return nil end
    local anchor, why = Anchor()
    if anchor then return "EllesmereUI Loot Feed: " .. sformat(L.FEED_OK, adopted) end
    if why == "off" then return "EllesmereUI Loot Feed: " .. L.FEED_OFF end
    return "EllesmereUI Loot Feed: " .. L.FEED_ABSENT
end

EG:On("CHAT_MSG_LOOT", Soon)
EG:On("MODIFIER_STATE_CHANGED", function(_, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    Soon()                          -- losgelassen: der Feed zeigt wieder die laufenden Zeilen, vielleicht in neuen
    if watching then return end
    watching = true                 -- endet von selbst, sobald Umschalt nicht mehr gehalten wird
    EG:After(WATCH, Watch)
end)
EG:Listen("INVALIDATED", Soon)      -- Einstellungen, Profil, Ausruestung
EG:Listen("REFRESH", Soon)          -- Gegenstandsdaten sind eingetroffen (Score.lua meldet es nach ITEMS_LOADED), die Gruppe hat sich geaendert
