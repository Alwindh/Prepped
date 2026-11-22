-- tests/mock_client.lua
-- A strict mock of the WoW Forever client (interface 16001), so Prepped can run
-- outside the game. "Strict": fields a real frame or API table doesn't have are
-- nil, so code that relies on something the client lacks fails the tests. Secure
-- (protected) frames refuse changes during the combat lockdown, like the client.
--
-- Mock.BuildEnv(S) returns the global environment for one scenario. S describes
-- the character and the world (all fields optional):
--   class, level, locale ("enUS", "deDE", "frFR", "esES"; translated names get a
--                        "DE:"/"FR:"/"ES:" prefix), time
--   spells, futureSpells     learned / listed-but-not-learned spell IDs
--   buffs                    { { spellId = id, expires = time }, ... }
--   items                    { [itemID] = count } (C_Item.GetItemCount; every character
--                            carries a Hearthstone unless noHearthstone or items[6948] says otherwise)
--   bags                     { { bag = n, slot = n, itemID = id, count = n }, ... }
--   equipped                 { [inventorySlot] = itemID }
--   enchants                 { [Enum.WeaponSlot] = { { type = Mock.IMBUE, ms = n, id = n }, ... } }
--   skills, talents          { [skillLineID] = rank }, { points in tree 1, 2, 3 }
--   unspentTalents, stagedTalents   talent points left to spend; unapplied talent changes
--   unspentLegacy            Legacy points left to spend: { professions, adventure, progression },
--                            or a number for one currency shared by the three Legacy trees
--   pet                      { dead, happiness, foodTypes, canEat = { [itemID] = true } }
--   petActions               { { spellID = id, autocast = bool }, ... } (the pet action bar)
--   form                     shapeshift form ID (1 cat, 3 travel, 4 aquatic, 5 bear, ...)
--   resting, inCombat, mounted, dead, inGroup, inRaid, instanceGroup, xpDisabled
--   instanceType             "party" or "raid" while in a dungeon or raid instance
--   chatLockdown             Forever blocks add-on chat messages (combat restrictions)
--   ammoCount, rangedCount, rangedDurability, headDurability
--   durability               { [inventorySlot] = { current, max } }
--   aurasSecret              buff data hidden (combat): aura scans error, like on Forever
--   secretBuffs, neverSecret { [spellID] = true }: individually hidden / never-hidden buffs
--   reagentEconomy           the Legacy perk is learned (vendor reagents aren't needed)
--   reagentFreeSpells        { [spellID] = true }: castable without its reagent (a perk Prepped doesn't know)
--   freeBagSlots             free slots in the backpack (default: 16 minus the items in bag 0)
--   uncachedItems            { [itemID] = true }: item data not loaded yet (GetItemInfo/GetItemSpell return nil)
--   tooltipsDontNameBuff     food tooltips word the food buff differently from the buff's name
--   noTooltipAPI             the client has no C_TooltipInfo
--   noMenuUtil               the client has no MenuUtil (context menus)
--   missingSpellIDs          { [spellID] = true } the client doesn't know
--   breakSettings            the Settings API errors
--   shift                    Shift is held down

local Mock = {
    IMBUE = 3,      -- Enum.ItemEnchantType.Imbue (poisons, shaman imbues, warlock stones)
    TEMPORARY = 2,  -- Enum.ItemEnchantType.Temporary (sharpening stones, oils)
    metadata = {},  -- the TOC's "## Key: value" lines, set by the runner
    SCREEN_WIDTH = 1920,
    SCREEN_HEIGHT = 1080,
}

------------------------------------------------------------------------
-- Secret values: any operation other than storing/passing them errors
------------------------------------------------------------------------
local SecretMT = {}
local function secretError() error("attempt to operate on a secret value", 2) end
for _, mm in ipairs({ "__index", "__newindex", "__call", "__concat", "__add", "__sub", "__mul",
    "__div", "__mod", "__pow", "__unm", "__lt", "__le", "__len", "__eq" }) do
    SecretMT[mm] = secretError
end
local function Secret() return setmetatable({}, SecretMT) end
local function IsSecretValue(v) return type(v) == "table" and getmetatable(v) == SecretMT end

------------------------------------------------------------------------
-- Spell and item data (English names)
------------------------------------------------------------------------
local SPELLS = {}
local function def(name, ...) for _, id in ipairs({ ... }) do SPELLS[id] = name end end
def("Drink", 430, 431, 432, 1133, 1135, 1137)
def("Food", 433, 434, 435, 1127, 1129, 1131)
def("Well Fed", 1248406, 19705, 19706, 19708, 19709, 19710, 19711, 24799) -- 1248406: Forever's cooked food
def("Camp Benefits", 1229741)
-- Hunter
def("Tame Beast", 1515); def("Call Pet", 883); def("Revive Pet", 982); def("Feed Pet", 6991)
def("Aspect of the Hawk", 13165, 14318, 14319, 14320, 14321, 14322, 25296)
def("Aspect of the Monkey", 13163); def("Aspect of the Cheetah", 5118); def("Aspect of the Pack", 13159)
def("Aspect of the Beast", 13161); def("Aspect of the Wild", 20043, 20190)
def("Growl", 2649, 14916, 14917, 14918, 14919, 14920, 14921); def("Bite", 17253)
-- Mage
def("Arcane Intellect", 1459, 1460, 1461, 10156, 10157); def("Arcane Brilliance", 23028)
def("Frost Armor", 168, 7300, 7301); def("Ice Armor", 7302, 7320, 10219, 10220); def("Mage Armor", 6117, 22782, 22783)
def("Conjure Mana Agate", 759); def("Conjure Mana Jade", 3552); def("Conjure Mana Citrine", 10053); def("Conjure Mana Ruby", 10054)
def("Conjure Water", 5504, 5505, 5506, 6127, 10138, 10139, 10140); def("Conjure Food", 587, 597, 990, 6129, 10144, 10145, 28612)
def("Teleport: Stormwind", 3561); def("Teleport: Ironforge", 3562); def("Teleport: Undercity", 3563)
def("Teleport: Darnassus", 3565); def("Teleport: Thunder Bluff", 3566); def("Teleport: Orgrimmar", 3567)
def("Portal: Stormwind", 10059); def("Portal: Ironforge", 11416); def("Portal: Orgrimmar", 11417)
def("Portal: Undercity", 11418); def("Portal: Darnassus", 11419); def("Portal: Thunder Bluff", 11420)
def("Teleport: Stonard", 777777) -- a Forever-only teleport whose ID Prepped doesn't list
-- Paladin
def("Seal of Righteousness", 20154, 21084); def("Seal of Command", 20375); def("Seal of the Crusader", 21082)
def("Seal of Justice", 20164); def("Seal of Light", 20165); def("Seal of Wisdom", 20166); def("Seal of Fury", 20421, 20423)
def("Judgement", 20271)
def("Devotion Aura", 465); def("Retribution Aura", 7294); def("Concentration Aura", 19746)
def("Shadow Resistance Aura", 19876); def("Frost Resistance Aura", 19888); def("Fire Resistance Aura", 19891); def("Sanctity Aura", 20218)
-- Forever has no Blessing of Light or Sanctuary, and Salvation isn't a blessing any more
def("Blessing of Might", 19740); def("Blessing of Wisdom", 19742); def("Blessing of Kings", 20217)
def("Greater Blessing of Might", 25782); def("Greater Blessing of Wisdom", 25894); def("Greater Blessing of Kings", 25898)
def("Blessing of Protection", 1022)
def("Righteous Fury", 25780); def("Divine Intervention", 19752)
-- Priest
def("Power Word: Fortitude", 1243, 1244, 1245, 2791, 10937, 10938); def("Prayer of Fortitude", 21562, 21564)
def("Inner Fire", 588, 7128, 602, 1006, 10951, 10952); def("Prayer of Spirit", 27681); def("Prayer of Shadow Protection", 27683)
-- Rogue
def("Vanish", 1856, 1857); def("Poisons", 2842); def("Blind", 2094)
-- Shaman
def("Lightning Shield", 324, 325, 905, 945, 8134, 10431, 10432)
def("Water Shield", 900001) -- new in Forever; its real spell ID isn't known yet
def("Reincarnation", 20608); def("Water Walking", 546); def("Water Breathing", 131)
def("Rockbiter Weapon", 8017, 8018, 8019, 10399, 16314, 16315, 16316); def("Flametongue Weapon", 8024, 8027, 8030, 16339, 16341, 16342)
def("Frostbrand Weapon", 8033, 8038, 10456, 16355, 16356); def("Windfury Weapon", 8232, 8235, 10486, 16362)
def("Stoneskin Totem", 8071, 8154, 8155, 10406, 10407, 10408); def("Earthbind Totem", 2484)
def("Stoneclaw Totem", 5730, 6390, 6391, 6392, 10427, 10428); def("Strength of Earth Totem", 8075, 8160, 8161, 10442, 25361)
def("Tremor Totem", 8143)
def("Searing Totem", 3599, 6363, 6364, 6365, 10437, 10438, 900002) -- 900002: a rank Prepped doesn't list
def("Frost Resistance Totem", 8181, 10478, 10479) -- Forever has no Fire Nova Totem
def("Magma Totem", 8190, 10585, 10586, 10587); def("Flametongue Totem", 8227, 8249, 10526, 16387)
def("Healing Stream Totem", 5394, 6375, 6377, 10462, 10463); def("Mana Spring Totem", 5675, 10495, 10496, 10497)
def("Poison Cleansing Totem", 8166); def("Disease Cleansing Totem", 8170); def("Fire Resistance Totem", 8184, 10537, 10538)
def("Mana Tide Totem", 16190, 17354, 17359)
def("Grounding Totem", 8177); def("Nature Resistance Totem", 10595, 10600, 10601); def("Windfury Totem", 8512, 10613, 10614)
def("Grace of Air Totem", 8835, 10627, 25359); def("Windwall Totem", 15107, 15111, 15112); def("Sentry Totem", 6495)
-- Forever has no Tranquil Air Totem
-- Warrior
def("Battle Shout", 6673, 5242, 6192, 11549, 11550, 11551, 25289)
-- Warlock
def("Demon Skin", 687, 696); def("Demon Armor", 706, 1086, 11733, 11734, 11735)
def("Summon Imp", 688); def("Summon Voidwalker", 697); def("Summon Succubus", 712); def("Summon Felhunter", 691)
def("Torment", 3716, 7809, 7810, 7811, 11774, 11775); def("Suffering", 17735, 17750, 17751, 17752)
def("Create Healthstone (Minor)", 6201); def("Create Healthstone (Lesser)", 6202); def("Create Healthstone", 5699)
def("Create Healthstone (Greater)", 11729); def("Create Healthstone (Major)", 11730)
def("Create Soulstone (Minor)", 693); def("Create Soulstone (Lesser)", 20752); def("Create Soulstone", 20755)
def("Create Soulstone (Greater)", 20756); def("Create Soulstone (Major)", 20757)
def("Create Firestone (Lesser)", 6366); def("Create Firestone", 17951); def("Create Firestone (Greater)", 17952); def("Create Firestone (Major)", 17953)
def("Create Spellstone", 2362); def("Create Spellstone (Greater)", 17727); def("Create Spellstone (Major)", 17728)
def("Burning Wish", 18789); def("Fel Stamina", 18790); def("Touch of Shadow", 18791); def("Fel Energy", 18792)
def("Soulstone Resurrection", 20707, 20762, 20763, 20764, 20765)
-- Druid
def("Mark of the Wild", 1126, 5232, 6756, 5234, 8907, 9884, 9885); def("Gift of the Wild", 21849, 21850)
def("Rebirth", 20484, 20739, 20742, 20747, 20748, 888888) -- 888888: a Rebirth rank Prepped doesn't list
def("Teleport: Moonglade", 18960)
-- Legacy perks
def("Reagent Economy", 1262650); def("Some Other Perk", 999999)
Mock.SPELLS = SPELLS

-- The reagent each spell needs: a spell is usable (C_Spell.IsSpellUsable) only
-- with its reagent in the bags, unless a perk removes it. Reincarnation is only
-- usable while dead.
local REAGENTS = {}
local function reagent(item, vendor, ...) for _, id in ipairs({ ... }) do REAGENTS[id] = { item = item, vendor = vendor } end end
reagent(17020, true, 23028)                                       -- Arcane Powder: Arcane Brilliance
reagent(17031, true, 3561, 3562, 3563, 3565, 3566, 3567, 777777)  -- Rune of Teleportation
reagent(17032, true, 10059, 11416, 11417, 11418, 11419, 11420)    -- Rune of Portals
reagent(17030, true, 20608)                                       -- Ankh: Reincarnation
reagent(17058, true, 546); reagent(17057, true, 131)              -- Fish Oil, Fish Scales
reagent(21177, true, 25782, 25894, 25898); reagent(17033, true, 19752) -- Symbols of Kings / Divinity
reagent(17028, true, 21562); reagent(17029, true, 21564, 27681, 27683) -- Holy / Sacred Candles
reagent(17034, true, 20484); reagent(17035, true, 20739); reagent(17036, true, 20742)
reagent(17037, true, 20747); reagent(17038, true, 20748, 888888)  -- Rebirth seeds
reagent(17021, true, 21849); reagent(17026, true, 21850)          -- Wild Berries / Thornroot
reagent(5140, true, 1856, 1857)                                   -- Flash Powder: Vanish
reagent(5530, false, 2094)                                        -- Blinding Powder (not sold by vendors): Blind
local ONLY_WHILE_DEAD = { [20608] = true }

-- Food and drink are Consumables (class 0) of subclass 5. `use` is the tooltip's
-- "Use:" line; food with `wellFed` also gives the food buff, which only that line
-- tells ("... you will become well fed and gain <wellFed> ...").
local EAT = "Use: Restores 61 health over 18 sec. Must remain seated while eating."
local DRINK = "Use: Restores 151 mana over 18 sec. Must remain seated while drinking."
local ITEMS = {
    [2504] = { name = "Worn Shortbow", classID = 2, subClassID = 2 },
    [2947] = { name = "Small Throwing Knife", classID = 2, subClassID = 16 },
    [1201] = { name = "Dull Heater Shield", classID = 4, subClassID = 6 },
    [2131] = { name = "Shortsword", classID = 2, subClassID = 7 },
    [159] = { name = "Refreshing Spring Water", classID = 0, subClassID = 5, spell = 430, use = DRINK },
    [5350] = { name = "Conjured Water", classID = 0, subClassID = 5, spell = 430, use = DRINK },
    [117] = { name = "Tough Jerky", classID = 0, subClassID = 5, spell = 433, use = EAT },
    [4536] = { name = "Shiny Red Apple", classID = 0, subClassID = 5, spell = 433, use = EAT },
    [5349] = { name = "Conjured Muffin", classID = 0, subClassID = 5, spell = 433, use = EAT },
    [2680] = { name = "Spiced Wolf Meat", classID = 0, subClassID = 5, spell = 433, use = EAT, wellFed = "2 Stamina and Spirit" },
    [6888] = { name = "Herb Baked Egg", classID = 0, subClassID = 5, spell = 433, use = EAT, wellFed = "2 Stamina and Spirit" },
    -- Forever also has drinks that give the food buff; this one (name and ID) is made up
    [900003] = { name = "Berry Smoothie", classID = 0, subClassID = 5, spell = 430, use = DRINK, wellFed = "5% experience from kills" },
    [1251] = { name = "Linen Bandage", classID = 0, subClassID = 7 },
    [6948] = { name = "Hearthstone", classID = 15, subClassID = 0 },
    -- Reagents
    [17020] = { name = "Arcane Powder" }, [17031] = { name = "Rune of Teleportation" }, [17032] = { name = "Rune of Portals" },
    [17030] = { name = "Ankh" }, [17058] = { name = "Fish Oil" }, [17057] = { name = "Shiny Fish Scales" },
    [21177] = { name = "Symbol of Kings" }, [17033] = { name = "Symbol of Divinity" },
    [17028] = { name = "Holy Candle" }, [17029] = { name = "Sacred Candle" },
    [17034] = { name = "Maple Seed" }, [17035] = { name = "Stranglethorn Seed" }, [17036] = { name = "Ashwood Seed" },
    [17037] = { name = "Hornbeam Seed" }, [17038] = { name = "Ironwood Seed" },
    [17021] = { name = "Wild Berries" }, [17026] = { name = "Wild Thornroot" },
    [5140] = { name = "Flash Powder" }, [5530] = { name = "Blinding Powder" }, [6265] = { name = "Soul Shard" },
    [5175] = { name = "Earth Totem" }, [5176] = { name = "Fire Totem" }, [5177] = { name = "Water Totem" }, [5178] = { name = "Air Totem" },
    -- Poisons, stones, gems
    [6947] = { name = "Instant Poison", classID = 0, subClassID = 8 }, [8928] = { name = "Instant Poison VI", classID = 0, subClassID = 8 },
    [2892] = { name = "Deadly Poison", classID = 0, subClassID = 8 }, [3775] = { name = "Crippling Poison", classID = 0, subClassID = 8 },
    [5512] = { name = "Minor Healthstone" }, [5232] = { name = "Minor Soulstone" }, [5514] = { name = "Mana Agate" },
    [1254] = { name = "Lesser Firestone" }, [13699] = { name = "Firestone" }, [5522] = { name = "Spellstone" },
}
Mock.ITEMS = ITEMS

local LOCALE_PREFIX = { deDE = "DE:", frFR = "FR:", esES = "ES:", esMX = "ES:" }
local CLASS_NAMES = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior" }

-- Where frame points sit on a frame: fraction of its width, of its height.
local ANCHORS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

-- What a protected frame refuses during the combat lockdown.
local BLOCKED_IN_COMBAT = {}
for m in ([[Show Hide SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight SetAttribute SetParent
    SetFrameLevel SetFrameStrata EnableMouse RegisterForClicks]]):gmatch("%S+") do BLOCKED_IN_COMBAT[m] = true end

------------------------------------------------------------------------
-- Environment builder
------------------------------------------------------------------------
function Mock.BuildEnv(S)
    local locale = S.locale or "enUS"
    local prefix = LOCALE_PREFIX[locale]
    local function Loc(name) if name and prefix then return prefix .. name end return name end
    local function SpellName(id)
        if S.missingSpellIDs and S.missingSpellIDs[id] then return nil end
        return Loc(SPELLS[id])
    end

    local env = {}
    env._G = env
    for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "setmetatable",
        "getmetatable", "tonumber", "tostring", "type", "unpack", "rawget", "rawset", "math", "string", "table" }) do
        env[k] = _G[k]
    end
    local printed, errors = {}, {}
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, " ")
    end
    env.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
    env.__printed, env.__errors = printed, errors

    -- The combat lockdown starts after PLAYER_REGEN_DISABLED has been handled.
    local function InLockdown() return S.inCombat == true and not env.__regenDisabling end
    env.__blocked = {} -- protected frame changes refused during the lockdown

    -- Frames (strict: unknown fields are nil, like on real frames) -------
    local eventFrames, updateFrames = {}, {}
    local Methods = {}
    local NOOP = function() end
    local NOOP_METHODS = {}
    for m in ([[SetColorTexture SetTextColor SetJustifyH SetJustifyV SetWordWrap SetVertexColor SetAlpha SetScale
        UnregisterEvent UnregisterAllEvents HookScript SetFontObject SetTexCoord SetParent]]):gmatch("%S+") do NOOP_METHODS[m] = true end
    local function NewObject(kind, name, parent, template)
        local obj = { __kind = kind, __name = name, __parent = parent, __shown = true, __scripts = {}, __events = {},
            __attrs = {}, __template = template, __protected = template ~= nil and template:find("Secure", 1, true) ~= nil }
        setmetatable(obj, { __index = function(self, k)
            if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
            if rawget(self, "__protected") and BLOCKED_IN_COMBAT[k] and InLockdown() then
                return function() env.__blocked[#env.__blocked + 1] = k end
            end
            if Methods[k] then return Methods[k] end
            if NOOP_METHODS[k] then return NOOP end
            return nil
        end })
        if name then env[name] = obj end
        return obj
    end
    Mock.NewObject = NewObject
    function Methods:Show() self.__shown = true; local s = rawget(self, "__scripts").OnShow; if s then s(self) end end
    function Methods:Hide() self.__shown = false end
    function Methods:IsShown() return self.__shown end
    function Methods:IsVisible() return self.__shown and (self.__parent == nil or self.__parent == env.UIParent or self.__parent:IsVisible()) end
    function Methods:GetName() return self.__name end
    function Methods:GetParent() return self.__parent end
    function Methods:SetScript(k, f)
        self.__scripts[k] = f
        if k == "OnUpdate" then updateFrames[self] = f and true or nil end
    end
    function Methods:GetScript(k) return self.__scripts[k] end
    function Methods:RegisterEvent(ev) self.__events[ev] = true; eventFrames[self] = true end
    function Methods:RegisterUnitEvent(ev, ...) self.__events[ev] = { ... }; eventFrames[self] = true end
    function Methods:SetText(t) self.__text = t end
    function Methods:GetText() return self.__text end
    function Methods:GetUnboundedStringWidth() return #(self.__text or "") * 7 end
    function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", self.__fontSize or 12, "" end
    function Methods:SetFont(_, size) self.__fontSize = size end
    function Methods:SetTexture(texture) self.__texture = texture end
    function Methods:GetTexture() return self.__texture end
    function Methods:CreateTexture() return NewObject("Texture", nil, self) end
    function Methods:CreateFontString() return NewObject("FontString", nil, self) end
    function Methods:SetFrameStrata(strata) self.__strata = strata end
    function Methods:GetFrameStrata() return self.__strata or "MEDIUM" end
    function Methods:SetFrameLevel(level) self.__level = level end
    function Methods:GetFrameLevel() return self.__level or 1 end
    function Methods:EnableMouse(enable) self.__mouse = enable end
    function Methods:EnableKeyboard(enable) self.__keyboard = enable end
    function Methods:SetPropagateKeyboardInput(propagate)
        if InLockdown() then env.__blocked[#env.__blocked + 1] = "SetPropagateKeyboardInput"; return end
        self.__propagate = propagate
    end
    function Methods:RegisterForDrag(...) self.__drag = { ... } end
    function Methods:RegisterForClicks(...) self.__clicks = { ... } end
    function Methods:SetMovable(movable) self.__movable = movable end
    function Methods:SetClampedToScreen(clamped) self.__clamped = clamped end
    function Methods:SetDontSavePosition(dontSave) self.__dontSave = dontSave end
    function Methods:StartMoving() env.__moving = self end
    function Methods:StopMovingOrSizing() env.__moving = nil end
    function Methods:SetAttribute(key, value) self.__attrs[key] = value end
    function Methods:GetAttribute(key) return self.__attrs[key] end
    function Methods:IsProtected() return self.__protected, self.__protected end

    -- Geometry: frames keep their size and anchors, and the Get* methods resolve
    -- them through the anchor chain, with UIParent filling a 1920x1080 screen.
    function Methods:SetPoint(point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if type(a) == "table" then
            relativeTo = a
            if type(b) == "string" then relativePoint, x, y = b, c, d else relativePoint, x, y = point, b, c end
        else
            relativeTo, relativePoint, x, y = self.__parent, point, a, b
        end
        local points = rawget(self, "__points") or {}
        for i, p in ipairs(points) do if p[1] == point then table.remove(points, i) break end end
        points[#points + 1] = { point, relativeTo or env.UIParent, relativePoint, x or 0, y or 0 }
        self.__points = points
    end
    function Methods:ClearAllPoints() self.__points = {}; self.__allPoints = nil end
    function Methods:SetAllPoints(relativeTo) self.__allPoints = relativeTo or self.__parent end
    function Methods:SetSize(w, h) self.__w, self.__h = w, h end
    function Methods:SetWidth(w) self.__w = w end
    function Methods:SetHeight(h) self.__h = h end
    function Methods:GetWidth() return self.__w or 0 end
    function Methods:GetHeight() return self.__h or 0 end
    function Methods:GetSize() return self.__w or 0, self.__h or 0 end
    function Methods:GetPoint(i)
        local p = (rawget(self, "__points") or {})[i or 1]
        if p then return p[1], p[2], p[3], p[4], p[5] end
    end
    function Methods:GetNumPoints() return #(rawget(self, "__points") or {}) end
    function Methods:GetEffectiveScale() return 1 end
    function Methods:GetScale() return 1 end
    local function Rect(frame, depth)
        if frame == env.UIParent then return 0, 0, Mock.SCREEN_WIDTH, Mock.SCREEN_HEIGHT end
        if (depth or 0) > 20 then return nil end
        local all = rawget(frame, "__allPoints")
        if all then return Rect(all, (depth or 0) + 1) end
        local p = (rawget(frame, "__points") or {})[1]
        if not p then return nil end
        local rl, rb, rw, rh = Rect(p[2], (depth or 0) + 1)
        if not rl then return nil end
        local rp, fp = ANCHORS[p[3]], ANCHORS[p[1]]
        local w, h = rawget(frame, "__w") or 0, rawget(frame, "__h") or 0
        return rl + rp[1] * rw + p[4] - fp[1] * w, rb + rp[2] * rh + p[5] - fp[2] * h, w, h
    end
    function Methods:GetRect() return Rect(self) end
    function Methods:GetCenter() local l, b, w, h = Rect(self); if l then return l + w / 2, b + h / 2 end end
    function Methods:GetLeft() return (Rect(self)) end
    function Methods:GetBottom() local _, b = Rect(self); return b end
    function Methods:GetTop() local _, b, _, h = Rect(self); if b then return b + h end end
    function Methods:GetRight() local l, _, w = Rect(self); if l then return l + w end end

    env.CreateFrame = function(kind, name, parent, template)
        return NewObject(kind, name, parent, template)
    end
    env.UIParent = NewObject("Frame", "UIParent")
    env.GameFontNormalLarge = NewObject("Font", "GameFontNormalLarge")
    env.StaticPopupDialogs = {}
    env.SlashCmdList = {}

    -- Fires an event at every frame registered for it (unit events: matching unit only).
    env.__fire = function(event, ...)
        if event == "PLAYER_REGEN_DISABLED" then env.__regenDisabling = true end
        for f in pairs(eventFrames) do
            local reg = f.__events[event]
            local unit = ...
            local matches = reg == true
            if type(reg) == "table" then
                for _, u in ipairs(reg) do if u == unit then matches = true end end
            end
            if matches and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
        end
        env.__regenDisabling = nil
    end

    -- Lets time pass: advances GetTime() and runs every OnUpdate script, in 0.1 s steps.
    env.__tick = function(seconds)
        for _ = 1, math.floor(seconds * 10 + 0.5) do
            S.time = (S.time or 1000) + 0.1
            for f in pairs(updateFrames) do f.__scripts.OnUpdate(f, 0.1) end
        end
    end

    -- Mouse and keyboard. A click on a secure action button runs its action
    -- (recorded in env.__actions), then PostClick, like the client.
    env.__actions = {}
    env.__click = function(button, mouseButton)
        mouseButton = mouseButton or "LeftButton"
        if not button.__shown then return false end
        if button.__protected then
            local attrs = button.__attrs
            local suffix = (mouseButton == "LeftButton" and "1") or (mouseButton == "RightButton" and "2") or ""
            local kind = attrs["type" .. suffix] or attrs.type
            if kind then
                env.__actions[#env.__actions + 1] = { type = kind, spell = attrs.spell, unit = attrs.unit, item = attrs.item,
                    targetSlot = attrs["target-slot"], macrotext = attrs.macrotext }
            end
        end
        local post = button.__scripts.PostClick
        if post then post(button, mouseButton, false) end
        return true
    end
    env.__enter = function(frame) local f = frame.__scripts.OnEnter; if f then f(frame) end end
    env.__leave = function(frame) local f = frame.__scripts.OnLeave; if f then f(frame) end end
    env.__mouseUp = function(frame, button) local f = frame.__scripts.OnMouseUp; if f then f(frame, button) end end
    env.__key = function(frame, key)
        local f = frame.__scripts.OnKeyDown
        if f and frame.__keyboard then f(frame, key) end
    end
    -- Drags `handle` by dx, dy: OnDragStart, the frame being moved moves, OnDragStop.
    env.__drag = function(handle, dx, dy)
        local start = handle.__scripts.OnDragStart
        if start then start(handle, "LeftButton") end
        local moving = env.__moving
        if moving then
            local l, b = moving:GetRect()
            moving.__points = { { "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", l + dx, b + dy } }
        end
        local stop = handle.__scripts.OnDragStop
        if stop then stop(handle) end
    end

    local tooltip = NewObject("GameTooltip", "GameTooltip")
    tooltip.__lines = {}
    function tooltip.SetOwner(self, owner) self.__owner = owner; self.__lines = {} end
    function tooltip.SetText(self, text) self.__lines = { text } end
    function tooltip.AddLine(self, text) self.__lines[#self.__lines + 1] = text end
    function tooltip.GetOwner(self) return self.__owner end
    env.__tooltipLines = function() return tooltip.__shown and tooltip.__lines or {} end

    if not S.noMenuUtil then
        env.MenuUtil = {
            CreateContextMenu = function(owner, generator)
                local menu = { owner = owner, items = {} }
                local root = {}
                function root.CreateTitle(_, text) menu.items[#menu.items + 1] = { kind = "title", text = text } end
                function root.CreateButton(_, text, callback) menu.items[#menu.items + 1] = { kind = "button", text = text, callback = callback } end
                function root.CreateDivider() menu.items[#menu.items + 1] = { kind = "divider" } end
                generator(owner, root)
                env.__menu = menu
                return menu
            end,
        }
    end
    -- Clicks the menu entry with this text.
    env.__menuClick = function(text)
        for _, item in ipairs(env.__menu and env.__menu.items or {}) do
            if item.text == text and item.callback then item.callback(); return true end
        end
        return false
    end

    local callbacks = {}
    env.EventRegistry = {
        RegisterCallback = function(_, event, func, owner)
            callbacks[event] = callbacks[event] or {}
            table.insert(callbacks[event], { func, owner })
        end,
    }
    env.__callback = function(event, ...)
        for _, c in ipairs(callbacks[event] or {}) do c[1](c[2], ...) end
    end

    -- Group chat: messages the add-on sends are kept in env.__chat
    env.__chat = {}
    env.C_ChatInfo = {
        SendChatMessage = function(message, chatType)
            assert(type(message) == "string" and #message <= 255, "chat message too long")
            env.__chat[#env.__chat + 1] = { message = message, chatType = chatType }
        end,
        InChatMessagingLockdown = function() return S.chatLockdown == true end,
    }
    env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2

    -- Settings API (Options > AddOns) ------------------------------------
    env.__opened, env.__popups = {}, {}
    env.StaticPopup_Show = function(name) env.__popups[#env.__popups + 1] = name end
    env.YES, env.NO, env.RESET, env.CANCEL = "Yes", "No", "Reset", "Cancel"
    local settingsByVar, categories = {}, {}
    env.__settings, env.__categories = settingsByVar, categories
    local function NewInitializer(kind, data)
        local init = { kind = kind, data = data }
        function init:SetParentInitializer(parent, predicate) self.parent = parent; self.predicate = predicate end
        function init:AddModifyPredicate(predicate) self.predicate = predicate end
        function init:AddSearchTags() end
        return init
    end
    local function NewCategory(name, parent)
        local layout = { initializers = {} }
        function layout:AddInitializer(init) self.initializers[#self.initializers + 1] = init end
        local category = { name = name, parent = parent, layout = layout, ID = 100 + #categories }
        function category:GetID() return self.ID end
        categories[#categories + 1] = category
        return category, layout
    end
    local function AddTo(category, init) category.layout:AddInitializer(init); return init end
    env.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        RegisterVerticalLayoutCategory = function(name) return NewCategory(name) end,
        RegisterVerticalLayoutSubcategory = function(parent, name) return NewCategory(name, parent) end,
        RegisterProxySetting = function(category, variable, varType, name, default, getValue, setValue)
            assert(type(variable) == "string" and type(name) == "string", "bad proxy arguments")
            assert(type(default) == varType, "default type mismatch for " .. variable)
            assert(not settingsByVar[variable], "duplicate setting variable " .. variable)
            local setting = { variable = variable, varType = varType, name = name, default = default, category = category, notified = 0 }
            function setting:GetValue() return getValue() end
            function setting:SetValue(value) setValue(value) end
            function setting:NotifyUpdate() self.notified = self.notified + 1; return getValue() end
            function setting:GetVariable() return variable end
            settingsByVar[variable] = setting
            return setting
        end,
        CreateCheckbox = function(category, setting) assert(setting.varType == "boolean"); return AddTo(category, NewInitializer("checkbox", { setting = setting })) end,
        CreateSlider = function(category, setting, options) assert(setting.varType == "number" and options); return AddTo(category, NewInitializer("slider", { setting = setting, options = options })) end,
        CreateColorSwatch = function(category, setting) assert(setting.varType == "string"); return AddTo(category, NewInitializer("color", { setting = setting })) end,
        CreateSliderOptions = function(minValue, maxValue, rate)
            local options = { minValue = minValue, maxValue = maxValue, rate = rate }
            function options:SetLabelFormatter(labelType, formatter) self.formatter = formatter end
            return options
        end,
        RegisterAddOnCategory = function(category) env.__addonCategory = category end,
        OpenToCategory = function(id) env.__opened[#env.__opened + 1] = id end,
    }
    env.CreateSettingsCheckboxSliderInitializer = function(cbSetting, cbLabel, cbTooltip, sliderSetting, sliderOptions)
        assert(cbSetting.varType == "boolean" and sliderSetting.varType == "number" and sliderOptions)
        return NewInitializer("checkboxSlider", { cbSetting = cbSetting, sliderSetting = sliderSetting, options = sliderOptions, label = cbLabel })
    end
    env.CreateSettingsListSectionHeaderInitializer = function(name) return NewInitializer("header", { name = name }) end
    env.CreateSettingsButtonInitializer = function(name, text, click, tooltip, addSearchTags)
        assert(addSearchTags ~= nil, "addSearchTags is required")
        return NewInitializer("button", { name = name, text = text, click = click })
    end
    env.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
    env.CreateColor = function(r, g, b)
        return { GenerateHexColor = function()
            return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
        end }
    end
    env.CreateColorFromHexString = function(hex)
        local r, g, b = tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
        return { GetRGB = function() return r, g, b end }
    end
    if S.breakSettings then env.Settings.RegisterVerticalLayoutCategory = function() error("settings broken") end end
    env.LOCALIZED_CLASS_NAMES_MALE = {}
    for token, name in pairs(CLASS_NAMES) do env.LOCALIZED_CLASS_NAMES_MALE[token] = Loc(name) end

    -- Character and world state ------------------------------------------
    env.GetTime = function() return S.time or 1000 end
    env.GetServerTime = function() return 1700000000 + math.floor(S.time or 1000) end
    env.GetLocale = function() return locale end
    env.UnitName = function() return "Tester" end
    env.GetRealmName = function() return "Ruleset" end
    env.UnitClass = function() return S.class, S.class end
    env.UnitLevel = function() return S.level or 60 end
    env.GetMaxPlayerLevel = function() return 60 end
    env.GetMaxLevelForPlayerExpansion = function() return 60 end
    env.IsXPUserDisabled = function() return S.xpDisabled == true end
    env.IsShiftKeyDown = function() return S.shift == true end
    local noMana = S.class == "WARRIOR" or S.class == "ROGUE"
    env.UnitPowerType = function()
        if S.form == 1 then return 3 end                -- cat form: energy
        if S.form == 5 or S.form == 8 then return 1 end -- bear forms: rage
        return noMana and 1 or 0
    end
    env.UnitPowerMax = function(_, powerType)
        if powerType == 0 then return noMana and 0 or 1000 end
        return 100
    end
    env.GetShapeshiftFormID = function() return S.form end
    env.IsResting = function() return S.resting == true end
    env.UnitIsDeadOrGhost = function() return S.dead == true end
    env.UnitOnTaxi = function() return false end
    env.UnitAffectingCombat = function() return S.inCombat == true end
    env.InCombatLockdown = InLockdown
    env.IsMounted = function() return S.mounted == true end
    env.IsInGroup = function(category)
        if category == 2 then return S.instanceGroup == true end
        return S.inGroup == true or S.inRaid == true or S.instanceGroup == true
    end
    env.IsInRaid = function(category)
        if category == 2 then return false end
        return S.inRaid == true
    end
    env.IsInInstance = function() return S.instanceType ~= nil, S.instanceType or "none" end
    env.GetNumGroupMembers = function() return (S.inGroup or S.inRaid or S.instanceGroup) and 5 or 0 end
    env.UnitExists = function(u) return u == "player" or (u == "pet" and S.pet ~= nil) end
    env.UnitIsDead = function(u) return u == "pet" and S.pet and S.pet.dead or false end
    env.GetInventoryItemID = function(_, slot) return S.equipped and S.equipped[slot] end
    env.GetInventoryItemCount = function(_, slot)
        if slot == 0 then return S.ammoCount or 0 end
        if slot == 18 then return S.rangedCount or 1 end
        return 1
    end
    env.GetInventoryItemTexture = function(_, slot)
        if slot == 0 then return (S.ammoCount or 0) > 0 and "itemicon:ammo" or nil end
        local id = S.equipped and S.equipped[slot]
        return id and ("itemicon:" .. id) or nil
    end
    env.GetInventoryItemDurability = function(slot)
        if S.durability and S.durability[slot] then return S.durability[slot][1], S.durability[slot][2] end
        if slot == 18 and S.rangedDurability then return S.rangedDurability, S.rangedDurability end
        if slot == 1 then return S.headDurability or 100, 100 end
        return nil
    end
    env.GetBuildInfo = function() return "1.60.1", "70862", "Nov 7 2026", 16001 end
    env.C_AddOns = { GetAddOnMetadata = function(name, key) if name == "Prepped" then return Mock.metadata[key] end end }
    env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
    local function NumSlots(bag) return (bag == 0 or bag == 5) and 16 or 0 end
    env.__bagSlotReads = 0
    env.C_Container = {
        GetContainerNumSlots = NumSlots,
        GetContainerItemInfo = function(bag, slot)
            env.__bagSlotReads = env.__bagSlotReads + 1
            for _, it in ipairs(S.bags or {}) do
                if it.bag == bag and it.slot == slot then return { itemID = it.itemID, stackCount = it.count } end
            end
        end,
        -- free slots, bag family (0 = any item)
        GetContainerNumFreeSlots = function(bag)
            if bag == 0 and S.freeBagSlots then return S.freeBagSlots, 0 end
            local used = 0
            for _, it in ipairs(S.bags or {}) do if it.bag == bag then used = used + 1 end end
            return NumSlots(bag) - used, 0
        end,
    }
    env.CanMerchantRepair = function() return S.merchantCanRepair == true end
    env.__talentWindowOpened = 0
    env.ToggleTalentFrame = function() env.__talentWindowOpened = env.__talentWindowOpened + 1 end
    env.__sounds = {}
    env.SOUNDKIT = { MAP_PING = 3175 }
    env.PlaySound = function(soundKitID) env.__sounds[#env.__sounds + 1] = soundKitID; return true end
    env.Enum = {
        ItemClass = { Consumable = 0, Weapon = 2, Armor = 4 },
        ItemConsumableSubclass = { Fooddrink = 5, Bandage = 7 },
        ItemWeaponSubclass = { Thrown = 16 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2 },
        WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 },
        ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 },
    }
    env.INVSLOT_AMMO, env.INVSLOT_MAINHAND, env.INVSLOT_OFFHAND, env.INVSLOT_RANGED = 0, 16, 17, 18
    env.C_EventUtils = { IsEventValid = function() return true end }
    env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT = 18, 18

    local function ItemCached(id) return ITEMS[id] ~= nil and not (S.uncachedItems and S.uncachedItems[id]) end
    env.C_Item = {
        GetItemInfo = function(id)
            if not ItemCached(id) then return nil end
            local it = ITEMS[id]
            return Loc(it.name), "link", 1, 1, 1, "type", "subtype", 20, "", 0, 0, it.classID, it.subClassID
        end,
        GetItemNameByID = function(id) if ItemCached(id) then return Loc(ITEMS[id].name) end end,
        GetItemInfoInstant = function(id)
            local it = ITEMS[id]; if not it then return nil end
            return id, "type", "subtype", "", "itemicon:" .. id, it.classID, it.subClassID
        end,
        GetItemCount = function(id)
            local count = S.items and S.items[id]
            if count == nil and id == 6948 and not S.noHearthstone then return 1 end -- everyone starts with one
            return count or 0
        end,
        GetItemSpell = function(id)
            if S.uncachedItems and S.uncachedItems[id] then return nil end
            local it = ITEMS[id]
            if it and it.spell then return SpellName(it.spell), it.spell end
        end,
        RequestLoadItemDataByID = function() end,
        GetWeaponEnchantInfo = function(slot)
            local list = {}
            for _, e in ipairs((S.enchants and S.enchants[slot]) or {}) do
                list[#list + 1] = { hasEnchant = true, enchantType = e.type, timeLeft = e.ms, charges = 0, enchantID = e.id or 1, enchantIconID = 1 }
            end
            return list
        end,
    }
    -- Item tooltips: the name, then the "Use:" line. Buff food names the buff there in
    -- the client's language, in lower case ("... you will become well fed ...").
    env.__tooltipReads = 0
    env.C_TooltipInfo = {
        GetItemByID = function(id)
            env.__tooltipReads = env.__tooltipReads + 1
            local it = ITEMS[id]
            if not it then return nil end
            if S.uncachedItems and S.uncachedItems[id] then
                return { type = 0, id = id, lines = { { leftText = "Retrieving item information" } } }
            end
            local lines = { { leftText = Loc(it.name) } }
            local use = Loc(it.use)
            if use and it.wellFed then
                local buff = S.tooltipsDontNameBuff and "refreshed" or string.lower(SpellName(19705))
                use = use .. " If you spend at least 10 seconds " .. (it.use == DRINK and "drinking" or "eating") .. " you will become "
                    .. buff .. " and gain " .. it.wellFed .. " for 15 min."
            end
            if use then lines[#lines + 1] = { leftText = use } end
            return { type = 0, id = id, lines = lines }
        end,
    }
    if S.noTooltipAPI then env.C_TooltipInfo = nil end

    -- Spellbook: learned spells are "Spell" items, futureSpells "FutureSpell" items
    local known = {}
    for _, id in ipairs(S.spells or {}) do known[id] = true end

    env.__usableChecks = 0
    env.C_Spell = {
        GetSpellName = SpellName,
        GetSpellTexture = function(id) if SPELLS[id] then return "spellicon:" .. id end end,
        -- isUsable, insufficientPower. Needs the spell's reagent unless a perk removes it.
        IsSpellUsable = function(id)
            env.__usableChecks = env.__usableChecks + 1
            if not known[id] or S.dead then return false, false end
            if ONLY_WHILE_DEAD[id] then return false, false end
            local need = REAGENTS[id]
            if not need then return true, false end
            if (S.reagentEconomy and need.vendor) or (S.reagentFreeSpells and S.reagentFreeSpells[id]) then return true, false end
            return ((S.items and S.items[need.item]) or 0) > 0, false
        end,
    }
    local book = {}
    for _, id in ipairs(S.spells or {}) do book[#book + 1] = { name = SpellName(id) or "?", spellID = id, actionID = id, itemType = 1, isOffSpec = false } end
    for _, id in ipairs(S.futureSpells or {}) do book[#book + 1] = { name = SpellName(id), spellID = id, actionID = id, itemType = 2, isOffSpec = false } end
    env.C_SpellBook = {
        IsSpellKnown = function(id) return known[id] == true end,
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
        GetSpellBookItemInfo = function(slot, bank) assert(bank == 0); return book[slot] end,
    }
    env.C_SkillInfo = {
        GetSkillLineInfoByID = function(id)
            local rank = S.skills and S.skills[id]
            if rank then return { skillID = id, name = "Skill", rank = rank, maxRank = 300 } end
        end,
    }

    -- Buffs. While buff data is hidden (combat), Forever refuses add-on scans with
    -- an error; outside of that, single buffs can still come back as secret values.
    local function IsAuraSecret(spellId)
        if S.neverSecret and S.neverSecret[spellId] then return false end
        return S.aurasSecret == true or (S.secretBuffs ~= nil and S.secretBuffs[spellId] == true)
    end
    local function BuffAt(i)
        local b = S.buffs and S.buffs[i]
        if not b then return nil end
        if IsAuraSecret(b.spellId) then return { name = Secret(), spellId = Secret(), expirationTime = Secret(), duration = Secret() } end
        return { name = SpellName(b.spellId), spellId = b.spellId, expirationTime = b.expires or 0, duration = b.duration or 0 }
    end
    env.__auraScans = 0
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            assert(unit == "player" and filter == "HELPFUL")
            env.__auraScans = env.__auraScans + 1
            if S.aurasSecret then
                error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'prepped'")
            end
            return BuffAt(i)
        end,
        GetPlayerAuraBySpellID = function(id)
            for _, b in ipairs(S.buffs or {}) do if b.spellId == id and not IsAuraSecret(id) then return { spellId = id } end end
        end,
    }
    env.issecretvalue = IsSecretValue
    env.canaccesstable = function() return true end
    env.C_Secrets = {
        ShouldAurasBeSecret = function() return S.aurasSecret == true end,
        ShouldSpellAuraBeSecret = function(id) return IsAuraSecret(id) end,
        GetSpellAuraSecrecy = function(id) return (S.neverSecret and S.neverSecret[id]) and 0 or 2 end,
    }

    -- Talents (class tree 900) and Legacy trees (1187-1189; Reagent Economy is node 2 of 1188)
    local t = S.talents or { 0, 0, 0 }
    env.Constants = { LegacyConsts = { LEGACY_TREE_PROFESSIONS_ID = 1187, LEGACY_TREE_ADVENTURE_ID = 1188, LEGACY_TREE_PROGRESSION_ID = 1189 } }
    env.C_ClassTalents = { GetActiveConfigID = function() return 7 end }
    env.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 7 end }
    env.C_Traits = {
        GetConfigInfo = function(id) assert(id == 7); return { treeIDs = { 900 } } end,
        GetGroupDisplayInfoByTreeID = function(tree)
            assert(tree == 900)
            return {
                { groupID = 33, orderIndex = 2, displayName = "Tree3" },
                { groupID = 11, orderIndex = 0, displayName = "Tree1" },
                { groupID = 22, orderIndex = 1, displayName = "Tree2" },
            }
        end,
        GetGroupCurrencyInfo = function(cfg, ids)
            local spent = { [11] = t[1], [22] = t[2], [33] = t[3] }
            local out = {}
            for _, gid in ipairs(ids) do out[#out + 1] = { traitNodeGroupID = gid, currencyInfos = { { spent = spent[gid] } } } end
            return out
        end,
        GetTreeCurrencyInfo = function(cfg, tree, excludeStaged)
            if tree >= 1187 and tree <= 1189 then
                assert(cfg == 500 + tree)
                local legacy = S.unspentLegacy
                if type(legacy) == "number" then return { { traitCurrencyID = 50, quantity = legacy, spent = 0 } } end
                return { { traitCurrencyID = tree, quantity = legacy and legacy[tree - 1186] or 0, spent = 0 } }
            end
            assert(cfg == 7 and tree == 900)
            return { { traitCurrencyID = 1, quantity = S.unspentTalents or 0, spent = t[1] + t[2] + t[3] } }
        end,
        ConfigHasStagedChanges = function(cfg) return S.stagedTalents == true end,
        GetConfigIDByTreeID = function(treeID) if treeID >= 1187 and treeID <= 1189 then return 500 + treeID end end,
        GetTreeNodes = function(treeID) if treeID == 1188 then return { 1, 2 } end return {} end,
        GetNodeInfo = function(configID, nodeID)
            local purchased = (nodeID == 1) or (nodeID == 2 and S.reagentEconomy == true)
            return { ranksPurchased = purchased and 1 or 0, activeEntry = { entryID = nodeID * 10, rank = purchased and 1 or 0 } }
        end,
        GetEntryInfo = function(configID, entryID) return { definitionID = entryID * 10 } end,
        GetDefinitionInfo = function(definitionID) return { spellID = (definitionID == 200) and 1262650 or 999999 } end,
    }
    env.C_PetInfo = {
        GetPetHappiness = function() if S.pet then return S.pet.happiness, 100, 0 end end,
        GetPetFoodTypes = function() return S.pet and S.pet.foodTypes or {} end,
        CanPetEatItem = function(id) return S.pet ~= nil and S.pet.canEat ~= nil and S.pet.canEat[id] == true end,
    }
    -- The pet action bar (modern return values)
    env.NUM_PET_ACTION_SLOTS = 10
    env.GetPetActionInfo = function(index)
        local action = S.pet and S.petActions and S.petActions[index]
        if not action then return nil end
        return SpellName(action.spellID), "spellicon:" .. action.spellID, false, false, true, action.autocast == true, action.spellID
    end
    return env
end

return Mock
