--[[---------------------------------------------------------------------------
    UI.lua - Baukasten der eigenen Fenster und der Einblendung

    Flache, dunkle Flaechen mit duennem Rand, eine Akzentfarbe, wenige klare Schriftgroessen, Abschnitte in
    Versalien, Reiter mit Unterstrich: das Aussehen heutiger Oberflaechen. Alles besteht aus einfarbigen
    Texturen und Schriften - keine Vorlagen der Standard-Oberflaeche, keine Bilddateien.

    Ist EllesmereUI geladen, uebernimmt EasyGear dessen Akzentfarbe (die im Thema gewaehlte) und dessen
    Schrift, damit die Fenster zu den uebrigen passen; sonst gelten die eigene Akzentfarbe und die Schrift
    des Spiels. Die Flaechenfarben sind die von EllesmereUI: ein warmes Fast-Schwarz, Raender und gedaempfter
    Text als Weiss mit Deckkraft.

    Bausteine:  UI.Text  UI.Fill  UI.Border  UI.Box  UI.Rule  UI.Button  UI.Tab  UI.Icon  UI.Window
-----------------------------------------------------------------------------]]

local _, EG = ...
local UI = {}
EG.UI = UI

local type, pcall, ipairs = type, pcall, ipairs
local mmax = math.max

------------------------------------------------------------------------------
-- 01  Farben und Schrift
------------------------------------------------------------------------------

-- Rolle -> Rot, Gruen, Blau, Deckkraft
local COLORS = {
    bg     = { 0.069, 0.058, 0.047, 0.97 },    -- Fensterflaeche (PANEL_BG von EllesmereUI)
    card   = { 1.00, 1.00, 1.00, 0.04 },       -- Karte auf der Flaeche
    stripe = { 0.00, 0.00, 0.00, 0.18 },       -- jede zweite Zeile einer Tabelle
    hover  = { 1.00, 1.00, 1.00, 0.09 },       -- Knopf unter der Maus
    border = { 1.00, 1.00, 1.00, 0.10 },
    line   = { 1.00, 1.00, 1.00, 0.07 },       -- Trennlinie
    text   = { 1.00, 1.00, 1.00, 1.00 },
    dim    = { 1.00, 1.00, 1.00, 0.62 },
    faint  = { 1.00, 1.00, 1.00, 0.42 },       -- Abschnittstitel, Abgeschaltetes
    good   = { 0.30, 0.90, 0.45, 1.00 },
    bad    = { 1.00, 0.38, 0.38, 1.00 },
    warn   = { 1.00, 0.80, 0.22, 1.00 },
    accent = { 0.20, 0.72, 1.00, 1.00 },       -- die eigene Akzentfarbe (das Blau des Chat-Namens)
}
UI.COLORS = COLORS

-- Die Akzentfarbe: die von EllesmereUI, wenn es geladen ist (sein Thema kann sie jederzeit aendern - darum bei jedem
-- Zeichnen gefragt), sonst die eigene
local function Accent()
    local eui = _G.EllesmereUI
    local c = type(eui) == "table" and eui.ELLESMERE_GREEN or nil
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return c.r, c.g, c.b, 1
    end
    local own = COLORS.accent
    return own[1], own[2], own[3], own[4]
end

-- Rot, Gruen, Blau, Deckkraft einer Rolle; alpha ersetzt die Deckkraft (eine Akzentflaeche, die nur toent)
function UI.Color(role, alpha)
    local r, g, b, a
    if role == "accent" then
        r, g, b, a = Accent()
    else
        local c = COLORS[role] or COLORS.text
        r, g, b, a = c[1], c[2], c[3], c[4]
    end
    return r, g, b, alpha or a
end

-- Client-Sprachen, deren Schrift die mitgelieferten Schriften von EllesmereUI nicht enthalten
local OWN_GLYPHS = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

--[[ Die Schriftdatei: die in EllesmereUI gewaehlte (Schriften -> global), sonst dessen Standardschrift, sonst die der
     Standardschrift des Spiels. Bei Client-Sprachen mit eigener Schrift (Koreanisch, Chinesisch, Russisch) immer die
     des Spiels: EllesmereUI richtet seine Schrift nach seiner Anzeigesprache, Gegenstandsnamen kommen aber in der
     Sprache des Clients.                                                                                            ]]
