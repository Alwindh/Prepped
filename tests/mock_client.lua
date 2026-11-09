-- tests/mock_client.lua
-- A strict mock of the WoW Forever client (interface 16001), so Prepped can run
-- outside the game. "Strict": fields a real frame or API table doesn't have are
-- nil, so code that relies on something the client lacks fails the tests.
--
-- Mock.BuildEnv(S) returns the global environment for one scenario. S describes
-- the character and the world (all fields optional):
--   class, level, locale ("enUS" or "deDE"; German names get a "DE:" prefix), time
--   spells, futureSpells     learned / listed-but-not-learned spell IDs
--   buffs                    { { spellId = id, expires = time }, ... }
--   items                    { [itemID] = count } (C_Item.GetItemCount)
--   bags                     { { bag = n, slot = n, itemID = id, count = n }, ... }
--   equipped                 { [inventorySlot] = itemID }
--   enchants                 { [Enum.WeaponSlot] = { { type = Mock.IMBUE, ms = n, id = n }, ... } }
--   skills, talents          { [skillLineID] = rank }, { points in tree 1, 2, 3 }
--   pet                      { dead, happiness, foodTypes, canEat = { [itemID] = true } }
--   form                     shapeshift form ID (1 cat, 3 travel, 4 aquatic, 5 bear, ...)
--   resting, inCombat, mounted, inGroup, xpDisabled
--   ammoCount, rangedCount, rangedDurability, headDurability
--   aurasSecret              buff data hidden (combat): aura scans error, like on Forever
--   secretBuffs, neverSecret { [spellID] = true }: individually hidden / never-hidden buffs
--   reagentEconomy           the Legacy perk is learned
--   missingSpellIDs          { [spellID] = true } the client doesn't know
--   breakSettings            the Settings API errors

