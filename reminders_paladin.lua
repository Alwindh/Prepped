-- Paladin-specific reminders module
local _, ns = ...
local Compat = ns.Compat

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
        messageLow = "Blessing expiring (%ss left)",
        mustNotRest = true,
    },
    {
        id = "paladin_kings",
        message = "Low on Symbol of Kings (%s left)",
        itemID = 21177,
        mustRest = true,
    },
    {
        id = "paladin_divinity",
        message = "Low on Symbol of Divinity (%s left)",
        itemID = 17033,
        mustRest = true,
    },
    {
        id = "paladin_righteous_fury",
        message = "Missing Righteous Fury!",
        messageLow = "Righteous Fury expiring (%ss left)",
        mustNotRest = true,
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

-- Talent tree order (same on TBC and Forever)
local TREE_HOLY = 1
local TREE_PROTECTION = 2

local auraNames = nil
local lastJudgementTime = 0

local function GetAuraNames()
    if auraNames then return auraNames end
    auraNames = {}
    for _, id in ipairs(auraSpellIDs) do
        local name = Compat.GetSpellName(id)
        if name then
            auraNames[name] = true
        end
    end
    return auraNames
end

-- Buff / spell name matchers
local function IsSeal(name)
    return name ~= nil and name:find("Seal of") ~= nil
end

local function IsPaladinAura(name)
    return name ~= nil and GetAuraNames()[name] == true
end

local function IsBlessing(name)
    return name ~= nil and name:find("Blessing of ") ~= nil
end

local function IsGreaterBlessing(name)
    return name ~= nil and name:find("Greater Blessing of ") ~= nil
end

local function IsJudgement(name)
    return name ~= nil and (name:find("^Judgement") ~= nil or name:find("^Judge") ~= nil)
end

local IsRighteousFury = Compat.NameIn({ "Righteous Fury" })

-- Checks if a shield is equipped
local function PlayerHasShield()
    local itemID = GetInventoryItemID("player", 17) -- Offhand
    if not itemID then return false end
    local _, _, _, _, _, itemClassID, itemSubClassID = Compat.GetItemInfoInstant(itemID)
    -- In Classic/Retail: itemClassID 4 is Armor, itemSubClassID 6 is Shields
    return itemClassID == 4 and itemSubClassID == 6
end

-- Checks if the player has more points in Protection than other trees
local function PlayerIsProtectionSpec()
    return Compat.GetPrimaryTalentTree() == TREE_PROTECTION
end

-- Checks if the player has more points in Holy than other trees
local function PlayerIsHolySpec()
    return Compat.GetPrimaryTalentTree() == TREE_HOLY
end

-- Shared "missing / expiring" evaluation for timed buffs.
-- Returns trigger, message. Hidden buff data ("unknown") never warns.
local function CheckTimedBuff(config, matcher, defaultThreshold)
    local state, remaining = Compat.FindPlayerBuff(matcher)
    if state == "missing" then
        return true, config.message
    elseif state == "present" and remaining and Prepped:IsLowEnabled(config.id) then
        local threshold = Prepped:GetRuleThreshold(config.id, defaultThreshold)
        if remaining <= threshold then
            return true, string.format(config.messageLow, math.max(0, math.floor(remaining)))
        end
    end
    return false, config.message
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
                    if playerLevel >= 10 and PlayerIsHolySpec() then
                        -- Skip seal reminders for Holy spec once talents are available
                    elseif (currentTime - lastJudgementTime) < 2.0 then
                        -- Judgement suppression
                    elseif not Compat.KnowsSpellMatching(IsSeal) or not Compat.KnowsSpellMatching(IsJudgement) then
                        -- Don't warn if they can't seal/judge yet
                    else
                        trigger, displayMessage = CheckTimedBuff(config, IsSeal, 5)
                    end

                -- Business logic: Paladin Aura
                elseif config.id == "paladin_aura" then
                    if not isMounted and Compat.KnowsSpellMatching(IsPaladinAura)
                        and Compat.FindPlayerBuff(IsPaladinAura) == "missing" then
                        trigger = true
                    end

                -- Business logic: Paladin Blessing
                elseif config.id == "paladin_blessing" then
                    if not isMounted and Compat.KnowsSpellMatching(IsBlessing) then
                        trigger, displayMessage = CheckTimedBuff(config, IsBlessing, 30)
                    end

                -- Business logic: Righteous Fury
                elseif config.id == "paladin_righteous_fury" then
                    if not isMounted and Compat.KnowsSpellNamed("Righteous Fury") then
                        local inGroup = IsInGroup() or GetNumGroupMembers() > 0
                        if inGroup and PlayerHasShield() and PlayerIsProtectionSpec() then
                            trigger, displayMessage = CheckTimedBuff(config, IsRighteousFury, 60)
                        end
                    end

                -- Business logic: Reagents
                elseif config.itemID then
                    local learned = false
                    if config.id == "paladin_kings" then
                        learned = Compat.KnowsSpellMatching(IsGreaterBlessing)
                    elseif config.id == "paladin_divinity" then
                        learned = Compat.KnowsSpellNamed("Divine Intervention")
                    end

                    if learned then
                        local count = Compat.GetItemCount(config.itemID)
                        local userThreshold = Prepped:GetRuleThreshold(config.id)

                        if count < userThreshold then
                            trigger = true
                            displayMessage = string.format(config.message, count)
                        end
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
Compat.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SENT", "player")
Compat.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:SetScript("OnEvent", function(self, event, unit, ...)
    if unit ~= "player" then return end

    local spellID
    if event == "UNIT_SPELLCAST_SENT" then
        local _, _, sentSpellID = ...
        spellID = sentSpellID
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, succeededSpellID = ...
        spellID = succeededSpellID
    end
    if spellID == nil or Compat.IsSecret(spellID) then return end

    local spellName = Compat.GetSpellName(spellID)
    if spellName and not Compat.IsSecret(spellName) and IsJudgement(spellName) then
        lastJudgementTime = GetTime()
        if Prepped and Prepped.CheckReminders then
            Prepped:CheckReminders()
        end
    end
end)

if Prepped then
    Prepped:RegisterReminderModule(PaladinReminders)
end
