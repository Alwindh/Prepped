-- Paladin-specific reminders module
-- (Forever hides buffs from add-ons in combat, so there is no in-combat Seal reminder.)
local _, ns = ...
local API = ns.API

local PaladinReminders = {}

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

local paladinReminders = {
    { id = "paladin_aura", message = "No Aura Active!", mustNotRest = true },
    { id = "paladin_blessing", message = "No Blessing Active!", messageLow = "Blessing expiring (%ss left)", mustNotRest = true },
    { id = "paladin_kings", message = "Low on Symbol of Kings (%s left)", item = SYMBOL_OF_KINGS, family = GREATER_BLESSINGS, mustRest = true },
    { id = "paladin_divinity", message = "Low on Symbol of Divinity (%s left)", item = SYMBOL_OF_DIVINITY, family = DIVINE_INTERVENTION, mustRest = true },
    { id = "paladin_righteous_fury", message = "Missing Righteous Fury!", messageLow = "Righteous Fury expiring (%ss left)", mustNotRest = true },
}

local function PlayerHasShield()
    local itemID = GetInventoryItemID("player", 17) -- off hand
    if not itemID then return false end
    local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
    return itemClassID == 4 and itemSubClassID == 6 -- Armor / Shields
end

-- Vendor reagents: not needed with the Legacy perk "Reagent Economy"
local function CheckReagent(config)
    if not API.KnowsFamily(config.family) or API.HasReagentEconomy() then return nil end
    local count = C_Item.GetItemCount(config.item)
    if count < Prepped:GetRuleThreshold(config.id) then
        return string.format(config.message, count)
    end
    return nil
end

local checks = {
    paladin_kings = CheckReagent,
    paladin_divinity = CheckReagent,
}

function checks.paladin_aura(config)
    if IsMounted() or not API.KnowsFamily(AURAS) then return nil end
    if API.FindPlayerBuff(IsPaladinAura) == "missing" then return config.message end
    return nil
end

function checks.paladin_blessing(config)
    if IsMounted() or not API.KnowsFamily(BLESSINGS) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsBlessing, config.message, config.messageLow)
end

-- Only for Protection paladins with a shield in a group
function checks.paladin_righteous_fury(config)
    if IsMounted() or not API.KnowsFamily(RIGHTEOUS_FURY) then return nil end
    if not (IsInGroup() or GetNumGroupMembers() > 0) then return nil end
    if not PlayerHasShield() or API.GetPrimaryTalentTree() ~= TREE_PROTECTION then return nil end
    return Prepped:CheckTimedBuff(config.id, IsRighteousFury, config.message, config.messageLow)
end

function PaladinReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PALADIN" then return end
    Prepped:RunReminders(paladinReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(PaladinReminders)
end
