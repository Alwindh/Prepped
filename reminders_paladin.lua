-- Paladin-specific reminders module
local _, ns = ...
local API = ns.API

local PaladinReminders = {}

local SEALS = API.SpellFamily("Seals", {
    20154, 21084, -- Seal of Righteousness
    20375,        -- Seal of Command
    21082,        -- Seal of the Crusader
    20164,        -- Seal of Justice
    20165,        -- Seal of Light
    20166,        -- Seal of Wisdom
    20421, 20423, -- Seal of Fury (new in Forever)
}, { class = "PALADIN", aura = true, englishPattern = "^Seal of " })
local JUDGEMENT = API.SpellFamily("Judgement", { 20271 }, { class = "PALADIN", englishPattern = "^Judgement" })
local AURAS = API.SpellFamily("Auras", {
    465,   -- Devotion Aura
    7294,  -- Retribution Aura
    19746, -- Concentration Aura
    19876, -- Shadow Resistance Aura
    19888, -- Frost Resistance Aura
    19891, -- Fire Resistance Aura
    20218, -- Sanctity Aura
}, { class = "PALADIN", aura = true })
local GREATER_BLESSINGS_IDS = { 25782, 25894, 25898, 25895, 25890, 25899 } -- Might, Wisdom, Kings, Salvation, Light, Sanctuary
local GREATER_BLESSINGS = API.SpellFamily("Greater Blessings", GREATER_BLESSINGS_IDS, { class = "PALADIN" })
-- Long-duration blessings (not short ones like Protection/Freedom/Sacrifice)
local BLESSINGS = API.SpellFamily("Blessings", {
    19740, -- Blessing of Might
    19742, -- Blessing of Wisdom
    20217, -- Blessing of Kings
    1038,  -- Blessing of Salvation
    19977, -- Blessing of Light
    20911, -- Blessing of Sanctuary
    unpack(GREATER_BLESSINGS_IDS),
}, { class = "PALADIN", aura = true })
local RIGHTEOUS_FURY = API.SpellFamily("Righteous Fury", { 25780 }, { class = "PALADIN", aura = true })
local DIVINE_INTERVENTION = API.SpellFamily("Divine Intervention", { 19752 }, { class = "PALADIN" })

local IsSeal = API.Matcher(SEALS)
local IsPaladinAura = API.Matcher(AURAS)
local IsBlessing = API.Matcher(BLESSINGS)
local IsRighteousFury = API.Matcher(RIGHTEOUS_FURY)

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
        requiredFamily = GREATER_BLESSINGS,
        mustRest = true,
    },
    {
        id = "paladin_divinity",
        message = "Low on Symbol of Divinity (%s left)",
        itemID = 17033,
        requiredFamily = DIVINE_INTERVENTION,
        mustRest = true,
    },
    {
        id = "paladin_righteous_fury",
        message = "Missing Righteous Fury!",
        messageLow = "Righteous Fury expiring (%ss left)",
        mustNotRest = true,
    },
}

-- Talent tree order
local TREE_HOLY = 1
local TREE_PROTECTION = 2

local lastJudgementTime = 0

-- Checks if a shield is equipped
local function PlayerHasShield()
    local itemID = GetInventoryItemID("player", 17) -- Offhand
    if not itemID then return false end
    local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
    -- itemClassID 4 is Armor, itemSubClassID 6 is Shields
    return itemClassID == 4 and itemSubClassID == 6
end

-- Checks if the player has more points in Protection than other trees
local function PlayerIsProtectionSpec()
    return API.GetPrimaryTalentTree() == TREE_PROTECTION
end

-- Checks if the player has more points in Holy than other trees
local function PlayerIsHolySpec()
    return API.GetPrimaryTalentTree() == TREE_HOLY
end

-- Shared "missing / expiring" evaluation for timed buffs.
-- Returns trigger, message. Hidden buff data ("unknown") never warns.
local function CheckTimedBuff(config, matcher, defaultThreshold)
    local state, remaining = API.FindPlayerBuff(matcher)
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
                    elseif not API.KnowsFamily(SEALS) or not API.KnowsFamily(JUDGEMENT) then
                        -- Don't warn if they can't seal/judge yet
                    else
                        trigger, displayMessage = CheckTimedBuff(config, IsSeal, 5)
                    end

                -- Business logic: Paladin Aura
                elseif config.id == "paladin_aura" then
                    if not isMounted and API.KnowsFamily(AURAS)
                        and API.FindPlayerBuff(IsPaladinAura) == "missing" then
                        trigger = true
                    end

                -- Business logic: Paladin Blessing
                elseif config.id == "paladin_blessing" then
                    if not isMounted and API.KnowsFamily(BLESSINGS) then
                        trigger, displayMessage = CheckTimedBuff(config, IsBlessing, 30)
                    end

                -- Business logic: Righteous Fury
                elseif config.id == "paladin_righteous_fury" then
                    if not isMounted and API.KnowsFamily(RIGHTEOUS_FURY) then
                        local inGroup = IsInGroup() or GetNumGroupMembers() > 0
                        if inGroup and PlayerHasShield() and PlayerIsProtectionSpec() then
                            trigger, displayMessage = CheckTimedBuff(config, IsRighteousFury, 60)
                        end
                    end

                -- Business logic: Reagents (not needed with the Legacy perk "Reagent Economy")
                elseif config.itemID then
                    if API.KnowsFamily(config.requiredFamily) and not API.HasReagentEconomy() then
                        local count = C_Item.GetItemCount(config.itemID)
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

-- Event listener for Judgement (suppresses the seal warning right after judging)
local eventFrame = CreateFrame("Frame")
API.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SENT", "player")
API.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
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
    if spellID == nil or API.IsSecret(spellID) then return end

    if API.FamilyMatches(JUDGEMENT, C_Spell.GetSpellName(spellID), spellID) then
        lastJudgementTime = GetTime()
        if Prepped and Prepped.CheckReminders then
            Prepped:CheckReminders()
        end
    end
end)

if Prepped then
    Prepped:RegisterReminderModule(PaladinReminders)
end