local Mock = {
    IMBUE = 3,      -- Enum.ItemEnchantType.Imbue (poisons, shaman imbues, warlock stones)
    TEMPORARY = 2,  -- Enum.ItemEnchantType.Temporary (sharpening stones, oils)
    metadata = {},  -- the TOC's "## Key: value" lines, set by the runner
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
def("Well Fed", 1248406, 19705, 19706, 19708, 19709, 19710, 19711, 24799) -- 1248406: Forever's cooked food
def("Camp Benefits", 1229741)
-- Hunter
def("Tame Beast", 1515)
def("Aspect of the Hawk", 13165, 14318, 14319, 14320, 14321, 14322, 25296)
def("Aspect of the Monkey", 13163); def("Aspect of the Cheetah", 5118); def("Aspect of the Pack", 13159)
def("Aspect of the Beast", 13161); def("Aspect of the Wild", 20043, 20190)
-- Mage
def("Arcane Intellect", 1459, 1460, 1461, 10156, 10157); def("Arcane Brilliance", 23028)
def("Frost Armor", 168, 7300, 7301); def("Ice Armor", 7302, 7320, 10219, 10220); def("Mage Armor", 6117, 22782, 22783)
def("Conjure Mana Agate", 759); def("Conjure Mana Jade", 3552); def("Conjure Mana Citrine", 10053); def("Conjure Mana Ruby", 10054)
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

local ITEMS = {
    [2504] = { name = "Worn Shortbow", classID = 2, subClassID = 2 },
    [2947] = { name = "Small Throwing Knife", classID = 2, subClassID = 16 },
    [1201] = { name = "Dull Heater Shield", classID = 4, subClassID = 6 },
    [2131] = { name = "Shortsword", classID = 2, subClassID = 7 },
    [159] = { name = "Refreshing Spring Water", classID = 0, subClassID = 5, spell = 430 },
    [117] = { name = "Tough Jerky", classID = 0, subClassID = 5 },
    [4536] = { name = "Shiny Red Apple", classID = 0, subClassID = 5 },
}

------------------------------------------------------------------------
-- Environment builder
------------------------------------------------------------------------
function Mock.BuildEnv(S)
    local locale = S.locale or "enUS"
    local function Loc(name) if name and locale == "deDE" then return "DE:" .. name end return name end
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

    -- Frames (strict: unknown fields are nil, like on real frames) -------
    local eventFrames = {}
    local Methods = {}
    local NOOP = function() end
    local NOOP_METHODS = {}
    for m in ([[SetPoint SetSize SetWidth SetHeight ClearAllPoints SetAllPoints SetColorTexture SetTextColor
        SetJustifyH SetJustifyV SetWordWrap SetFont SetFrameLevel SetFrameStrata SetTexture SetVertexColor
        SetAlpha SetScale SetParent EnableMouse UnregisterEvent UnregisterAllEvents HookScript
        SetFontObject]]):gmatch("%S+") do NOOP_METHODS[m] = true end
    local function NewObject(kind, name, parent)
        local obj = { __kind = kind, __name = name, __parent = parent, __shown = true, __scripts = {}, __events = {} }
        setmetatable(obj, { __index = function(_, k)
            if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
            if Methods[k] then return Methods[k] end
            if NOOP_METHODS[k] then return NOOP end
            return nil
        end })
        if name then env[name] = obj end
        return obj
    end
    function Methods:Show() self.__shown = true; local s = rawget(self, "__scripts").OnShow; if s then s(self) end end
    function Methods:Hide() self.__shown = false end
    function Methods:IsShown() return self.__shown end
    function Methods:GetName() return self.__name end
    function Methods:SetScript(k, f) self.__scripts[k] = f end
    function Methods:GetScript(k) return self.__scripts[k] end
    function Methods:RegisterEvent(ev) self.__events[ev] = true; eventFrames[self] = true end
    function Methods:RegisterUnitEvent(ev, ...) self.__events[ev] = { ... }; eventFrames[self] = true end
    function Methods:SetText(t) self.__text = t end
    function Methods:GetText() return self.__text end
    function Methods:GetUnboundedStringWidth() return #(self.__text or "") * 7 end
    function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function Methods:CreateTexture() return NewObject("Texture") end
    function Methods:CreateFontString() return NewObject("FontString") end

    env.CreateFrame = function(kind, name, parent)
        return NewObject(kind, name, parent)
    end
    env.UIParent = NewObject("Frame", "UIParent")
    env.GameFontNormalLarge = NewObject("Font", "GameFontNormalLarge")
    env.StaticPopupDialogs = {}
    env.SlashCmdList = {}

    -- Fires an event at every frame registered for it (unit events: matching unit only).
    env.__fire = function(event, ...)
        for f in pairs(eventFrames) do
            local reg = f.__events[event]
            local unit = ...
            local matches = reg == true
            if type(reg) == "table" then
                for _, u in ipairs(reg) do if u == unit then matches = true end end
            end
            if matches and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
        end
    end

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
        return NewInitializer("button", { name = name, click = click })
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

    -- Character and world state ------------------------------------------
    env.GetTime = function() return S.time or 1000 end
    env.GetLocale = function() return locale end
    env.UnitName = function() return "Tester" end
    env.GetRealmName = function() return "Ruleset" end
    env.UnitClass = function() return S.class, S.class end
    env.UnitLevel = function() return S.level or 60 end
    env.GetMaxPlayerLevel = function() return 60 end
    env.GetMaxLevelForPlayerExpansion = function() return 60 end
    env.IsXPUserDisabled = function() return S.xpDisabled == true end
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
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitOnTaxi = function() return false end
    env.UnitAffectingCombat = function() return S.inCombat == true end
    env.InCombatLockdown = function() return S.inCombat == true end
    env.IsMounted = function() return S.mounted == true end
    env.IsInGroup = function() return S.inGroup == true end
    env.GetNumGroupMembers = function() return S.inGroup and 5 or 0 end
    env.UnitExists = function(u) return u == "player" or (u == "pet" and S.pet ~= nil) end
    env.UnitIsDead = function(u) return u == "pet" and S.pet and S.pet.dead or false end
    env.GetInventoryItemID = function(_, slot) return S.equipped and S.equipped[slot] end
    env.GetInventoryItemCount = function(_, slot)
        if slot == 0 then return S.ammoCount or 0 end
        if slot == 18 then return S.rangedCount or 1 end
        return 1
    end
    env.GetInventoryItemDurability = function(slot)
        if slot == 18 and S.rangedDurability then return S.rangedDurability, S.rangedDurability end
        if slot == 1 then return S.headDurability or 100, 100 end
        return nil
    end
    env.GetBuildInfo = function() return "1.60.1", "70862", "Nov 7 2026", 16001 end
    env.C_AddOns = { GetAddOnMetadata = function(name, key) if name == "Prepped" then return Mock.metadata[key] end end }
    env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
    env.C_Container = {
        GetContainerNumSlots = function(bag) return (bag == 0 or bag == 5) and 16 or 0 end,
        GetContainerItemInfo = function(bag, slot)
            for _, it in ipairs(S.bags or {}) do
                if it.bag == bag and it.slot == slot then return { itemID = it.itemID, stackCount = it.count } end
            end
        end,
    }
    env.Enum = {
        ItemClass = { Weapon = 2, Armor = 4 },
        ItemWeaponSubclass = { Thrown = 16 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2 },
        WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 },
        ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 },
    }
    env.INVSLOT_AMMO, env.INVSLOT_MAINHAND, env.INVSLOT_OFFHAND, env.INVSLOT_RANGED = 0, 16, 17, 18
    env.C_EventUtils = { IsEventValid = function() return true end }
    env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT = 18, 18

    env.C_Item = {
        GetItemInfo = function(id)
            local it = ITEMS[id]; if not it then return nil end
            return Loc(it.name), "link", 1, 1, 1, "type", "subtype", 20, "", 0, 0, it.classID, it.subClassID
        end,
        GetItemInfoInstant = function(id)
            local it = ITEMS[id]; if not it then return nil end
            return id, "type", "subtype", "", 0, it.classID, it.subClassID
        end,
        GetItemCount = function(id) return (S.items and S.items[id]) or 0 end,
        GetItemSpell = function(id)
            local it = ITEMS[id]
            if it and it.spell then return SpellName(it.spell), it.spell end
        end,
        GetWeaponEnchantInfo = function(slot)
            local list = {}
            for _, e in ipairs((S.enchants and S.enchants[slot]) or {}) do
                list[#list + 1] = { hasEnchant = true, enchantType = e.type, timeLeft = e.ms, charges = 0, enchantID = e.id or 1, enchantIconID = 1 }
            end
            return list
        end,
    }
    env.C_Spell = { GetSpellName = SpellName }

    -- Spellbook: learned spells are "Spell" items, futureSpells "FutureSpell" items
    local known = {}
    for _, id in ipairs(S.spells or {}) do known[id] = true end
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
    return env
end

return Mock
