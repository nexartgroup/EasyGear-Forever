--[[---------------------------------------------------------------------------
    Marks.lua - Markierungen auf Gegenstandssymbolen

    Eine Markierung ist eine kleine Textur oben links auf dem Symbol (wie der gruene Pfeil, den die
    Taschen der Standard-Oberflaeche selbst mitbringen). So sehen die Markierungen aus, bis man in den
    Optionen eine andere Form oder Farbe waehlt (siehe "Aussehen" weiter unten):

        gruener Pfeil   echte Verbesserung gegenueber dem Angelegten                 (Art UPGRADE)
        gelber Pfeil    waere eine, aber die Charakterstufe reicht noch nicht        (Art LEVEL)
        violetter Stern fuer dich keine Verbesserung, aber fuer ein Gruppenmitglied  (Art GROUP, Group.lua)
        Haken (rechts)  beste Wahl unter den Questbelohnungen: groesste Verbesserung (Art PICK)
                        oder, wenn nichts besser ist, hoechster Verkaufspreis        (Art SELL)

    Die Texturen sitzen auf einem eigenen Rahmen ueber dem Knopf (HostOf). Fremde Oberflaechen wie die
    Fensterhaut von EllesmereUI blenden beim Neuzeichnen eines Knopfes jede Textur aus, die direkt an ihm
    haengt; ein Kindrahmen bleibt unberuehrt und liegt ueber Rahmen, Ringen und Texten des Knopfes.

    Die Engine kennt kein Fenster. Contexts.lua meldet ihr "dieser Knopf zeigt jetzt diesen Link"
    (Marks.Set); sie merkt sich den Knopf und frischt ihn auf, wenn sich Ausruestung, Profil oder
    Einstellungen aendern (Ereignisse INVALIDATED / REFRESH).
-----------------------------------------------------------------------------]]

local _, EG = ...
local Marks = {}
EG.Marks = Marks

local Score = EG.Score
local L = EG.L

local pairs, ipairs, pcall, type, tonumber = pairs, ipairs, pcall, type, tonumber
local sformat, smatch, slower, abs = string.format, string.match, string.lower, math.abs

local ARROW_SIZE, CHECK_SIZE = 18, 20
local HOST_LEVEL = 8                  -- Rahmenebenen ueber dem Knopf
local COLOR_TOLERANCE = 2             -- Stufen je Farbkanal (von 255), um die eine Farbe von der Standardfarbe abweichen darf

local registry = setmetatable({}, { __mode = "k" })     -- Knopf -> Daten
Marks.registry = registry

