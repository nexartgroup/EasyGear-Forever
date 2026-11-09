--[[---------------------------------------------------------------------------
    Compat.lua - Anbindung an Baganator und EllesmereUI

    EasyGear braucht beide nicht. Sind sie da, erscheinen die Markierungen auch in ihren Taschen und Fenstern.

    Baganator ersetzt die Taschen und die Bank. Seine Knoepfe zeichnen keine Symbole ueber die globale Funktion
    SetItemButtonQuality der Oberflaeche, sondern ueber "Eckenelemente", die andere Addons bei ihm anmelden
    (Baganator.API.RegisterCornerWidget, beschrieben in seiner Schnittstelle). EasyGear meldet seinen Pfeil als
    Eckenelement an - Voreinstellung oben rechts, denn Baganator legt oben links Muellsymbol und Gegenstandsstufe ab -
    und zusaetzlich als Quelle fuer "Verbesserung" (RegisterUpgradePlugin), damit Baganators Suche und Kategorien
    dieselbe Auskunft benutzen. Mehr als diese oeffentliche Schnittstelle wird nicht angefasst, und die Rueckrufe
    fangen jeden Fehler ab: ein Fehler hier darf nie Baganators Taschen stoeren. Baganator fuegt das Eckenelement nur
    in das Profil ein, das beim Anmelden gilt; in anderen Profilen waehlt man es unter "Symbolecken" selbst. Ohne
    Syndicator startet Baganator nicht - dann meldet EasyGear nichts an und sagt es in /eg status.

    EllesmereUI hat zwei Seiten:
      * Seine Taschen (EllesmereUI Bags) bauen eigene Knoepfe aus der Vorlage der Standard-Taschen und setzen die
        Qualitaet ueber die Methode des Knopfes - die Haken auf die globale Funktion sehen sie nicht. Fuer Zusatz-
        Symbole bietet das Modul eine eigene Schnittstelle (EUI_Bags.RegisterItemOverlayIcon): der angemeldete Maler
        laeuft fuer jeden gezeichneten Platz der Taschen, der Reagenzientasche und der Bank, in der Gitter- wie in
        der Listenansicht, auch fuer leere Plaetze. EasyGear malt dort den Pfeil an die Deckschicht ueber dem
        Symbol (btn._textOverlay), oben rechts - oben links steht die Gegenstandsstufe.
      * Seine Fensterhaut blendet auf vielen Fenstern jede Textur eines Knopfes aus, wenn sie ihn neu zeichnet.
        Die Markierungen sitzen darum auf einem eigenen Rahmen (Marks.lua) und sind davon nicht betroffen. Der Rahmen
        folgt auch den Rahmenebenen, die die Taschen ihren Knoepfen spaeter neu geben.
        Die Haendlerliste ("Als Liste") ist keine Sache dieser Datei: dort deckt der Knopf die ganze Zeile, und
        Contexts.lua setzt den Pfeil an das Zeilensymbol.
-----------------------------------------------------------------------------]]

local _, EG = ...
local Compat = {}
EG.Compat = Compat

local L = EG.L
local Score, Marks = EG.Score, EG.Marks

local type, pcall, tostring, floor = type, pcall, tostring, math.floor

local WIDGET_ID = "easygear"
local WIDGET_SIZE = 15              -- Pfeil in Baganators Ecke
local EUI_ARROW_MAX = 16            -- Pfeil auf den Knoepfen von EllesmereUI Bags: so gross bei einem Platz ab 32 Pixeln ...
local EUI_ARROW_MIN = 8             -- ... und halb so gross wie das Symbol darunter, aber nie kleiner als dies

local baganatorOK = false           -- Baganator: Eckenelement und Quelle sind angemeldet
local baganatorProblem = nil        -- Baganator: Text, wenn die Anmeldung nicht ging
local ellesmereOK = false           -- EllesmereUI Bags: der Maler ist angemeldet

local function IsLoaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

------------------------------------------------------------------------------
-- 01  Wem gehoert ein Knopf?
------------------------------------------------------------------------------

--[[ Knoepfe fremder Taschen erkennt man an dem, was sie selbst mitbringen. Rueckgabe: "baganator" | "ellesmere" | nil
     Baganator: jeder Knopf traegt seine Gegenstandsdaten (BGR) und seine Eckenelemente.
     EllesmereUI Bags: Texte liegen auf einer eigenen Deckschicht (_textOverlay); die Plaetze des Gitters tragen darauf die
     Gegenstandsstufe oben links (ItemLevelText), die Zeilen der Listenansicht ein Zeilensymbol (_lvIcon).
     Diese Knoepfe zeichnet Compat ueber die Schnittstelle des Gastgebers; die Haken auf die Funktionen der
     Oberflaeche (Contexts.lua) uebergehen sie, sonst stuende der Pfeil doppelt dort.                           ]]
