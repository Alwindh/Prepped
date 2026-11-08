-- reminders_priest.lua
-- Priest-specific reminders for the Prepped addon

local _, ns = ...
local Compat = ns.Compat

local PriestReminders = {}

-- Reminder configuration
local priestReminders = {
    {
        id = "priest_fortitude",
        message = "Missing Power Word: Fortitude!",
        messageLow = "Fortitude expiring (%ss left)",
        mustNotRest = true,
    },
}

-- Spell IDs for all ranks of Power Word: Fortitude
local fortitudeSpellIDs = {1243, 1244, 1245, 2791, 10937, 10938, 25389}
local fortitudeNames = nil

-- Spell IDs for all ranks of Prayer of Fortitude
local prayerFortitudeSpellIDs = {21562, 21564, 25392}
local prayerFortitudeNames = nil

-- Build localized spell name lookup table for Fortitude
local function GetFortitudeNames()
    if fortitudeNames then return fortitudeNames end
    fortitudeNames = {}
    for _, spellID in ipairs(fortitudeSpellIDs) do
        local spellName = Compat.GetSpellName(spellID)
        if spellName then
            fortitudeNames[spellName] = true
        end
    end
    return fortitudeNames
end

-- Build localized spell name lookup table for Prayer of Fortitude
local function GetPrayerFortitudeNames()
    if prayerFortitudeNames then return prayerFortitudeNames end
    prayerFortitudeNames = {}
    for _, spellID in ipairs(prayerFortitudeSpellIDs) do
        local spellName = Compat.GetSpellName(spellID)
        if spellName then
            prayerFortitudeNames[spellName] = true
        end
    end
    return prayerFortitudeNames
end

-- Check if player knows any rank of Power Word: Fortitude
local function PlayerKnowsFortitude()
    local names = GetFortitudeNames()
    for name in pairs(names) do
        if Compat.KnowsSpellNamed(name) then
            return true
        end
    end
    return false
end

-- Check if player knows any rank of Prayer of Fortitude
local function PlayerKnowsPrayerFortitude()
    local names = GetPrayerFortitudeNames()
    for name in pairs(names) do
        if Compat.KnowsSpellNamed(name) then
            return true
        end
    end
    return false
end

-- Matches both regular Fortitude and Prayer of Fortitude
local function IsFortitudeBuff(name)
    return GetFortitudeNames()[name] or GetPrayerFortitudeNames()[name] or false
end

-- Main reminder check function
function PriestReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then
        return
    end
    
    -- Get state variables
    local isResting = IsResting()
    local inCombat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown())
    local isMounted = IsMounted()
    
    -- Process each reminder
    for _, config in ipairs(priestReminders) do
        if Prepped:IsRuleEnabled(config.id) then
            -- Apply filters
            local filterPassed = true
            if config.mustRest and not isResting then
                filterPassed = false
            end
            if config.mustNotRest and isResting then
                filterPassed = false
            end
            if config.inCombatOnly and not inCombat then
                filterPassed = false
            end
            
            if filterPassed then
                local trigger = false
                local displayMessage = config.message
                
                -- Check for Power Word: Fortitude
                if config.id == "priest_fortitude" then
                    -- Skip if mounted
                    if not isMounted then
                        -- Check if player knows Fortitude (Prayer or regular)
                        local knowsFortitude = PlayerKnowsPrayerFortitude() or PlayerKnowsFortitude()
                        
                        if knowsFortitude then
                            local state, remaining = Compat.FindPlayerBuff(IsFortitudeBuff)

                            if state == "missing" then
                                -- Buff is missing
                                trigger = true
                                displayMessage = config.message
                            elseif state == "present" and remaining and Prepped:IsLowEnabled(config.id) then
                                -- Check if buff is expiring soon
                                local threshold = Prepped:GetRuleThreshold(config.id, 60)
                                if remaining <= threshold then
                                    trigger = true
                                    displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                                end
                            end
                            -- "unknown": buff data hidden by combat restrictions, don't warn
                        end
                    end
                end
                
                -- Display the reminder if triggered
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
end

-- Register this module with the core system
if Prepped then
    Prepped:RegisterReminderModule(PriestReminders)
    print("Prepped: Priest module registered") -- Debug message
else
    print("Prepped: ERROR - Prepped core not found when loading priest module!") -- Debug message
end