local function AtlasExists(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

------------------------------------------------------------------------------
-- 01  Aussehen: Formen, Arten, Farben
------------------------------------------------------------------------------

--[[ Formen zur Auswahl. Atlas-Namen stehen im Client (die Taschen und Fenster der Standard-Oberflaeche benutzen
     "bags-greenarrow", "common-icon-checkmark", "bags-junkcoin"); fehlt ein Atlas oder hat die Form keinen, nimmt die
     Markierung die feste Textur. Die acht Zeichen der Schlachtzugsmarkierungen stehen als Dateien in jedem Client.
     name = Schluessel des Namens in den Sprachdateien.                                                            ]]
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CHECK_FILE = "Interface\\Buttons\\UI-CheckBox-Check"
Marks.SHAPES = {
    { id = "arrow",    name = "SHAPE_ARROW",    atlas = "bags-greenarrow",       file = CHECK_FILE },
    { id = "star",     name = "SHAPE_STAR",     atlas = "tradeskills-star",      file = RAID_ICON .. "1" },
    { id = "check",    name = "SHAPE_CHECK",    atlas = "common-icon-checkmark", file = CHECK_FILE },
    { id = "coin",     name = "SHAPE_COIN",     atlas = "bags-junkcoin",         file = "Interface\\MoneyFrame\\UI-GoldIcon" },
    { id = "circle",   name = "SHAPE_CIRCLE",   file = RAID_ICON .. "2" },
    { id = "diamond",  name = "SHAPE_DIAMOND",  file = RAID_ICON .. "3" },
    { id = "triangle", name = "SHAPE_TRIANGLE", file = RAID_ICON .. "4" },
    { id = "moon",     name = "SHAPE_MOON",     file = RAID_ICON .. "5" },
    { id = "square",   name = "SHAPE_SQUARE",   file = RAID_ICON .. "6" },
    { id = "cross",    name = "SHAPE_CROSS",    file = RAID_ICON .. "7" },
    { id = "skull",    name = "SHAPE_SKULL",    file = RAID_ICON .. "8" },
}
local SHAPE_BY_ID = {}
for _, shape in ipairs(Marks.SHAPES) do SHAPE_BY_ID[shape.id] = shape end

--[[ Arten von Markierungen, jede mit eigener Form und Farbe (Einstellungen shapeKey / colorKey, Standardwerte in
     Core.lua). `original` ist das Aussehen, das die Markierung vor der Wahl in den Optionen hatte: solange Form und
     Farbe der Standard sind, bleibt es genau so (der Pfeil in seinen eigenen Farben, der Stern entsaettigt und
     violett, ...). Jede andere Wahl faerbt die entsaettigte Form in der gewaehlten Farbe.
     size = Groesse auf dem Symbol.                                                                             ]]
Marks.KINDS = {
    { id = "UPGRADE", name = "MARK_UPGRADE", tip = "MARK_UPGRADE_TIP", shapeKey = "markUpgradeShape", colorKey = "markUpgradeColor",
      size = ARROW_SIZE, original = { desaturate = false, r = 1, g = 1, b = 1 } },
    { id = "LEVEL",   name = "MARK_LEVEL",   tip = "MARK_LEVEL_TIP",   shapeKey = "markLevelShape",   colorKey = "markLevelColor",
      size = ARROW_SIZE, original = { desaturate = true, r = 1.0, g = 0.82, b = 0.0 } },
    { id = "GROUP",   name = "MARK_GROUP",   tip = "MARK_GROUP_TIP",   shapeKey = "markGroupShape",   colorKey = "markGroupColor",
      size = ARROW_SIZE, original = { desaturate = true, r = 0.75, g = 0.40, b = 1.0 } },
    { id = "PICK",    name = "MARK_PICK",    tip = "MARK_PICK_TIP",    shapeKey = "markPickShape",    colorKey = "markPickColor",
      size = CHECK_SIZE, original = { desaturate = false, r = 0.25, g = 1.0, b = 0.25 } },
    { id = "SELL",    name = "MARK_SELL",    tip = "MARK_SELL_TIP",    shapeKey = "markSellShape",    colorKey = "markSellColor",
      size = CHECK_SIZE, original = { desaturate = false, r = 0.25, g = 1.0, b = 0.25 } },
}
local KINDS = Marks.KINDS
local KIND_BY_ID = {}
for _, kind in ipairs(KINDS) do KIND_BY_ID[kind.id] = kind end

function Marks.Kind(id) return KIND_BY_ID[id] end
function Marks.Shape(id) return SHAPE_BY_ID[id] end

-- Farbe als "AARRGGBB" (so liefert sie das Farbfeld der Einstellungsseite) oder "RRGGBB" (Chatbefehl), mit oder ohne
-- "#" davor. Rueckgabe immer "ffrrggbb" in Kleinbuchstaben (die Deckkraft zaehlt nicht), sonst nil.
function Marks.NormalizeColor(value)
    if type(value) ~= "string" then return nil end
    local hex = smatch(value, "^#?(%x%x%x%x%x%x)$") or smatch(value, "^#?%x%x(%x%x%x%x%x%x)$")
    if not hex then return nil end
    return "ff" .. slower(hex)
end

-- r, g, b (0..1) einer Farbe; nil bei ungueltiger Eingabe
function Marks.ColorRGB(value)
    local color = Marks.NormalizeColor(value)
    if not color then return nil end
    return tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255, tonumber(color:sub(7, 8), 16) / 255
end

-- Sind zwei Farben ("ffrrggbb") gleich bis auf eine Rundungsabweichung? Das Farbfeld rechnet die Farbe in Kommazahlen und
-- zurueck, schon sein Oeffnen kann einen Kanal um eine Stufe verschieben; die Standardfarbe soll davon nicht kippen.
local function SameColor(a, b)
    for i = 3, 7, 2 do
        if abs(tonumber(a:sub(i, i + 1), 16) - tonumber(b:sub(i, i + 1), 16)) > COLOR_TOLERANCE then return false end
    end
    return true
end

-- Gewaehlte Form (Kennung) und Farbe ("ffrrggbb") einer Art. Ein Wert, den es nicht gibt (von Hand veraenderte
-- Einstellungen, eine Form aus einer anderen Fassung), gilt als Standard.
function Marks.Choice(kindId)
    local kind = KIND_BY_ID[kindId] or KINDS[1]
    local shape = EG:Get(kind.shapeKey)
    if not SHAPE_BY_ID[shape] then shape = EG.DEFAULTS[kind.shapeKey] end
    local color = Marks.NormalizeColor(EG:Get(kind.colorKey)) or EG.DEFAULTS[kind.colorKey]
    return shape, color
end

--[[ So sieht die Markierung einer Art aus. Rueckgabe: Form (Eintrag aus Marks.SHAPES), entsaettigen?, r, g, b.
     Standard-Form in Standard-Farbe: das urspruengliche Aussehen. Sonst die entsaettigte Form, in der Farbe getoent;
     so kann jede Form jede Farbe annehmen, auch die, die von sich aus bunt ist.                                   ]]
function Marks.Look(kindId)
    local kind = KIND_BY_ID[kindId] or KINDS[1]
    local shapeId, color = Marks.Choice(kind.id)
    if shapeId == EG.DEFAULTS[kind.shapeKey] and SameColor(color, EG.DEFAULTS[kind.colorKey]) then
        local original = kind.original
        return SHAPE_BY_ID[shapeId], original.desaturate, original.r, original.g, original.b
    end
    local r, g, b = Marks.ColorRGB(color)
    return SHAPE_BY_ID[shapeId], true, r, g, b
end

-- Form und/oder Farbe einer Art in die Einstellungen schreiben (nil = unveraendert). Ungueltiges wird abgewiesen
-- (false), ohne etwas zu aendern. Schreibt nur: wer es aufruft, sorgt selbst fuer das Neuzeichnen (EG:InvalidateAll).
function Marks.WriteChoice(kindId, shapeId, color)
    local kind = KIND_BY_ID[kindId]
    if not kind then return false end
    if shapeId ~= nil and not SHAPE_BY_ID[shapeId] then return false end
    local normalized
    if color ~= nil then
        normalized = Marks.NormalizeColor(color)
        if not normalized then return false end
    end
    if shapeId ~= nil then EG.db[kind.shapeKey] = shapeId end
    if normalized then EG.db[kind.colorKey] = normalized end
    return true
end

function Marks.SetChoice(kindId, shapeId, color)
    if not Marks.WriteChoice(kindId, shapeId, color) then return false end
    EG:InvalidateAll()
    return true
end

-- Eine Art - ohne Angabe alle - auf das urspruengliche Aussehen zuruecksetzen
function Marks.ResetChoice(kindId)
    for _, kind in ipairs(KINDS) do
        if kindId == nil or kind.id == kindId then
            EG.db[kind.shapeKey] = EG.DEFAULTS[kind.shapeKey]
            EG.db[kind.colorKey] = EG.DEFAULTS[kind.colorKey]
        end
    end
    EG:InvalidateAll()
end

-- Eintrag in der Formliste der Optionen: das Bild der Form, dann ihr Name
function Marks.ShapeLabel(shape, size)
    size = size or 16
    local picture
    if shape.atlas and AtlasExists(shape.atlas) then
        picture = sformat("|A:%s:%d:%d|a", shape.atlas, size, size)
    else
        picture = sformat("|T%s:%d:%d|t", shape.file, size, size)
    end
    return picture .. " " .. L[shape.name]
end

--[[ Bild und Faerbung einer Art auf eine Textur legen - fuer die Markierungen hier und fuer Eckenelemente fremder
     Taschen (Compat.lua). Das Bild wird bei jedem Aufruf gesetzt: ein Eckenelement von Baganator zeigt mal den
     Pfeil, mal den Stern.  kind: "UPGRADE" | "LEVEL" | "GROUP" | "PICK" | "SELL"                                  ]]
function Marks.Paint(tex, kindId)
    local shape, desaturate, r, g, b = Marks.Look(kindId)
    if shape.atlas and AtlasExists(shape.atlas) then
        tex:SetAtlas(shape.atlas)
    else
        tex:SetTexture(shape.file)
        tex:SetTexCoord(0, 1, 0, 1)         -- ein Atlas davor liesse seinen Ausschnitt stehen
    end
    tex:SetDesaturated(desaturate)
    tex:SetVertexColor(r, g, b)
end

function Marks.Style(tex, kindId, size)
    local kind = KIND_BY_ID[kindId] or KINDS[1]
    size = size or kind.size
    tex:SetSize(size, size)
    Marks.Paint(tex, kind.id)
    tex:SetSize(size, size)             -- manche Bilder setzen ihre eigene Groesse
    tex:SetAlpha(1)
end

-- Der Rahmen, auf dem die Markierungen eines Knopfes sitzen; scheitert das Anlegen, traegt der Knopf sie selbst.
-- Fremde Taschen geben einen eigenen Rahmen vor (data.anchor, bei EllesmereUI die Deckschicht ueber dem Symbol): der
-- Rahmen haengt dann daran und folgt dessen Sichtbarkeit.
local function HostOf(button, data)
    local host = button.EasyGearHost
    if host then return host end
    local parent = data and data.anchor or button
    if CreateFrame then
        local ok, frame = pcall(CreateFrame, "Frame", nil, parent)
        if ok and frame then
            frame:SetAllPoints(parent)
            frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + HOST_LEVEL)
            button.EasyGearHost = frame
            return frame
        end
    end
    return button
