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

local generalReminders = {
    { id = "general_water", message = "Low on water (%s left)", mustRest = true },
    {
        id = "general_food",
        message = "Missing food buff (Well Fed)",
        messageLow = "Food buff expiring (%ss left)",
        mustNotRest = true,
        outOfCombat = true,
    },
}

local function GetWaterCount()
    local count = 0
    for bag = 0, API.NumBags() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- Water = any item whose use effect is the "Drink" spell (any client language)
            if info and API.IsDrinkItem(info.itemID) then
                count = count + info.stackCount
            end
        end
    end
    return count
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
    local _, class = UnitClass("player")
    if class == "MAGE" or not UsesMana() then return nil end
    if UnitLevel("player") < Prepped:GetRuleThreshold("general_water_minlevel", 10) then return nil end
    local count = GetWaterCount()
    if count < Prepped:GetRuleThreshold(config.id) then
        return string.format(config.message, count)
    end
    return nil
end

-- While leveling; not while mounted or in a travel form.
function checks.general_food(config)
    if API.IsTraveling() or not API.IsLeveling() then return nil end
    return Prepped:CheckTimedBuff(config.id, IsFoodBuff, config.message, config.messageLow)
end

function GeneralReminders.CheckReminders()
    Prepped:RunReminders(generalReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(GeneralReminders)
end
