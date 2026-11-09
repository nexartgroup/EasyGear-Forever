--[[---------------------------------------------------------------------------
    Classes.lua - Was die neun Klassen tragen und fuehren koennen

    Gebraucht fuer die Gruppenhinweise (Group.lua): ob ein Gegenstand fuer das Mitglied einer anderen Klasse
    in Frage kommt, steht nicht im Tooltip des Spielers - dessen rote Zeilen gelten nur fuer ihn. Darum die
    klassischen Regeln hier als Tabelle:

      * Ruestungsarten (Stoff, Leder, Kette, Platte, Schild, Buecher/Idole/Totems) und die Stufe, ab der
        Kette (Jaeger, Schamane) und Platte (Krieger, Paladin) getragen werden
      * Waffenarten je Klasse
      * die Klassenzeile des Tooltips ("Klassen: Krieger, Paladin"), wenn der Gegenstand klassengebunden ist

    Die Tabellen folgen den klassischen Regeln (Vanilla bis Wrath). Weicht Forever ab, sind sie hier zu
    aendern; die Gruppenhinweise sind Richtwerte, wie die Gewichte der Profile auch.

    Stufen: ein Gegenstand gilt als verwendbar, wenn das Mitglied ihn tragen kann oder dafuer hoechstens eine Stufe zu
    niedrig ist (LEVEL_TOLERANCE) - die Stufenanforderung des Gegenstands und die Stufe, ab der die Klasse die
    Ruestungsart traegt (Kette/Platte ab 40), zaehlen gleich. Classes.Usable meldet dann die Stufe mit, ab der er passt.

    Unterklassen (Enum.ItemArmorSubclass / Enum.ItemWeaponSubclass):
      Ruestung  0 Sonstiges  1 Stoff  2 Leder  3 Kette  4 Platte  6 Schild  7 Buch  8 Idol  9 Totem
      Waffe     0 Axt  1 Zweihandaxt  2 Bogen  3 Gewehr  4 Streitkolben  5 Zweihandstreitkolben  6 Stangenwaffe
                7 Schwert  8 Zweihandschwert  10 Stab  13 Faustwaffe  15 Dolch  16 Wurfwaffe  18 Armbrust  19 Zauberstab
-----------------------------------------------------------------------------]]

local _, EG = ...
local Classes = {}
EG.Classes = Classes

local pairs, ipairs, type = pairs, ipairs, type
local sfind = string.find

Classes.ARMOR_CLASS, Classes.WEAPON_CLASS = 4, 2

-- So viele Stufen darf ein Mitglied unter dem liegen, was ein Gegenstand verlangt, und gilt trotzdem als Kandidat
Classes.LEVEL_TOLERANCE = 1

-- Ruestungsart -> Stufe, ab der die Klasse sie tragen kann
Classes.ARMOR = {
    WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER  = { [1] = 1, [2] = 1, [3] = 40 },
    ROGUE   = { [1] = 1, [2] = 1 },
    PRIEST  = { [1] = 1 },
    SHAMAN  = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
    MAGE    = { [1] = 1 },
    WARLOCK = { [1] = 1 },
    DRUID   = { [1] = 1, [2] = 1, [8] = 1 },
}

local function Set(list)
    local out = {}
    for _, v in pairs(list) do out[v] = true end
    return out
end

-- Waffenarten je Klasse (Fernkampfwaffen und Zauberstaebe eingeschlossen)
Classes.WEAPON = {
    WARRIOR = Set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }),
    PALADIN = Set({ 0, 1, 4, 5, 6, 7, 8 }),
    HUNTER  = Set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }),
    ROGUE   = Set({ 0, 2, 3, 4, 7, 13, 15, 16, 18 }),
    PRIEST  = Set({ 4, 10, 15, 19 }),
    SHAMAN  = Set({ 0, 1, 4, 5, 10, 13, 15 }),
    MAGE    = Set({ 7, 10, 15, 19 }),
    WARLOCK = Set({ 7, 10, 15, 19 }),
    DRUID   = Set({ 4, 5, 6, 10, 13, 15 }),
}

-- Plaetze, an denen die Ruestungsart zaehlt (Umhang, Hals, Ringe, Schmuck kann jede Klasse tragen)
Classes.ARMOR_SLOT_LOCS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true,
    INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

