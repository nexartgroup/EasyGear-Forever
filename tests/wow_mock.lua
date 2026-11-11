--[[ Minimal WoW Forever client for the unit tests.

     Mock.new(opts) builds a sandbox environment (a table used as the global environment of the addon
     files), fills it with the parts of the client the addon touches and returns a handle with helpers to
     load the addon, fire events, advance timers and read what the addon did.

     This is a model, not the client: it follows the call patterns and data shapes of the Forever UI source
     (Interface/AddOns 1.60.1) but nothing here proves the addon works in the game.                       ]]

local Mock = {}

local unpack = unpack or table.unpack
local sformat = string.format

------------------------------------------------------------------------------
-- Global strings of the client (English)
------------------------------------------------------------------------------

local GLOBAL_STRINGS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility", ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect", ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Ranged Attack Power",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "Feral Attack Power", ITEM_MOD_SPELL_POWER_SHORT = "Spell Power",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Spell Damage", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "Spell Penetration",
    ITEM_MOD_HIT_RATING_SHORT = "Hit Rating", ITEM_MOD_CRIT_RATING_SHORT = "Critical Strike",
    ITEM_MOD_HASTE_RATING_SHORT = "Haste", ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "Armor Penetration", ITEM_MOD_RESILIENCE_RATING_SHORT = "Resilience",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense", ITEM_MOD_DODGE_RATING_SHORT = "Dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "Parry", ITEM_MOD_BLOCK_RATING_SHORT = "Block Rating",
    ITEM_MOD_BLOCK_VALUE_SHORT = "Block Value", ITEM_MOD_POWER_REGEN0_SHORT = "Mana per 5 sec.",
    ITEM_MOD_HEALTH_SHORT = "Health", ITEM_MOD_MANA_SHORT = "Mana", RESISTANCE0_NAME = "Armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Damage Per Second",
    -- long forms ("Improves ... by %s.")
    ITEM_MOD_CRIT_RATING = "Improves critical strike rating by %s.",
    ITEM_MOD_HASTE_RATING = "Improves haste rating by %s.",
    ITEM_MOD_HIT_RATING = "Improves hit rating by %s.",
    ITEM_MOD_ATTACK_POWER = "+%s Attack Power",
    ITEM_MOD_SPELL_POWER = "Increases spell power by %s.",
    ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:", ITEM_SPELL_TRIGGER_ONUSE = "Use:", ITEM_SPELL_TRIGGER_ONPROC = "Chance on hit:",
    ITEM_MIN_LEVEL = "Requires Level %d", DPS_TEMPLATE = "(%s damage per second)",
    ITEM_SOCKET_BONUS = "Socket Bonus: %s", ENCHANTED_TOOLTIP_LINE = "Enchanted: %s",
    ITEM_UNIQUE = "Unique", ITEM_UNIQUE_EQUIPPABLE = "Unique-Equipped", SPELL_STATALL = "All Stats",
    ITEM_CLASSES_ALLOWED = "Classes: %s",
    HEADSLOT = "Head", NECKSLOT = "Neck", SHOULDERSLOT = "Shoulder", SHIRTSLOT = "Shirt", CHESTSLOT = "Chest",
    WAISTSLOT = "Waist", LEGSSLOT = "Legs", FEETSLOT = "Feet", WRISTSLOT = "Wrist", HANDSSLOT = "Hands",
    FINGER0SLOT = "Finger", FINGER1SLOT = "Finger", TRINKET0SLOT = "Trinket", TRINKET1SLOT = "Trinket",
    BACKSLOT = "Back", MAINHANDSLOT = "Main Hand", SECONDARYHANDSLOT = "Off Hand", RANGEDSLOT = "Ranged",
    TABARDSLOT = "Tabard", ACCEPT = "Accept", CANCEL = "Cancel", YES = "Yes", NO = "No",
}

local TOOLTIP_LINE_TYPE = {
    None = 0, Blank = 1, UnitName = 2, GemSocket = 3, SellPrice = 11, ItemEnchantmentPermanent = 15,
    ItemBinding = 20, EquipSlot = 21, ItemName = 22, Separator = 23, GemSocketEnchantment = 30, ItemLevel = 31,
    ItemUpgradeLevel = 32, ItemQuality = 35, TradeTimeRemaining = 36, FlavorText = 37, ItemSpellTriggerLearn = 38,
    LearnTransmogSet = 39, LearnTransmogIllusion = 40, ErrorLine = 41, DisabledLine = 42, UsageRequirement = 43,
    ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46,
}
Mock.LINE = TOOLTIP_LINE_TYPE

local COLOR = {
    white = { r = 1, g = 1, b = 1 }, red = { r = 1, g = 0.125, b = 0.125 },
    grey = { r = 0.5, g = 0.5, b = 0.5 }, green = { r = 0, g = 1, b = 0 },
}
Mock.COLOR = COLOR

-- Templates and frame types that exist in the Forever UI (the rest raises like the client does)
local KNOWN_TEMPLATES = {
    ButtonFrameTemplate = true, UIPanelButtonTemplate = true, WowStyle1DropdownTemplate = true,
    BackdropTemplate = true,
}
local KNOWN_TYPES = {
    Frame = true, Button = true, EditBox = true, ItemButton = true, DropdownButton = true, GameTooltip = true,
    CheckButton = true, ScrollFrame = true, Slider = true,
}

------------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------------

local Region = {}
Region.__index = Region

local function newRegion(kind, name, parent)
    local r = setmetatable({}, Region)
    r.__kind, r.__name, r.__parent = kind, name, parent
    r.__shown = true
    r.__points = {}
    r.__scripts = {}
    r.__events = {}
    r.__children = {}
    r.__text = ""
    r.__id = 0
    r.__w, r.__h = 0, 0
    r.__enabled = true
    r.__alpha = 1
    r.__scale = 1
    r.__vertex = { 1, 1, 1, 1 }
    return r
end

function Region:GetName() return self.__name end
function Region:GetParent() return self.__parent end
function Region:GetObjectType() return self.__kind end
function Region:SetID(id) self.__id = id end
function Region:GetID() return self.__id end
function Region:Show() self.__shown = true if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function Region:Hide() local was = self.__shown self.__shown = false if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.__shown end
function Region:IsVisible()
    local f = self
    while f do
        if not f.__shown then return false end
        f = f.__parent
    end
    return true
end
function Region:SetSize(w, h) self.__w, self.__h = w, h end
function Region:SetWidth(w) self.__w = w end
function Region:SetHeight(h) self.__h = h end
function Region:GetWidth() return self.__w end
function Region:GetHeight() return self.__h end
function Region:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
    self.__points[#self.__points + 1] = { point, rel, relPoint, x or 0, y or 0 }
end
function Region:GetPoint(i)
    local p = self.__points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function Region:ClearAllPoints() self.__points = {} end
function Region:SetAllPoints() end
function Region:SetAlpha(a) self.__alpha = a end
function Region:SetScale(s) self.__scale = s end
function Region:GetScale() return self.__scale end
function Region:SetAtlas(a) self.__atlas = a self.__texture = nil self.__texcoord = { 0.25, 0.75, 0.25, 0.75 } end   -- an atlas shows a part of its file
function Region:GetAtlas() return self.__atlas end
function Region:SetTexture(t) self.__texture = t self.__atlas = nil end
function Region:GetTexture() return self.__texture end
function Region:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a } end
function Region:SetVertexColor(r, g, b, a)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetVertexColor: three numbers expected")
    self.__vertex = { r, g, b, a or 1 }
end
function Region:SetTexCoord(l, r, t, b) self.__texcoord = { l, r, t, b } end
function Region:GetTexCoord() local c = self.__texcoord or { 0, 1, 0, 1 } return c[1], c[2], c[3], c[4] end
function Region:SetDesaturated(v)
    assert(type(v) == "boolean", "SetDesaturated: a boolean expected, got " .. type(v))
    self.__desaturated = v