function UI.FontFile()
    local eui = _G.EllesmereUI
    if type(eui) == "table" and not OWN_GLYPHS[GetLocale and GetLocale() or ""] then
        -- nur fragen, wenn EllesmereUI seine Schriften schon eingerichtet hat (die Frage legt sie sonst an)
        local db = _G.EllesmereUIDB
        if type(eui.GetFontPath) == "function" and type(db) == "table" and type(db.fonts) == "table" then
            local ok, file = pcall(eui.GetFontPath)
            if ok and type(file) == "string" and file ~= "" then return file end
        end
        if type(eui.EXPRESSWAY) == "string" and eui.EXPRESSWAY ~= "" then return eui.EXPRESSWAY end
    end
    local font = _G.GameFontNormal
    if type(font) == "table" and type(font.GetFont) == "function" then
        local ok, file = pcall(font.GetFont, font)
        if ok and type(file) == "string" and file ~= "" then return file end
    end
    return _G.STANDARD_TEXT_FONT
end

-- Schriftgroesse setzen; scheitert es (keine Schriftdatei), bleibt die Schrift der Vorlage
function UI.Font(fs, size)
    local file = UI.FontFile()
    if type(file) == "string" then pcall(fs.SetFont, fs, file, size, "") end
end

function UI.Paint(fs, role)
    fs:SetTextColor(UI.Color(role))
end

------------------------------------------------------------------------------
-- 02  Bausteine
------------------------------------------------------------------------------

-- Text in einer Rolle ("text" | "dim" | "faint" | "accent" | "good" | "bad" | "warn") und Groesse
function UI.Text(parent, size, role)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(fs, size or 12)
    UI.Paint(fs, role or "text")
    fs:SetJustifyH("LEFT")
    fs.role = role or "text"
    return fs
end

-- Einfarbige Flaeche ueber den ganzen Rahmen
function UI.Fill(frame, role, layer)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(UI.Color(role))
    return tex
end

-- Rand von einem Pixel an der Innenkante; Rueckgabe: die vier Linien
function UI.Border(frame, role)
    local lines = {}
    for i, def in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetPoint(def[1], frame, def[1], 0, 0)
        tex:SetPoint(def[2], frame, def[2], 0, 0)
        if def[3] then tex:SetHeight(1) else tex:SetWidth(1) end
        tex:SetColorTexture(UI.Color(role or "border"))
        lines[i] = tex
    end
    return lines
end

-- Flaeche mit Rand
function UI.Box(frame, fillRole, borderRole)
    frame.fill = UI.Fill(frame, fillRole or "card")
    frame.edge = UI.Border(frame, borderRole or "border")
    return frame
end

-- Waagerechte Trennlinie ueber die Breite von parent, y unter dessen Oberkante (negativ) oder ueber der Unterkante
function UI.Rule(parent, anchor, y)
    local tex = parent:CreateTexture(nil, "BORDER")
    tex:SetPoint(anchor .. "LEFT", parent, anchor .. "LEFT", 0, y)
    tex:SetPoint(anchor .. "RIGHT", parent, anchor .. "RIGHT", 0, y)
    tex:SetHeight(1)
    tex:SetColorTexture(UI.Color("line"))
    return tex
end

