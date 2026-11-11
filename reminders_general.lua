-- General reminders (all classes)
local _, ns = ...
local API = ns.API

local GeneralReminders = {}

local IsFoodBuff = API.Matcher(API.WELL_FED)
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

-- Buffs worth keeping up while leveling; new characters are left alone.
local LEVELING_BUFF_MIN_LEVEL = 10

local function CheckLevelingBuff(config, matcher)
    if not API.IsLeveling() or UnitLevel("player") < LEVELING_BUFF_MIN_LEVEL then return nil end
    return Prepped:CheckTimedBuff(config.id, matcher, config.message, config.messageLow)
end

-- Only while you carry food that gives the buff: without it there's nothing you
-- can do about the reminder.
function checks.general_food(config)
    local text = CheckLevelingBuff(config, IsFoodBuff)
    if text and not API.HasBuffFood() then return nil end
    return text
end

function checks.general_camp(config)
    return CheckLevelingBuff(config, IsCampBuff)
end

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
