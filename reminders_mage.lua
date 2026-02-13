-- Mage-specific reminders module
function HasAnyBuff(buffList)
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        for _, buff in ipairs(buffList) do
            if name == buff then return true end
        end
    end
    return false
end

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
        buffNames = {"Arcane Intellect", "Arcane Brilliance"},
    },
        {
            id = "mage_armor_buff",
            message = "Buff Missing: Mage Armor",
            messageLow = "Armor buff expiring (%ss left)",
            mustRest = false,
            requiredAnySpell = {"Frozen Armor", "Ice Armor", "Mage Armor", "Molten Armor"},
            missingBuffs = {"Frozen Armor", "Ice Armor", "Mage Armor", "Molten Armor"},
            buffNames = {"Frozen Armor", "Ice Armor", "Mage Armor", "Molten Armor"},
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

local function IsSpellLearned(spellName)
    -- iterate spellbook
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellNameBook = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellNameBook == spellName then return true end
        end
    end
    return false
end

local function IsAnySpellLearned(spellList)
    for _, spell in ipairs(spellList) do
        if IsSpellLearned(spell) then return true end
    end
    return false
end

local function GetBuffExpiration(buffNames)
    for i = 1, 40 do
        local name, _, _, _, duration, expirationTime = UnitAura("player", i, "HELPFUL")
        if not name then break end
        for _, buffName in ipairs(buffNames) do
            if name == buffName then
                if expirationTime and expirationTime > 0 then
                    return expirationTime - GetTime()
                else
                    return 999
                end
            end
        end
    end
    return nil
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
                if not IsSpellLearned(config.requiredSpell) then trigger = false end
            end

            -- Any Spell Learned Check
            if trigger and config.requiredAnySpell then
                if not IsAnySpellLearned(config.requiredAnySpell) then trigger = false end
            end

            -- Missing Buffs Check
            if trigger and config.missingBuffs then
                if HasAnyBuff(config.missingBuffs) then
                    -- Buff is present, but check for low warning
                    if config.buffNames and Prepped:IsLowEnabled(config.id) then
                        local remaining = GetBuffExpiration(config.buffNames)
                        if remaining and remaining <= Prepped:GetRuleThreshold(config.id, 60) then
                            trigger = true
                            displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                        else
                            trigger = false
                        end
                    else
                        trigger = false
                    end
                end
            end

            -- Item Count Check
            if trigger and config.itemCheck then
                local count = GetItemCount(config.itemCheck)
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
                    if not IsAnySpellLearned(MageConjureSpells) then
                        trigger = false
                    else
                        -- 2. Check if ANY mana gem is in bags
                        local hasGem = false
                        for _, gemID in ipairs(MageManaGems) do
                            if GetItemCount(gemID) > 0 then
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