end

-- Fremde Taschen setzen die Rahmenebenen ihrer Knoepfe und Deckschichten spaeter neu (EllesmereUI: beim Anheben des
-- Fensters); Kindrahmen folgen dem nicht. Der Rahmen mit den Markierungen zieht darum bei jedem Zeichnen nach, sonst
-- laege er irgendwann unter der Deckschicht oder unter dem Fenster.
local function FollowLevel(button)
    local host = button.EasyGearHost
    if not host then return end
    local parent = host.GetParent and host:GetParent()
    if parent and parent.GetFrameLevel and host.SetFrameLevel then
        host:SetFrameLevel(parent:GetFrameLevel() + HOST_LEVEL)
    end
end

local function Ensure(button, data, key, layerLevel)
    local tex = button[key]
    if tex then return tex end
    tex = HostOf(button, data):CreateTexture(nil, "OVERLAY", nil, layerLevel or 7)
    button[key] = tex
    tex:Hide()
    return tex
end

-- Das Symbol eines Knopfes, woran die Markierung haengt: Oberflaechen, die das Symbol zuschneiden oder verschieben,
-- nehmen sie so mit; bei breiten Knoepfen (Questbelohnungen, Beute) sitzt das Symbol links
local function IconOf(button)
    local icon = button.Icon or button.icon
    if type(icon) == "table" and icon.GetObjectType then return icon end
    return button
