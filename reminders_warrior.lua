-- Warrior-specific reminders module
-- (Forever hides buffs from add-ons in combat, so there is no Battle Shout reminder.)

local WarriorReminders = {}

local warriorReminders = {
    {
        id = "warrior_no_ammo",
        message = "No ammo/thrown equipped",
        noAmmoCheck = true,
    },
    {
        id = "warrior_ammo_critical",
        message = "Critically low on ammo/thrown (%s left)",
        ammoCheck = true,
    },
    {
        id = "warrior_ammo_low",
        message = "Low on ammo/thrown (%s left)",
        ammoCheck = true,
        mustRest = true,
    },
}

function WarriorReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "WARRIOR" then return end
    
    local isResting = IsResting()

    local criticalTriggered = false
    local count = Prepped:GetAmmoCount()

    for _, config in ipairs(warriorReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = false
            local displayMessage = config.message
            local value -- amount for the group message (Prepped:BuildGroupMessage)
            
            -- Basic filters
            local filterPassed = true
            if config.mustRest and not Prepped:IsSupplyTime() then filterPassed = false end

            -- If we already showed a "No Ammo" or "Critical" warning, skip "Low"
            if config.id == "warrior_ammo_low" and criticalTriggered then
                filterPassed = false
            end
            
            if filterPassed then
                -- Ammo Logic
                if config.ammoCheck then
                    trigger = true
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
                            if config.id == "warrior_ammo_critical" then
                                criticalTriggered = true
                            end
                        end
                        displayMessage = string.format(config.message, count)
                        value = count
                    end
                -- No Ammo Check
                elseif config.noAmmoCheck then
                    trigger = true
                    -- count is already fetched
                    if count ~= 0 then -- count == nil (no weapon) or count > 0 (has ammo)
                        trigger = false
                    else
                        -- If "No Ammo" triggered, also treat it as "critical" to suppress "Low"
                        criticalTriggered = true
                    end
                end
            end
            
            if trigger then
                Prepped:ShowReminder(displayMessage, config.id, value)
            end
        end
    end
end

if Prepped then
    Prepped:RegisterReminderModule(WarriorReminders)
end
