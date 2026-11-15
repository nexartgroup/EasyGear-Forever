--[[---------------------------------------------------------------------------
    Feed.lua - Anbindung an den Loot Feed von EllesmereUI (Forever Essentials)

    Der Loot Feed zeigt, was der Spieler gerade bekommt, als kurzlebige Zeilen: Symbol, Name, zweite Zeile
    (Gegenstandsstufe), rechts der Preis. EasyGear kennzeichnet darin, was besser ist als das Angelegte:

        [Markierung auf der Ecke des Symbols]   die Zeile in der Farbe der Markierung getoent   "+83.1%" unten rechts

    Verbesserung: Pfeil und Zugewinn; Verbesserung erst mit hoeherer Stufe: gelber Pfeil und die Stufe; besser fuer
    ein Gruppenmitglied: violetter Stern. Form und Farbe sind die der Optionen (Aussehen der Markierungen).

    Der Loot Feed bietet anderen Addons keine Schnittstelle; seine Zeilen sind namenlose Rahmen. EasyGear findet sie
    ueber den Rahmen des Feeds - EllesmereUI fuehrt ihn im Entsperrmodus unter dem Schluessel "EUI_LootFeed"
    (EllesmereUI._unlockRegisteredElements) - und erkennt eine Zeile an ihrem Aufbau (icon, name, sub, value). Jede
    Zeile wird einmal angenommen: von da an meldet ein Haken auf icon:SetTexture jede neue Belegung (der Feed fuellt
    eine Zeile immer zuerst mit dem Symbol; r.data traegt dann schon den neuen Gegenstand). Die eigenen Teile sind
    Kinder der Zeile und blenden mit ihr aus. Gesucht wird nur, wenn etwas gepluendert wurde oder Daten eintreffen.

    Gelesen aus EllesmereUIForeverEssentials_LootFeed.lua (9.8.6). Fehlt etwas davon, sagt /eg status es.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Feed = {}
EG.Feed = Feed

local L = EG.L
local Score, Marks = EG.Score, EG.Marks

local type, pcall, ipairs = type, pcall, ipairs
local sformat = string.format
local mmax, mmin = math.max, math.min

local ELEMENT = "EUI_LootFeed"      -- Schluessel des Loot Feeds im Entsperrmodus von EllesmereUI
local TINT_ALPHA = 0.16             -- so stark toent die Farbe der Markierung die Zeile
local MARK_MIN, MARK_MAX = 12, 20   -- Groesse der Markierung auf dem Symbol (60 % des Symbols, in diesen Grenzen)

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
       and type(f.name) == "table" and type(f.sub) == "table" and type(f.value) == "table"
       and type(f.CreateTexture) == "function" and type(f.CreateFontString) == "function"
end

------------------------------------------------------------------------------
-- 02  Eine Zeile kennzeichnen
------------------------------------------------------------------------------

local function Hide(row)
    if row.EasyGearMark then row.EasyGearMark:Hide() end
    if row.EasyGearTint then row.EasyGearTint:Hide() end
    if row.EasyGearText then row.EasyGearText:Hide() end
end

-- Was unten rechts steht: der Zugewinn, die Stufe, oder dass es der Gruppe nuetzt
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

local function Paint(row)
    local data = row.data
    local link = type(data) == "table" and type(data.link) == "string" and data.link or nil
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

    local icon = row.icon
    local mark = row.EasyGearMark
    if not mark then
        mark = row:CreateTexture(nil, "OVERLAY")
        mark:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3)
        row.EasyGearMark = mark
    end
    local side = type(icon.GetHeight) == "function" and icon:GetHeight() or 0
    Marks.Style(mark, state, mmax(MARK_MIN, mmin(MARK_MAX, side * 0.6)))
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
        text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 3)
        text:SetJustifyH("RIGHT")
        row.EasyGearText = text
    end
    -- Kacheln (Icon Tray) zeigen keinen Namen und tragen unten rechts die Anzahl: dort steht nur die Markierung
    local named = type(row.name.IsShown) ~= "function" or row.name:IsShown()
    if named then
        MatchFont(text, row.sub)
        text:SetText(Label(state, link))
        text:SetTextColor(r, g, b, 1)
        text:Show()
    else
        text:Hide()
    end
end

------------------------------------------------------------------------------
-- 03  Zeilen annehmen und nachziehen
------------------------------------------------------------------------------

local function Adopt(row)
    rows[row] = true
    adopted = adopted + 1
    -- der Feed fuellt eine Zeile immer zuerst mit dem Symbol (Fill): da traegt r.data schon den neuen Gegenstand
    pcall(hooksecurefunc, row.icon, "SetTexture", function() EG:Try("feed", Paint, row) end)
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

local function Soon()
    EG:Debounce("feedScan", 0.05, function() EG:Try("feed", Feed.Scan) end)
    EG:Debounce("feedLate", 0.6, function() EG:Try("feed", Feed.Scan) end)     -- Gegenstaende, die der Feed erst laden musste
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
EG:Listen("ITEMS_LOADED", Soon)
EG:Listen("INVALIDATED", Soon)
EG:Listen("REFRESH", Soon)
