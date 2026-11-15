-- UI.lua: the kit the windows and the notification are built from, and what the windows make of it
return function(T)
    local F = require("fixtures")

    local function world(setup)
        return T.world(F.arms(), function(W)
            W.I = F.armsWarrior(W)
            W.I.better = F.gear(W, 9601, "Better Chestplate", "INVTYPE_CHEST", 40, { STR = 30, STA = 40, CRIT = 20 }, { armor = 500, minLevel = 35, quality = 4 })
            W.I.weak = F.gear(W, 9602, "Weak Chestplate", "INVTYPE_CHEST", 10, { STR = 1 })
            W.I.ring = F.gear(W, 9603, "Good Ring", "INVTYPE_FINGER", 40, { STR = 20, HIT = 15 }, { typeText = "" })
            if setup then setup(W) end
        end)
    end
    local function rgba(t) return t[1], t[2], t[3], t[4] end

    ------------------------------------------------------------------ colors and font
    T.test("ui: the accent is EasyGear's own blue, the font the game's - until EllesmereUI is there", function()
        local W = world()
        local UI = W.EG.UI
        local r, g, b, a = UI.Color("accent")
        T.near(r, 0.20) T.near(g, 0.72) T.eq(b, 1) T.eq(a, 1)
        T.eq(UI.FontFile(), "Fonts\\FRIZQT__.TTF", "the file of the game's standard font")
        T.eq(select(4, UI.Color("accent", 0.16)), 0.16, "an accent that only tints")
        local dr, dg, db, da = UI.Color("dim")
        T.eq(dr, 1) T.eq(dg, 1) T.eq(db, 1) T.near(da, 0.62, 1e-9, "dimmed text is white with less opacity, like EllesmereUI's")
        T.eq(select(1, UI.Color("no such role")), 1, "an unknown role is plain text")
        T.eq(select(4, UI.Color("bg")) < 1, true, "the window surface lets a little of the world through")
    end)

    T.test("ui: with EllesmereUI its accent color and its font are taken - and a changed theme is followed", function()
        local W = world(function(w)
            w.env.EllesmereUI = { ELLESMERE_GREEN = { r = 0.88, g = 0.66, b = 0.51 }, EXPRESSWAY = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf" }
        end)
        local UI = W.EG.UI
        local r, g, b = UI.Color("accent")
        T.eq(r, 0.88) T.eq(g, 0.66) T.eq(b, 0.51)
        T.has(UI.FontFile(), "Expressway")
        W.EG.Window.Open()
        local f = W.env.EasyGearWindow
        T.eq(f.accentLine.__color[1], 0.88, "the line at the top of the window") T.eq(f.title.__textColor[1], 0.88, "the title")
        T.has(f.title.__fontFile, "Expressway") T.eq(f.title.__fontSize, 18)
        W.env.EllesmereUI.ELLESMERE_GREEN.r = 0.10            -- the user picks another theme: the table is changed in place
        f:Hide() W.EG.Window.Open()
        T.eq(f.accentLine.__color[1], 0.10, "followed the next time the window shows") T.eq(f.title.__textColor[1], 0.10)

        -- a broken accent table or font path falls back instead of breaking
        local V = world(function(w) w.env.EllesmereUI = { ELLESMERE_GREEN = { r = "red" }, EXPRESSWAY = "" } end)
        T.near(select(1, V.EG.UI.Color("accent")), 0.20) T.eq(V.EG.UI.FontFile(), "Fonts\\FRIZQT__.TTF")
        V.env.GameFontNormal = nil
        T.eq(V.EG.UI.FontFile(), "Fonts\\FRIZQT__.TTF", "STANDARD_TEXT_FONT when even the font object is missing")
    end)

    ------------------------------------------------------------------ building blocks
    T.test("ui: a button is flat, lights up under the mouse and dims its text when disabled", function()
        local W = world()
        local UI = W.EG.UI
        local clicks = 0
        local b = UI.Button(W.env.UIParent, "Go", 120, nil, function() clicks = clicks + 1 end)
        T.eq(b.__template, nil) T.eq(b:GetWidth(), 120) T.eq(b:GetHeight(), 24)
        T.eq(b:GetText(), "Go") T.eq(b.label:GetText(), "Go")
        T.near(b.fill.__color[4], 0.04, 1e-9) T.eq(#b.edge, 4, "a one pixel border of four lines")
        b.__scripts.OnEnter(b)
        T.near(b.fill.__color[4], 0.09, 1e-9, "lit")
        b.__scripts.OnLeave(b)
        T.near(b.fill.__color[4], 0.04, 1e-9)
        b:SetEnabled(false)
        T.eq(b:IsEnabled(), false) T.near(b.label.__textColor[4], 0.42, 1e-9, "dimmed")
        b.__scripts.OnEnter(b)
        T.near(b.fill.__color[4], 0.04, 1e-9, "a disabled button does not light up")
        b:SetEnabled(true)
        T.eq(b.label.__textColor[4], 1)
        b.__scripts.OnClick(b)
        T.eq(clicks, 1)
        b:SetText("Stop")
        T.eq(b.label:GetText(), "Stop")
        -- a button that switches itself off under the mouse (it gets no OnLeave any more) does not stay lit
        b.__scripts.OnEnter(b)
        T.near(b.fill.__color[4], 0.09, 1e-9)
        b:SetEnabled(false)
        T.near(b.fill.__color[4], 0.04, 1e-9, "the light goes with the switching off")
        b.__scripts.OnEnter(b)
        b:SetEnabled(true)
        T.near(b.fill.__color[4], 0.04, 1e-9, "switching on does not light it")
    end)

    T.test("ui: the font is the one chosen in EllesmereUI - asked only when its fonts are set up, never on clients with a script of their own", function()
        local asked = 0
        local function eui(path)
            return { EXPRESSWAY = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf",
                     GetFontPath = function(key)
                         asked = asked + 1
                         assert(key == nil, "the global font: no module key")
                         if path == "error" then error("fonts not ready") end
                         return path
                     end }
        end
        local W = world(function(w)
            w.env.EllesmereUI = eui("Interface\\AddOns\\SharedMedia\\fonts\\Chosen.ttf")
            w.env.EllesmereUIDB = { fonts = { global = "Chosen" } }
        end)
        T.has(W.EG.UI.FontFile(), "Chosen", "the font picked under Fonts in EllesmereUI")
        T.ok(asked > 0)
        local fs = W.EG.UI.Text(W.env.UIParent, 12, "text")
        T.has(select(1, fs:GetFont()), "Chosen", "and it is what the texts are set in")

        -- EllesmereUI has not set its fonts up yet (asking would make it create them): its standard font, without asking
        asked = 0
        local early = world(function(w) w.env.EllesmereUI = eui("Interface\\Chosen.ttf") end)
        T.has(early.EG.UI.FontFile(), "Expressway") T.eq(asked, 0, "not asked")
        early.env.EllesmereUIDB = { profiles = {} }
        T.has(early.EG.UI.FontFile(), "Expressway") T.eq(asked, 0, "a database without fonts: not asked either")
        T.eq(early.env.EllesmereUIDB.fonts, nil, "and nothing was created in it")

        -- the question fails or answers nonsense: the standard font
        for _, answer in ipairs({ "error", "", 17 }) do
            local V = world(function(w)
                w.env.EllesmereUI = eui(answer)
                w.env.EllesmereUIDB = { fonts = {} }
            end)
            T.has(V.EG.UI.FontFile(), "Expressway", "answer " .. tostring(answer))
            T.eq(V.EG.lastError, nil)
        end

        -- Korean, Chinese, Russian clients: item names come in the client's script, which EllesmereUI's fonts lack
        for _, locale in ipairs({ "koKR", "zhCN", "zhTW", "ruRU" }) do
            asked = 0
            local K = T.world(F.arms({ locale = locale }), function(w)
                w.env.EllesmereUI = eui("Interface\\Chosen.ttf")
                w.env.EllesmereUIDB = { fonts = { global = "Chosen" } }
            end)
            T.eq(K.EG.UI.FontFile(), "Fonts\\FRIZQT__.TTF", locale .. ": the game's own font")
            T.eq(asked, 0, locale)
        end
        local D = T.world(F.arms({ locale = "deDE" }), function(w)
            w.env.EllesmereUI = eui("Interface\\Chosen.ttf")
            w.env.EllesmereUIDB = { fonts = { global = "Chosen" } }
        end)
        T.has(D.EG.UI.FontFile(), "Chosen", "a Latin client follows EllesmereUI")
    end)

    T.test("ui: a tab is text with an underline in the accent color when chosen, as wide as its text", function()
        local W = world()
        local tab = W.EG.UI.Tab(W.env.UIParent, "Finger 1")
        T.eq(tab.line:IsShown(), false) T.near(tab.label.__textColor[4], 0.62, 1e-9)
        T.eq(tab:GetWidth(), 8 * 12 * 0.5 + 16, "the text plus 16")
        tab:SetSelected(true)
        T.eq(tab.line:IsShown(), true) T.near(tab.line.__color[2], 0.72) T.eq(tab.label.__textColor[4], 1)
        tab:SetSelected(false)
        T.eq(tab.line:IsShown(), false) T.eq(tab.selected, false)
        tab:SetText("x")
        T.eq(tab:GetWidth(), 40, "never narrower than 40")
    end)

    T.test("ui: an icon shows the picture inside a one pixel ring in the quality color, and an empty well without one", function()
        local W = world()
        local icon = W.EG.UI.Icon(W.env.UIParent, 40)
        T.eq(icon.icon:IsShown(), false, "empty")
        icon:SetItem(12345, 0.64, 0.21, 0.93)
        T.eq(icon.icon:GetTexture(), 12345) T.eq(icon.icon:IsShown(), true)
        T.eq(icon.ring.__color[1], 0.64) T.eq(icon.ring.__color[4], 1)
        local l, r = icon.icon:GetTexCoord()
        T.near(l, 0.08) T.near(r, 0.92, 1e-9, "the frame the game's icons carry is cut away")
        icon:SetItem(nil)
        T.eq(icon.icon:IsShown(), false) T.near(icon.ring.__color[4], 0.10, 1e-9, "the plain border again")
    end)

    T.test("ui: footer buttons sit side by side, eight pixels apart", function()
        local W = world()
        W.EG.Window.Open()
        local f = W.env.EasyGearWindow
        T.eq(select(4, f.btnClear:GetPoint(1)), 0)
        T.eq(select(4, f.btnChat:GetPoint(1)), 120 + 8)
        T.eq(select(4, f.btnProfiles:GetPoint(1)), 120 + 8 + 150 + 8)
        T.eq(f.btnChat:GetText(), W.EG.L.BTN_CHAT)
    end)

    ------------------------------------------------------------------ the comparison window
    T.test("window: behind each row a bar shows its share of the score - the largest contribution fills the row", function()
        local W = world()
        W.EG.Window.SetItem(W.I.better)
        local f = W.env.EasyGearWindow
        local rows = f.cand.rows
        local top, topIndex = 0, nil
        for i, row in ipairs(rows) do
            if row.share > top then top, topIndex = row.share, i end
        end
        T.eq(top, 1, "one row has the largest contribution")
        T.eq(rows[topIndex].bar:GetWidth(), 302, "its bar spans the card")
        T.eq(rows[topIndex].label:GetText(), "Strength", "30 points: the largest")
        local stamina
        for _, row in ipairs(rows) do if row.label:GetText() == "Stamina" then stamina = row end end
        local points, topPoints = tonumber(stamina.points:GetText()), tonumber(rows[topIndex].points:GetText())
        T.eq(points, 4) T.eq(topPoints, 30)
        T.near(stamina.share, 4 / 30, 1e-6, "the others in proportion")
        T.near(stamina.bar:GetWidth(), 302 * 4 / 30, 1e-6)
        T.eq(stamina.bar:IsShown(), true) T.near(stamina.bar.__color[4], 0.16, 1e-9, "a light bar in the accent color")
        T.eq(rows[15].bar:IsShown(), false, "an empty row has none") T.eq(rows[15].share, 0)
        T.ok(rows[2].stripe and not rows[1].stripe, "every second row is darker")
        W.EG.Window.Clear()
        for i, row in ipairs(rows) do T.eq(row.bar:IsShown(), false, "cleared: row " .. i) end
    end)

    T.test("window: the verdict and the bar beside it carry the color of the verdict", function()
        local W = world()
        local late = F.gear(W, 9610, "Late", "INVTYPE_CHEST", 90, { STR = 100 }, { minLevel = 65 })
        local tabard = F.gear(W, 9611, "Tabard", "INVTYPE_TABARD", 1, {})
        local f
        local function verdict(link)
            W.EG.Window.SetItem(link)
            f = W.env.EasyGearWindow
            return f.verdict.role, f.verdictBar.__color, f.verdict.__textColor
        end
        local role, bar, text = verdict(W.I.better)
        T.eq(role, "good") T.near(bar[1], 0.30) T.near(bar[2], 0.90) T.near(text[2], 0.90)
        role, bar = verdict(W.I.weak)
        T.eq(role, "bad") T.eq(bar[1], 1) T.near(bar[2], 0.38)
        role, bar = verdict(late)
        T.eq(role, "warn") T.near(bar[2], 0.80)
        role, bar = verdict(tabard)
        T.eq(role, "dim") T.near(bar[4], 0.62, 1e-9)
        local robe = F.gear(W, 9612, "Robe", "INVTYPE_CHEST", 90, { INT = 100 }, { badType = true, typeText = "Cloth" })
        role, bar = verdict(robe)
        T.eq(role, "bad") T.near(bar[2], 0.38, 1e-9, "not usable is red as well")
        W.EG.Window.Clear()
        T.near(f.verdictBar.__color[4], 0.07, 1e-9, "nothing to judge: the bar is a faint line")
        T.eq(f.verdictCaption:GetText(), W.EG.L.WIN_VERDICT)
    end)

    T.test("window: the tabs of a ring show which slot is on screen", function()
        local W = world()
        W.EG.Window.SetItem(W.I.ring)
        local f = W.env.EasyGearWindow
        T.eq(f.tab1.selected, true) T.eq(f.tab2.selected, false) T.eq(f.tab1.line:IsShown(), true)
        f.tab2.__scripts.OnClick(f.tab2)
        T.eq(f.tab1.selected, false) T.eq(f.tab2.selected, true) T.eq(f.tab2.line:IsShown(), true)
        T.eq(f.eq.name:GetText(), "Plain Ring")
    end)

    T.test("window: the item name takes the color of its quality, the icon's ring too; column titles stand over the table", function()
        local W = world()
        W.EG.Window.SetItem(W.I.better)
        local f = W.env.EasyGearWindow
        local qr, qg, qb = W.env.C_Item.GetItemQualityColor(4)
        T.eq(f.cand.name.__textColor[1], qr) T.eq(f.cand.name.__textColor[2], qg) T.eq(f.cand.name.__textColor[3], qb)
        T.eq(f.cand.button.ring.__color[1], qr) T.eq(f.cand.button.icon:GetTexture(), 100000 + 9601)
        local heads = {}
        for i, fs in ipairs(f.cand.heads) do heads[i] = fs:GetText() end
        T.eq(table.concat(heads, "|"), "ATTRIBUTE|VALUE|WEIGHT|POINTS")
        T.eq(f.cand.score.__textColor[2] > 0.7, true, "the score in the accent color")
        W.EG.Window.Clear()
        T.near(f.cand.name.__textColor[4], 0.62, 1e-9, "the hint is dimmed") T.eq(f.cand.button.icon:IsShown(), false)
    end)

    ------------------------------------------------------------------ the profile window
    T.test("profile window: more points than the other side are green, fewer red, the total in the accent color", function()
        local W = world()
        W.EG.ProfileWindow.Open()
        local f = W.env.EasyGearProfileWindow
        W.EG.ProfileWindow.Select("WARRIOR_PROT")
        local seen = {}
        for i = 1, 18 do
            local l, r = f.left.rows[i], f.right.rows[i]
            if l.points:GetText() ~= "" then
                local a, b = tonumber(l.points:GetText()), tonumber(r.points:GetText())
                if a > b then T.eq(l.points.role, "good", "row " .. i) T.eq(r.points.role, "bad", "row " .. i) seen.more = true
                elseif a < b then T.eq(l.points.role, "bad", "row " .. i) T.eq(r.points.role, "good", "row " .. i) seen.less = true
                else T.eq(l.points.role, "dim", "row " .. i) seen.same = true end
            end
        end
        T.ok(seen.more and seen.less, "the two profiles differ both ways")
        T.near(f.left.totalValue.__textColor[2], 0.72, 1e-9)
        T.ok(f.left.rows[2].stripe and not f.left.rows[1].stripe, "zebra rows here as well")
        T.eq(f.left.caption:GetText(), W.EG.L.P_CANDIDATE)
    end)

    T.test("profile window: the edit fields are dark wells with a border in the accent color", function()
        local W = world()
        W.EG.ProfileWindow.Open()
        local f = W.env.EasyGearProfileWindow
        W.EG.ProfileWindow.ToggleEdit()
        local eb = f.left.rows[2].edit
        T.eq(eb:IsShown(), true) T.eq(#eb.edge, 4) T.near(eb.edge[1].__color[2], 0.72)
        T.eq(f.right.rows[2].edit, nil, "the active side is not edited")
    end)
end
