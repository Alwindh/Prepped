-- Paladin-specific reminders module
local PaladinReminders = {}

local paladinReminders = {
    {
        id = "paladin_seal",
        message = "No Seal Active!",
        messageLow = "Seal is expiring soon (%ss left)",
        inCombatOnly = true,
    },
    {
        id = "paladin_aura",
        message = "No Aura Active!",
        mustNotRest = true,
    },
    {
        id = "paladin_blessing",
        message = "No Blessing Active!",
        mustNotRest = true,
    },
    {
        id = "paladin_kings",
        message = "Low on Symbol of Kings (%s left)",
        itemID = 17033,
        mustRest = true,
        minLevel = 52,
    },
}

-- List of Paladin Aura Spell IDs for localization support
local auraSpellIDs = {
    465,   -- Devotion Aura
    7294,  -- Retribution Aura
    19746, -- Concentration Aura
    19876, -- Shadow Resistance Aura
    19888, -- Frost Resistance Aura
    19891, -- Fire Resistance Aura
    20218, -- Sanctity Aura
    31792, -- Crusader Aura
}

local auraNames = nil
local lastJudgementTime = 0

local function GetAuraNames()
    if auraNames then return auraNames end
    auraNames = {}
    for _, id in ipairs(auraSpellIDs) do
        local name = GetSpellInfo(id)
        if name then
            auraNames[name] = true
        end
    end
    return auraNames
end

-- Checks for Seal buff and returns remaining time
local function GetSealExpiration()
    for i = 1, 40 do
        local name, _, _, _, duration, expirationTime = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if name:find("Seal of") then
            if expirationTime and expirationTime > 0 then
                return expirationTime - GetTime()
            else
                -- In some cases duration might be present but expirationTime is 0 (permanent)
                -- but Seals always have a duration.
                return 999 
            end
        end
    end
    return nil
end

-- Checks if the player has an active Aura buff
local function PlayerHasAura()
    local names = GetAuraNames()
    for i = 1, 40 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if names[name] then
            return true
        end
    end
    return false
end

-- Checks if the player has an active Blessing buff
local function PlayerHasBlessing()
    for i = 1, 40 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if name:find("Blessing of ") then
            return true
        end
    end
    return false
end

-- Checks if the player has learned any Seal spell
local function PlayerKnowsAnySeal()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName and spellName:find("Seal of") then
                return true
            end
        end
    end
    return false
end

-- Checks if the player has learned any Aura spell
local function PlayerKnowsAnyAura()
    local names = GetAuraNames()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName and names[spellName] then
                return true
            end
        end
    end
    return false
end

-- Checks if the player has learned any Blessing spell
local function PlayerKnowsAnyBlessing()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName and spellName:find("Blessing of ") then
                return true
            end
        end
    end
    return false
end

-- Checks if the player has learned the Judgement spell
local function PlayerKnowsJudgement()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName and (spellName:find("^Judgement") or spellName:find("^Judge")) then
                return true
            end
        end
    end
    return false
end

function PaladinReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PALADIN" then return end
    
    local inCombat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown())
    local isResting = IsResting()
    local playerLevel = UnitLevel("player")
    local isMounted = IsMounted()
    local currentTime = GetTime()
    
    for _, config in ipairs(paladinReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = false
            local displayMessage = config.message
            
            -- Basic filters
            local filterPassed = true
            if config.inCombatOnly and not inCombat then filterPassed = false end
            if config.mustRest and not isResting then filterPassed = false end
            if config.mustNotRest and isResting then filterPassed = false end
            
            if filterPassed then
                -- Business logic: Paladin Seal
                if config.id == "paladin_seal" then
                    if (currentTime - lastJudgementTime) < 2.0 then
                        -- Judgement suppression
                    elseif not PlayerKnowsAnySeal() or not PlayerKnowsJudgement() then
                        -- Don't warn if they can't seal/judge yet
                    else
                        local remaining = GetSealExpiration()
                        if not remaining then
                            trigger = true
                            displayMessage = config.message
                        elseif Prepped:IsLowEnabled(config.id) then
                            local threshold = Prepped:GetRuleThreshold(config.id, 5)
                            if remaining <= threshold then
                                trigger = true
                                displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                            end
                        end
                    end

                -- Business logic: Paladin Aura
                elseif config.id == "paladin_aura" then
                    if not isMounted and PlayerKnowsAnyAura() and not PlayerHasAura() then
                        trigger = true
                    end

                -- Business logic: Paladin Blessing
                elseif config.id == "paladin_blessing" then
                    if not isMounted and PlayerKnowsAnyBlessing() and not PlayerHasBlessing() then
                        trigger = true
                    end

                -- Business logic: Symbol of Kings (Reagents)
                elseif config.itemID then
                    local count = GetItemCount(config.itemID)
                    local userThreshold = Prepped:GetRuleThreshold(config.id, 20)
                    
                    if count < userThreshold then
                        trigger = true
                        displayMessage = string.format(config.message, count)
                    end
                end
            end
            
            -- Display if triggered
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

-- Event listener for Judgement
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:SetScript("OnEvent", function(self, event, unit, ...)
    if unit ~= "player" then return end
    
    local spellName
    if event == "UNIT_SPELLCAST_SENT" then
        local _, _, spellID = ...
        spellName = GetSpellInfo(spellID)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, spellID = ...
        spellName = GetSpellInfo(spellID)
    end
    
    if spellName then
        if spellName:find("^Judgement") or spellName:find("^Judge") then
            lastJudgementTime = GetTime()
            if Prepped and Prepped.CheckReminders then
                Prepped:CheckReminders()
            end
        end
    end
end)

if Prepped then
    Prepped:RegisterReminderModule(PaladinReminders)
end
