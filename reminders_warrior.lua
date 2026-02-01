-- Warrior-specific reminders module
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
    {
        id = "warrior_battle_shout",
        message = "No Battle Shout Active!",
        messageLow = "Battle Shout expiring (%ss left)",
        inCombatOnly = true,
    },
}

-- Checks if the player has learned Battle Shout
local function PlayerKnowsBattleShout()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName == "Battle Shout" then
                return true
            end
        end
    end
    return false
end

-- Checks for Battle Shout buff and returns remaining time
local function GetBattleShoutExpiration()
    for i = 1, 40 do
        local name, _, _, _, duration, expirationTime = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if name == "Battle Shout" then
            if expirationTime and expirationTime > 0 then
                return expirationTime - GetTime()
            else
                return 999
            end
        end
    end
    return nil
end

function WarriorReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "WARRIOR" then return end
    
    local isResting = IsResting()
    local inCombat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown())
    local isMounted = IsMounted()
    
    local criticalTriggered = false
    local count = Prepped:GetAmmoCount()

    for _, config in ipairs(warriorReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = false
            local displayMessage = config.message
            
            -- Basic filters
            local filterPassed = true
            if config.mustRest and not isResting then filterPassed = false end
            if config.inCombatOnly and not inCombat then filterPassed = false end

            -- If we already showed a "No Ammo" or "Critical" warning, skip "Low"
            if config.id == "warrior_ammo_low" and criticalTriggered then
                filterPassed = false
            end
            
            if filterPassed then
                -- Battle Shout Logic
                if config.id == "warrior_battle_shout" then
                    if not isMounted and PlayerKnowsBattleShout() then
                        local remaining = GetBattleShoutExpiration()
                        if not remaining then
                            trigger = true
                            displayMessage = config.message
                        elseif Prepped:IsLowEnabled(config.id) then
                            local threshold = Prepped:GetRuleThreshold(config.id, 10)
                            if remaining <= threshold then
                                trigger = true
                                displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                            end
                        end
                    end
                -- Ammo Logic
                elseif config.ammoCheck then
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
    Prepped:RegisterReminderModule(WarriorReminders)
end
