-- Mage-specific reminders module
local _, ns = ...
local API = ns.API

local MageReminders = {}

local ARCANE_INTELLECT = API.SpellFamily("Arcane Intellect", { 1459, 1460, 1461, 10156, 10157 }, { class = "MAGE", aura = true })
local ARCANE_BRILLIANCE = API.SpellFamily("Arcane Brilliance", { 23028 }, { class = "MAGE", aura = true })
local ARMORS = API.SpellFamily("Mage armors", {
    168, 7300, 7301,          -- Frost Armor
    7302, 7320, 10219, 10220, -- Ice Armor
    6117, 22782, 22783,       -- Mage Armor
}, { class = "MAGE", aura = true })
local CONJURE_MANA_GEM = API.SpellFamily("Conjure Mana Gem", { 759, 3552, 10053, 10054 }, { class = "MAGE" })
-- Forever-only destinations are caught by the English pattern until their IDs are known.
local TELEPORTS = API.SpellFamily("Teleports", { 3561, 3562, 3563, 3565, 3566, 3567 }, { class = "MAGE", englishPattern = "^Teleport: " })
local PORTALS = API.SpellFamily("Portals", { 10059, 11416, 11417, 11418, 11419, 11420 }, { class = "MAGE", englishPattern = "^Portal: " })

local MageManaGems = {
    5514, -- Agate
    5513, -- Jade
    8007, -- Citrine
    8008, -- Ruby
}

local mageReminders = {
    {
        id = "mage_ai_buff",
        message = "Buff Missing: Arcane Intellect",
        messageLow = "Arcane Intellect expiring (%ss left)",
        mustRest = false,
        requiredFamily = ARCANE_INTELLECT,
        buffMatcher = API.Matcher(ARCANE_INTELLECT, ARCANE_BRILLIANCE),
    },
    {
        id = "mage_armor_buff",
        message = "Buff Missing: Mage Armor",
        messageLow = "Armor buff expiring (%ss left)",
        mustRest = false,
        requiredFamily = ARMORS,
        buffMatcher = API.Matcher(ARMORS),
    },
    {
        id = "mage_powder",
        message = "Low on reagents: Arcane Powder (%s left!)", -- %s will be replaced by the number
        itemCheck = 17020, -- Arcane Powder
        vendorReagent = true,
        mustRest = true,
        requiredFamily = ARCANE_BRILLIANCE,
    },
    {
        id = "mage_rune_teleport",
        message = "Low on reagents: Rune of Teleportation (%s left!)",
        itemCheck = 17031, -- Rune of Teleportation
        vendorReagent = true,
        mustRest = true,
        requiredFamily = TELEPORTS,
    },
    {
        id = "mage_rune_portals",
        message = "Low on reagents: Rune of Portals (%s left!)",
        itemCheck = 17032, -- Rune of Portals
        vendorReagent = true,
        mustRest = true,
        requiredFamily = PORTALS,
    },
    {
        id = "mage_mana_gem",
        message = "Missing item: Mana Gem",
        mustRest = false,
        inCombatOnly = false,
        manaGemCheck = true,
    },
}

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
            if trigger and config.requiredFamily then
                if not API.KnowsFamily(config.requiredFamily) then trigger = false end
            end

            -- Reagents aren't needed with the Legacy perk "Reagent Economy"
            if trigger and config.vendorReagent and API.HasReagentEconomy() then
                trigger = false
            end

            -- Missing Buffs Check
            if trigger and config.buffMatcher then
                local state, remaining = API.FindPlayerBuff(config.buffMatcher)
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
                local count = C_Item.GetItemCount(config.itemCheck)
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
                    if not API.KnowsFamily(CONJURE_MANA_GEM) then
                        trigger = false
                    else
                        -- 2. Check if ANY mana gem is in bags
                        local hasGem = false
                        for _, gemID in ipairs(MageManaGems) do
                            if C_Item.GetItemCount(gemID) > 0 then
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