function Compat.HostOf(button)
    if type(button) ~= "table" then return nil end
    if button.BGR ~= nil or button.cornerPlugins ~= nil or button.widgetContainer ~= nil then return "baganator" end
    if button._textOverlay ~= nil and (button.ItemLevelText ~= nil or button._lvIcon ~= nil) then return "ellesmere" end
    return nil
end

------------------------------------------------------------------------------
-- 02  Baganator
------------------------------------------------------------------------------

local function BaganatorAPI()
    local B = _G.Baganator
    if type(B) == "table" and type(B.API) == "table" and type(B.API.RegisterCornerWidget) == "function" then
        return B
    end
    return nil
end

-- Ist fuer diesen Gegenstand ein Pfeil faellig?  Rueckgabe: "UPGRADE" | "LEVEL" | false | nil (Daten fehlen noch)
local function Verdict(itemLink)
    if not itemLink or not EG:Get("showBagIcons") then return false end
    local state, loading = Score.UpgradeState(itemLink)
    if state then return state end
    if loading then return nil end
    return false
end

-- Eckenelement: das Bild wird einmal je Knopf angelegt (Baganator haengt es um und verankert es in der Ecke)
local function InitWidget(itemButton)
    local tex = itemButton:CreateTexture(nil, "OVERLAY")
    Marks.StyleArrow(tex, "UPGRADE", WIDGET_SIZE)
    tex:Hide()
    return tex
end

-- true = zeigen, false = nicht zeigen, nil = die Gegenstandsdaten sind noch nicht da (Baganator fragt spaeter noch einmal)
local function UpdateWidget(widget, details)
    local state = Verdict(type(details) == "table" and details.itemLink or nil)
    if state == nil then return nil end
    if state == false then return false end
    Marks.TintArrow(widget, state)
    return true
end

local function SafeInit(itemButton)
    local ok, widget = EG:Try("baganator", InitWidget, itemButton)
    if ok then return widget end
    return itemButton:CreateTexture(nil, "OVERLAY")
end

local function SafeUpdate(widget, details)
    local ok, show = EG:Try("baganator", UpdateWidget, widget, details)
    if ok then return show end
    return false
end

-- Quelle fuer Baganators Suche und Kategorien: nur echte Verbesserungen; ohne Daten nil
local function UpgradeSource(itemLink)
    local ok, state = EG:Try("baganator", Verdict, itemLink)
    if not ok then return false end
    if state == "UPGRADE" then return true end
    if state == nil then return nil end
    return false
end