function Classes.Known(class)
    return type(class) == "string" and Classes.ARMOR[class] ~= nil
end

--[[ Die hoechste Stoff/Leder/Kette/Platte-Art, die die Klasse auf dieser Stufe traegt. Wer Platte tragen kann, traegt
     keine Stoffruestung: ein Stoffstueck gilt fuer ihn nicht als Verbesserung, auch wenn die Werte besser aussehen. ]]
function Classes.BestArmor(class, level)
    local rules = Classes.ARMOR[class]
    if not rules then return nil end
    local best = nil
    for sub, from in pairs(rules) do
        if sub >= 1 and sub <= 4 and (level or 0) >= from and (not best or sub > best) then best = sub end
    end
    return best
end

--[[ Steht der Name der Klasse in der Klassenzeile? Die Namen der Liste kennen eine maennliche und eine weibliche Form
     ("Krieger" / "Kriegerin"); verglichen wird mit beiden und mit dem, was UnitClass meldet. Ohne bekannten Namen
     laesst sich die Zeile nicht pruefen: dann gilt der Gegenstand nicht als verwendbar.                          ]]
local function ClassListed(text, member)
    local names = {}
    local male, female = _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE
    if type(male) == "table" and type(male[member.class]) == "string" then names[#names + 1] = male[member.class] end
    if type(female) == "table" and type(female[member.class]) == "string" then names[#names + 1] = female[member.class] end
    if type(member.className) == "string" then names[#names + 1] = member.className end
    for _, name in ipairs(names) do
        if name ~= "" and sfind(text, name, 1, true) then return true end
    end
    return false
end

--[[ Kommt der Gegenstand fuer dieses Mitglied in Frage?
     member = { class = "WARRIOR", className = "Krieger", level = 60 }
     worn   = der Gegenstand, den es dort traegt (oder nil): dieselbe Ruestungsart wie dort bleibt erlaubt, auch wenn
              sie nicht die hoechste ist (Stufe 39 -> 40, noch kein Plattenstueck gefunden)
     Rueckgabe: true, nil, Stufe | false, Grund ("class" | "level" | "type")
       Stufe ist gesetzt, wenn das Mitglied den Gegenstand erst ab einer hoeheren Stufe tragen kann (hoechstens eine
       hoeher als seine eigene).                                                                                   ]]
function Classes.Usable(member, item, worn)
    if type(member) ~= "table" or type(item) ~= "table" then return false, "type" end
    local class, level = member.class, member.level or 0
    local reach = level + Classes.LEVEL_TOLERANCE
    local need = item.reqLevel or 0

    -- 1) Klassenzeile des Tooltips
    if item.classesText and item.classesText ~= "" and not ClassListed(item.classesText, member) then
        return false, "class"
    end

    -- 2) Art; die Stufe, ab der die Klasse die Ruestungsart traegt, kann die Anforderung des Gegenstands erhoehen
    if item.classID == Classes.ARMOR_CLASS then
        local sub = item.subclassID or 0
        -- Sonstiges (Ringe, Hals, Schmuck, Halteitems) tragen alle; Umhaenge sind Stoff, und Stoff kann jede Klasse tragen
        if sub ~= 0 then
            local from = Classes.ARMOR[class] and Classes.ARMOR[class][sub]
            if not from or reach < from then return false, "type" end
            if from > need then need = from end
            if Classes.ARMOR_SLOT_LOCS[item.equipLoc] and sub >= 1 and sub <= 4 then
                -- die hoechste Art, die das Mitglied jetzt traegt oder (eine Stufe weiter) bald tragen wird
                local sameAsWorn = type(worn) == "table" and worn.classID == Classes.ARMOR_CLASS and worn.subclassID == sub
                if sub ~= Classes.BestArmor(class, level) and sub ~= Classes.BestArmor(class, reach) and not sameAsWorn then
                    return false, "type"
                end
            end
        end
    elseif item.classID == Classes.WEAPON_CLASS then
        local rules = Classes.WEAPON[class]
        if not (rules and rules[item.subclassID]) then return false, "type" end
    end

    -- 3) Stufe: hoechstens eine zu hoch
    if need > reach then return false, "level" end
    return true, nil, (need > level) and need or nil
end
