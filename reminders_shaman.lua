-- Shaman-specific reminders module
local _, ns = ...
local Compat = ns.Compat

local ShamanReminders = {}

-- Talent tree order (same on TBC and Forever)
local TREE_ELEMENTAL = 1
local TREE_RESTORATION = 3

-- Helper Functions
local buffMatchers = {}
local function GetBuffMatcher(config)
    local matcher = buffMatchers[config.id]
    if not matcher then
        matcher = Compat.NameIn(config.missingBuffs)
        buffMatchers[config.id] = matcher
    end
    return matcher
end

-- Returns false (missing), "low" (found but expiring), or true (satisfied).
-- Buff data hidden by combat restrictions counts as satisfied: never warn blind.
local function HasAnyBuff(config, minDuration)
    local state, remaining = Compat.FindPlayerBuff(GetBuffMatcher(config))
    if state == "missing" then return false end
    if state == "present" and minDuration and minDuration > 0 and remaining and remaining <= minDuration then
        return "low"
    end
    return true
end

local function IsEnhancementOrLeveling()
    -- Suppress only when Elemental or Restoration strictly leads.
    -- Enhancement leading, no talents yet, a tie, or no talent data -> show reminder.
    local primaryTree = Compat.GetPrimaryTalentTree()
    return primaryTree ~= TREE_ELEMENTAL and primaryTree ~= TREE_RESTORATION
end

local function IsDualWielding()
    local offHandID = GetInventoryItemID("player", 17)
    if not offHandID then return false end

    -- Use Instant info to avoid cache delay issues
    local _, _, _, _, _, classID = Compat.GetItemInfoInstant(offHandID)

    if classID == 2 then return true end -- 2 is Enum.ItemClass.Weapon
    return false
end

local shamanReminders = {
    {
        id = "shaman_shield_buff",
        message = "Buff missing: Shield",
        mustNotRest = true,
        requiredAnySpell = {"Water Shield", "Lightning Shield"},
        missingBuffs = {"Water Shield", "Lightning Shield"},
    },
    {
        id = "shaman_weapon_buff",
        message = "Buff missing: Weapon",
        mustNotRest = true,
        weaponCheck = true,
    },
    {
        id = "shaman_ankh",
        message = "Low on reagents: Ankh (%s left)",
        item = 17030,
        mustRest = true,
        spell = 20608, -- Reincarnation
    },
    {
        id = "shaman_fish_oil",
        message = "Low on reagents: Fish Oil (%s left)",
        item = 17058,
        mustRest = true,
        spell = 546, -- Water Walking
    },
    {
        id = "shaman_fish_scales",
        message = "Low on reagents: Fish Scales (%s left)",
        item = 17057,
        mustRest = true,
        spell = 131, -- Water Breathing
    },
}

function ShamanReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "SHAMAN" then return end
    local isResting = IsResting()
    for _, config in ipairs(shamanReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            if config.mustRest and not isResting then trigger = false end
            if config.mustNotRest and isResting then trigger = false end

            -- Spell Learned Check
            if trigger and config.requiredSpell then
                if not Compat.KnowsSpellNamed(config.requiredSpell) then trigger = false end
            end
            -- Any Spell Learned Check
            if trigger and config.requiredAnySpell then
                if not Compat.KnowsAnySpellNamed(config.requiredAnySpell) then trigger = false end
            end
            -- Reagents only matter once the spell that uses them is learned
            if trigger and config.spell then
                if not Compat.KnowsSpellID(config.spell) then trigger = false end
            end

            -- Missing Buffs Check
            if trigger and config.missingBuffs then
                -- Get User Threshold (Duration)
                local threshold = 0
                if Prepped and Prepped.GetRuleThreshold then
                     threshold = Prepped:GetRuleThreshold(config.id, 0)
                end

                local status = HasAnyBuff(config, threshold)

                if status == true then
                    trigger = false
                elseif status == "low" then
                    -- Respect "Warn if Low" setting
                    if Prepped and Prepped.IsLowEnabled and not Prepped:IsLowEnabled(config.id) then
                        trigger = false
                    else
                        trigger = true
                        displayMessage = "SHIELD RUNNING LOW!"
                    end
                else
                    trigger = true -- Missing
                end
            end

            -- Weapon Buff Check
            if trigger and config.weaponCheck then
                if not IsEnhancementOrLeveling() then
                    trigger = false
                else
                    local hasMH, mhExp, hasOH, ohExp = Compat.GetWeaponEnchants()
                    -- hasMH/hasOH are booleans. mhExp/ohExp are numbers (milliseconds remaining).

                    local threshold = 0
                    if Prepped and Prepped.GetRuleThreshold then
                         threshold = Prepped:GetRuleThreshold(config.id, 0)
                    end
                    local thresholdMs = threshold * 1000

                    local missing = false
                    local isLow = false

                    -- Main Hand Logic
                    if not hasMH then
                        missing = true
                    elseif mhExp and mhExp > 0 and mhExp <= thresholdMs then
                        isLow = true
                    end

                    -- Off Hand Logic (only if DW)
                    if IsDualWielding() then
                        if not hasOH then
                            missing = true
                        elseif ohExp and ohExp > 0 and ohExp <= thresholdMs then
                            isLow = true
                        end
                    end

                    if missing then
                        trigger = true
                    elseif isLow then
                        if Prepped and Prepped.IsLowEnabled and not Prepped:IsLowEnabled(config.id) then
                            trigger = false
                        else
                            trigger = true
                            displayMessage = "WEAPON BUFF RUNNING LOW!"
                        end
                    else
                        trigger = false
                    end
                end
            end

            -- Item Logic
            if trigger and config.item then
                local count = Compat.GetItemCount(config.item)
                local threshold = 0
                if Prepped and Prepped.GetRuleThreshold then
                     threshold = Prepped:GetRuleThreshold(config.id)
                end
                if count >= threshold then trigger = false end
                displayMessage = string.format(config.message, count)
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
    Prepped:RegisterReminderModule(ShamanReminders)
end