-- Baganator soll seine Knopf-Elemente neu auswerten: nach Ausruestungs-, Profil- und Einstellungswechseln und wenn
-- Gegenstandsdaten angekommen sind. Nur, wenn EasyGear dort wirklich benutzt wird.
local function RequestRefresh()
    local B = BaganatorAPI()
    if not (B and type(B.API.RequestItemButtonsRefresh) == "function") then return end
    local widgetOn = type(B.API.IsCornerWidgetActive) == "function" and B.API.IsCornerWidgetActive(WIDGET_ID)
    local sourceOn = type(B.API.IsUpgradePluginActive) == "function" and B.API.IsUpgradePluginActive(WIDGET_ID)
    if not (widgetOn or sourceOn) then return end

    local reasons = type(B.Constants) == "table" and B.Constants.RefreshReason or nil
    if type(reasons) == "table" and reasons.ItemWidgets then
        local list = { reasons.ItemWidgets }
        if sourceOn and reasons.Searches then list[#list + 1] = reasons.Searches end
        B.API.RequestItemButtonsRefresh(list)
    else
        B.API.RequestItemButtonsRefresh()
    end
end

local function ScheduleRefresh()
    EG:Debounce("baganator", 0.1, function() EG:Try("baganator", RequestRefresh) end)
end

function Compat.RegisterBaganator()
    if baganatorOK then return true end
    local B = BaganatorAPI()
    if not B then
        if IsLoaded("Baganator") then
            baganatorProblem = "RegisterCornerWidget"
            EG:HookResult("baganator", false, "Baganator.API.RegisterCornerWidget fehlt")
        end
        return false
    end
    -- Ohne Syndicator bricht Baganator beim Start ab: seine Schnittstelle steht zwar da, angewendet wird aber nichts, und
    -- /eg status wuerde eine Anmeldung melden, die nie zeichnet.
    if type(_G.Syndicator) ~= "table" then
        baganatorProblem = "Syndicator"
        EG:HookResult("baganator", false, "Syndicator fehlt - Baganator startet ohne nicht")
        return false
    end

    local ok, err = pcall(function()
        B.API.RegisterCornerWidget(L.COMPAT_WIDGET, WIDGET_ID, SafeUpdate, SafeInit, { corner = "top_right", priority = 1 })
        if type(B.API.RegisterUpgradePlugin) == "function" then
            B.API.RegisterUpgradePlugin("EasyGear", WIDGET_ID, UpgradeSource)
        end
    end)
    if not ok then
        baganatorProblem = tostring(err)
        EG:HookResult("baganator", false, baganatorProblem)
        return false
    end

    baganatorOK = true
    baganatorProblem = nil
    EG:HookResult("baganator", true)
    EG:Listen("INVALIDATED", ScheduleRefresh)
    EG:Listen("ITEMS_LOADED", ScheduleRefresh)
    return true
end

------------------------------------------------------------------------------
-- 03  EllesmereUI Bags
------------------------------------------------------------------------------

local function EllesmereBags()
    local bags = _G.EUI_Bags
    if type(bags) == "table" and type(bags.RegisterItemOverlayIcon) == "function" then return bags end
    return nil
end

-- Die Pfeilgroesse folgt dem Symbol: die Deckschicht liegt im Gitter auf dem ganzen Platz, in der Liste auf dem Zeilensymbol
-- (dort nur 20 Pixel). Ist die Hoehe (noch) nicht bekannt, gilt die volle Groesse.
local function EllesmereArrowSize(overlay)
    local height = type(overlay) == "table" and overlay.GetHeight and overlay:GetHeight() or nil
    if type(height) ~= "number" or height <= 0 then return EUI_ARROW_MAX end
    local size = floor(height * 0.5)
    if size < EUI_ARROW_MIN then return EUI_ARROW_MIN end
    if size > EUI_ARROW_MAX then return EUI_ARROW_MAX end
    return size
end

--[[ Der Maler fuer einen Platz (btn = Knopf, data = { bag, slot, info, itemLink }, nur waehrend des Aufrufs gueltig).
     Ein leerer Platz hat keinen Link: Marks.Set raeumt dann auf, was der Knopf vorher zeigte. Spaetere Aenderungen von
     Ausruestung, Profil und Einstellungen frischt Marks selbst auf (Ereignisse INVALIDATED / REFRESH).               ]]
local function PaintEllesmere(btn, data)
    local link = type(data) == "table" and data.itemLink or nil
    local overlay = btn._textOverlay
    Marks.Set(btn, link, { ctx = "bag", anchor = overlay, corner = "TOPRIGHT", arrowSize = EllesmereArrowSize(overlay) })
end

function Compat.RegisterEllesmere()
    if ellesmereOK then return true end
    local bags = EllesmereBags()
    if not bags then
        if IsLoaded("EllesmereUIBags") then
            EG:HookResult("ellesmere", false, "EUI_Bags.RegisterItemOverlayIcon fehlt")
        end
        return false
    end
    local ok, err = pcall(bags.RegisterItemOverlayIcon, "EasyGear", function(btn, data)
        EG:Try("ellesmere", PaintEllesmere, btn, data)
    end)
    if not ok then
        EG:HookResult("ellesmere", false, tostring(err))
        return false
    end
    ellesmereOK = true
    EG:HookResult("ellesmere", true)
    return true
end

------------------------------------------------------------------------------
-- 04  Auskunft fuer /eg status
------------------------------------------------------------------------------

function Compat.StatusLines()
    local lines = {}
    if baganatorOK then
        lines[#lines + 1] = "Baganator: " .. L.COMPAT_BAGANATOR_OK
    elseif baganatorProblem then
        lines[#lines + 1] = "Baganator: " .. L.COMPAT_BAGANATOR_NOAPI .. " (" .. baganatorProblem .. ")"
    else
        lines[#lines + 1] = "Baganator: " .. L.COMPAT_NOT_FOUND
    end
    if IsLoaded("EllesmereUI") then
        local bags
        if ellesmereOK then
            bags = L.COMPAT_ELLESMERE_BAGS
        elseif IsLoaded("EllesmereUIBags") then
            bags = L.COMPAT_ELLESMERE_NOAPI
        else
            bags = L.COMPAT_ELLESMERE_NOBAGS
        end
        lines[#lines + 1] = "EllesmereUI: " .. L.COMPAT_ELLESMERE_OK .. " " .. bags
    else
        lines[#lines + 1] = "EllesmereUI: " .. L.COMPAT_NOT_FOUND
    end
    return lines
end

-- Alle Addons sind beim Anmelden geladen; erst dann sind ihre Schnittstellen sicher da
EG:OnLogin("compat", function()
    Compat.RegisterBaganator()
    Compat.RegisterEllesmere()
end)
