# EasyGear for WoW Forever

Gear scoring, upgrade detection and item comparison for **World of Warcraft Forever**.

EasyGear tells you whether an item is actually better than what you are wearing - using stat
weights for **your talents, your level and the rest of your equipment**, not item level alone -
and puts the answer where you look at items: bags, bank, vendors, loot, rolls, quest rewards,
trade, mail, the character window and every item tooltip.

It **only compares and recommends**. It does not equip anything, send commands, create items or
need any other addon: it is built on the default Forever interface and nothing else.

* Interface `16001`, Lua 5.1, no XML files
* Settings page in *Options > AddOns*, entry in the minimap addon compartment, comparison window and
  profile window in the standard frame style
* Texts in English and German; other client languages are partly translated and fall back to English

[Deutsche Version weiter unten](#easygear-für-wow-forever-deutsch)

> **Status.** This edition was written against the source of the Forever user interface (1.60.1) and
> checked offline: static checks against that source and unit tests on a model of the client (see
> [Verification](#verification)). **It has only been tried in the game briefly so far** (the group hints were
> reported to work). The stat weights are estimates (see [Known limits](#known-limits)). If something looks wrong, `/eg status` and
> `/eg parse` show what the addon sees.

---

## Contents

- [Installation](#installation)
- [What you see](#what-you-see)
- [Commands](#commands)
- [Scoring](#scoring)
- [Profiles](#profiles)
- [Slots, weapons, rings](#slots-weapons-rings)
- [Settings](#settings)
- [Group hints](#group-hints)
- [Marker look](#marker-look)
- [Baganator and EllesmereUI](#baganator-and-ellesmereui)
- [Troubleshooting](#troubleshooting)
- [Verification](#verification)
- [Known limits](#known-limits)
- [The 3.3.5a edition](#the-335a-edition)
- [Changes in 4.3.0](#changes-in-430)
- [Changes in 4.2.0](#changes-in-420)
- [Changes in 4.1.0](#changes-in-410)
- [Changes in 4.0.0](#changes-in-400)

---

## Installation

Copy the folder `EasyGear` (the one that contains `EasyGear.toc`) into the `Interface/AddOns` folder of
your WoW Forever installation, so that you end up with `.../Interface/AddOns/EasyGear/EasyGear.toc`.
Restart the game or `/reload`. Saved settings are `EasyGearDB` (account) and `EasyGearCharDB` (character).

From GitHub: *Code > Download ZIP*, unpack it, and copy the inner folder `EasyGear` - not the folder of the
ZIP itself (`EasyGear-Forever-main`), which also holds the tests and tools.

At login the chat shows `EasyGear 4.3.0 loaded.`

## What you see

| Where | What |
|---|---|
| Bags, bank | green **arrow** at the top left of an item that is better than what you wear |
| Vendors, loot windows, loot rolls, trade (their items), mail attachments | the same arrow |
| Quest rewards | the arrow, and a green **check mark** on the best choice when there are several (the largest upgrade, otherwise the highest vendor price) |
| Character window | an arrow on an equipment slot when something better for that slot is in your bags |
| Item tooltips | `EasyGear  Score: 81` - the slot and score of the item you would replace, the verdict (`UPGRADE +37 (+83.1%)`, `NO UPGRADE`, `NOT USABLE`, `UPGRADE from level 45`) and the attribute differences |
| Worn items, compare tooltips | only the score (comparing an item with itself is pointless) |

A **yellow** arrow means: it would be an upgrade, but your level is too low for it yet.
Items the client marks as unusable for you (wrong armor type, class) never get an arrow.

A **violet star** in the same place means: no upgrade for you, but better for somebody in your group than what
they wear - see [Group hints](#group-hints).

This page describes the markers as they look when you leave them alone. **Shape and colour of each marker are your
choice** - see [Marker look](#marker-look).

**Comparison window** (`/eg`, `/eggui`, or the addon-compartment entry): drag an item onto the
left slot, shift-click an item while the window is open, or type `/eg <item link>`. It shows the
full calculation of both items - attribute, value, weight, points - and the verdict. Rings, trinkets
and one-hand weapons get a tab for each slot.

**Profile window** (`/egprofile`): the weighting profile of your choice on the left, your active profile
on the right, both applied to the gear you are wearing. See [Profiles](#profiles).

## Commands

`/eg` or `/easygear`; `/eggui` opens the window, `/egprofile` the profile window.

| Command | Does |
|---|---|
| `/eg` | open or close the comparison window |
| `/eg <item link or item ID>` | report in chat and in the window |
| `/eg upgrades` | list every upgrade in your bags (and the open bank), best first |
| `/eg group [on\|off\|scan\|raid\|inspect]` | the group: who was read and what is known; switch the hints, read again, include the raid, let the addon inspect |
| `/eg marker [<kind> <shape> [RRGGBB]]` | shape and colour of the markers: list them, change one kind, or reset (kinds: `upgrade`, `level`, `group`, `pick`, `sell`) |
| `/eg profile list` / `/eg profile <id>` / `/eg profile auto` | list, choose, or detect automatically |
| `/eg weight <stat> <value>` | set a weight in your active *own* profile (`/eg weight CRIT 0.8`) |
| `/eg autolevel [on\|off]` | below the maximum level use the Leveling profile of your class |
| `/eg enchants [on\|off]` | count enchants, gems and active socket bonuses |
| `/eg socket <0-1000\|auto>` | points per empty socket (auto: from level and profile) |
| `/eg ilvl <0-2>` / `/eg ilvlscale [on\|off]` | item level weight / scale it with your level |
| `/eg mindelta <0-1000>` / `/eg mindeltapct <0-10>` | minimum gain for "upgrade" (absolute points / percent) |
| `/eg icons \| items \| quest \| char \| tooltip \| stats \| diff` | switch marker groups and tooltip parts on or off |
| `/eg options` | open the settings page |
| `/eg scale <0.5-2>` | window scale |
| `/eg status` | profile, detected talent points, settings, state of every interface hook |
| `/eg parse <item link>` | what was read from an item (base values, extras, unknown stats) |
| `/eg unknown` | item stats in your gear and bags that the addon does not know |
| `/eg locale` | language file in use and how much of it is translated |
| `/eg reset` | back to defaults (your own profiles are kept) |

## Scoring

```
score =  item level x item level weight x (character level / maximum level)
       + sum of  (value x weight)    base values + enchant + gems + active socket bonus
       + weapon DPS x weight         (an off-hand weapon counts half)
       + empty sockets x socket value
```

* **Item level weight** 0.5 points per level at the maximum level (`/eg ilvl`). It grows with your
  level so that low-level attributes are not drowned out by the item level (`/eg ilvlscale off`).
* **Weights** come from the profile, normalised so that the main attribute of the profile is 1.00.
* **Values** come from `C_Item.GetItemStats` (language independent) and the tooltip lines (enchants,
  gems, socket bonus, ratings the API does not list). Lines are read with patterns built at run time
  from the client's own strings, so no text of one language is hard-coded.
* **Empty sockets** are worth a typical gem of your level for the main attribute of the profile, minus 10 %.
* **Upgrade** means: the gain is positive *and* at least `max(minimum, percent of the worn item's score)` -
  defaults 0 points and 1 %. Small differences are noise, not upgrades.

Every item is compared per slot: the candidate is "put into" each slot it fits and compared with what
is worn there; the slot with the largest gain wins.

## Profiles

A profile is a set of weights, for example *Arms*, *Protection* or *Holy*. For every one of the nine
classes there is a profile per talent tree, a *Leveling* profile and an *All-round* profile; plus two
general ones (*Leveling (neutral)* and *Item level only*).

**Automatic selection** (default): the tree with the most talent points decides (at least 5 points).
Below the maximum level the *Leveling* profile of your class is used instead - except for tank and
healer trees, whose weights differ too much (`/eg autolevel off` to always use the tree profile).
A tree with two profiles (the Druid's second tree has *Cat* and *Bear*; the Warrior's Fury tree has a dual-wield
and a two-hand variant) is resolved by the role the client reports for the tree (tank, healer), then by the weapons
you carry, otherwise the first profile is used - for that Druid tree this is *Cat*, so choose *Bear* yourself
(`/eg profile DRUID_BEAR`) if the client does not report the tree as a tank tree.
Without talent information the addon uses *All-round* (maximum level) or *Leveling*.

**Custom profiles** are made in the profile window: pick any profile, press *Edit*, change the weights
(decimal comma works), *Save as new profile*. Own profiles can be overwritten, renamed and deleted there.
They are stored for the whole account; the choice of the active profile is stored per character.
Stats the addon does not know can be weighted in a custom profile by their raw name:
`/eg unknown` lists them, `/eg weight ITEM_MOD_xxx_SHORT 0.5` sets the weight.

## Slots, weapons, rings

* Rings and trinkets are compared with both slots; the one that gains most is the target.
* A one-hand weapon may go to the off hand if your character can dual wield *and* the profile wants it
  (tanks, healers and casters only when a weapon is already in the off hand; never while a shield or
  held-in-off-hand item is worn); off-hand weapons count half of their damage.
* A two-hander is compared with main hand plus off hand together; a shield or off-hand item while a
  two-hander is worn is compared with that two-hander.
* Unique items: the second copy replaces the first.
* Shirts and tabards are never compared.

## Settings

*Options > AddOns > EasyGear*: marker groups (bags/bank, vendors/loot/rolls/trade/mail, quest rewards,
character window), group hints (the star, inspecting members, raid members), the look of the markers (shape and colour),
tooltip parts, enchants, Leveling profile, item level weight and scaling, minimum
gain, the profile choice and a reset button. Everything takes effect immediately - also when you change
a value by chat command while the page is open.
The addon-compartment entry on the minimap: left click opens the comparison window, right click the settings.

## Group hints

An item that is **no upgrade for you** but would be **better for a group member than what he wears** gets a
**violet star** - in your bags, the bank, loot windows and roll windows (where the arrow shows). The tooltip says who
gains:

```
Better for the group:
Bob (Shadow)                      +12.3%
Eve (All-round)                   nothing equipped
```

If the item is an upgrade for you as well, you get the green arrow, and the tooltip still names the members.

* **Who counts:** your party. *Include raid members* adds a raid, but in a raid almost every item is better for somebody,
  so it is off by default.
* **What they wear:** the addon inspects members the way the inspect window does. At most one request every 2.5 seconds,
  only members in range, never in combat and never while you have an inspect window open. Every inspection that you or
  another addon starts is used as well. A member is read again after five minutes or when his equipment changes; out of
  range or offline, the last reading stays. A member who wears little (a low level, a bare alt) is looked at a few times
  only, an empty answer never wipes a good reading, and an equipment change is not re-read more often than every 30
  seconds. The addon also waits a few seconds after an inspection that you or another addon started. *Inspect group
  members* off: only inspections you start yourself count.
* **Which profile:** the talents of the inspected member if the client hands them out (and names three different trees);
  otherwise the class default - the All-round profile, below the maximum level the Leveling profile of the class.
  Druids of the feral tree are rated as cats.
* **How it is rated:** like your own items (member's profile, level and worn gear), with the thresholds of your settings
  and at least 3 %: the weights are estimates, and a star should mean something.
* **Who can use it:** the class line of the item tooltip, armor type (a plate wearer is not offered cloth), weapon types
  of the class (`Classes.lua`, the classic rules) and level. The member must be able to use it **or be at most one level
  short** - the tooltip then adds `from level N`.
* **Weapons** are compared with weapons of the same kind only: one-hand with one-hand (an off hand counts half), two-hand
  with two-hand, shield with shield, held item with held item. Whether somebody should change his style is not decided.
* **An empty slot** counts only when the reading of the member is complete (eight or more worn pieces): an unfinished
  reading says nothing about a missing ring.
* **Bound items** in your bags and bank get no star and their tooltip names nobody - you cannot hand them over - unless
  their trade time (looted items, in the tooltip) is still running.
* **Baganator and EllesmereUI** show the star in the same place as the arrow; Baganator only for items of this
  character's bags and bank.
* `/eg group` lists the members, their profile (from talents or class default) and when they were read; `/eg group scan`
  reads everybody again.

## Marker look

*Options > AddOns > EasyGear > Marker look* lets you choose **shape and colour** of every marker. There are five kinds:

| Kind (word for `/eg marker`) | Shows on | Original look |
|---|---|---|
| Upgrade for you (`upgrade`) | gear that beats what you wear | green arrow |
| Upgrade, level too low (`level`) | would be an upgrade, but your level is not high enough yet | yellow arrow |
| Better for the group (`group`) | no upgrade for you, but for a group member | violet star |
| Best quest reward, upgrade (`pick`) | the largest upgrade among several quest rewards | green check mark |
| Best quest reward, to sell (`sell`) | no upgrade among them: the highest vendor price | green check mark |

* **Shape:** arrow, star, check mark, coin, circle, diamond, triangle, moon, square, cross, skull. The list shows each
  shape with its picture.
* **Colour:** the colour field of the interface (colour wheel and hex box). Any colour other than the original is put on
  the grey picture of the shape, so every shape can take every colour; dark parts of a picture stay dark, and very
  dark colours give dark marks.
* The default of every kind is the original look, exactly as before - and choosing the original colour of a kind with
  its original shape brings the original look back.
* The choice holds wherever the markers show - bags, bank, vendors, loot, rolls, trade, mail, quest rewards, the
  character window - and in the Baganator and EllesmereUI bags. A change shows up right away (while you drag in the
  colour wheel, as soon as you pause).
* *Reset marker look* puts every kind back (so does `/eg reset`, together with all other settings).
* The same by chat: `/eg marker` lists kinds, shapes and what is chosen; `/eg marker group diamond ff8800` chooses a
  shape and a colour (six hex digits `RRGGBB`; either one alone is enough, in any order); `/eg marker group reset` and
  `/eg marker reset` put one kind or all of them back.
* A value that does not exist (a hand-edited saved variable, a shape from another version) counts as the original.

## Baganator and EllesmereUI

Neither is needed. When they are installed, the arrow shows up in their windows too; `/eg status` lists what
EasyGear found.

* **Baganator** (bags, bank, warband bank, other characters) draws its icons through *Icon Corners* that other
  addons can fill. EasyGear registers one, **EasyGear marker**, by default in the **top right** corner
  (Baganator's own layout puts the junk coin and the item level at the top left). Green means upgrade, yellow
  means upgrade as soon as your level reaches. Move or remove it under *Icon Corners* in Baganator's settings.
  EasyGear also registers as an upgrade source (*Upgrade detection*), so that Baganator's searches and categories
  use the same verdict; Baganator selects it by itself when no other source is chosen. The setting for bag markers
  (`/eg icons`) switches both off. Baganator needs its companion addon **Syndicator** to run at all; without it
  EasyGear registers nothing and `/eg status` says so.
  Baganator puts a new corner widget into the layout of the profile that is active at login only. In another Baganator
  profile, pick **EasyGear marker** yourself under *Icon Corners*.
* **EllesmereUI**: its Bags module builds its own item buttons, which the hooks on the interface's functions do not
  see. It offers an overlay interface for other addons (`EUI_Bags.RegisterItemOverlayIcon`) that runs for every slot of
  the bags, the reagent bag and the bank, in the grid and in the list view, empty slots included. EasyGear paints its
  arrow through it - at the **top right** of each item, because the top left carries the item level - and the arrow
  disappears when a slot is emptied. It is half as high as the icon below it (16 pixels on a regular slot, 10 in the
  list view, never less than 8). EllesmereUI's window skin fades the textures of the item buttons it restyles
  (vendor, loot, mail, quest rewards, character sheet); EasyGear's marks therefore sit on a frame of their own above
  each button and stay visible; the frame follows the frame levels that the bags give their buttons later. In the
  vendor window's *Show As List* view the button covers the whole row, so the arrow goes to the corner of the row's
  icon (and to the other corner when the stock number sits there).
* Both were read from their source (Baganator release 834, EllesmereUI Bags 9.8.3) and built against their public
  interfaces; **they were tested here with models of those interfaces, not in the game with the real addons**
  (see [Known limits](#known-limits)).

## Troubleshooting

`/eg status` shows the interface hooks the addon installed (`itembuttons`, `merchant`, `merchantstock`, `rolls`,
`tooltip`, `settings`, `shiftclick`, plus `baganator` and `ellesmere` when those addons are installed): a red name
with a reason means that part of the client interface was not found and that feature is off. It lists the other
addons it found. It also prints the detected talent points and the last internal error.
Internal errors are printed once in the chat as `EasyGear[label]: message`.

If an item scores oddly, `/eg parse <item link>` shows the values read from it; `/eg unknown` shows
stats that are read but not scored.

**Reporting a problem:** please include the output of `/eg status` (it names the client version, the
detected talent points and which interface hooks work), plus `/eg parse <item link>` for a wrongly scored item
and the exact text of any Lua error (`/console scriptErrors 1` shows them). For group hints add the output of
`/eg group`: it shows for every member whether and when he was read, and why not.

## Verification

Run from the root of this repository:

```
lua5.1 tests/run.lua                 # unit tests on a model of the client (Lua 5.1 only), ~380 checks
python3 tests/mutate.py              # mutation check: breaks the addon in ~420 small ways, the tests must notice
tools/check.sh <Interface/AddOns of the Forever UI source>
                                     # luacheck against a std built from the UI source + checks that every
                                     # method, event, template, font, atlas and global the addon names exists
```

What this proves and what it does not:

* The static checks read the real Forever UI source (the `forever` branch of `Gethe/wow-ui-source`, 1.60.1)
  and apply the load rules of the game type (`[Family]` = Mainline, `[Game]` = Camelot). A function,
  event or template that does not exist there is an error.
* The unit tests run on `tests/wow_mock.lua`, a model of the client that follows the call patterns and
  data shapes of that source. It is written by the same author as the addon: it catches logic errors and
  regressions, not wrong assumptions about the client.
* **Nothing here replaces running the addon in the game.**

## Known limits

* Tried in the real game only briefly so far (see Status).
* **Weights are estimates.** They follow the common stat priorities of the classic ratings systems and are
  normalised to the main attribute of each profile. Forever's own itemisation and balance may differ;
  tune the weights in a custom profile.
* The three talent trees are assumed to be in the order the client shows them (tree 1, 2, 3 of the class).
  If automatic detection picks the wrong profile, choose one yourself and check `/eg status`.
* Item effects (procs, on-use, set bonuses) are not scored; stats written as percentages are not parsed.
* Every item gets the item level term, also one without scored stats; an item that adds nothing else
  still has a score of item level x weight.
* Two-handers are always compared with main hand plus off hand together; carrying two two-handers
  (Titan's Grip style) is not modelled.
* Whether you can use an item (class, armor type, reputation, profession) is read from the red lines of its
  tooltip when the addon first looks at the item; it is not re-evaluated when you gain reputation or a skill
  until the next level-up or `/reload`.
* The auction house is not marked; own trade items and sent mail are not marked.
* Group hints are estimates: the weights are the profile weights, armor and weapon types follow the classic rules in
  `Classes.lua` (change them there if Forever differs), and whether the client hands out the talents of an inspected
  member is not known - without them the class default decides. They need inspecting, so members out of range or
  who never came close are not rated.
* Heirlooms, gem or enchant recommendations and automatic equipping do not exist by design.
* Marker look: the shape list in the options shows every shape in its own colours (the marker itself takes the colour
  you chose), and the colour is laid on the grey picture of the shape - for shapes with dark parts the result is
  darker than, and only close to, the colour you picked. The tooltip lines (the violet heading of the group hint, the
  green line of the quest pick) keep their colours.
* Texts: English and German are complete; other languages are partly translated (missing texts show in English).
* Baganator and EllesmereUI are connected through their public interfaces (corner widgets and upgrade source; item
  overlay interface of the Bags module), tested against models of them. If an arrow does not show there, `/eg status`
  tells which part was found. EllesmereUI's offline views of other characters' bags are not painted. Other bag addons
  (Bagnon, ElvUI bags, ...) are not supported specifically.

## The 3.3.5a edition

The addon for the old Wrath client (interface 30300, with ElvUI/Bagnon/Immersion support and the GM
heirloom tools) lives in its own repository, [nexartgroup/EasyGear](https://github.com/nexartgroup/EasyGear).
This edition is a new codebase for the Forever client, not an update of that one.

## Changes in 4.3.0

* **Marker look:** shape and colour of every marker are chosen in the options (*Marker look*) or by `/eg marker`:
  upgrade for you, upgrade with a level that is too low, better for the group, and the best quest reward - split into
  the one chosen as an upgrade and the one chosen **to sell**. Eleven shapes, any colour from the interface's colour
  field. The defaults are the original look, so nothing changes until you choose something.
* The look holds in bags, bank, vendors, loot, rolls, trade, mail, quest rewards, the character window, and in the
  Baganator and EllesmereUI bags; a change redraws open windows at once.
* New command `/eg marker`, new button *Reset marker look*. The *Group hints* option no longer names the star.

## Changes in 4.2.0

* **Group hints**: a violet star on items that are no upgrade for you but better for a group member than what they wear,
  and the members named in the tooltip. Members are inspected (gently: one request per 2.5 seconds, in range, not in
  combat), rated with their own profile, level and gear, and must be able to use the item or be at most one level short.
  Bound items without trade time get no star. Works in bags, bank, loot and rolls, and in Baganator and EllesmereUI.
* New settings *Group hints*, *Inspect group members*, *Include raid members*; new command `/eg group`.
* Findings of an independent review are in: incomplete readings and equipment events cannot start a loop of requests,
  an empty answer keeps the old reading, a reading that brings nothing new does not recompute everything, the talent
  tree is only taken from three different specialization numbers, members' levels follow `UNIT_LEVEL`, a late roster
  entry is looked at again, and no violet star flashes while your own verdict is still loading.
* Armor and weapon types of the nine classes (`Classes.lua`); the class line of item tooltips is read.

## Changes in 4.1.0

* **Baganator**: the arrow is a corner widget of Baganator (default: top right) and Baganator's upgrade source.
* **EllesmereUI**: its Bags module shows the arrow through its overlay interface (top right of the item, removed when a
  slot is emptied); EllesmereUI's window skin can no longer fade the marks.
* The marks sit on a frame of their own above each item button and follow its icon; skins that fade the textures of a
  button cannot hide them. The frame follows the frame levels the bags give their buttons later.
* EllesmereUI's vendor window in *Show As List* view: the arrow sits at the corner of the row's icon, not at the end of
  the row, and moves to the other corner when the stock number appears (new hook `merchantstock`).
* EllesmereUI's arrow is half as high as the icon below it (8 to 16 pixels) instead of a fixed 16, so it fits the list view.
* Baganator is only connected when Syndicator is there, which Baganator itself needs; `/eg status` reports the case.
* `/eg status` lists the other addons that were found.

## Changes in 4.0.0

First edition for WoW Forever.

* Default Forever interface only: item button hook (`SetItemButtonQuality`) for bags, bank, loot, quest
  rewards, trade, mail and the character window; vendor and roll hooks; tooltip data processor.
* Settings page through the Settings API, addon compartment entry, windows built from the standard frame
  templates, standard menus (`DropdownButton`) and dialogs (`StaticPopup`).
* Nine classes with a profile per talent tree, Leveling and All-round profiles; talent detection through
  `C_SpecializationInfo` and `C_Traits`.
* Removed from the 3.3.5a edition: GM heirloom packages, heirloom handling, PvP mode, recipe/prospecting/
  milling markers, third-party addon integration.

---
---

# EasyGear für WoW Forever (Deutsch)

Ausrüstungsbewertung, Upgrade-Erkennung und Vergleich für **World of Warcraft Forever**.

EasyGear sagt dir, ob ein Item wirklich besser ist als das, was du trägst - mit Gewichten für **deine
Talente, deine Stufe und den Rest deiner Ausrüstung**, nicht nur nach Gegenstandsstufe - und zeigt die
Antwort dort, wo du Items ansiehst: Taschen, Bank, Händler, Beute, Würfeln, Questbelohnungen, Handel,
Post, Charakterfenster und in jedem Item-Tooltip.

Es **vergleicht und empfiehlt nur**. Es legt nichts an, schickt keine Befehle, erzeugt keine Items und
braucht kein weiteres Addon: es baut allein auf der Standard-Oberfläche von Forever auf.

> **Stand.** Diese Ausgabe wurde gegen den Quelltext der Forever-Oberfläche (1.60.1) geschrieben und
> offline geprüft: statische Prüfungen gegen diesen Quelltext und Tests auf einem Modell des Clients
> (siehe [Prüfung](#prüfung)). **Im Spiel wurde sie bisher nur kurz ausprobiert** (die Gruppenhinweise liefen
> laut Rückmeldung). Die Gewichte sind
> Schätzwerte (siehe [Bekannte Grenzen](#bekannte-grenzen)). Wirkt etwas falsch, zeigen `/eg status`
> und `/eg parse`, was das Addon sieht.

## Installation

Den Ordner `EasyGear` (der mit `EasyGear.toc`) in den Ordner `Interface/AddOns` deiner WoW-Forever-
Installation kopieren, sodass `.../Interface/AddOns/EasyGear/EasyGear.toc` entsteht. Spiel neu starten
oder `/reload`. Gespeichert wird in `EasyGearDB` (Konto) und `EasyGearCharDB` (Charakter).

Von GitHub: *Code > Download ZIP*, entpacken und den inneren Ordner `EasyGear` kopieren - nicht den Ordner des ZIPs
selbst (`EasyGear-Forever-main`), in dem auch Tests und Werkzeuge liegen.

## Was du siehst

| Wo | Was |
|---|---|
| Taschen, Bank | grüner **Pfeil** oben links an einem Item, das besser ist als das Getragene |
| Händler, Beute, Würfelfenster, Handel (Items des Partners), Post-Anhänge | derselbe Pfeil |
| Questbelohnungen | der Pfeil und ein grüner **Haken** an der besten Wahl, wenn es mehrere gibt (größte Verbesserung, sonst höchster Verkaufspreis) |
| Charakterfenster | ein Pfeil am Ausrüstungsplatz, für den in den Taschen etwas Besseres liegt |
| Item-Tooltips | `EasyGear  Wertung: 81` - Platz und Wertung des ersetzten Items, das Urteil (`VERBESSERUNG +37 (+83.1%)`, `KEINE VERBESSERUNG`, `NICHT VERWENDBAR`, `VERBESSERUNG ab Stufe 45`) und die Attribut-Unterschiede |
| Getragene Items, Vergleichs-Tooltips | nur die Wertung |

Ein **gelber** Pfeil heißt: wäre eine Verbesserung, aber deine Stufe reicht noch nicht. Items, die der Client
als unbrauchbar für dich kennzeichnet (falsche Rüstungsart, Klasse), bekommen nie einen Pfeil.

Ein **violetter Stern** an derselben Stelle heißt: keine Verbesserung für dich, aber für jemanden in deiner Gruppe besser
als das, was er trägt - siehe [Gruppenhinweise](#gruppenhinweise).

Hier steht, wie die Markierungen aussehen, solange du nichts änderst. **Form und Farbe jeder Markierung wählst du selbst**
- siehe [Aussehen der Markierungen](#aussehen-der-markierungen).

**Vergleichsfenster** (`/eg`, `/eggui` oder der Eintrag im Addon-Fach): ein Item auf das linke Feld ziehen,
bei offenem Fenster mit Umschalt anklicken oder `/eg <Itemlink>` eingeben. Es zeigt die volle Rechnung beider
Items (Attribut, Wert, Gewicht, Punkte) und das Urteil. Ringe, Schmuck und Einhandwaffen haben je einen Reiter
pro Platz.

**Profilfenster** (`/egprofile`): links das gewählte Vergleichsprofil, rechts dein aktives, beide auf die
Ausrüstung angewandt, die du gerade trägst.

## Befehle

`/eg` oder `/easygear`; `/eggui` öffnet das Fenster, `/egprofile` das Profilfenster. Die Befehle sind oben in
der englischen Tabelle aufgeführt und in jeder Sprache gleich; `/eg help` erklärt sie in deiner Sprache.
Wichtig sind `/eg upgrades` (alle Verbesserungen in den Taschen), `/eg group` (die Gruppe: wer gelesen ist, was für wen besser wäre), `/eg profile ...` (Profil wählen),
`/eg marker` (Form und Farbe der Markierungen), `/eg weight <Wert> <Gewicht>` (Gewicht im eigenen Profil), `/eg status` (Profil, erkannte Talentpunkte,
Zustand jeder Oberflächen-Anbindung), `/eg parse <Itemlink>` (was aus einem Item gelesen wurde) und
`/eg unknown` (Werte, die das Addon nicht kennt).

## Bewertung

```
Wertung =  Gegenstandsstufe x Stufengewicht x (Charakterstufe / Höchststufe)
         + Summe aus (Wert x Gewicht)       Basiswerte + Verzauberung + Edelsteine + aktiver Sockelbonus
         + Waffen-DPS x Gewicht             (Nebenhand zählt halb)
         + leere Sockel x Sockelwert
```

* **Stufengewicht** 0,5 Punkte je Stufe auf der Höchststufe (`/eg ilvl`); wächst mit deiner Stufe
  (`/eg ilvlscale off` schaltet das ab).
* **Gewichte** stammen aus dem Profil, normiert auf das Hauptattribut des Profils (1,00).
* **Werte** kommen aus `C_Item.GetItemStats` (sprachunabhängig) und den Tooltipzeilen (Verzauberungen, Edelsteine,
  Sockelbonus). Die Zeilen werden mit Mustern gelesen, die zur Laufzeit aus den Texten des Clients gebaut werden.
* **Leere Sockel** zählen wie ein typischer Stein deiner Stufe für das Hauptattribut, minus 10 %.
* **Verbesserung** heißt: der Zugewinn ist positiv *und* mindestens `max(Minimum, Prozent der Wertung des Getragenen)`
  - Standard 0 Punkte und 1 %.

Verglichen wird je Platz: der Kandidat wird in jeden passenden Platz "eingesetzt"; der Platz mit dem größten
Zugewinn gewinnt.

## Profile

Ein Profil ist ein Satz Gewichte, z. B. *Waffen*, *Schutz* oder *Heilig*. Für jede der neun Klassen gibt es ein
Profil je Talentbaum, ein *Leveln*- und ein *Allround*-Profil, dazu zwei klassenunabhängige.

**Automatische Wahl** (Standard): der Talentbaum mit den meisten Punkten entscheidet (mindestens 5 Punkte). Unter der
Höchststufe gilt stattdessen das *Leveln*-Profil deiner Klasse - außer bei Tank- und Heilerbäumen
(`/eg autolevel off`: immer das Baumprofil). Ohne Talentangaben: *Allround* (Höchststufe) bzw. *Leveln*.
Hat ein Baum zwei Profile (der zweite Druidenbaum: *Katze* und *Bär*; der Furor-Baum der Krieger: Zweihand- und
Beidhändig-Variante), entscheidet die Rolle, die der Client für den Baum meldet (Tank, Heiler), dann die getragenen
Waffen, sonst das erste Profil - beim Druidenbaum also *Katze*. Meldet der Client den Baum nicht als Tankbaum,
wähle *Bär* selbst (`/eg profile DRUID_BEAR`).

**Eigene Profile** entstehen im Profilfenster: ein beliebiges Profil wählen, *Bearbeiten*, Gewichte ändern
(Dezimalkomma geht), *Als neues Profil speichern*. Eigene Profile lassen sich dort überschreiben, umbenennen und
löschen; sie gelten für das ganze Konto, das aktive Profil wird je Charakter gemerkt. Unbekannte Werte lassen
sich mit ihrem rohen Namen gewichten: `/eg unknown` listet sie, `/eg weight ITEM_MOD_xxx_SHORT 0.5` setzt das Gewicht.

## Plätze, Waffen, Ringe

Ringe und Schmuck werden mit beiden Plätzen verglichen. Eine Einhandwaffe darf in die Nebenhand, wenn der
Charakter beidhändig kämpfen kann und das Profil es will (Tanks, Heiler, Zauberer nur, wenn dort schon eine
Waffe liegt; nie, solange ein Schild oder Buch in der Nebenhand liegt); Nebenhand-Waffen zählen halb. Eine Zweihandwaffe wird mit Waffen- plus Nebenhand verglichen.
Einzigartige Items: das zweite Exemplar ersetzt das erste. Hemd und Wappenrock werden nie verglichen.

## Einstellungen

*Optionen > AddOns > EasyGear*: Markierungsgruppen, Gruppenhinweise (Stern, Mitglieder untersuchen, Schlachtzug), Aussehen der Markierungen (Form und Farbe), Tooltip-Teile, Verzauberungen, Leveln-Profil, Stufengewicht
und -skalierung, Mindestzugewinn, Profilwahl und ein Zurücksetzen-Knopf. Alles wirkt sofort - auch wenn du einen
Wert per Chatbefehl änderst, während die Seite offen ist.
Der Eintrag im Addon-Fach der Minimap: Linksklick Vergleichsfenster, Rechtsklick Einstellungen.

## Gruppenhinweise

Ein Item, das **für dich keine Verbesserung** ist, aber **für ein Gruppenmitglied besser als das, was es trägt**, bekommt
einen **violetten Stern** - in deinen Taschen, der Bank, Beutefenstern und Würfelfenstern (dort, wo der Pfeil erscheint).
Der Tooltip nennt, wer gewinnt:

```
Besser für die Gruppe:
Bob (Schatten)                    +12.3%
Eve (Allround)                    nichts angelegt
```

Ist das Item auch für dich besser, bekommst du den grünen Pfeil; der Tooltip nennt die Mitglieder trotzdem.

* **Wer zählt:** deine Gruppe. *Auch Schlachtzugsmitglieder* nimmt einen Schlachtzug dazu; dort ist fast jedes Item für
  irgendwen besser, deshalb ist es standardmäßig aus.
* **Was sie tragen:** das Addon untersucht Mitglieder wie das Untersuchen-Fenster. Höchstens eine Anfrage alle 2,5 Sekunden,
  nur Mitglieder in Reichweite, nie im Kampf und nie bei offenem Untersuchen-Fenster. Jede Untersuchung, die du oder ein
  anderes Addon startest, wird mitgenommen. Ein Mitglied wird nach fünf Minuten oder bei einem Wechsel seiner Ausrüstung
  neu gelesen; außer Reichweite oder offline bleibt der letzte Stand. Wer wenig trägt (niedrige Stufe, nackter
  Zweitcharakter), wird nur ein paarmal angesehen, eine leere Antwort löscht nie einen guten Stand, und ein
  Ausrüstungswechsel wird nicht öfter als alle 30 Sekunden neu gelesen. Nach einer Untersuchung, die du oder ein
  anderes Addon gestartet hast, wartet das Addon ein paar Sekunden. *Gruppenmitglieder untersuchen* aus: nur
  Untersuchungen, die du selbst startest, zählen.
* **Welches Profil:** die Talente des untersuchten Mitglieds, wenn der Client sie herausgibt (und drei verschiedene
  Bäume nennt); sonst der Klassenstandard - das Allround-Profil, unter der Höchststufe das Leveln-Profil der Klasse.
  Druiden des Wildheitsbaums werden als Katze bewertet.
* **Wie bewertet wird:** wie bei deinen eigenen Items (Profil, Stufe und getragene Ausrüstung des Mitglieds), mit den
  Schwellen deiner Einstellungen und mindestens 3 %: die Gewichte sind Schätzwerte, und ein Stern soll etwas heißen.
* **Wer es nutzen kann:** die Klassenzeile des Tooltips, die Rüstungsart (ein Plattenträger bekommt keinen Stoff
  angeboten), die Waffenarten der Klasse (`Classes.lua`, die klassischen Regeln) und die Stufe. Das Mitglied muss es
  nutzen können **oder höchstens eine Stufe zu niedrig sein** - der Tooltip ergänzt dann `ab Stufe N`.
* **Waffen** werden nur mit gleichartigen verglichen: Einhand mit Einhand (die Nebenhand zählt halb), Zweihand mit
  Zweihand, Schild mit Schild, Halteitem mit Halteitem. Ob jemand seine Haltung wechseln sollte, entscheidet das Addon nicht.
* **Ein leerer Platz** zählt nur, wenn der Stand des Mitglieds vollständig ist (acht oder mehr getragene Teile): ein
  unfertiger Stand sagt nichts über einen fehlenden Ring.
* **Gebundene Items** in deinen Taschen und der Bank bekommen keinen Stern und ihr Tooltip nennt niemanden - du kannst
  sie nicht abgeben -, es sei denn, ihre Tauschfrist (bei erbeuteten Items, steht im Tooltip) läuft noch.
* **Baganator und EllesmereUI** zeigen den Stern an derselben Stelle wie den Pfeil; Baganator nur bei Items in den
  Taschen und der Bank dieses Charakters.
* `/eg group` listet die Mitglieder, ihr Profil (aus Talenten oder Klassenstandard) und wann sie gelesen wurden;
  `/eg group scan` liest alle neu.

## Aussehen der Markierungen

*Optionen > AddOns > EasyGear > Aussehen der Markierungen* lässt dich **Form und Farbe** jeder Markierung wählen. Es gibt
fünf Arten:

| Art (Wort für `/eg marker`) | Erscheint an | Original |
|---|---|---|
| Verbesserung für dich (`upgrade`) | Ausrüstung, die besser ist als die getragene | grüner Pfeil |
| Verbesserung, Stufe noch zu niedrig (`level`) | wäre eine Verbesserung, aber deine Stufe reicht noch nicht | gelber Pfeil |
| Besser für die Gruppe (`group`) | keine Verbesserung für dich, aber für ein Gruppenmitglied | violetter Stern |
| Beste Questbelohnung, Verbesserung (`pick`) | die größte Verbesserung unter mehreren Questbelohnungen | grüner Haken |
| Beste Questbelohnung, zum Verkaufen (`sell`) | keine Verbesserung darunter: der höchste Händlerpreis | grüner Haken |

* **Form:** Pfeil, Stern, Haken, Münze, Kreis, Raute, Dreieck, Mond, Quadrat, Kreuz, Totenkopf. Die Liste zeigt jede Form
  mit ihrem Bild.
* **Farbe:** das Farbfeld der Oberfläche (Farbkreis und Hex-Feld). Jede Farbe außer der ursprünglichen wird auf das graue
  Bild der Form gelegt, so kann jede Form jede Farbe annehmen; dunkle Teile eines Bildes bleiben dunkel, und sehr dunkle
  Farben ergeben dunkle Markierungen.
* Standard jeder Art ist das ursprüngliche Aussehen, genau wie zuvor - und wer die ursprüngliche Farbe einer Art mit ihrer
  ursprünglichen Form wählt, hat das Original zurück.
* Die Wahl gilt überall, wo die Markierungen erscheinen - Taschen, Bank, Händler, Beute, Würfeln, Handel, Post,
  Questbelohnungen, Charakterfenster - und in den Taschen von Baganator und EllesmereUI. Eine Änderung ist sofort zu sehen
  (beim Ziehen im Farbkreis, sobald du kurz innehältst).
* *Aussehen zurücksetzen* stellt alle Arten zurück (`/eg reset` auch, zusammen mit allen anderen Einstellungen).
* Dasselbe im Chat: `/eg marker` zeigt Arten, Formen und die Wahl; `/eg marker group diamond ff8800` wählt Form und Farbe
  (sechs Hexziffern `RRGGBB`; eines von beiden genügt, in beliebiger Reihenfolge); `/eg marker group reset` und `/eg marker reset` stellen
  eine Art oder alle zurück.
* Ein Wert, den es nicht gibt (von Hand geänderte Einstellungsdatei, eine Form aus einer anderen Fassung), gilt als Original.

## Baganator und EllesmereUI

Beide werden nicht gebraucht. Sind sie installiert, erscheint der Pfeil auch in ihren Fenstern; `/eg status` listet, was
EasyGear gefunden hat.

* **Baganator** (Taschen, Bank, Kriegsmeute-Bank, andere Charaktere) zeichnet seine Symbole über *Icon-Ecken*, die andere
  Addons füllen können. EasyGear meldet eine an, den **EasyGear-Markierung**, voreingestellt in der Ecke **oben
  rechts** (Baganator legt oben links Müllsymbol und Gegenstandsstufe ab). Grün heißt Verbesserung, gelb heißt: eine
  Verbesserung, sobald deine Stufe reicht. In Baganators Einstellungen unter *Icon-Ecken* lässt er sich verschieben oder
  entfernen. Außerdem meldet sich EasyGear als Quelle für die *Erkennung von Upgrades* an, damit Baganators Suche und
  Kategorien dasselbe Urteil benutzen; Baganator wählt sie selbst, wenn noch keine Quelle gewählt ist. Die Einstellung
  für Taschenmarkierungen (`/eg icons`) schaltet beides ab. Baganator läuft nur mit seinem Begleiter-Addon **Syndicator**;
  fehlt der, meldet EasyGear nichts an und sagt es in `/eg status`.
  Ein neues Eckenelement fügt Baganator nur in das Profil ein, das beim Anmelden aktiv ist. In einem anderen
  Baganator-Profil wählst du den **EasyGear-Markierung** selbst unter *Icon-Ecken*.
* **EllesmereUI**: sein Taschenmodul baut eigene Gegenstandsknöpfe, die die Haken auf die Funktionen der Oberfläche nicht
  sehen. Es bietet anderen Addons eine Overlay-Schnittstelle (`EUI_Bags.RegisterItemOverlayIcon`), die für jeden Platz der
  Taschen, der Reagenzientasche und der Bank läuft, in der Gitter- wie in der Listenansicht, auch für leere Plätze. EasyGear
  malt seinen Pfeil darüber - **oben rechts** am Gegenstand, weil oben links die Gegenstandsstufe steht -, und er
  verschwindet, wenn ein Platz geleert wird. Er ist halb so hoch wie das Symbol darunter (16 Pixel auf einem
  normalen Platz, 10 in der Listenansicht, nie unter 8). Die Fensterhaut von EllesmereUI blendet die Texturen der
  Gegenstandsknöpfe aus, die sie umgestaltet (Händler, Beute, Post, Questbelohnungen, Charakterfenster); die Markierungen
  von EasyGear sitzen darum auf einem eigenen Rahmen über jedem Knopf und bleiben sichtbar; der Rahmen folgt den
  Rahmenebenen, die die Taschen ihren Knöpfen später neu geben. In der Ansicht *Als Liste* des Händlerfensters deckt der
  Knopf die ganze Zeile, darum sitzt der Pfeil an der Ecke des Zeilensymbols (und an der anderen Ecke, wenn dort die
  Restmenge steht).
* Beide wurden anhand ihres Quelltexts (Baganator Release 834, EllesmereUI Bags 9.8.3) und ihrer öffentlichen
  Schnittstellen gebaut; **getestet wurde hier mit Modellen dieser Schnittstellen, nicht im Spiel mit den echten Addons**
  (siehe [Bekannte Grenzen](#bekannte-grenzen)).

## Fehlersuche

`/eg status` zeigt die Oberflächen-Anbindungen (`itembuttons`, `merchant`, `merchantstock`, `rolls`, `tooltip`, `settings`, `shiftclick`,
bei installiertem Baganator bzw. EllesmereUI auch `baganator` und `ellesmere`): ein roter Name mit Grund heißt, dass dieser Teil der Client-Oberfläche nicht gefunden wurde und die
Funktion aus ist. Dazu die erkannten Talentpunkte und der letzte interne Fehler. Interne Fehler erscheinen einmalig im Chat als `EasyGear[Name]: Meldung`.

**Fehler melden:** bitte die Ausgabe von `/eg status` mitschicken (Clientversion, erkannte Talentpunkte, welche
Anbindungen funktionieren), bei falsch bewerteten Items `/eg parse <Itemlink>` und den genauen Text eines
Lua-Fehlers (`/console scriptErrors 1` zeigt sie an). Bei den Gruppenhinweisen zusätzlich die Ausgabe von
`/eg group`: sie zeigt je Mitglied, ob und wann er gelesen wurde und warum nicht.

## Prüfung

Im Hauptordner dieses Repositories: `lua5.1 tests/run.lua` (Modultests auf einem Modell des Clients), `python3 tests/mutate.py`
(Mutationsprüfung: die Tests müssen künstliche Fehler bemerken), `tools/check.sh <Interface/AddOns des Forever-
Quelltexts>` (luacheck gegen eine aus dem Quelltext gebaute Standardbibliothek; jede Methode, jedes Ereignis, jede
Vorlage, Schrift, jeder Atlas und jede Funktion, die das Addon nennt, muss dort vorkommen).

Das belegt die Form der Aufrufe gegen den echten Quelltext und die Logik auf einem Modell - **es ersetzt keinen Lauf
im Spiel**.

## Bekannte Grenzen

* Im Spiel bisher nur kurz ausprobiert.
* **Die Gewichte sind Schätzwerte** nach den üblichen Prioritäten klassischer Wertungssysteme. Itemisierung und
  Balance von Forever können abweichen; im eigenen Profil nachstellen.
* Die drei Talentbäume werden in der Reihenfolge angenommen, in der der Client sie zeigt. Wählt die Erkennung ein
  falsches Profil, ein Profil selbst wählen und `/eg status` prüfen.
* Item-Effekte (Procs, Benutzen, Setboni) werden nicht bewertet; Prozentangaben in Texten nicht gelesen.
* Jedes Item bekommt den Stufenanteil, auch eines ohne bewertete Werte: es hat dann mindestens Stufe x Gewicht.
* Zweihandwaffen werden immer mit Waffen- plus Nebenhand zusammen verglichen; zwei Zweihänder gleichzeitig
  (Titanengriff-Art) sind nicht abgebildet.
* Ob du ein Item benutzen kannst (Klasse, Rüstungsart, Ruf, Beruf), liest das Addon aus den roten Zeilen des Tooltips,
  wenn es das Item zum ersten Mal ansieht; nach Rufgewinn oder neuer Fertigkeit gilt das erst nach dem nächsten
  Stufenaufstieg oder `/reload`.
* Das Auktionshaus wird nicht markiert. Heirlooms, Edelstein- oder Verzauberungsempfehlungen und automatisches
  Anlegen gibt es absichtlich nicht.
* Aussehen der Markierungen: die Formliste in den Optionen zeigt jede Form in ihren eigenen Farben (die Markierung selbst
  nimmt die gewählte Farbe), und die Farbe wird auf das graue Bild der Form gelegt - bei Formen mit dunklen Teilen ist
  das Ergebnis dunkler als die gewählte Farbe und ihr nur nahe. Die Tooltip-Zeilen (die violette Überschrift der
  Gruppenhinweise, die grüne Zeile der Questwahl) behalten ihre Farben.
* Die Gruppenhinweise sind Schätzungen: es gelten die Profilgewichte, Rüstungs- und Waffenarten folgen den klassischen
  Regeln in `Classes.lua` (dort ändern, wenn Forever abweicht), und ob der Client die Talente eines untersuchten
  Mitglieds herausgibt, ist nicht bekannt - ohne sie entscheidet der Klassenstandard. Sie brauchen das Untersuchen:
  Mitglieder, die nie in Reichweite kamen, werden nicht bewertet.
* Texte: Englisch und Deutsch vollständig; andere Sprachen teilweise übersetzt (Fehlendes erscheint englisch).
* Baganator und EllesmereUI sind über ihre öffentlichen Schnittstellen angebunden (Eckenelemente und Upgrade-Quelle;
  Overlay-Schnittstelle des Taschenmoduls) und gegen Modelle von ihnen getestet. Zeigt sich dort kein Pfeil, sagt
  `/eg status`, welcher Teil gefunden wurde. Die Offline-Ansichten fremder Charaktere von EllesmereUI werden nicht bemalt.
  Andere Taschen-Addons (Bagnon, ElvUI-Taschen, ...) werden nicht gezielt unterstützt.

## Die 3.3.5a-Ausgabe

Das Addon für den alten Wrath-Client (Interface 30300, mit ElvUI/Bagnon/Immersion und den GM-Heirloom-Werkzeugen)
liegt in einem eigenen Repository, [nexartgroup/EasyGear](https://github.com/nexartgroup/EasyGear). Diese Ausgabe ist ein neuer Code für den Forever-Client,
keine Aktualisierung jener.