end

local function ShowArrow(button, data, state)
    local tex = Ensure(button, data, "EasyGearArrow", 7)
    tex:ClearAllPoints()
    -- Wie der eigene Pfeil der Taschen oben links; zeigt der Haendler dort den Restbestand (Stock), geht er nach rechts.
    -- Fremde Taschen legen ihre eigenen Texte oben links ab (data.corner = "TOPRIGHT", siehe Compat.lua).
    local corner = data.corner or "TOPLEFT"
    local stock = button.Stock
    if corner == "TOPLEFT" and type(stock) == "table" and stock.IsShown and stock:IsShown() then corner = "TOPRIGHT" end
    tex:SetPoint(corner, data.iconRegion or data.anchor or IconOf(button), corner, 0, 0)
    Marks.Style(tex, state, data.arrowSize)
    tex:Show()
end

local function ShowCheck(button, data)
    local tex = Ensure(button, data, "EasyGearCheck", 7)
    tex:ClearAllPoints()
    -- Questbelohnungen sind breite Knoepfe (Symbol links, Name rechts): der Haken gehoert ans Symbol
    tex:SetPoint("TOPRIGHT", IconOf(button), "TOPRIGHT", 2, 2)
    -- gewaehlt wurde die Beste nach Verkaufspreis ("VENDOR", siehe Recommend.lua) oder nach Verbesserung
    Marks.Style(tex, data.bestKind == "VENDOR" and "SELL" or "PICK")
    tex:Show()
end

local function HideAll(button)
    if button.EasyGearArrow then button.EasyGearArrow:Hide() end
    if button.EasyGearCheck then button.EasyGearCheck:Hide() end
end

-- Welche Gruppe von Einstellungen schaltet diese Art von Knopf?
local SETTING_FOR = {
    bag = "showBagIcons", bank = "showBagIcons",
    merchant = "showItemIcons", loot = "showItemIcons", roll = "showItemIcons",
    trade = "showItemIcons", mail = "showItemIcons",
    quest = "showQuestIcons", char = "showCharIcons",
}
Marks.SETTING_FOR = SETTING_FOR

