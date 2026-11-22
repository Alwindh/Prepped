-- reminders_mage.lua
-- Mage reminders: Arcane Intellect, armor, Mana Gem, conjured water and food,
-- reagents for Arcane Brilliance, teleports and portals.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local FROST_ARMOR = { 168, 7300, 7301 }
local ICE_ARMOR = { 7302, 7320, 10219, 10220 }
local MAGE_ARMOR = { 6117, 22782, 22783 }
local ALL_ARMORS = {}
for _, list in ipairs({ FROST_ARMOR, ICE_ARMOR, MAGE_ARMOR }) do
    for _, id in ipairs(list) do ALL_ARMORS[#ALL_ARMORS + 1] = id end
end

local ARCANE_INTELLECT = API.SpellFamily("Arcane Intellect", { 1459, 1460, 1461, 10156, 10157 }, { class = "MAGE", aura = true })
local ARCANE_BRILLIANCE = API.SpellFamily("Arcane Brilliance", { 23028 }, { class = "MAGE", aura = true })
local ARMORS = API.SpellFamily("Mage armors", ALL_ARMORS, { class = "MAGE", aura = true })
local CONJURE_MANA_GEM = API.SpellFamily("Conjure Mana Gem", { 759, 3552, 10053, 10054 }, { class = "MAGE" })
local CONJURE_WATER = API.SpellFamily("Conjure Water", { 5504, 5505, 5506, 6127, 10138, 10139, 10140 }, { class = "MAGE" })
local CONJURE_FOOD = API.SpellFamily("Conjure Food", { 587, 597, 990, 6129, 10144, 10145, 28612 }, { class = "MAGE" })
-- Teleports and portals to Forever-only places are recognised by the start of
-- their name ("Teleport: ", in the client's language) until their IDs are known.
local TELEPORTS = API.SpellFamily("Teleports", { 3561, 3562, 3563, 3565, 3566, 3567 }, { class = "MAGE", sharedPrefix = true })
local PORTALS = API.SpellFamily("Portals", { 10059, 11416, 11417, 11418, 11419, 11420 }, { class = "MAGE", sharedPrefix = true })

local IsIntellectBuff = API.Matcher(ARCANE_INTELLECT, ARCANE_BRILLIANCE)
local IsMageArmor = API.Matcher(ARMORS)

local MANA_GEMS = {
    5514, -- Agate
    5513, -- Jade
    8007, -- Citrine
    8008, -- Ruby
}

local function CheckReagent(rule) return Prepped:CheckReagent(rule) end

-- Conjured water or food below the threshold: out of combat, anywhere.
local function CheckConjured(rule, family, count, what)
    if not API.KnowsFamily(family) then return nil end
    if count < Prepped:GetRuleThreshold(rule.id) then
        return format(L["Conjure %s (%d left)"], what, count), count, API.GetSpellIcon(API.BestKnownFamilySpell(family))
    end
end

Prepped:RegisterModule({
    class = "MAGE",
    group = "Mage",
    reminders = {
        {
            id = "mage_ai_buff", label = L["Missing Arcane Intellect"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to keep Arcane Intellect (or Arcane Brilliance) on yourself."],
            adventuring = true, noTravel = true,
            check = function(rule)
                local spellID = API.BestKnownFamilySpell(ARCANE_INTELLECT)
                if not spellID then return nil end
                return Prepped:CheckTimedBuff(rule, IsIntellectBuff, C_Spell.GetSpellName(spellID)), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(API.BestKnownFamilySpell(ARCANE_INTELLECT), true) end,
        },
        {
            -- Clicking casts the armor you had up last; Ice Armor takes over from Frost Armor.
            id = "mage_armor_buff", label = L["Missing Armor Buff"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to keep an armor (Frost, Ice or Mage Armor) up. Clicking it casts the one you had up last."],
            adventuring = true, noTravel = true,
            family = ARMORS, prefer = { ICE_ARMOR, FROST_ARMOR, MAGE_ARMOR },
            upgrades = { { from = FROST_ARMOR, to = ICE_ARMOR } },
            check = function(rule)
                if not API.KnowsFamily(ARMORS) then return nil end
                local name, spellID = Prepped:ChooseSpell(rule)
                return Prepped:CheckTimedBuff(rule, IsMageArmor, name), nil, API.GetSpellIcon(spellID)
            end,
            action = function(rule) return Action.Cast(select(2, Prepped:ChooseSpell(rule))) end,
        },
        {
            id = "mage_mana_gem", label = L["Missing Mana Gem"],
            description = L["Reminds you to conjure a Mana Gem when you aren't resting and don't have one."],
            adventuring = true, outOfCombat = true,
            check = function()
                local spellID = API.BestKnownSpell(CONJURE_MANA_GEM.ids) or API.BestKnownFamilySpell(CONJURE_MANA_GEM)
                if not spellID or API.CountItems(MANA_GEMS) > 0 then return nil end
                return L["Conjure a Mana Gem"], nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(API.BestKnownSpell(CONJURE_MANA_GEM.ids) or API.BestKnownFamilySpell(CONJURE_MANA_GEM)) end,
        },
        {
            id = "mage_conjure_water", label = L["Conjure Water"], defaultThreshold = 20, unit = "count", range = { 0, 100, 5 },
            description = L["Out of combat, reminds you to conjure water when you have less than this."],
            outOfCombat = true, noTravel = true,
            check = function(rule) return CheckConjured(rule, CONJURE_WATER, ns.CountWater(), L["water"]) end,
            action = function() return Action.Cast(API.BestKnownFamilySpell(CONJURE_WATER)) end,
        },
        {
            id = "mage_conjure_food", label = L["Conjure Food"], defaultThreshold = 10, unit = "count", range = { 0, 100, 5 },
            description = L["Out of combat, reminds you to conjure food when you have less than this."],
            outOfCombat = true, noTravel = true,
            check = function(rule) return CheckConjured(rule, CONJURE_FOOD, ns.CountFood(), L["food"]) end,
            action = function() return Action.Cast(API.BestKnownFamilySpell(CONJURE_FOOD)) end,
        },
        {
            id = "mage_powder", label = L["Low Arcane Powder"], defaultThreshold = 10, unit = "count", range = { 0, 100, 1 },
            description = L["While resting, warns when you have less Arcane Powder than this (for Arcane Brilliance)."],
            announce = { L["low on Arcane Powder ({count} left)"], L["buy more Arcane Powder"] },
            supply = true, item = 17020, itemName = "Arcane Powder", family = ARCANE_BRILLIANCE,
            check = CheckReagent,
        },
        {
            id = "mage_rune_teleport", label = L["Low Runes of Teleportation"], defaultThreshold = 10, unit = "count", range = { 0, 60, 1 },
            description = L["While resting, warns when you have fewer Runes of Teleportation than this."],
            supply = true, item = 17031, itemName = "Rune of Teleportation", family = TELEPORTS,
            check = CheckReagent,
        },
        {
            id = "mage_rune_portals", label = L["Low Runes of Portals"], defaultThreshold = 10, unit = "count", range = { 0, 60, 1 },
            description = L["While resting, warns when you have fewer Runes of Portals than this."],
            announce = { L["low on Runes of Portals ({count} left)"], L["buy more Runes of Portals"] },
            supply = true, item = 17032, itemName = "Rune of Portals", family = PORTALS,
            check = CheckReagent,
        },
    },
})
