--[[---------------------------------------------------------------------------
    Marks.lua - Markierungen auf Gegenstandssymbolen

    Eine Markierung ist eine kleine Textur oben links auf dem Symbol (wie der gruene Pfeil, den die
    Taschen der Standard-Oberflaeche selbst mitbringen):

        gruener Pfeil   echte Verbesserung gegenueber dem Angelegten
        gelber Pfeil    waere eine, aber die Charakterstufe reicht noch nicht
        Haken (rechts)  beste Wahl unter den Questbelohnungen

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

local pairs, pcall, type = pairs, pcall, type

-- Atlas-Namen stehen im Client (die Taschen der Standard-Oberflaeche benutzen "bags-greenarrow");
-- fehlt einer, faellt die Markierung auf eine feste Textur zurueck.
local ARROW_ATLAS, CHECK_ATLAS = "bags-greenarrow", "common-icon-checkmark"
local ARROW_FILE, CHECK_FILE = "Interface\\Buttons\\UI-CheckBox-Check", "Interface\\Buttons\\UI-CheckBox-Check"
local ARROW_SIZE, CHECK_SIZE = 18, 20
local HOST_LEVEL = 8                  -- Rahmenebenen ueber dem Knopf

local registry = setmetatable({}, { __mode = "k" })     -- Knopf -> Daten
Marks.registry = registry

local function AtlasExists(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

--[[ Aussehen des Pfeils - fuer die Markierungen hier und fuer Eckenelemente fremder Taschen (Compat.lua):
     Bild und Groesse, dann die Faerbung nach Zustand (gelb und entsaettigt: die Stufe reicht noch nicht)  ]]
function Marks.TintArrow(tex, state)
    if state == "LEVEL" then
        tex:SetDesaturated(true)
        tex:SetVertexColor(1.0, 0.82, 0.0)
    else
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1)
    end
end

function Marks.StyleArrow(tex, state, size)
    size = size or ARROW_SIZE
    tex:SetSize(size, size)
    if AtlasExists(ARROW_ATLAS) then
        tex:SetAtlas(ARROW_ATLAS)
        tex:SetSize(size, size)
    else
        tex:SetTexture(ARROW_FILE)
    end
    tex:SetAlpha(1)
    Marks.TintArrow(tex, state)
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
    Marks.StyleArrow(tex, state, data.arrowSize)
    tex:Show()
end

local function ShowCheck(button, data)
    local tex = Ensure(button, data, "EasyGearCheck", 7)
    tex:ClearAllPoints()
    -- Questbelohnungen sind breite Knoepfe (Symbol links, Name rechts): der Haken gehoert ans Symbol
    tex:SetPoint("TOPRIGHT", IconOf(button), "TOPRIGHT", 2, 2)
    tex:SetSize(CHECK_SIZE, CHECK_SIZE)
    if AtlasExists(CHECK_ATLAS) then
        tex:SetAtlas(CHECK_ATLAS)
        tex:SetSize(CHECK_SIZE, CHECK_SIZE)
    else
        tex:SetTexture(CHECK_FILE)
    end
    tex:SetVertexColor(0.25, 1.0, 0.25)
    tex:SetAlpha(1)
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
            state = Score.UpgradeState(data.link)
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
