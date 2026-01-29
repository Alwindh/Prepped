-- Rogue-specific reminders module
local RogueReminders = {}

local rogueReminders = {
    {
        id = "rogue_no_ammo",
        message = "No ammo/thrown equipped",
        noAmmoCheck = true,
    },
    {
        id = "rogue_ammo_critical",
        message = "Critically low on ammo/thrown (%s left)",
        ammoCheck = true,
    },
    {
        id = "rogue_ammo_low",
        message = "Low on ammo/thrown (%s left)",
        ammoCheck = true,
        mustRest = true,
    },
}

function RogueReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "ROGUE" then return end
    
    local isResting = IsResting()
    
    local criticalTriggered = false
    local count = Prepped:GetAmmoCount()

    for _, config in ipairs(rogueReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            
            if config.mustRest and not isResting then trigger = false end
            
            -- If we already showed a "No Ammo" or "Critical" warning, skip "Low"
            if config.id == "rogue_ammo_low" and criticalTriggered then
                trigger = false
            end

            -- Ammo Logic
            if trigger and config.ammoCheck then
                -- count is already fetched
                if not count or count == 0 then
                    trigger = false
                else
                    local threshold = 0
                    if Prepped and Prepped.GetRuleThreshold then
                        threshold = Prepped:GetRuleThreshold(config.id)
                    end
                    if count >= threshold then 
                        trigger = false 
                    else
                        -- If this is the critical warning and it triggered, mark it
                        if config.id == "rogue_ammo_critical" then
                            criticalTriggered = true
                        end
                    end
                    displayMessage = string.format(config.message, count)
                end
            end

            -- No Ammo Check
            if trigger and config.noAmmoCheck then
                -- count is already fetched
                if count ~= 0 then -- count == nil (no weapon) or count > 0 (has ammo)
                    trigger = false
                else
                    -- If "No Ammo" triggered, also treat it as "critical" to suppress "Low"
                    criticalTriggered = true
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
    Prepped:RegisterReminderModule(RogueReminders)
end