end
function Region:IsDesaturated() return self.__desaturated end
function Region:SetText(t) self.__text = t == nil and "" or t end
function Region:GetText() return self.__text end
function Region:SetFormattedText(fmt, ...) self.__text = sformat(fmt, ...) end
function Region:SetTextColor(r, g, b) self.__textColor = { r, g, b } end
function Region:SetJustifyH() end
function Region:SetJustifyV() end
function Region:SetWordWrap(v) self.__wordWrap = v and true or false end
function Region:SetFontObject(f) self.__font = f end
function Region:SetTextInsets() end
function Region:SetMaxLetters() end
function Region:SetAutoFocus() end
function Region:ClearFocus() end
function Region:HighlightText() self.__highlighted = true end
function Region:SetBlendMode() end
function Region:SetFrameStrata() end
function Region:SetFrameLevel(l) self.__level = l end
function Region:GetFrameLevel() return self.__level or 1 end
function Region:SetParent(p) self.__parent = p end
function Region:GetAlpha() return self.__alpha end
function Region:GetRegions()
    local out = {}
    for _, c in ipairs(self.__children) do out[#out + 1] = c end
    return unpack(out)
end
function Region:SetClampedToScreen() end
function Region:SetMovable() end
function Region:EnableMouse() end
function Region:EnableMouseWheel() end
function Region:RegisterForDrag() end
function Region:RegisterForClicks() end
function Region:StartMoving() self.__moving = true end
function Region:StopMovingOrSizing() self.__moving = false end
function Region:SetEnabled(v) self.__enabled = v and true or false end
function Region:IsEnabled() return self.__enabled end
function Region:Enable() self.__enabled = true end
function Region:Disable() self.__enabled = false end
function Region:SetBorder() end
function Region:SetPortraitShown() end
function Region:SetTitle(t) self.__title = t end
function Region:GetTitle() return self.__title end

function Region:SetScript(name, fn) self.__scripts[name] = fn end
function Region:GetScript(name) return self.__scripts[name] end
function Region:HookScript(name, fn)
    local old = self.__scripts[name]
    self.__scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Region:RegisterEvent(event) self.__events[event] = true end
function Region:UnregisterEvent(event) self.__events[event] = nil end

function Region:CreateTexture(name, layer)
    local t = newRegion("Texture", name, self)
    t.__layer = layer
    self.__children[#self.__children + 1] = t
    return t
end
function Region:CreateFontString(name, layer, template)
    local t = newRegion("FontString", name, self)
    t.__layer, t.__template = layer, template
    self.__children[#self.__children + 1] = t
    return t
end

-- Dropdown (WowStyle1DropdownTemplate): the generator builds a description that records its entries
local MenuDescription = {}
MenuDescription.__index = MenuDescription
function MenuDescription:CreateRadio(text, isSelected, setSelected, data)
    local e = { kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data }
    self.entries[#self.entries + 1] = e
    return e
end
function MenuDescription:CreateButton(text, callback)
    local e = { kind = "button", text = text, callback = callback }
    self.entries[#self.entries + 1] = e
    return e
end
function MenuDescription:CreateTitle(text)
    local e = { kind = "title", text = text }
    self.entries[#self.entries + 1] = e
    return e
end
function MenuDescription:CreateDivider() self.entries[#self.entries + 1] = { kind = "divider" } end
function MenuDescription:SetScrollMode(n) self.scroll = n end

function Region:GetEditBox() return self.__editBox end

local Dropdown = {}
function Dropdown.SetupMenu(self, generator) self.__generator = generator self:GenerateMenu() end
function Dropdown.GenerateMenu(self)
    if not self.__generator then return end
    local d = setmetatable({ entries = {} }, MenuDescription)
    self.__generator(self, d)
    self.__menu = d
    self.__menuBuilds = (self.__menuBuilds or 0) + 1
end
-- helper for tests: the text of the selected radio, like the client's selection text
function Dropdown.SelectedText(self)
    for _, e in ipairs(self.__menu and self.__menu.entries or {}) do
        if e.kind == "radio" and e.isSelected(e.data) then return e.text end
    end
end
-- helper for tests: choose the radio with this text
function Dropdown.ChooseRadio(self, text)
    for _, e in ipairs(self.__menu and self.__menu.entries or {}) do
        if e.kind == "radio" and e.text == text then e.setSelected(e.data) return true end
    end
    return false
end


-- Item buttons (intrinsic ItemButton)
local function makeItemButton(r)
    r.icon = newRegion("Texture", nil, r)
    r.IconBorder = newRegion("Texture", nil, r)
    r.Count = newRegion("FontString", nil, r)
    r.__isItemButton = true
    -- ItemButtonMixin has GetBagID/SetBagID for every item button
    function r:GetBagID() return self.bagID end
    function r:SetBagID(id) self.bagID = id end
end

------------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------------

local function makeTooltip(env, name)
    local t = newRegion("GameTooltip", name, nil)
    t.__lines = {}
    function t:SetOwner(owner, anchor) self.__owner = owner self.__anchor = anchor self.__lines = {} end
    function t:GetOwner() return self.__owner end
    function t:ClearLines() self.__lines = {} end
    function t:AddLine(text, r, g, b, wrap)
        self.__lines[#self.__lines + 1] = { left = text, color = { r, g, b }, wrap = wrap }
    end
    function t:AddDoubleLine(l, rr, lr, lg, lb, rrr, rg, rb)
        self.__lines[#self.__lines + 1] = { left = l, right = rr, color = { lr, lg, lb }, rightColor = { rrr, rg, rb } }
    end
    function t:NumLines() return #self.__lines end
    function t:Show() self.__shown = true end
    function t:Hide() self.__shown = false end
    function t:SetHyperlink(link) env.__showItem(self, link) end
    -- text of all lines, for assertions
    function t:Dump()
        local out = {}
        for _, l in ipairs(self.__lines) do
            out[#out + 1] = l.right and (tostring(l.left) .. " | " .. tostring(l.right)) or tostring(l.left)
        end
        return table.concat(out, "\n")
    end
    function t:HasLine(substr)
        for _, l in ipairs(self.__lines) do
            if (type(l.left) == "string" and l.left:find(substr, 1, true))
               or (type(l.right) == "string" and l.right:find(substr, 1, true)) then
                return true
            end
        end
        return false
    end
    return t
end

------------------------------------------------------------------------------
-- Sandbox
------------------------------------------------------------------------------

local function readFile(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local function tocFiles(addonDir)
    local files = {}
    for line in readFile(addonDir .. "/EasyGear.toc"):gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and not line:match("^%s*$") and not line:match("^##") then
            files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
        end
    end
    return files
end
Mock.tocFiles = tocFiles

--[[ opts:
       addonDir   path of the EasyGear folder (default "EasyGear")
       locale     client locale (default "enUS")
       strings    { GLOBAL = "text" } replaces Blizzard global strings (the item stat names of another language)
       class      class token (default "WARRIOR"), level (default 60), maxLevel (default 60)
       talents    { points = {a,b,c}, mode = "specinfo"|"traits"|"selected"|"none", roles = {...} }
       noTooltipProcessor, noSettings ... switches that remove a part of the client          ]]
function Mock.new(opts)
    opts = opts or {}
    local env = {}
    env._G = env
    setmetatable(env, { __index = _G })

    local self = { env = env, chat = {}, popups = {}, frames = {}, timers = {}, now = 0, items = {}, bags = {},
                   equipped = {}, loadRequests = {}, postCalls = {}, hooks = {}, settings = {}, opened = {},
                   cursor = nil, shift = false }
    env.__self = self

    local player = { class = opts.class or "WARRIOR", level = opts.level or 60, maxLevel = opts.maxLevel or 60,
                     classID = opts.classID or 1 }
    self.player = player

    ------------------------------------------------------------ plain globals
    for k, v in pairs(GLOBAL_STRINGS) do env[k] = v end
    for k, v in pairs(opts.strings or {}) do env[k] = v end      -- another client language's texts
    env.WOW_PROJECT_CAMELOT = 18
    env.WOW_PROJECT_ID = opts.notForever and 1 or 18
    env.LOCALIZED_CLASS_NAMES_MALE = {
        WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
        SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
    }
    env.LOCALIZED_CLASS_NAMES_FEMALE = {}
    for k, v in pairs(env.LOCALIZED_CLASS_NAMES_MALE) do env.LOCALIZED_CLASS_NAMES_FEMALE[k] = v end
    env.RAID_CLASS_COLORS = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
        PRIEST = { r = 1.00, g = 1.00, b = 1.00 }, SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
        MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
        DRUID = { r = 1.00, g = 0.49, b = 0.04 },
    }
    env.GetLocale = function() return opts.locale or "enUS" end
    env.GetBuildInfo = function() return "1.60.1", "70862", "Nov  7 2026", 16001 end
    env.GetTime = function() return self.now end
    env.UnitClass = function() return player.class:sub(1, 1) .. player.class:sub(2):lower(), player.class, player.classID end
    env.UnitLevel = function() return player.level end
    env.GetMaxPlayerLevel = function() return player.maxLevel end
    env.CanDualWield = function() return player.dualWield ~= false end
    env.IsShiftKeyDown = function() return self.shift end
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    self.addons = {}
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field) if field == "Version" then return "4.0.0-test" end end,
        IsAddOnLoaded = function(name) return self.addons[name] == true end,
    }

    env.Enum = {
        TooltipDataLineType = TOOLTIP_LINE_TYPE,
        TooltipDataType = { Item = 0 },
        TooltipDataUsageRequirementType = { Level = 5 },
        BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
                     CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, AccountBankTab_1 = 15 },
    }
    env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    env.NUM_BAG_SLOTS = 4
    env.NUM_REAGENTBAG_SLOTS = 1

    ------------------------------------------------------------ chat
    local chatFrame = newRegion("Frame", "DEFAULT_CHAT_FRAME", nil)
    chatFrame.AddMessage = function(_, text) self.chat[#self.chat + 1] = text end
    env.DEFAULT_CHAT_FRAME = chatFrame

    ------------------------------------------------------------ frames
    env.UIParent = newRegion("Frame", "UIParent", nil)
    env.CreateFrame = function(kind, name, parent, template)
        if not KNOWN_TYPES[kind] then error("CreateFrame: unknown frame type " .. tostring(kind), 2) end
        for tpl in tostring(template or ""):gmatch("[^,%s]+") do
            if not KNOWN_TEMPLATES[tpl] then
                error("CreateFrame: Couldn't find inherited node \"" .. tpl .. "\"", 2)
            end
        end
        local f = (kind == "GameTooltip") and makeTooltip(env, name) or newRegion(kind, name, parent or env.UIParent)
        f.__template = template
        if kind == "ItemButton" then
            makeItemButton(f)
            for k, v in pairs(env.ItemButtonMixin) do f[k] = v end      -- the engine copies the mixin when the frame is created
        end
        if template and template:find("ButtonFrameTemplate", 1, true) then
            f.Inset = newRegion("Frame", name and (name .. "Inset") or nil, f)
            f.TitleContainer = newRegion("Frame", nil, f)
            f.Bg = newRegion("Texture", nil, f)
        end
        if kind == "DropdownButton" then
            for k, v in pairs(Dropdown) do f[k] = v end
        end
        if kind == "EditBox" then f.__editBox = nil end
        if name then env[name] = f end
        self.frames[#self.frames + 1] = f
        return f
    end
    env.hooksecurefunc = function(a, b, c)
        local tbl, name, fn
        if type(a) == "string" then tbl, name, fn = env, a, b else tbl, name, fn = a, b, c end
        local orig = tbl[name]
        if type(orig) ~= "function" then error("hooksecurefunc: " .. tostring(name) .. " is not a function", 2) end
        tbl[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
        self.hooks[#self.hooks + 1] = name
    end

    ------------------------------------------------------------ timers
    env.C_Timer = {
        After = function(delay, fn)
            self.timers[#self.timers + 1] = { at = self.now + (delay or 0), fn = fn, seq = #self.timers + 1 }
        end,
    }

    ------------------------------------------------------------ cursor
    env.GetCursorInfo = function()
        if self.cursor then return "item", self.cursor.id, self.cursor.link end
    end
    env.ClearCursor = function() self.cursor = nil end

    ------------------------------------------------------------ item data
    local function itemFromAny(linkOrId)
        local id
        if type(linkOrId) == "number" then id = linkOrId
        elseif type(linkOrId) == "string" then id = tonumber(linkOrId:match("item:(%d+)")) end
        return id and self.items[id] or nil, id
    end
    self.itemFromAny = itemFromAny

    env.C_Item = {
        GetItemInfo = function(linkOrId)
            local it, id = itemFromAny(linkOrId)
            if not it then return nil end
            if it.uncached then return nil end
            return it.name, it.reportedLink or it.link, it.quality or 1, it.ilvl or 1, it.minLevel or 0, it.type or "Armor",
                   it.subType or "Plate", 1, it.equipLoc or "", it.texture or 100000 + id, it.sellPrice or 0,
                   it.classID or 4, it.subclassID or 0, 1
        end,
        GetItemInfoInstant = function(linkOrId)
            local it, id = itemFromAny(linkOrId)
            if not it then return nil end
            return id, it.type or "Armor", it.subType or "Plate", it.equipLoc or "", it.texture or 100000 + id,
                   it.classID or 4, it.subclassID or 0
        end,
        GetItemStats = function(link)
            local it = itemFromAny(link)
            if not it then return nil end
            local out = {}
            for k, v in pairs(it.stats or {}) do out[k] = v end
            if it.dps then out.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = it.dps end
            if it.sockets then out.EMPTY_SOCKET_RED = it.sockets end
            return out
        end,
        GetDetailedItemLevelInfo = function(link)
            local it = itemFromAny(link)
            if not it then return nil end
            return it.effectiveIlvl or it.ilvl or 1
        end,
        IsCosmeticItem = function(link)
            local it = itemFromAny(link)
            return it and it.cosmetic or false
        end,
        RequestLoadItemDataByID = function(id)
            self.loadRequests[#self.loadRequests + 1] = id
        end,
        GetItemQualityColor = function(q) return 1, 1, 1 end,
    }

    -- Tooltip data in the shape of C_TooltipInfo.GetHyperlink
    local function tooltipDataFor(it)
        local lines = {}
        local function add(l) lines[#lines + 1] = l end
        add({ type = TOOLTIP_LINE_TYPE.ItemName, leftText = it.name, leftColor = COLOR.white })
        add({ type = TOOLTIP_LINE_TYPE.ItemLevel, leftText = "Item Level " .. (it.ilvl or 1), leftColor = COLOR.white })
        if it.equipLoc and it.equipLoc ~= "" then
            add({ type = TOOLTIP_LINE_TYPE.EquipSlot, leftText = it.slotText or "Chest", rightText = it.typeText or "Plate",
                  leftColor = COLOR.white, rightColor = it.badType and COLOR.red or COLOR.white,
                  isValidItemType = not it.badType, isValidInvSlot = true })
        end
        if it.unique then add({ type = 0, leftText = it.unique == "equip" and "Unique-Equipped" or "Unique", leftColor = COLOR.white }) end
        if it.classes then
            local mine = self.player.class:sub(1, 1) .. self.player.class:sub(2):lower()
            add({ type = TOOLTIP_LINE_TYPE.UsageRequirement, requirementType = 0,
                  leftText = sformat(GLOBAL_STRINGS.ITEM_CLASSES_ALLOWED, it.classes),
                  leftColor = it.classes:find(mine, 1, true) and COLOR.white or COLOR.red })
        end
        if (it.minLevel or 0) > 0 then
            local red = (it.minLevel or 0) > (self.player.level or 1)
            add({ type = TOOLTIP_LINE_TYPE.UsageRequirement, requirementType = 5,
                  leftText = sformat(GLOBAL_STRINGS.ITEM_MIN_LEVEL, it.minLevel), leftColor = red and COLOR.red or COLOR.white })
        end
        if it.armor then add({ type = 0, leftText = it.armor .. " Armor", leftColor = COLOR.white }) end
        if it.dps then
            add({ type = 0, leftText = sformat("%.1f damage per second", it.dps), leftColor = COLOR.white })
            add({ type = 0, leftText = sformat(GLOBAL_STRINGS.DPS_TEMPLATE, sformat("%.1f", it.dps)), leftColor = COLOR.white })
        end
        for _, name in ipairs(it.statOrder or {}) do
            local v = (it.stats or {})[name]
            if v and GLOBAL_STRINGS[name] then
                add({ type = 0, leftText = sformat("+%d %s", v, GLOBAL_STRINGS[name]), leftColor = COLOR.white })
            end
        end
        for _, l in ipairs(it.lines or {}) do
            if type(l) == "string" then add({ type = 0, leftText = l, leftColor = COLOR.white })
            else add(l) end
        end
        return { type = 0, id = it.id, hyperlink = it.link, lines = lines }
    end

    env.C_TooltipInfo = {
        GetHyperlink = function(link)
            local it = itemFromAny(link)
            if not it or it.uncached or it.noTooltip then return nil end
            return tooltipDataFor(it)
        end,
        GetLootRollItem = function(rollID)
            local link = self.rolls and self.rolls[rollID]
            local it = link and itemFromAny(link)
            if not it then return nil end
            return tooltipDataFor(it)
        end,
        -- the tooltip of a bag item; a soulbound item that may still be traded carries the trade time line
        GetBagItem = function(bag, slot)
            local b = self.bags[bag]
            local link = b and b.items[slot]
            local it = link and itemFromAny(link)
            if not it then return nil end
            local data = tooltipDataFor(it)
            if b.trade and b.trade[slot] then
                data.lines[#data.lines + 1] = { type = TOOLTIP_LINE_TYPE.TradeTimeRemaining,
                                                leftText = "You may trade this item for the next 1 hour.", leftColor = COLOR.white }
            end
            return data
        end,
    }

    env.TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, fn)
            self.postCalls[#self.postCalls + 1] = { kind = kind, fn = fn }
        end,
    }
    env.TooltipUtil = {
        GetDisplayedItem = function(tooltip) return tooltip.__itemName, tooltip.__itemLink, tooltip.__itemId end,
    }

    -- the client builds the tooltip, then runs the post calls (before :Show)
    env.__showItem = function(tooltip, link, extra)
        local it = itemFromAny(link)
        tooltip.__itemLink = link
        tooltip.__itemName = it and it.name
        tooltip.__itemId = it and it.id
        local data = (it and not it.uncached) and tooltipDataFor(it) or { type = 0 }
        if extra then for k, v in pairs(extra) do data[k] = v end end
        if it then
            tooltip:AddLine(it.name, 1, 1, 1)
        end
        for _, pc in ipairs(self.postCalls) do
            if pc.kind == env.Enum.TooltipDataType.Item then pc.fn(tooltip, data) end
        end
        tooltip:Show()
    end

    env.GameTooltip = makeTooltip(env, "GameTooltip")
    env.ShoppingTooltip1 = makeTooltip(env, "ShoppingTooltip1")
    env.ShoppingTooltip1.isShopping = true
    env.ItemRefTooltip = makeTooltip(env, "ItemRefTooltip")

    ------------------------------------------------------------ containers and equipment
    env.C_Container = {
        GetContainerNumSlots = function(bag)
            local b = self.bags[bag]
            return b and b.size or 0
        end,
        GetContainerItemLink = function(bag, slot)
            local b = self.bags[bag]
            return b and b.items[slot] or nil
        end,
        GetContainerItemInfo = function(bag, slot)
            local b = self.bags[bag]
            local link = b and b.items[slot]
            if not link then return nil end
            local it = itemFromAny(link)
            return { hyperlink = link, itemID = it and it.id, quality = it and it.quality,
                     isBound = (b.bound and b.bound[slot]) and true or false }
        end,
    }
    env.GetInventoryItemLink = function(unit, slot)
        if unit ~= "player" then return nil end
        return self.equipped[slot]
    end

    ------------------------------------------------------------ talents
    -- copy: the tests change the points of one world and must not leak into the next
    local talents = {}
    for k, v in pairs(opts.talents or { points = { 0, 0, 0 }, mode = "specinfo" }) do talents[k] = v end
    talents.points = { unpack(talents.points or { 0, 0, 0 }) }
    if talents.roles then talents.roles = { unpack(talents.roles) } end
    self.talents = talents
    env.C_SpecializationInfo = {
        -- in Forever the count may be smaller than the number of trees; the addon must not rely on it
        GetNumSpecializationsForClassID = function() return talents.numSpecs or 3 end,
        GetSpecializationInfo = function(i)
            if talents.mode == "none" or i > 3 then return nil end
            local role = talents.roles and talents.roles[i] or "DAMAGER"
            -- only the mode "specinfo" fills the points; the other modes answer with zeros (the feared case)
            local spent = (talents.mode == "specinfo") and (talents.points[i] or 0) or 0
            return 100 + i, "Tree" .. i, "", 1, role, 1, spent
        end,
        GetSpecialization = function()
            if talents.mode ~= "selected" then return nil end
            return talents.selected or 0
        end,
        GetActiveSpecGroup = function() return 1 end,
        GetCombatConfigIDForSpecGroup = function() return 77 end,
    }
    env.C_Traits = {
        GetConfigInfo = function() return { treeIDs = { 5 } } end,
        GetGroupDisplayInfoByTreeID = function()
            if talents.mode ~= "traits" then return nil end
            -- the list order is the tree order the talent frame shows; orderIndex is deliberately out of line
            return { { groupID = 12, orderIndex = 3 }, { groupID = 13, orderIndex = 1 }, { groupID = 11, orderIndex = 2 } }
        end,
        GetGroupCurrencyInfo = function()
            if talents.mode ~= "traits" then return nil end
            -- tree 1 = group 12, tree 2 = group 13, tree 3 = group 11 (the list order above)
            return {
                { traitNodeGroupID = 12, currencyInfos = { { spent = talents.points[1] or 0 } } },
                { traitNodeGroupID = 13, currencyInfos = { { spent = talents.points[2] or 0 } } },
                { traitNodeGroupID = 11, currencyInfos = { { spent = talents.points[3] or 0 } } },
            }
        end,
    }

    ------------------------------------------------------------ textures and misc
    env.C_Texture = {
        GetAtlasInfo = function(name)
            if opts.noAtlas then return nil end
            if opts.missingAtlas and opts.missingAtlas[name] then return nil end
            return { width = 16, height = 16 }
        end,
    }
    env.C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "c" end }
    -- ItemButtonMixin: the methods of every ItemButton. The global functions hand over to the button's own method,
    -- so a caller that uses the method never passes through the global (this is what bag addons do).
    env.ItemButtonMixin = {}
    function env.ItemButtonMixin:SetItemButtonQuality(quality, itemIDOrLink)
        self.__quality, self.__qualityArg = quality, itemIDOrLink
    end
    function env.ItemButtonMixin:SetItemButtonTexture(texture)
        if self.icon then self.icon:SetTexture(texture) self.icon:SetShown(texture ~= nil) end
    end
    env.SetItemButtonTexture = function(button, texture)
        if button.SetItemButtonTexture then
            button:SetItemButtonTexture(texture)
        elseif button.icon then
            button.icon:SetTexture(texture) button.icon:SetShown(texture ~= nil)
        end
    end
    env.ButtonFrameTemplate_HidePortrait = function() end
    env.StaticPopup_Show = function(which, a1, a2, data)
        local dlg = newRegion("Frame", nil, nil)
        dlg.which, dlg.data = which, data
        local eb = newRegion("EditBox", nil, dlg)
        dlg.__editBox = eb
        self.popups[#self.popups + 1] = dlg
        return dlg
    end
    env.StaticPopup_ShowCustomGenericConfirmation = function(data)
        env.StaticPopup_Show("GENERIC_CONFIRMATION", nil, nil, data)
    end
    env.HandleModifiedItemClick = function(link) return false end

    ------------------------------------------------------------ settings API
    env.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
    local Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" } }
    env.Settings = Settings
    local nextCategory = 1
    local callbacks = {}
    local byVariable = {}
    local function makeSetting(cat, variable, name, default, vtype, getv, setv)
        local s = { variable = variable, name = name, default = default, vtype = vtype }
        function s:GetValue() return getv() end
        function s:SetValue(v)
            setv(v)
            for _, cb in ipairs(callbacks[variable] or {}) do cb(self, v) end
        end
        function s:SetValueChangedCallback(fn)
            callbacks[variable] = callbacks[variable] or {}
            table.insert(callbacks[variable], fn)
        end
        -- like SettingMixin:NotifyUpdate: the current value goes to every value-changed callback
        function s:NotifyUpdate()
            self.notified = (self.notified or 0) + 1
            local v = getv()
            for _, cb in ipairs(callbacks[variable] or {}) do cb(self, v) end
        end
        byVariable[variable] = s
        cat.settings[#cat.settings + 1] = s
        return s
    end
    Settings.RegisterVerticalLayoutCategory = function(name)
        local cat = { name = name, id = nextCategory, settings = {}, controls = {}, initializers = {} }
        nextCategory = nextCategory + 1
        function cat:GetID() return self.id end
        local layout = {}
        function layout:AddInitializer(init) cat.initializers[#cat.initializers + 1] = init end
        self.settings[#self.settings + 1] = cat
        return cat, layout
    end
    Settings.RegisterAddOnSetting = function(cat, variable, key, tbl, vtype, name, default)
        if tbl[key] == nil then tbl[key] = default end
        local s = makeSetting(cat, variable, name, default, vtype, function() return tbl[key] end, function(v) tbl[key] = v end)
        s.key, s.tbl = key, tbl
        return s
    end
    Settings.RegisterProxySetting = function(cat, variable, vtype, name, default, getv, setv)
        return makeSetting(cat, variable, name, default, vtype, getv, setv)
    end
    Settings.CreateSliderOptions = function(min, max, rate)
        local o = { minValue = min, maxValue = max, steps = (max - min) / rate }
        function o:SetLabelFormatter(kind, fn) self.formatter = fn end
        return o
    end
    Settings.CreateControlTextContainer = function()
        local c = { data = {} }
        function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
        function c:GetData() return self.data end
        return c
    end
    local function control(kind)
        return function(cat, setting, a, b)
            local init = { kind = kind, setting = setting }
            if kind == "slider" then init.options, init.tooltip = a, b elseif kind == "dropdown" then init.getOptions, init.tooltip = a, b else init.tooltip = a end
            cat.controls[#cat.controls + 1] = init
            cat.initializers[#cat.initializers + 1] = init
            return init
        end
    end
    Settings.CreateCheckbox = control("checkbox")
    Settings.CreateSlider = control("slider")
    Settings.CreateDropdown = control("dropdown")
    Settings.CreateColorSwatch = control("swatch")
    Settings.RegisterAddOnCategory = function(cat) cat.registered = true end
    Settings.OpenToCategory = function(id) self.opened[#self.opened + 1] = id end
    Settings.NotifyUpdate = function(variable)
        local s = byVariable[variable]
        if s then s:NotifyUpdate() end
    end
    -- the settings window: only an open page needs to hear about changes made elsewhere (tests set state.settingsOpen)
    env.SettingsPanel = { IsShown = function() return self.settingsOpen == true end }
    env.CreateSettingsListSectionHeaderInitializer = function(name) return { kind = "header", name = name } end
    env.CreateSettingsButtonInitializer = function(name, text, onClick, tip, search)
        assert(search ~= nil, "addSearchTags must be given")
        return { kind = "button", name = name, text = text, onClick = onClick, tooltip = tip }
    end
    self.settingByVariable = byVariable

    ------------------------------------------------------------ Blizzard UI functions the addon hooks
    env.SetItemButtonQuality = function(button, quality, itemIDOrLink, ...)
        if button.SetItemButtonQuality then
            button:SetItemButtonQuality(quality, itemIDOrLink, ...)
        else
            button.__quality, button.__qualityArg = quality, itemIDOrLink
        end
    end
    env.MerchantFrameItem_UpdateQuality = function(frame, link)
        frame.__merchantLink = link
    end
    -- ItemButtonTemplate.lua: the remaining stock of a vendor item; shows or hides the Stock text of the button
    env.SetItemButtonStock = function(button, numInStock)
        if not button then return end
        button.numInStock = numInStock or ""
        local stock = button.Stock
        if not stock then return end
        if (numInStock or 0) > 0 then stock:Show() else stock:Hide() end
    end
    env.GroupLootFrame_SetupItemDisplay = function(frame)
        if not frame.rollID then return false end
        return true
    end

    ------------------------------------------------------------ switches that remove parts of the client
    if opts.noTooltipProcessor then env.TooltipDataProcessor = nil end
    if opts.noSettings then env.Settings = nil end
    if opts.noColorSwatch and env.Settings then env.Settings.CreateColorSwatch = nil end
    if opts.noDropdown then
        local create = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            if kind == "DropdownButton" then error("unknown frame type DropdownButton", 2) end
            return create(kind, name, parent, template)
        end
    end

    -- Handles for the tests -------------------------------------------------
    local H = { env = env, state = self }

    function H.advance(dt)
        local target = self.now + dt
        while true do
            local best, bi
            for i, t in ipairs(self.timers) do
                if t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then best, bi = t, i end
            end
            if not best then break end
            table.remove(self.timers, bi)
            self.now = math.max(self.now, best.at)
            best.fn()
        end
        self.now = target
    end
    function H.flush() H.advance(5) end

    function H.fire(event, ...)
        for _, f in ipairs(self.frames) do
            if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
        end
    end

    -- Load the addon files in .toc order into the sandbox
    function H.load(dir)
        dir = dir or opts.addonDir or "EasyGear"
        local EGns = {}
        for _, file in ipairs(tocFiles(dir)) do
            local path = dir .. "/" .. file
            local chunk, err = loadfile(path)
            if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
            setfenv(chunk, env)
            chunk("EasyGear", EGns)
        end
        H.EG = env.EasyGear
        return H.EG
    end

    function H.boot()
        H.fire("ADDON_LOADED", "EasyGear")
        H.fire("PLAYER_LOGIN")
        H.flush()
        return H.EG
    end

    ------------------------------------------------------------ world building
    function H.item(def)
        def.id = def.id or (#self.items + 1)
        def.link = def.link or sformat("|cff1eff00|Hitem:%d::::::::60:::::|h[%s]|h|r", def.id, def.name)
        def.statOrder = def.statOrder or {}
        if def.stats and #def.statOrder == 0 then
            for k in pairs(def.stats) do def.statOrder[#def.statOrder + 1] = k end
            table.sort(def.statOrder)
        end
        self.items[def.id] = def
        return def.link, def
    end
    function H.equip(slot, link) self.equipped[slot] = link end
    function H.bag(bag, size, items)
        self.bags[bag] = { size = size, items = items or {} }
    end
    function H.put(bag, slot, link)
        self.bags[bag] = self.bags[bag] or { size = 16, items = {} }
        self.bags[bag].items[slot] = link
    end
    function H.chatText() return table.concat(self.chat, "\n") end
    function H.clearChat() self.chat = {} end
    function H.setLevel(l) player.level = l H.fire("PLAYER_LEVEL_UP", l) end
    function H.slash(msg) env.SlashCmdList["EASYGEAR"](msg) end
    function H.tooltipFor(owner, link, extraData)
        local tip = env.GameTooltip
        tip:SetOwner(owner, "ANCHOR_RIGHT")
        env.__showItem(tip, link, extraData)
        return tip
    end

    -- Quest reward choices as QuestInfo builds them: choices = { { link =, count =, usable = }, ... }
    function H.questRewards(choices, questLog)
        local buttons = {}
        for i = 1, #choices do
            local b = env.CreateFrame("ItemButton", "QuestInfoRewardsFrameQuestInfoItem" .. i, env.UIParent)
            b:SetID(i)
            b.type, b.objectType = "choice", "item"
            buttons[i] = b
        end
        env.QuestInfoFrame = { questLog = questLog and true or false, rewardsFrame = { RewardButtons = buttons } }
        local function link(kind, i) local c = choices[i] return kind == "choice" and c and c.link or nil end
        local function info(i)
            local c = choices[i]
            return "name", 1, c and c.count or 1, 1, not c or c.usable ~= false
        end
        env.GetQuestItemLink = link
        env.GetQuestLogItemLink = link
        env.GetQuestItemInfo = function(kind, i) return info(i) end
        env.GetQuestLogChoiceInfo = function(i) return info(i) end
        -- what Blizzard does when it shows the rewards
        function H.showRewards()
            for i, b in ipairs(buttons) do env.SetItemButtonQuality(b, 3, choices[i].link) end
            H.flush()
        end
        return buttons
    end

    -- Item buttons the way the Forever UI builds them --------------------------------------------------
    local function button(name, parent)
        local b = env.CreateFrame("ItemButton", name, parent or env.UIParent)
        return b
    end
    -- container item button (ContainerFrameItemButtonMixin): has UpdateNewItem, GetBagID, GetID
    function H.bagButton(bag, slot, name)
        local b = button(name)
        b:SetID(slot)
        b.bagID = bag
        b.UpdateNewItem = function() end
        return b
    end
    -- Camelot bank button (BankPanelItemButtonMixin)
    function H.bankButton(tab, slot)
        local b = button()
        b.GetBankTabID = function() return tab end
        b.GetContainerSlotID = function() return slot end
        return b
    end
    -- plain item button with a name (character slots, trade, mail, merchant)
    function H.namedButton(name, id)
        local b = button(name)
        if id then b:SetID(id) end
        return b
    end
    -- loot frame element: parent has GetSlotIndex and .Item
    function H.lootButton(slotIndex)
        local element = env.CreateFrame("Frame", nil, env.UIParent)
        element.GetSlotIndex = function() return slotIndex end
        local b = button(nil, element)
        element.Item = b
        return b, element
    end

    -- A bound item in a bag; with tradeWindow the item may still be traded (the loot trade time line is in its tooltip)
    function H.bind(bag, slot, tradeWindow)
        local b = self.bags[bag]
        b.bound = b.bound or {}
        b.trade = b.trade or {}
        b.bound[slot] = true
        b.trade[slot] = tradeWindow and true or nil
    end

    ------------------------------------------------------------ party, raid and inspecting
    --[[ A party or raid and the inspect machinery of the client, reduced to what the addon touches (Blizzard_InspectUI):
         unit tokens with guid, name, class and level; CanInspect, CheckInteractDistance, NotifyInspect and the event
         INSPECT_READY(guid) that follows a request after a short latency - only for a member who is connected, visible
         and within 28 yards. While the client holds the data of a member (he was inspected last), his equipment can
         be read with GetInventoryItemLink(unit, slot) and his specialization with GetInspectSpecialization(unit).
         member def: name, class, level, distance, connected, visible, gear = { [slot] = link }, tab (talent tree 1..3) ]]
    local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9,
                        DRUID = 11 }
    function H.installGroup()
        local G = { members = {}, notified = {}, raid = false, combat = false, lockdown = false, inspectFrameShown = false,
                    talentInspect = false, latency = 0.3, answers = true, failNotify = false, inspectedGUID = nil,
                    unreadable = {} }
        local counter = 0

        function G.add(unit, def)
            def = def or {}
            counter = counter + 1
            local class = def.class or "PRIEST"
            local m = {
                unit = unit, guid = def.guid or ("Player-1-" .. counter), name = def.name or ("Member" .. counter),
                class = class, classID = CLASS_IDS[class], level = def.level or 60, connected = def.connected ~= false,
                visible = def.visible ~= false, distance = def.distance or 10, gear = def.gear or {}, tab = def.tab,
                className = def.className, isPlayer = def.isPlayer, npc = def.npc, inspectable = def.inspectable,
            }
            G.members[unit] = m
            return m
        end
        function G.remove(unit) G.members[unit] = nil end
        function G.setRaid(on) G.raid = on and true or false end
        function G.rosterChanged() H.fire("GROUP_ROSTER_UPDATE") end
        function G.gearChanged(unit) H.fire("UNIT_INVENTORY_CHANGED", unit) end
        function G.levelChanged(unit) H.fire("UNIT_LEVEL", unit) end
        -- somebody inspects a member by hand (the player, or another addon): the client answers like it does for a request
        function G.inspectByHand(unit)
            local m = G.members[unit]
            G.inspectedGUID = m.guid
            H.fire("INSPECT_READY", m.guid)
        end
        function G.requests(unit)
            local n = 0
            for _, r in ipairs(G.notified) do if unit == nil or r.unit == unit then n = n + 1 end end
            return n
        end

        local function count()
            local n = 0
            for _ in pairs(G.members) do n = n + 1 end
            return n
        end
        env.IsInGroup = function() return next(G.members) ~= nil end
        env.IsInRaid = function() return G.raid end
        env.GetNumGroupMembers = function()
            if G.raid then
                local top = 0
                for unit in pairs(G.members) do
                    local i = tonumber(unit:match("^raid(%d+)$"))
                    if i and i > top then top = i end
                end
                return top
            end
            return count() + 1
        end
        env.UnitExists = function(unit) return unit == "player" or G.members[unit] ~= nil end
        env.UnitIsUnit = function(a, b)
            if a == b then return true end
            local ma, mb = G.members[a], G.members[b]
            if a == "player" and mb and mb.isPlayer then return true end
            if b == "player" and ma and ma.isPlayer then return true end
            return false
        end
        env.UnitIsPlayer = function(unit)
            local m = G.members[unit]
            return unit == "player" or (m ~= nil and not m.npc)
        end
        env.UnitGUID = function(unit)
            local m = G.members[unit]
            if unit == "player" or (m and m.isPlayer) then return "Player-1-PLAYER" end
            return m and m.guid or nil
        end
        env.UnitName = function(unit)
            local m = G.members[unit]
            if m then return m.name end
            return "Player"
        end
        local baseClass, baseLevel = env.UnitClass, env.UnitLevel
        env.UnitClass = function(unit)
            local m = G.members[unit]
            if unit == "player" or not m or m.isPlayer then return baseClass() end
            return m.className or (m.class:sub(1, 1) .. m.class:sub(2):lower()), m.class, m.classID
        end
        env.UnitLevel = function(unit)
            local m = G.members[unit]
            if unit == "player" or not m or m.isPlayer then return baseLevel() end
            return m.level
        end
        env.UnitIsConnected = function(unit) local m = G.members[unit] return m == nil or m.connected end
        env.UnitIsVisible = function(unit) local m = G.members[unit] return m == nil or m.visible end
        env.CanInspect = function(unit) local m = G.members[unit] return m ~= nil and m.inspectable ~= false end
        env.CheckInteractDistance = function(unit, index)
            local m = G.members[unit]
            return m ~= nil and index == 1 and m.distance <= 28
        end
        env.InCombatLockdown = function() return G.lockdown end          -- the two differ in the client: the lockdown
        env.UnitAffectingCombat = function() return G.combat end         -- of the interface and the state of the unit
        env.InspectFrame = { IsShown = function() return G.inspectFrameShown end }
        env.PlayerSpellsFrame = { IsInspecting = function() return G.talentInspect end }
        env.NotifyInspect = function(unit)
            if G.failNotify then error("NotifyInspect failed") end
            local m = G.members[unit]
            -- what the world looked like when the request was made (the fuzz test checks the manners of the addon)
            G.notified[#G.notified + 1] = { unit = unit, at = self.now, combat = G.combat, lockdown = G.lockdown,
                                            frame = G.inspectFrameShown, talents = G.talentInspect,
                                            distance = m and m.distance, connected = m and m.connected,
                                            visible = m and m.visible, inspectable = m and m.inspectable }
            if not (m and m.connected and m.visible and m.distance <= 28 and G.answers) then return end
            env.C_Timer.After(G.latency, function()
                -- staleReply: the client still holds the data of somebody else (it drops requests when flooded)
                G.inspectedGUID = G.staleReply and "Player-1-SOMEBODY-ELSE" or m.guid
                H.fire("INSPECT_READY", m.guid)
                -- echoEvent: reading the equipment of a unit makes the client announce a change of it (the item data arrive)
                if G.echoEvent then
                    env.C_Timer.After(0.5, function() H.fire("UNIT_INVENTORY_CHANGED", unit) end)
                end
            end)
        end

        local baseLink = env.GetInventoryItemLink
        env.GetInventoryItemLink = function(unit, slot)
            if unit == "player" then return baseLink(unit, slot) end
            local m = G.members[unit]
            if m and G.inspectedGUID == m.guid and not G.unreadable[slot] then return m.gear[slot] end
            return nil
        end
        env.GetInventoryItemID = function(unit, slot)
            local m = G.members[unit]
            local link = m and G.inspectedGUID == m.guid and m.gear[slot]
            return link and tonumber(tostring(link):match("item:(%d+)")) or nil
        end
        -- specs: "same" = one number for all trees, "few" = only the first tree is known
        env.GetSpecializationInfoForClassID = function(classID, index)
            if not classID or index < 1 or index > 3 then return nil end
            if G.specs == "same" then return 1000 * classID + 3, "Tree3" end         -- (the tests use members of tree 3)
            if G.specs == "few" and index > 1 then return nil end
            return 1000 * classID + index, "Tree" .. index
        end
        env.C_SpecializationInfo.GetInspectSpecialization = function(unit)
            local m = G.members[unit]
            if not (m and G.inspectedGUID == m.guid and m.tab) then return 0 end
            return 1000 * m.classID + m.tab
        end
        return G
    end

    ------------------------------------------------------------ other addons (models for the compatibility tests)
    --[[ Baganator, reduced to what its public interface promises (API/Main.lua of release 834): corner widgets - the game
         calls onInit once per button and onUpdate on every refresh, the first widget of a corner list that answers true
         is shown, nil means "item information not available yet" -, an upgrade source and refresh requests. A button is
         a container item button that carries its details (BGR), its widget container and its corner widgets, and it
         sets the quality through the METHOD of the button, never through the global function.                     ]]
    function H.installBaganator(options)
        options = options or {}
        local B = { API = {}, Constants = { RefreshReason = { ItemWidgets = "item_widgets", Searches = "searches" } } }
        local model = { widgets = {}, plugins = {}, refreshes = {}, corners = {}, buttons = {}, B = B }

        function B.API.RegisterCornerWidget(label, id, onUpdate, onInit, defaultPosition, isFast)
            if options.broken then error("assertion failed!") end
            assert(id and label and onUpdate and onInit and not model.widgets[id])
            model.widgets[id] = { label = label, onUpdate = onUpdate, onInit = onInit, isFast = isFast or false }
            if defaultPosition and type(defaultPosition.corner) == "string" and type(defaultPosition.priority) == "number" then
                model.corners[id] = defaultPosition.corner          -- automatic insertion into the user's corner list
            end
        end
        function B.API.IsCornerWidgetActive(id) return model.corners[id] ~= nil end
        function B.API.GetCurrentCornerForWidget(id) return model.corners[id] end
        function B.API.RegisterUpgradePlugin(label, id, callback)
            assert(type(label) == "string" and type(id) == "string" and type(callback) == "function")
            model.plugins[id] = { label = label, callback = callback }
            if model.upgradePlugin == nil then model.upgradePlugin = id end      -- the first plugin selects itself
        end
        function B.API.IsUpgradePluginActive(id) return model.upgradePlugin == id end
        function B.API.RequestItemButtonsRefresh(reasons) model.refreshes[#model.refreshes + 1] = reasons or "all" end

        if options.noWidgetAPI then B.API.RegisterCornerWidget = nil end
        env.Baganator = B
        self.addons.Baganator = true
        -- Baganator needs Syndicator: without it the game reports an error at start and applies nothing (Core/Initialize.lua)
        if not options.noSyndicator then
            env.Syndicator = { API = {} }
            self.addons.Syndicator = true
        end

        function model.button(parent)
            local b = env.CreateFrame("ItemButton", nil, parent or env.UIParent)
            b.UpdateNewItem = function() end
            b.widgetContainer = env.CreateFrame("Frame", nil, b)
            b.cornerPlugins = {}
            for id, w in pairs(model.widgets) do
                local widget = w.onInit(b)
                if widget then
                    widget:SetParent(b.widgetContainer)
                    widget:Hide()
                    b.cornerPlugins[id] = widget
                end
            end
            model.buttons[#model.buttons + 1] = b
            return b
        end
        -- one refresh of a button. Returns the id of the widget that is shown (the first one of the corner list that says yes)
        function model.update(b, link, details)
            b.BGR = { itemLink = link }
            for k, v in pairs(details or {}) do b.BGR[k] = v end
            b:SetItemButtonQuality(1, link, false, false)
            for _, widget in pairs(b.cornerPlugins) do widget:Hide() end
            local shownBy, pending = nil, false
            for id in pairs(model.corners) do
                local widget = b.cornerPlugins[id]
                if widget then
                    local show = model.widgets[id].onUpdate(widget, b.BGR)
                    if show == nil then pending = true
                    elseif show then widget:Show() shownBy = id break end
                end
            end
            b.__pending = pending
            return shownBy
        end
        -- what the active upgrade source says (Baganator wraps the call in pcall)
        function model.isUpgrade(link)
            local plugin = model.upgradePlugin and model.plugins[model.upgradePlugin]
            if not plugin then return false end
            local ok, result = pcall(plugin.callback, link)
            return ok and result == true, ok and result
        end
        return model
    end

    --[[ EllesmereUI Bags as EllesmereUIBags_Grid.lua builds its slots: a plain frame whose ID is the bag, an ItemButton from the
         container template inside it, a text overlay with the item level at the top left. A filled slot gets its icon and
         SetItemButtonQuality AS A METHOD (the hooks on the global function never see it); an empty slot only loses its
         texture. At the end of every paint - empty slots included - the module runs the painters that other addons
         registered with EUI_Bags.RegisterItemOverlayIcon(name, fn(btn, data)), data = { bag, slot, info, itemLink }.
         The window skin fades every direct texture region of a frame it has registered.                              ]]
    function H.installEllesmere(options)
        options = options or {}
        env.EllesmereUI = { IS_FOREVER = true }
        self.addons.EllesmereUI = true
        self.addons.EllesmereUIBags = not options.noBags
        local model = { overlayErrors = {} }
        if not options.noBags then
            local bags = { itemOverlayIcons = {} }
            if not options.noOverlayAPI then
                function bags.RegisterItemOverlayIcon(name, updateFn) bags.itemOverlayIcons[name] = updateFn end
                function bags.UnregisterItemOverlayIcon(name) bags.itemOverlayIcons[name] = nil end
            end
            function bags.RunItemOverlays(btn, data)
                for _, fn in pairs(bags.itemOverlayIcons) do
                    local ok, err = pcall(fn, btn, data)          -- securecallfunction: a painter never stops the render
                    if not ok then model.overlayErrors[#model.overlayErrors + 1] = tostring(err) end
                end
            end
            env.EUI_Bags = bags
            model.bags = bags
        end
        --[[ A grid slot (asRow = nil) has its text overlay over the whole slot and the item level on it; a row of the list view
             (asRow = true, EllesmereUIBags_List.lua) has an overlay over the 20 pixel row icon, a row icon of its own and
             no item level text.                                                                                         ]]
        function model.slot(bag, slot, asRow)
            local parent = env.CreateFrame("Frame", nil, env.UIParent)
            parent:SetID(bag)
            local b = env.CreateFrame("ItemButton", nil, parent)
            b:SetID(slot)
            b.UpdateNewItem = function() end
            b.GetBagID = function(self) return self:GetParent():GetID() end
            b._textOverlay = env.CreateFrame("Frame", nil, b)
            b._textOverlay:SetFrameLevel(b:GetFrameLevel() + 3)
            if asRow then
                b._lvIcon = b:CreateTexture(nil, "ARTWORK")
                b._textOverlay:SetSize(20, 20)
            else
                b.ItemLevelText = b._textOverlay:CreateFontString(nil, "OVERLAY")
                b._textOverlay:SetSize(37, 37)
            end
            return b
        end
        function model.render(b, link)
            local data = { bag = b:GetParent():GetID(), slot = b:GetID(), itemLink = link, info = link and {} or nil }
            if link then
                b:SetItemButtonTexture(134400)
                b:SetItemButtonQuality(3, link, false, false)
            else
                b:SetItemButtonTexture(nil)
            end
            if model.bags then model.bags.RunItemOverlays(b, data) end
        end
        function model.fade(frame)
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.__kind == "Texture" then region:SetAlpha(0) end
            end
        end
        return model
    end

    --[[ Dialogue UI (Raenore, Peterodox), reduced to what EasyGear touches, after its source (Code/Tooltip/Tooltip_Base.lua,
         Tooltip_Private.lua, Tooltip_Public.lua, Code/Dialogue/DialogueUI.lua, UITemplates.lua, API.lua):
           * DialogueUIAPI.AddItemTooltipProcessorExternal(processor): processor(tooltip, itemID, itemLink) -> changed?; the
             call comes one frame after the shared tooltip has shown an item (CallbackRegistry:TriggerOnNextUpdate keeps only
             the last call per event), after the comparison and the Shift hint were built
           * the shared tooltip (not a GameTooltip): AddLeftLine / AddRightLine (pairs with the last left line) / AddBlankLine /
             AddLine / AddDoubleLine, ProcessTooltipData -> ShowItemComparison (block "Replaces: ..." only while
             DialogueUI_DB.TooltipShowItemComparison, then tooltip:ProcessItemExternal(link) - where Dialogue UI puts Pawn's
             lines -, then the Shift hint as the last lines), ReprocessInfo; items from SetQuestItem are items, a hyperlink
             (getter "GetHyperlink") is not
           * DUIQuestFrame with an object pool of item buttons: Icon, type "choice" | "reward", index, objectType, isEquippable,
             ShowUpgradeIcon (once per button: the marker "upgrade") ; ReleaseAllObjects hands every button back before the
             rewards of the next quest are built
         options: expanded (comparison shown), pawn (a Pawn-like ProcessItemExternal), noProcessorAPI, noQuestFrame, noReprocess,
                  noProcessItemExternal, noReleaseAllObjects, noItemButtonPool, missingMethods = { AddBlankLine = true } (taken away from the tooltip),
                  nativeArrow = { [link] = true } (Dialogue UI's own item level arrow)                                  ]]
    function H.installDialogueUI(options)
        options = options or {}
        self.addons.DialogueUI = true
        local D = { processors = {}, upgrades = {}, buttons = {}, hints = 0, builds = 0, calls = {}, relayouts = 0, enters = 0 }
        env.DialogueUI_DB = { TooltipShowItemComparison = options.expanded and true or false }
        env.DialogueUIAPI = {}

        -- CallbackRegistry:TriggerOnNextUpdate and its Processor frame, as in the source (Code/CallbackRegistry.lua): one
        -- queue, one call per event; the flag is cleared before the loop, the queue after it - so a trigger from INSIDE a
        -- callback builds a queue that the end of the loop throws away and leaves the flag set; from then on every trigger
        -- indexes a nil queue and raises. (A model that "re-queues" instead hid exactly this once.)
        local Processor = { triggerQueue = nil, anyDelayedTrigger = nil, scheduled = false }
        D.processor = Processor
        local function onSetItem(tooltip, itemID, link)                     -- Tooltip_Public.lua: Tooltip_OnSetItem
            local any
            for processor in pairs(D.processors) do
                D.calls[#D.calls + 1] = link
                if processor(tooltip, itemID, link) then any = true end
            end
            if any then D.relayouts = D.relayouts + 1 tooltip:Show() end
        end
        local function processorOnUpdate()
            Processor.scheduled = false                                      -- SetScript("OnUpdate", nil)
            if Processor.triggerQueue and Processor.anyDelayedTrigger then
                Processor.anyDelayedTrigger = nil
                for _, args in pairs(Processor.triggerQueue) do onSetItem(args[1], args[2], args[3]) end
                Processor.triggerQueue = nil
            end
        end
        local function triggerOnNextUpdate(tooltip, itemID, link)
            if not D.callbackAdded then return end                           -- self.events[event]
            if not Processor.anyDelayedTrigger then
                Processor.triggerQueue = {}
                Processor.anyDelayedTrigger = true
            end
            Processor.triggerQueue["SharedTooltip.SetItem"] = { tooltip, itemID, link }
            if not Processor.scheduled then
                Processor.scheduled = true
                env.C_Timer.After(0, processorOnUpdate)                      -- SetScript("OnUpdate", Processor_OnUpdate)
            end
        end
        if not options.noProcessorAPI then
            function env.DialogueUIAPI.AddItemTooltipProcessorExternal(processor)
                D.callbackAdded = true
                D.processors[processor] = true
            end
        end

        -------------------------------------------------------------------- the shared tooltip
        local tip = env.CreateFrame("Frame", nil, env.UIParent)
        tip:Hide()
        tip.rows = {}
        D.tooltip = tip
        function tip:ClearLines() self.rows = {} self.hasHotkey = false end
        function tip:NumLines() return #self.rows end
        -- the tooltip builds itself with these; options.missingMethods takes one of them away from the object afterwards
        local function addLeft(self, text, r, g, b, wrap, offsetY, sizeIndex, horizontalOffset)
            if not text or text == "" then return nil end
            local fs = { text = text, r = r, g = g, b = b, wrap = wrap, size = sizeIndex or 2, indent = horizontalOffset or 0 }
            self.rows[#self.rows + 1] = { left = fs }
            return fs
        end
        local function addRight(self, text, r, g, b, wrap, offsetY, sizeIndex)
            if not text or text == "" then return nil end
            local current = self.rows[#self.rows]
            assert(current and current.left, "a right line comes in pairs with a left line")
            current.right = { text = text, r = r, g = g, b = b, size = sizeIndex or 2 }
            return current.right
        end
        local function addBlank(self) self.rows[#self.rows + 1] = { blank = true } end
        tip.AddLeftLine, tip.AddRightLine, tip.AddBlankLine = addLeft, addRight, addBlank
        function tip:AddLine(text, r, g, b, wrap) return addLeft(self, text, r, g, b, wrap, nil, 2) end
        function tip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
            addLeft(self, left, lr, lg, lb)
            addRight(self, right, rr, rg, rb)
        end
        if options.missingMethods then
            for name in pairs(options.missingMethods) do tip[name] = nil end
        end
        tip:SetScript("OnHide", function(self)
            self.tooltipData, self.tooltipInfo = nil, nil                    -- SharedTooltip:SetScript("OnHide")
            self.rows, self.hasHotkey = {}, false                             -- TooltipBaseMixin:Hide: ClearLines (and the anchors)
        end)
        -- TooltipBaseMixin:ReTriggerOnEnter: the OnEnter of the hovered owner again
        function tip:ReTriggerOnEnter()
            if self:IsVisible() and self.owner and self.owner.OnEnter and self.owner:IsShown() and self.owner:IsMouseOver() then
                self.owner:OnEnter()
            end
        end
        function tip:SetOwner(owner) self.owner = owner end
        function tip:GetHyperlink() return self.hyperlink end
        function tip:GetItemID() return self.hyperlink and tonumber(self.hyperlink:match("item:(%d+)")) end
        function tip:ShowHotkey(key, description)
            addBlank(self)
            addLeft(self, description, 0.5, 0.5, 0.5, true, nil, 2, 20)
            self.hasHotkey = true
            D.hints = D.hints + 1
        end
        if not options.noProcessItemExternal then
            if options.pawn then
                function tip:ProcessItemExternal(link)                      -- what Pawn's integration does (SupportedAddOns/Pawn.lua)
                    addBlank(self)
                    addLeft(self, "Pawn: 12% upgrade", 1, 1, 1, false, nil, 2)
                end
            else
                function tip:ProcessItemExternal() end
            end
        end
        function tip:ShowItemComparison()
            local it = self.hyperlink and self.itemFromAny(self.hyperlink)
            if not (it and it.equipLoc and it.equipLoc ~= "" and not it.cosmetic) then return end
            local expanded = env.DialogueUI_DB.TooltipShowItemComparison == true
            local canCompare = options.canCompare ~= false
            if canCompare and expanded then
                addBlank(self)
                addLeft(self, "Replaces: [worn item]", 1, 0.82, 0, true)
                addLeft(self, "Item Level +3", 1, 1, 1, false, nil, 2, 12)
            end
            if self.ProcessItemExternal then self:ProcessItemExternal(self.hyperlink) end
            if canCompare then self:ShowHotkey("Shift", expanded and "Hide Comparison" or "Show Comparison") end
        end
        tip.itemFromAny = self.itemFromAny
        function tip:ProcessTooltipData(data)
            if not (data and data.lines) then self.tooltipData = nil return false end
            D.builds = D.builds + 1
            self.tooltipData, self.hyperlink = data, data.hyperlink
            for i, l in ipairs(data.lines) do
                local c = l.leftColor or { r = 1, g = 0.82, b = 0 }
                addLeft(self, l.leftText, c.r, c.g, c.b, l.wrapText or false, nil, (i == 1) and 1 or 2)
                if l.rightText then
                    local rc = l.rightColor or c
                    addRight(self, l.rightText, rc.r, rc.g, rc.b, false, nil, 2)
                end
            end
            if data.isItem then
                self:ShowItemComparison()
                triggerOnNextUpdate(self, self:GetItemID(), self.hyperlink)
            end
            return true
        end
        function tip:ProcessInfo(info)
            self.tooltipInfo = info
            local data = info.fetch()
            self:ClearLines()
            if data then data.isItem = info.isItem end
            if self:ProcessTooltipData(data) then self:Show() else self:Hide() end
        end
        if not options.noReprocess then
            function tip:ReprocessInfo()
                if self.tooltipData then
                    self:ClearLines()
                    self:ProcessTooltipData(self.tooltipData)
                    self:Show()
                end
            end
        end
        function tip:SetQuestItem(kind, index)
            return self:ProcessInfo({ isItem = true, fetch = function()
                local link = env.GetQuestItemLink(kind, index)
                return link and env.C_TooltipInfo.GetHyperlink(link)
            end })
        end
        function tip:SetHyperlink(link)
            return self:ProcessInfo({ isItem = nil, fetch = function() return env.C_TooltipInfo.GetHyperlink(link) end })
        end
        function D.lines()
            local out = {}
            for _, r in ipairs(tip.rows) do
                if r.blank then out[#out + 1] = ""
                else out[#out + 1] = r.left.text .. (r.right and (" | " .. r.right.text) or "") end
            end
            return out
        end
        function D.text() return table.concat(D.lines(), "\n") end
        -- the row that starts with this text (or nil), and its index
        function D.row(prefix)
            for i, r in ipairs(tip.rows) do
                if r.left and r.left.text:sub(1, #prefix) == prefix then return r, i end
            end
        end

        -------------------------------------------------------------------- the quest frame and its reward buttons
        if not options.noQuestFrame then
            local frame = env.CreateFrame("Frame", "DUIQuestFrame", env.UIParent)
            frame:Hide()
            frame.chooseItems = false
            D.frame = frame
            local function pool(create, remove)
                local p = { active = {}, free = {} }
                function p:Acquire()
                    local o = table.remove(self.free, 1) or create()
                    self.active[#self.active + 1] = o
                    o:Show()
                    return o
                end
                function p:Release()
                    for _, o in ipairs(self.active) do remove(o) self.free[#self.free + 1] = o end
                    self.active = {}
                end
                function p:ProcessActiveObjects(fn) for _, o in ipairs(self.active) do fn(o) end end
                return p
            end
            local function createButton()
                local b = env.CreateFrame("Button", nil, frame)
                b.Icon = b:CreateTexture(nil, "ARTWORK")
                function b:SetItem(kind, index)
                    self.objectType, self.type, self.index = "item", kind, index
                    local link = env.GetQuestItemLink(kind, index)
                    local it = link and self.itemFromAny(link)
                    self.itemID = it and it.id
                    self.rewardAmount = 1
                    self.isEquippable = (it and it.equipLoc and it.equipLoc ~= "") or nil
                    if self.isEquippable and options.nativeArrow and options.nativeArrow[link] then self:ShowUpgradeIcon() end
                    self.context = nil
                    local list = (kind == "choice") and D.spec.choices or ((kind == "reward") and D.spec.rewards or D.spec.required)
                    local c = list and list[index]
                    if type(c) == "table" and c.context then self.context = true end
                end
                b.itemFromAny = self.itemFromAny
                function b:DoesButtonHaveMarker(name) return self.markers ~= nil and self.markers[name] == true end
                function b:ShowUpgradeIcon(playAnimation)
                    if self:DoesButtonHaveMarker("upgrade") then return end
                    self.markers = self.markers or {}
                    self.markers.upgrade = true
                    D.upgrades[#D.upgrades + 1] = { button = self, animation = playAnimation }
                end
                function b:OnRelease() self:ClearAllPoints() self:Hide() self.markers = nil end
                function b:IsMouseOver() return D.mouseOver == self and self:IsShown() end
                -- CustomTooltip_OnEnter: hide, build, then add lines AFTER the build (not part of the tooltip data)
                function b:OnEnter()
                    tip:Hide()
                    tip:SetOwner(self, "ANCHOR_NONE")
                    tip:SetQuestItem(self.type, self.index, true)
                    if self.type == "required" then                                     -- "You have N" for a required item
                        tip:AddLeftLine("You have 3", 1, 0.82, 0)
                        tip:Show()
                    end
                    if self.context then                                                -- the reward context line (bonus)
                        tip:AddBlankLine()
                        tip:AddLeftLine("First-time bonus", 0.4, 1, 0.4)
                        tip:Show()
                    end
                    D.enters = D.enters + 1
                end
                b:SetScript("OnEnter", function(self) D.mouseOver = self self:OnEnter() end)
                b:SetScript("OnLeave", function(self) if D.mouseOver == self then D.mouseOver = nil end tip:Hide() end)
                return b
            end
            if not options.noItemButtonPool then
                frame.itemButtonPool = pool(createButton, function(b) b:OnRelease() end)
            end
            frame.iconFramePool = pool(function() return env.CreateFrame("Frame", nil, frame) end, function() end)
            function frame:IsChoosingReward() return self.chooseItems == true end
            local function releaseAll()
                if frame.itemButtonPool then frame.itemButtonPool:Release() end
                frame.iconFramePool:Release()
                D.upgrades = {}
                D.buttons = {}
            end
            if not options.noReleaseAllObjects then
                function frame:ReleaseAllObjects() releaseAll() end
            end

            -- what HandleQuestComplete / HandleQuestDetail do: release everything, build the buttons, show the frame
            -- spec = { choices = { link | { link =, count =, usable = } }, rewards = { ... }, currencies = n, choosing = bool }
            -- (a currency reward is a button of type "reward" and objectType "currency": same type name, other kind of index)
            function D.showQuest(spec)
                spec = spec or {}
                spec.choices, spec.rewards, spec.required = spec.choices or {}, spec.rewards or {}, spec.required or {}
                D.spec = spec
                local choices, rewards, required = spec.choices, spec.rewards, spec.required
                local function entry(kind, i)
                    local list = (kind == "choice") and choices or ((kind == "reward") and rewards or required)
                    local c = list[i]
                    if type(c) == "table" then return c end
                    return c and { link = c } or nil
                end
                env.GetQuestItemLink = function(kind, i) local c = entry(kind, i) return c and c.link or nil end
                env.GetQuestItemInfo = function(kind, i)
                    local c = entry(kind, i)
                    return "name", 1, c and c.count or 1, 1, not c or c.usable ~= false
                end
                env.GetNumQuestChoices = function() return #choices end
                frame.chooseItems = (spec.choosing ~= false) and #choices > 1
                if frame.ReleaseAllObjects then frame:ReleaseAllObjects() else releaseAll() end
                for i = 1, #choices do
                    local b = frame.itemButtonPool:Acquire()
                    b:SetItem("choice", i)
                    D.buttons[#D.buttons + 1] = b
                end
                for i = 1, #rewards do
                    local b = frame.itemButtonPool:Acquire()
                    b:SetItem("reward", i)
                    D.buttons[#D.buttons + 1] = b
                end
                for i = 1, #required do
                    local b = frame.itemButtonPool:Acquire()
                    b:SetItem("required", i)
                    D.buttons[#D.buttons + 1] = b
                end
                for i = 1, spec.currencies or 0 do
                    local b = frame.itemButtonPool:Acquire()
                    b.objectType, b.type, b.index = "currency", "reward", i
                    D.buttons[#D.buttons + 1] = b
                end
                frame:Show()
                return D.buttons
            end
            -- the client tells the shown children of a frame when it is hidden or shown
            function D.hide()
                frame:Hide()
                for _, f in ipairs(self.frames) do
                    if f.__parent == frame and f.__scripts.OnHide then f.__scripts.OnHide(f) end
                end
            end
            function D.show()
                frame:Show()
                for _, f in ipairs(self.frames) do
                    if f.__parent == frame and f.__shown and f.__scripts.OnShow then f.__scripts.OnShow(f) end
                end
            end
            -- a frame that is shown runs the OnUpdate of its children, then the timers of the client advance
            function D.tick(dt)
                for _, f in ipairs(self.frames) do
                    if f.__parent == frame and f.__scripts.OnUpdate and f:IsVisible() then f.__scripts.OnUpdate(f, dt) end
                end
                H.advance(dt)
            end
            function D.hover(button) button.__scripts.OnEnter(button) H.advance(0) end
            function D.leave(button) button.__scripts.OnLeave(button) end
            D.spec = { choices = {}, rewards = {}, required = {} }
        end
        return D
    end

    return H
end

return Mock