-- Flacher Knopf. SetText / GetText gelten dem eigenen Text; SetEnabled daempft ihn.
function UI.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 24)
    UI.Box(b, "card", "border")
    b.label = UI.Text(b, 12, "text")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetWordWrap(false)
    b.SetText = function(self, t) self.label:SetText(t) end
    b.GetText = function(self) return self.label:GetText() end
    local setEnabled = b.SetEnabled
    b.SetEnabled = function(self, on)
        setEnabled(self, on and true or false)
        UI.Paint(self.label, on and "text" or "faint")
        -- ein Knopf, der sich unter der Maus abschaltet, bekommt kein OnLeave mehr: die Hervorhebung jetzt zuruecknehmen
        self.fill:SetColorTexture(UI.Color("card"))
    end
    b:SetText(text or "")
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.fill:SetColorTexture(UI.Color("hover")) end
    end)
    b:SetScript("OnLeave", function(self) self.fill:SetColorTexture(UI.Color("card")) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Reiter: Text mit Unterstrich in der Akzentfarbe, wenn gewaehlt
function UI.Tab(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(60, 22)
    b.label = UI.Text(b, 12, "dim")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.line:SetHeight(2)
    b.line:Hide()
    b.SetText = function(self, t)
        self.label:SetText(t)
        self:SetWidth(mmax(40, (self.label:GetStringWidth() or 0) + 16))
    end
    b.GetText = function(self) return self.label:GetText() end
    b.SetSelected = function(self, on)
        self.selected = on and true or false
        UI.Paint(self.label, on and "text" or "dim")
        self.line:SetColorTexture(UI.Color("accent"))
        self.line:SetShown(self.selected)
    end
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

--[[ Gegenstandssymbol: beschnittenes Bild in einem Rahmen von einem Pixel, der die Farbe der Qualitaet annimmt.
     kind: "Button" (anklickbar, Standard) oder "Frame".  :SetItem(Textur, r, g, b) - ohne Textur leer.          ]]
function UI.Icon(parent, size, kind)
    local f = CreateFrame(kind or "Button", nil, parent)
    f:SetSize(size, size)
    f.ring = UI.Fill(f, "border", "BACKGROUND")
    f.well = f:CreateTexture(nil, "BORDER")
    f.well:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.well:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.well:SetColorTexture(0, 0, 0, 0.45)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)       -- ohne den Rahmen, den die Symbole des Spiels mitbringen
    f.icon:Hide()
    f.SetItem = function(self, texture, r, g, b)
        if texture then
            self.icon:SetTexture(texture)
            self.icon:Show()
            self.ring:SetColorTexture(r or 1, g or 1, b or 1, 1)
        else
            self.icon:Hide()
            self.ring:SetColorTexture(UI.Color("border"))
        end
        self.texture = texture
    end
    return f
end

------------------------------------------------------------------------------
-- 03  Fenster
------------------------------------------------------------------------------

UI.HEADER, UI.FOOTER, UI.PAD = 46, 44, 12

--[[ Ein Fenster: Flaeche mit Rand, oben eine Linie in der Akzentfarbe, Kopf mit Titel und Untertitel, Schliessen-Knopf,
     Rumpf (f.body) und Fuss (f.footer, fuer Knoepfe). Verschiebbar; Escape schliesst es (UISpecialFrames).
     f.accents: was die Akzentfarbe traegt - UI.Refresh(f) faerbt es neu (beim Zeigen: das Thema kann gewechselt haben). ]]
function UI.Window(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)                 -- ein Klick holt das Fenster vor die anderen seiner Ebene
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    UI.Box(f, "bg", "border")

    f.accentLine = f:CreateTexture(nil, "ARTWORK")
    f.accentLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.accentLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.accentLine:SetHeight(2)

    f.title = UI.Text(f, 18, "accent")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", UI.PAD + 2, -14)
    f.title:SetText(title or "")
    f.subtitle = UI.Text(f, 12, "dim")
    f.subtitle:SetPoint("BOTTOMLEFT", f.title, "BOTTOMRIGHT", 10, 1)

    f.close = UI.Button(f, "x", 24, 24, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -11)

    f.headerLine = UI.Rule(f, "TOP", -UI.HEADER)
    f.footerLine = UI.Rule(f, "BOTTOM", UI.FOOTER)

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", UI.PAD, -(UI.HEADER + UI.PAD))
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -UI.PAD, UI.FOOTER + UI.PAD)
    f.footer = CreateFrame("Frame", nil, f)
    f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", UI.PAD, 0)
    f.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -UI.PAD, 0)
    f.footer:SetHeight(UI.FOOTER)

    f.accents = { f.accentLine }
    f.accentText = { f.title }
    UI.Refresh(f)
    f:Hide()
    if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
    return f
end

-- Die Akzentfarbe eines Fensters neu auftragen
function UI.Refresh(f)
    for _, tex in ipairs(f.accents or {}) do tex:SetColorTexture(UI.Color("accent")) end
    for _, fs in ipairs(f.accentText or {}) do UI.Paint(fs, "accent") end
end

-- Knoepfe nebeneinander in den Fuss eines Fensters setzen, von links
function UI.FooterButton(f, text, width, onClick)
    local b = UI.Button(f.footer, text, width, 24, onClick)
    local x = f.footerX or 0
    b:SetPoint("LEFT", f.footer, "LEFT", x, 0)
    f.footerX = x + width + 8
    return b
end
