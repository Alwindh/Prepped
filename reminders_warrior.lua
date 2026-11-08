-- Warrior-specific reminders module
local _, ns = ...
local API = ns.API

local WarriorReminders = {}

local BATTLE_SHOUT = API.SpellFamily("Battle Shout", { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, { class = "WARRIOR", aura = true })

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
    return API.KnowsFamily(BATTLE_SHOUT)
end

local IsBattleShout = API.Matcher(BATTLE_SHOUT)

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
                        -- In combat, Forever may hide buff data ("unknown"): don't warn then.
                        local state, remaining = API.FindPlayerBuff(IsBattleShout)
                        if state == "missing" then
                            trigger = true
                            displayMessage = config.message
                        elseif state == "present" and remaining and Prepped:IsLowEnabled(config.id) then
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
