-- Mage-specific reminders module
local _, ns = ...
local Compat = ns.Compat

local MageReminders = {}

local MageManaGems = {
    5514, -- Agate
    5513, -- Jade
    8007, -- Citrine
    8008, -- Ruby
    22044, -- Emerald
}

local MageConjureSpells = {
    "Conjure Mana Agate",
    "Conjure Mana Jade",
    "Conjure Mana Citrine",
    "Conjure Mana Ruby",
    "Conjure Mana Emerald",
}

local mageReminders = {
    {
        id = "mage_ai_buff",
        message = "Buff Missing: Arcane Intellect",
        messageLow = "Arcane Intellect expiring (%ss left)",
        mustRest = false,
        requiredSpell = "Arcane Intellect",
        missingBuffs = {"Arcane Intellect", "Arcane Brilliance"},
    },
        {
            id = "mage_armor_buff",
            message = "Buff Missing: Mage Armor",
            messageLow = "Armor buff expiring (%ss left)",
            mustRest = false,
            requiredAnySpell = {"Frost Armor", "Frozen Armor", "Ice Armor", "Mage Armor", "Molten Armor"},
            missingBuffs = {"Frost Armor", "Frozen Armor", "Ice Armor", "Mage Armor", "Molten Armor"},
        },
    {
        id = "mage_powder",
        message = "Low on reagents: Arcane Powder (%s left!)", -- %s will be replaced by the number
        itemCheck = 17020, -- Arcane Powder
        mustRest = true,
        requiredSpell = "Arcane Brilliance"
    },
    {
        id = "mage_rune_teleport",
        message = "Low on reagents: Rune of Teleportation (%s left!)",
        itemCheck = 17031, -- Rune of Teleportation
        mustRest = true,
        requiredAnySpell = {
            "Teleport: Theramore",
            "Teleport: Stormwind",
            "Teleport: Ironforge",
            "Teleport: Darnassus",
            "Teleport: Exodar",
            "Teleport: Orgrimmar",
            "Teleport: Undercity",
            "Teleport: Thunder Bluff",
            "Teleport: Stonard",
            "Teleport: Silvermoon",
            "Teleport: Shattrath"
        }
    },
        {
        id = "mage_rune_portals",
        message = "Low on reagents: Rune of Portals (%s left!)",
        itemCheck = 17032, -- Rune of Portals
        mustRest = true,
        requiredAnySpell = {
            "Portal: Theramore",
            "Portal: Stormwind",
            "Portal: Ironforge",
            "Portal: Darnassus",
            "Portal: Exodar",
            "Portal: Orgrimmar",
            "Portal: Undercity",
            "Portal: Thunder Bluff",
            "Portal: Stonard",
            "Portal: Silvermoon",
            "Portal: Shattrath"
        }
    },
    {
        id = "mage_mana_gem",
        message = "Missing item: Mana Gem",
        mustRest = false,
        inCombatOnly = false,
        manaGemCheck = true,
    },

}

local buffMatchers = {}
local function GetBuffMatcher(config)
    local matcher = buffMatchers[config.id]
    if not matcher then
        matcher = Compat.NameIn(config.missingBuffs)
        buffMatchers[config.id] = matcher
    end
    return matcher
end

function MageReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "MAGE" then return end

    local isResting = IsResting()

    for _, config in ipairs(mageReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message

            -- Resting check
            if config.mustRest ~= nil then
                if config.mustRest and not isResting then trigger = false end
                if not config.mustRest and isResting then trigger = false end
            end

            -- Spell Learned Check
            if trigger and config.requiredSpell then
                if not Compat.KnowsSpellNamed(config.requiredSpell) then trigger = false end
            end

            -- Any Spell Learned Check
            if trigger and config.requiredAnySpell then
                if not Compat.KnowsAnySpellNamed(config.requiredAnySpell) then trigger = false end
            end

            -- Missing Buffs Check
            if trigger and config.missingBuffs then
                local state, remaining = Compat.FindPlayerBuff(GetBuffMatcher(config))
                if state == "missing" then
                    -- Buff is missing: warn
                elseif state == "present" and Prepped:IsLowEnabled(config.id)
                    and remaining and remaining <= Prepped:GetRuleThreshold(config.id, 60) then
                    -- Buff is present but running out
                    displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                else
                    -- Present, or hidden by combat restrictions ("unknown")
                    trigger = false
                end
            end

            -- Item Count Check
            if trigger and config.itemCheck then
                local count = Compat.GetItemCount(config.itemCheck)
                local threshold = 0
                if Prepped and Prepped.GetRuleThreshold then
                     threshold = Prepped:GetRuleThreshold(config.id)
                end
                if count >= threshold then
                    trigger = false
                else
                    displayMessage = string.format(config.message, count)
                end
            end

            -- Mana Gem Check
            if trigger and config.manaGemCheck then
                -- Don't show mana gem reminder when in combat
                local inCombat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown())
                if inCombat then
                    trigger = false
                else
                    -- 1. Check if ANY conjure spell is learned
                    if not Compat.KnowsAnySpellNamed(MageConjureSpells) then
                        trigger = false
                    else
                        -- 2. Check if ANY mana gem is in bags
                        local hasGem = false
                        for _, gemID in ipairs(MageManaGems) do
                            if Compat.GetItemCount(gemID) > 0 then
                                hasGem = true
                                break
                            end
                        end
                        if hasGem then trigger = false end
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
    Prepped:RegisterReminderModule(MageReminders)
end
