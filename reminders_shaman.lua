-- Shaman-specific reminders module
local _, ns = ...
local API = ns.API

local ShamanReminders = {}

-- Water Shield is a Restoration talent in Forever; its Forever spell ID isn't
-- known yet, so the English name is a fallback until the TBC IDs are confirmed.
local SHIELDS = API.SpellFamily("Shields", {
    324, 325, 905, 945, 8134, 10431, 10432, -- Lightning Shield
    24398, 33736,                           -- Water Shield
}, { class = "SHAMAN", aura = true, englishNames = { "Water Shield" } })
local REINCARNATION = API.SpellFamily("Reincarnation", { 20608 }, { class = "SHAMAN" })
local WATER_WALKING = API.SpellFamily("Water Walking", { 546 }, { class = "SHAMAN" })
local WATER_BREATHING = API.SpellFamily("Water Breathing", { 131 }, { class = "SHAMAN" })

local IsShield = API.Matcher(SHIELDS)

-- Talent tree order
local TREE_ELEMENTAL = 1
local TREE_RESTORATION = 3

-- Returns false (missing), "low" (found but expiring), or true (satisfied).
-- Buff data hidden by combat restrictions counts as satisfied: never warn blind.
local function HasShield(minDuration)
    local state, remaining = API.FindPlayerBuff(IsShield)
    if state == "missing" then return false end
    if state == "present" and minDuration and minDuration > 0 and remaining and remaining <= minDuration then
        return "low"
    end
    return true
end

local function IsEnhancementOrLeveling()
    -- Suppress only when Elemental or Restoration strictly leads.
    -- Enhancement leading, no talents yet, a tie, or no talent data -> show reminder.
    local primaryTree = API.GetPrimaryTalentTree()
    return primaryTree ~= TREE_ELEMENTAL and primaryTree ~= TREE_RESTORATION
end

local function IsDualWielding()
    local offHandID = GetInventoryItemID("player", 17)
    if not offHandID then return false end

    -- Use Instant info to avoid cache delay issues
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(offHandID)

    if classID == 2 then return true end -- 2 is Enum.ItemClass.Weapon
    return false
end

local shamanReminders = {
    {
        id = "shaman_shield_buff",
        message = "Buff missing: Shield",
        mustNotRest = true,
        requiredFamily = SHIELDS,
        shieldCheck = true,
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
        requiredFamily = REINCARNATION,
    },
    {
        id = "shaman_fish_oil",
        message = "Low on reagents: Fish Oil (%s left)",
        item = 17058,
        mustRest = true,
        requiredFamily = WATER_WALKING,
    },
    {
        id = "shaman_fish_scales",
        message = "Low on reagents: Fish Scales (%s left)",
        item = 17057,
        mustRest = true,
        requiredFamily = WATER_BREATHING,
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

            -- Spell Learned Check (reagents only matter once the spell that uses them is learned)
            if trigger and config.requiredFamily then
                if not API.KnowsFamily(config.requiredFamily) then trigger = false end
            end

            -- Reagents aren't needed with the Legacy perk "Reagent Economy"
            if trigger and config.item and API.HasReagentEconomy() then
                trigger = false
            end

            -- Missing Shield Check
            if trigger and config.shieldCheck then
                -- Get User Threshold (Duration)
                local threshold = 0
                if Prepped and Prepped.GetRuleThreshold then
                     threshold = Prepped:GetRuleThreshold(config.id, 0)
                end

                local status = HasShield(threshold)

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
                    -- Only imbues count, not sharpening stones/oils (Forever lets them stack).
                    local hasMH, mhExp, hasOH, ohExp = API.GetWeaponImbues()
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
                local count = C_Item.GetItemCount(config.item)
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
