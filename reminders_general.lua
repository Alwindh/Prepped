-- General reminders (Multi-class)
local _, ns = ...
local API = ns.API

local GeneralReminders = {}

local generalRules = {
    {
        id = "general_water",
        message = "Low on water (%s left)",
        mustRest = true,
        onlyMana = true,
        checkWater = true,
        minLevelConfig = "general_water_minlevel",
    }
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

function GeneralReminders.CheckReminders()
    local isResting = IsResting()
    local powerType = UnitPowerType("player") -- 0 = Mana
    
    for _, config in ipairs(generalRules) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            
            if config.mustRest and not isResting then trigger = false end
            
            -- Mana Check
            if config.onlyMana and powerType ~= 0 then trigger = false end

            -- Min Level Check (if configured)
            if trigger and config.minLevelConfig then
                 local minLevel = Prepped:GetRuleThreshold(config.minLevelConfig, 10)
                 if UnitLevel("player") < minLevel then trigger = false end
            end

            -- Mage Exception for Water
            if trigger and config.id == "general_water" then
                local _, class = UnitClass("player")
                if class == "MAGE" then trigger = false end
            end
            
            if trigger and config.checkWater then
                local count = GetWaterCount()
                local threshold = 0
                if Prepped and Prepped.GetRuleThreshold then
                     threshold = Prepped:GetRuleThreshold(config.id)
                end
                
                if count >= threshold then 
                    trigger = false 
                else
                    displayMessage = string.format(config.message, count)
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
    Prepped:RegisterReminderModule(GeneralReminders)
end
