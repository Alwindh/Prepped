-- Multi-class reminders module (repairs)
local MultiClassReminders = {}

local multiclassReminders = {
    { id = "general_repair", message = "Repair your gear", mustRest = true },
}

-- Average durability of your equipped gear, in percent (100 without breakable items).
local function GetAverageDurability()
    local totalCurrent, totalMax = 0, 0
    for slot = 1, 19 do
        local current, max = GetInventoryItemDurability(slot)
        if current and max then
            totalCurrent = totalCurrent + current
            totalMax = totalMax + max
        end
    end
    if totalMax == 0 then return 100 end
    return (totalCurrent / totalMax) * 100
end

local checks = {}

-- Below the configured percentage; the group message names the percentage.
function checks.general_repair(config)
    local durability = GetAverageDurability()
    if durability < Prepped:GetRuleThreshold(config.id, 100) then
        return config.message, math.floor(durability)
    end
    return nil
end

function MultiClassReminders.CheckReminders()
    Prepped:RunReminders(multiclassReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(MultiClassReminders)
end
