-- reminders_shaman.lua
-- Shaman reminders: totem items, Lightning or Water Shield, weapon imbues and reagents.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

-- Water Shield is new in Forever and its spell ID isn't known yet, so it is
-- recognised by its English name (English clients only) until it's listed here.
local LIGHTNING_SHIELD = { 324, 325, 905, 945, 8134, 10431, 10432 }
local SHIELDS = API.SpellFamily("Shields", LIGHTNING_SHIELD, { class = "SHAMAN", aura = true, englishNames = { "Water Shield" } })
local REINCARNATION = API.SpellFamily("Reincarnation", { 20608 }, { class = "SHAMAN" })
local WATER_WALKING = API.SpellFamily("Water Walking", { 546 }, { class = "SHAMAN" })
local WATER_BREATHING = API.SpellFamily("Water Breathing", { 131 }, { class = "SHAMAN" })

-- Weapon imbues; clicking casts the first you know of Windfury, Rockbiter,
-- Flametongue and Frostbrand Weapon.
local ROCKBITER = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }
local FLAMETONGUE = { 8024, 8027, 8030, 16339, 16341, 16342 }
local FROSTBRAND = { 8033, 8038, 10456, 16355, 16356 }
local WINDFURY = { 8232, 8235, 10486, 16362 }
local IMBUE_CHOICE = { WINDFURY, ROCKBITER, FLAMETONGUE, FROSTBRAND }
local ALL_IMBUES = {}
for _, list in ipairs(IMBUE_CHOICE) do
    for _, id in ipairs(list) do ALL_IMBUES[#ALL_IMBUES + 1] = id end
end
API.SpellFamily("Weapon imbues", ALL_IMBUES, { class = "SHAMAN" }) -- listed for /prepped debug

local IsShield = API.Matcher(SHIELDS)

-- Totems still need their element's totem item in your bags in Forever
-- (quest rewards at level 4, 10, 20 and 30). An element counts once you know
-- any of its totems. Forever has no Fire Nova Totem or Tranquil Air Totem.
local TOTEM_ELEMENTS = {
    { name = "Earth Totem", item = 5175, family = API.SpellFamily("Earth totems", {
        8071, 8154, 8155, 10406, 10407, 10408, -- Stoneskin Totem
        2484,                                  -- Earthbind Totem
        5730, 6390, 6391, 6392, 10427, 10428,  -- Stoneclaw Totem
        8075, 8160, 8161, 10442, 25361,        -- Strength of Earth Totem
        8143,                                  -- Tremor Totem
    }, { class = "SHAMAN" }) },
    { name = "Fire Totem", item = 5176, family = API.SpellFamily("Fire totems", {
        3599, 6363, 6364, 6365, 10437, 10438,  -- Searing Totem
        8181, 10478, 10479,                    -- Frost Resistance Totem
        8190, 10585, 10586, 10587,             -- Magma Totem
        8227, 8249, 10526, 16387,              -- Flametongue Totem
    }, { class = "SHAMAN" }) },
    { name = "Water Totem", item = 5177, family = API.SpellFamily("Water totems", {
        5394, 6375, 6377, 10462, 10463,        -- Healing Stream Totem
        5675, 10495, 10496, 10497,             -- Mana Spring Totem
        8166,                                  -- Poison Cleansing Totem
        8170,                                  -- Disease Cleansing Totem
        8184, 10537, 10538,                    -- Fire Resistance Totem
        16190, 17354, 17359,                   -- Mana Tide Totem
    }, { class = "SHAMAN" }) },
    { name = "Air Totem", item = 5178, family = API.SpellFamily("Air totems", {
        8177,                                  -- Grounding Totem
        10595, 10600, 10601,                   -- Nature Resistance Totem
        8512, 10613, 10614,                    -- Windfury Totem
        8835, 10627, 25359,                    -- Grace of Air Totem
        15107, 15111, 15112,                   -- Windwall Totem
        6495,                                  -- Sentry Totem
    }, { class = "SHAMAN" }) },
}

-- Talent tree order
local TREE_ELEMENTAL = 1
local TREE_RESTORATION = 3

local function IsEnhancementOrLeveling()
    -- Suppress only when Elemental or Restoration strictly leads.
    -- Enhancement leading, no talents yet, a tie, or no talent data -> show reminder.
    local primaryTree = API.GetPrimaryTalentTree()
    return primaryTree ~= TREE_ELEMENTAL and primaryTree ~= TREE_RESTORATION
end

local function ImbueSpell()
    for _, list in ipairs(IMBUE_CHOICE) do
        local spellID = API.BestKnownSpell(list)
        if spellID then return spellID end
    end
    return nil
end

local function CheckReagent(rule) return Prepped:CheckReagent(rule) end

Prepped:RegisterModule({
    class = "SHAMAN",
    group = "Shaman",
    reminders = {
        {
            -- The totem items you need (you know a totem of that element) but don't
            -- carry, e.g. after leaving one in the bank.
            id = "shaman_totems", label = L["Missing Totem Items"],
            description = L["Out of combat, warns when the Earth, Fire, Water or Air Totem item for totems you know isn't in your bags (for example when it's still in the bank)."],
            announce = { L["missing your {name}"], L["check your bank"] },
            outOfCombat = true,
            check = function(rule)
                local missing, firstItem
                for _, element in ipairs(TOTEM_ELEMENTS) do
                    if API.KnowsFamily(element.family) and C_Item.GetItemCount(element.item) == 0 then
                        missing = missing or {}
                        missing[#missing + 1] = API.GetItemName(element.item, element.name)
                        firstItem = firstItem or element.item
                    end
                end
                if not missing then return nil end
                local value = rule.value or {}
                rule.value = value
                value.name, value.count = ns.JoinList(missing), #missing
                return format(L["Missing %s"], value.name), value, API.GetItemIcon(firstItem)
            end,
        },
        {
            -- Clicking casts the shield you had up last.
            id = "shaman_shield_buff", label = L["Missing Shield Buff"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to keep Lightning Shield (or Water Shield) up. Clicking it casts the one you had up last."],
            adventuring = true, noTravel = true,
            family = SHIELDS, prefer = { LIGHTNING_SHIELD },
            check = function(rule)
                if not API.KnowsFamily(SHIELDS) then return nil end
                local name, spellID = Prepped:ChooseSpell(rule)
                return Prepped:CheckTimedBuff(rule, IsShield, name), nil, API.GetSpellIcon(spellID)
            end,
            action = function(rule) return Action.Cast(select(2, Prepped:ChooseSpell(rule))) end,
        },
        {
            -- Enhancement (or still leveling) only; both weapons when dual wielding.
            -- Only imbues count, not sharpening stones or oils (Forever lets them stack).
            id = "shaman_weapon_buff", label = L["Missing Weapon Imbue"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds Enhancement (and leveling) shamans to keep a weapon imbue up, on both weapons when dual wielding. Clicking it casts Windfury, Rockbiter, Flametongue or Frostbrand Weapon, the first you know."],
            adventuring = true, noTravel = true,
            icon = function() return API.GetSpellIcon(ImbueSpell()) end,
            check = function(rule)
                if not IsEnhancementOrLeveling() then return nil end
                local state, first, second = Prepped:CheckWeaponImbue(rule, true)
                if state == "expiring" then return format(L["%s expires in %s"], L["Weapon imbue"], ns.FormatDuration(first)) end
                if state ~= "missing" then return nil end
                return (first or not second) and L["Imbue your weapon"] or L["Imbue your off hand"]
            end,
            action = function() return Action.Cast(ImbueSpell()) end,
        },
        {
            id = "shaman_ankh", label = L["Buy Ankhs"], defaultThreshold = 8, unit = "count", range = { 0, 40, 1 },
            description = L["While resting, warns when you have fewer Ankhs than this (for Reincarnation)."],
            announce = { L["low on Ankhs ({count} left)"], L["buy more Ankhs"] },
            supply = true, item = 17030, itemName = "Ankh", family = REINCARNATION,
            check = CheckReagent,
        },
        {
            id = "shaman_fish_oil", label = L["Buy Fish Oil"], defaultThreshold = 10, unit = "count", range = { 0, 40, 1 },
            description = L["While resting, warns when you have less Fish Oil than this (for Water Walking)."],
            supply = true, item = 17058, itemName = "Fish Oil", family = WATER_WALKING,
            check = CheckReagent,
        },
        {
            id = "shaman_fish_scales", label = L["Buy Fish Scales"], defaultThreshold = 10, unit = "count", range = { 0, 40, 1 },
            description = L["While resting, warns when you have fewer Fish Scales than this (for Water Breathing)."],
            supply = true, item = 17057, itemName = "Shiny Fish Scales", family = WATER_BREATHING,
            check = CheckReagent,
        },
    },
})
