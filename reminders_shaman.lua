-- Shaman-specific reminders module
local _, ns = ...
local API = ns.API

local ShamanReminders = {}

-- Water Shield is new in Forever and its spell ID isn't known yet, so it is
-- recognised by its English name (English clients only) until it's listed here.
local SHIELDS = API.SpellFamily("Shields", {
    324, 325, 905, 945, 8134, 10431, 10432, -- Lightning Shield
}, { class = "SHAMAN", aura = true, englishNames = { "Water Shield" } })
local REINCARNATION = API.SpellFamily("Reincarnation", { 20608 }, { class = "SHAMAN" })
local WATER_WALKING = API.SpellFamily("Water Walking", { 546 }, { class = "SHAMAN" })
local WATER_BREATHING = API.SpellFamily("Water Breathing", { 131 }, { class = "SHAMAN" })

local IsShield = API.Matcher(SHIELDS)

-- Totems still need their element's totem item in your bags in Forever
-- (quest rewards at level 4, 10, 20 and 30). An element counts once you know
-- any of its totems. Forever has no Fire Nova Totem or Tranquil Air Totem.
local TOTEM_ELEMENTS = {
    { name = "Earth Totem", item = 5175, family = API.SpellFamily("Earth totems", {
        8071, 8154, 8155, 10406, 10407, 10408, -- Stoneskin Totem
        2484,                                  -- Earthbind Totem
        5730, 6390, 6391, 6392, 10427, 10428,  -- Stoneclaw Totem
        8075, 8160, 8161, 10442, 25361,        -- Strength of Earth Totem
        8143,                                  -- Tremor Totem
    }, { class = "SHAMAN" }) },
    { name = "Fire Totem", item = 5176, family = API.SpellFamily("Fire totems", {
        3599, 6363, 6364, 6365, 10437, 10438,  -- Searing Totem
        8181, 10478, 10479,                    -- Frost Resistance Totem
        8190, 10585, 10586, 10587,             -- Magma Totem
        8227, 8249, 10526, 16387,              -- Flametongue Totem
    }, { class = "SHAMAN" }) },
    { name = "Water Totem", item = 5177, family = API.SpellFamily("Water totems", {
        5394, 6375, 6377, 10462, 10463,        -- Healing Stream Totem
        5675, 10495, 10496, 10497,             -- Mana Spring Totem
        8166,                                  -- Poison Cleansing Totem
        8170,                                  -- Disease Cleansing Totem
        8184, 10537, 10538,                    -- Fire Resistance Totem
        16190, 17354, 17359,                   -- Mana Tide Totem
    }, { class = "SHAMAN" }) },
    { name = "Air Totem", item = 5178, family = API.SpellFamily("Air totems", {
        8177,                                  -- Grounding Totem
        10595, 10600, 10601,                   -- Nature Resistance Totem
        8512, 10613, 10614,                    -- Windfury Totem
        8835, 10627, 25359,                    -- Grace of Air Totem
        15107, 15111, 15112,                   -- Windwall Totem
        6495,                                  -- Sentry Totem
    }, { class = "SHAMAN" }) },
}

-- Names of the totem items you need (you know a totem of that element) but don't carry.
local function GetMissingTotemItems()
    local missing = {}
    for _, element in ipairs(TOTEM_ELEMENTS) do
        if API.KnowsFamily(element.family) and C_Item.GetItemCount(element.item) == 0 then
            missing[#missing + 1] = element.name
        end
    end
    return missing
end

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
        id = "shaman_totems",
        outOfCombat = true,
        totemCheck = true,
    },
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
    local inCombat = UnitAffectingCombat("player") or InCombatLockdown()
    for _, config in ipairs(shamanReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            if config.mustRest and not isResting then trigger = false end
            if config.mustNotRest and isResting then trigger = false end
            if config.outOfCombat and inCombat then trigger = false end

            -- Totem Items Check (e.g. a totem left in the bank)
            if trigger and config.totemCheck then
                local missing = GetMissingTotemItems()
                if #missing == 0 then
                    trigger = false
                else
                    displayMessage = (#missing == 1 and "Missing item: " or "Missing items: ") .. table.concat(missing, ", ")
                end
            end

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