function Marks.Enabled(ctx)
    local key = SETTING_FOR[ctx]
    return key == nil or EG:Get(key) ~= false
end

--[[ Zustand eines Knopfes neu bestimmen und zeichnen.
     data = { ctx, link, best, hintSlot }                                                      ]]
function Marks.Update(button)
    local data = registry[button]
    if not data then return end

    local state, show = nil, false
    if Marks.Enabled(data.ctx) then
        if data.ctx == "char" then
            local hint = data.hint and data.hint() or nil
            state = hint and "UPGRADE" or nil
        elseif data.link then
            local loading
            state, loading = Score.UpgradeState(data.link)
            -- Keine Verbesserung fuer dich: vielleicht fuer ein Gruppenmitglied (violetter Stern) - aber erst, wenn deine
            -- eigene Antwort feststeht; sonst stuende kurz ein Stern da, wo gleich der Pfeil erscheint
            if state == nil and not loading and EG.Group then
                state = EG.Group.State(data.link, data.ctx, data.bag, data.slot)
            end
        end
        if data.best and Marks.Enabled(data.ctx) then show = true end
    end

    if state or show then
        FollowLevel(button)
        if state then ShowArrow(button, data, state) elseif button.EasyGearArrow then button.EasyGearArrow:Hide() end
        if show then ShowCheck(button, data) elseif button.EasyGearCheck then button.EasyGearCheck:Hide() end
    else
        HideAll(button)
    end
end

--[[ Ein Knopf zeigt jetzt diesen Link (nil = leer).
     opts: ctx (Pflicht), best (beste Questwahl), hint (Funktion -> Eintrag; nur fuer das Charakterfenster),
           bag / slot (das Fach bei Taschen und Bank: die Gruppenhinweise pruefen daran, ob der Gegenstand noch tauschbar ist),
           corner / arrowSize / anchor (Lage, Groesse und Bezugsrahmen des Pfeils, wenn der Gastgeber des Knopfes
           sie vorgibt),
           iconRegion (das Symbol, wenn der Knopf breiter ist als das Symbol: der Pfeil sitzt dann dessen Ecke an,
           nicht der des ganzen Knopfes; gilt nur fuer diesen Aufruf)

     Beim Aufruf aus Contexts.lua wird die Questwahl bewusst zurueckgesetzt: Blizzard setzt den Knopf neu,
     wenn sich die Belohnungen aendern, und die beste Wahl wird danach neu bestimmt.                         ]]
function Marks.Set(button, link, opts)
    if not button then return end
    local data = registry[button]
    if not data then
        data = {}
        registry[button] = data
    end
    data.ctx = opts and opts.ctx or data.ctx
    data.link = link
    data.best = opts and opts.best or false
    data.bestKind = nil
    data.hint = opts and opts.hint or data.hint
    data.corner = opts and opts.corner or data.corner
    data.arrowSize = opts and opts.arrowSize or data.arrowSize
    data.anchor = opts and opts.anchor or data.anchor
    data.iconRegion = opts and opts.iconRegion or nil
    data.bag = opts and opts.bag or nil
    data.slot = opts and opts.slot or nil
    Marks.Update(button)
end

-- Beste Questwahl; kind = "UPGRADE" (groesster Zugewinn) oder "VENDOR" (hoechster Verkaufswert)
function Marks.SetBest(button, best, kind)
    local data = registry[button]
    if not data then return end
    data.best = best and true or false
    data.bestKind = data.best and kind or nil
    Marks.Update(button)
end

function Marks.Clear(button)
    local data = registry[button]
    if data then
        data.link, data.best, data.bestKind = nil, false, nil
    end
    HideAll(button)
end

-- Alle sichtbaren Knoepfe auffrischen
function Marks.RefreshAll()
    for button, data in pairs(registry) do
        if button.IsVisible and button:IsVisible() then
            EG:Try("mark", Marks.Update, button)
        elseif data.ctx and not Marks.Enabled(data.ctx) then
            HideAll(button)
        end
    end
end

local function Schedule()
    EG:Debounce("marks", 0.15, Marks.RefreshAll)
end
EG:Listen("INVALIDATED", Schedule)
EG:Listen("REFRESH", Schedule)
