-- Multi-class reminders module
local MultiClassReminders = {}

local multiclassReminders = {
    {
        id = "general_repair",
        message = "REPAIR YOUR GEAR!",
        repairCheck = true,
        mustRest = true,
    },
}

-- Checks if the user's equipped gear's average durability is below the configured threshold.
local function GetAverageDurability()
    local totalCurrent = 0
    local totalMax = 0
    local itemCount = 0
    
    for i = 1, 19 do
        local current, max = GetInventoryItemDurability(i)
        if current and max then
            totalCurrent = totalCurrent + current
            totalMax = totalMax + max
            itemCount = itemCount + 1
        end
    end
    
    if totalMax == 0 then return 100 end -- No items or all indestructible
    return (totalCurrent / totalMax) * 100
end

function MultiClassReminders.CheckReminders()
    local isResting = IsResting()
    
    for _, config in ipairs(multiclassReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            
            if config.mustRest and not isResting then trigger = false end
            
            if trigger and config.repairCheck then
                local threshold = 100
                if Prepped and Prepped.GetRuleThreshold then
                    threshold = Prepped:GetRuleThreshold(config.id, 100)
                end
                
                local durability = GetAverageDurability()
                if durability >= threshold then
                    trigger = false
                end
            end
            
            if trigger then
                local line = Prepped:GetNextLine()
                if line then
                    line.text:SetText(displayMessage)
                    line:Show()
                end
            end
        end
    end
end

if Prepped then
    Prepped:RegisterReminderModule(MultiClassReminders)
end
