-- General reminders (all classes)
local _, ns = ...
local API = ns.API

local GeneralReminders = {}

-- Every food buff is called "Well Fed" (they differ in their extra effect), and in
-- Forever cooked food's Well Fed also gives +5% experience from kills. Matching the
-- name these IDs have covers every food in any client language.
local WELL_FED = API.SpellFamily("Well Fed", {
    1248406,                                         -- Well Fed (Forever cooked food)
    19705, 19706, 19708, 19709, 19710, 19711, 24799, -- Well Fed (older foods)
}, { aura = true })
local IsFoodBuff = API.Matcher(WELL_FED)
-- Sitting at a camp for a minute combines the buffs of its objects into "Camp Benefits" (1 hour).
local CAMP_BENEFITS = API.SpellFamily("Camp Benefits", { 1229741 }, { aura = true })
local IsCampBuff = API.Matcher(CAMP_BENEFITS)

local generalReminders = {
    { id = "general_water", message = "Low on water (%s left)", mustRest = true },
    {
        id = "general_food",
        message = "Missing food buff (Well Fed)",
        messageLow = "Food buff expiring (%ss left)",
        mustNotRest = true,
        outOfCombat = true,
        noTravel = true,
    },
    {
        id = "general_camp",
        message = "Missing Camp Benefits",
        messageLow = "Camp Benefits expiring (%ss left)",
        mustNotRest = true,
        outOfCombat = true,
        noTravel = true,
    },
    { id = "general_talents", outOfCombat = true },
}

-- Water = any item whose use effect is the "Drink" spell (any client language).
-- Counted once per change of the bags, not on every check.
local waterCount, waterBagGeneration = 0, nil

local function AddWater(itemID, stackCount)
    if API.IsDrinkItem(itemID) then waterCount = waterCount + stackCount end
end

local function GetWaterCount()
    local generation = API.GetBagGeneration()
    if waterBagGeneration ~= generation then
        waterCount = 0
        API.ForEachBagItem(AddWater)
        waterBagGeneration = generation
    end
    return waterCount
end

-- Mana users, including druids in a form that uses rage or energy.
local function UsesMana()
    local maxMana = UnitPowerMax("player", 0) -- 0 = Mana
    if maxMana == nil or API.IsSecret(maxMana) then
        return UnitPowerType("player") == 0
    end
    return maxMana > 0
end

local checks = {}

-- Mana users from the configured level on; mages conjure their own.
function checks.general_water(config)
    if Prepped:GetPlayerClass() == "MAGE" or not UsesMana() then return nil end
    if UnitLevel("player") < Prepped:GetRuleThreshold("general_water_minlevel") then return nil end
    local count = GetWaterCount()
    if count < Prepped:GetRuleThreshold(config.id) then
        return string.format(config.message, count), count
    end
    return nil
end

-- Buffs worth keeping up while leveling.
local function LevelingBuff(matcher)
    return function(config)
        if not API.IsLeveling() then return nil end
        return Prepped:CheckTimedBuff(config.id, matcher, config.message, config.messageLow)
    end
end

checks.general_food = LevelingBuff(IsFoodBuff)
checks.general_camp = LevelingBuff(IsCampBuff)

function checks.general_talents()
    local unspent, staged = API.GetTalentPointStatus()
    if not unspent then return nil end
    if staged then return "Talent changes not applied" end
    if unspent > 0 then
        return unspent == 1 and "1 unspent talent point" or string.format("%d unspent talent points", unspent)
    end
    return nil
end

function GeneralReminders.CheckReminders()
    Prepped:RunReminders(generalReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(GeneralReminders)
end
