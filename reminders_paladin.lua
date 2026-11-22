-- reminders_paladin.lua
-- Paladin reminders: Aura, Blessing, Righteous Fury (on when tanking, off when
-- not) and Symbols.
-- (Forever hides buffs from add-ons in combat, so there is no in-combat Seal reminder.)

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local DEVOTION, RETRIBUTION, CONCENTRATION, SANCTITY = { 465 }, { 7294 }, { 19746 }, { 20218 }
local SHADOW_RES, FROST_RES, FIRE_RES = { 19876 }, { 19888 }, { 19891 }
local AURAS = API.SpellFamily("Auras", {
    465,   -- Devotion Aura
    7294,  -- Retribution Aura
    19746, -- Concentration Aura
    19876, -- Shadow Resistance Aura
    19888, -- Frost Resistance Aura
    19891, -- Fire Resistance Aura
    20218, -- Sanctity Aura
}, { class = "PALADIN", aura = true })
-- Forever's blessings: Might, Wisdom and Kings (Sanctuary is gone, Salvation isn't a blessing)
local MIGHT, WISDOM, KINGS = { 19740 }, { 19742 }, { 20217 }
local GREATER_BLESSINGS_IDS = { 25782, 25894, 25898 } -- Greater Blessing of Might, Wisdom, Kings
local GREATER_BLESSINGS = API.SpellFamily("Greater Blessings", GREATER_BLESSINGS_IDS, { class = "PALADIN" })
local BLESSINGS = API.SpellFamily("Blessings", {
    19740, -- Blessing of Might
    19742, -- Blessing of Wisdom
    20217, -- Blessing of Kings
    unpack(GREATER_BLESSINGS_IDS),
}, { class = "PALADIN", aura = true })
local RIGHTEOUS_FURY = API.SpellFamily("Righteous Fury", { 25780 }, { class = "PALADIN", aura = true })
local DIVINE_INTERVENTION = API.SpellFamily("Divine Intervention", { 19752 }, { class = "PALADIN" })

local IsPaladinAura = API.Matcher(AURAS)
local IsBlessing = API.Matcher(BLESSINGS)
local IsRighteousFury = API.Matcher(RIGHTEOUS_FURY)

local TREE_PROTECTION = 2 -- talent tree order: Holy, Protection, Retribution
local SYMBOL_OF_KINGS = 21177
local SYMBOL_OF_DIVINITY = 17033

local function PlayerHasShield()
    local itemID = GetInventoryItemID("player", API.OFF_HAND_SLOT)
    if not itemID then return false end
    local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
    return itemClassID == 4 and itemSubClassID == 6 -- Armor / Shields
end

local function RighteousFuryName()
    local spellID = API.BestKnownFamilySpell(RIGHTEOUS_FURY)
    return spellID and C_Spell.GetSpellName(spellID), spellID
end

-- Vendor reagents: hidden when not needed (Legacy perk "Reagent Economy", ...)
local function CheckReagent(rule) return Prepped:CheckReagent(rule) end

-- A buff with several choices: casts the one you had up last.
local function CheckChoice(rule, family, matcher)
    if not API.KnowsFamily(family) then return nil end
    local name, spellID = Prepped:ChooseSpell(rule)
    return Prepped:CheckTimedBuff(rule, matcher, name), nil, API.GetSpellIcon(spellID)
end

Prepped:RegisterModule({
    class = "PALADIN",
    group = "Paladin",
    reminders = {
        {
            id = "paladin_aura", label = L["Missing Aura"],
            description = L["Reminds you to have an Aura up. Clicking it casts the one you had up last."],
            adventuring = true, noTravel = true,
            family = AURAS, prefer = { DEVOTION, RETRIBUTION, CONCENTRATION, SANCTITY, SHADOW_RES, FROST_RES, FIRE_RES },
            check = function(rule) return CheckChoice(rule, AURAS, IsPaladinAura) end,
            action = function(rule) return Action.Cast(select(2, Prepped:ChooseSpell(rule))) end,
        },
        {
            id = "paladin_blessing", label = L["Missing Self-Blessing"], hasLowWarningToggle = true, defaultThreshold = 30, range = { 0, 600, 10 },
            description = L["Reminds you to have a Blessing on yourself when not resting. Clicking it casts the one you had up last on you."],
            adventuring = true, noTravel = true,
            family = BLESSINGS, prefer = { MIGHT, WISDOM, KINGS },
            check = function(rule) return CheckChoice(rule, BLESSINGS, IsBlessing) end,
            action = function(rule) return Action.Cast(select(2, Prepped:ChooseSpell(rule)), true) end,
        },
        {
            -- Only for Protection paladins with a shield in a group
            id = "paladin_righteous_fury", label = L["Missing Righteous Fury"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to turn on Righteous Fury if you are in a group, have a shield equipped, and are Protection spec."],
            adventuring = true, noTravel = true,
            check = function(rule)
                local name, spellID = RighteousFuryName()
                if not name then return nil end
                if not (IsInGroup() or GetNumGroupMembers() > 0) then return nil end
                if not PlayerHasShield() or API.GetPrimaryTalentTree() ~= TREE_PROTECTION then return nil end
                return Prepped:CheckTimedBuff(rule, IsRighteousFury, name), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(select(2, RighteousFuryName())) end,
        },
        {
            -- The other way round: a Holy or Retribution paladin with Righteous
            -- Fury up takes threat from the tank.
            id = "paladin_righteous_fury_off", label = L["Righteous Fury While Not Tanking"],
            description = L["In a dungeon or raid group, warns when Righteous Fury is on while your talents aren't Protection, so you don't take threat from the tank. Clicking it turns Righteous Fury off."],
            outOfCombat = true,
            check = function()
                local name, spellID = RighteousFuryName()
                if not name or not API.InGroupInstance() then return nil end
                local tree = API.GetPrimaryTalentTree()
                if tree == nil or tree == TREE_PROTECTION then return nil end
                if API.FindPlayerBuff(IsRighteousFury) ~= "present" then return nil end
                return format(L["Turn off %s (not tanking)"], name), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.CancelAura((RighteousFuryName())) end,
        },
        {
            id = "paladin_kings", label = L["Low Symbol of Kings"], defaultThreshold = 50, unit = "count", range = { 0, 200, 10 },
            description = L["While resting, warns when you have fewer Symbols of Kings than this (for Greater Blessings)."],
            announce = { L["low on Symbol of Kings ({count} left)"], L["buy more Symbols of Kings"] },
            supply = true, item = SYMBOL_OF_KINGS, itemName = "Symbol of Kings", family = GREATER_BLESSINGS,
            check = CheckReagent,
        },
        {
            id = "paladin_divinity", label = L["Low Symbol of Divinity"], defaultThreshold = 5, unit = "count", range = { 0, 20, 1 },
            description = L["While resting, warns when you have fewer Symbols of Divinity than this (for Divine Intervention)."],
            announce = { L["low on Symbol of Divinity ({count} left)"], L["buy more Symbols of Divinity"] },
            supply = true, item = SYMBOL_OF_DIVINITY, itemName = "Symbol of Divinity", family = DIVINE_INTERVENTION,
            check = CheckReagent,
        },
    },
})
