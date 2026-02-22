-- reminders_priest.lua
-- Priest-specific reminders for the Prepped addon

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
        local spellName = GetSpellInfo(spellID)
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
        local spellName = GetSpellInfo(spellID)
        if spellName then
            prayerFortitudeNames[spellName] = true
        end
    end
    return prayerFortitudeNames
end

-- Check if a spell with given name is learned
local function IsSpellLearned(spellName)
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellNameBook = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellNameBook == spellName then
                return true
            end
        end
    end
    return false
end

-- Check if player knows any rank of Power Word: Fortitude
local function PlayerKnowsFortitude()
    local names = GetFortitudeNames()
    for name in pairs(names) do
        if IsSpellLearned(name) then
            return true
        end
    end
    return false
end

-- Check if player knows any rank of Prayer of Fortitude
local function PlayerKnowsPrayerFortitude()
    local names = GetPrayerFortitudeNames()
    for name in pairs(names) do
        if IsSpellLearned(name) then
            return true
        end
    end
    return false
end

-- Check if player has Fortitude buff active
local function PlayerHasFortitude()
    local names = GetFortitudeNames()
    local prayerNames = GetPrayerFortitudeNames()
    
    for i = 1, 40 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then break end
        
        -- Check both regular Fortitude and Prayer of Fortitude
        if names[name] or prayerNames[name] then
            return true
        end
    end
    return false
end

-- Get remaining time on Fortitude buff in seconds
local function GetFortitudeExpiration()
    local names = GetFortitudeNames()
    local prayerNames = GetPrayerFortitudeNames()
    
    for i = 1, 40 do
        local name, _, _, _, _, expirationTime = UnitAura("player", i, "HELPFUL")
        if not name then break end
        
        -- Check both regular Fortitude and Prayer of Fortitude
        if names[name] or prayerNames[name] then
            if expirationTime and expirationTime > 0 then
                return expirationTime - GetTime()
            else
                -- Permanent buff (shouldn't happen with Fortitude, but handle it)
                return 999
            end
        end
    end
    return nil  -- Buff not found
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
                            local remaining = GetFortitudeExpiration()
                            
                            if not remaining then
                                -- Buff is missing
                                trigger = true
                                displayMessage = config.message
                            elseif Prepped:IsLowEnabled(config.id) then
                                -- Check if buff is expiring soon
                                local threshold = Prepped:GetRuleThreshold(config.id, 60)
                                if remaining <= threshold then
                                    trigger = true
                                    displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                                end
                            end
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
