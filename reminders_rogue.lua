-- Rogue-specific reminders module
local RogueReminders = {}

local rogueReminders = {
    {
        id = "rogue_no_ammo",
        message = "No ammo/thrown equipped",
        noAmmoCheck = true,
    },
    {
        id = "rogue_ammo_critical",
        message = "Critically low on ammo/thrown (%s left)",
        ammoCheck = true,
    },
    {
        id = "rogue_ammo_low",
        message = "Low on ammo/thrown (%s left)",
        ammoCheck = true,
        mustRest = true,
    },
    {
        id = "rogue_flash_powder",
        message = "Low on Flash Powder (%s left)",
        mustRest = true,
    },
    {
        id = "rogue_poison_stock",
        message = "Low on Poison (%s total)",
        mustRest = true,
    },
    {
        id = "rogue_weapon_poison",
        message = "Missing Weapon Poison!",
        messageLow = "Weapon Poison expiring (%ss left)",
        mustNotRest = true,
    },
}

-- Flash Powder item ID
local FLASH_POWDER_ID = 5140

-- Poison item IDs (all ranks of each poison type)
local poisonItemIDs = {
    -- Instant Poison (Ranks 1-6)
    6947, 6949, 6950, 8926, 8927, 8928,
    -- Deadly Poison (Ranks 1-5)
    2892, 2893, 8984, 8985, 20844,
    -- Crippling Poison
    3775,
    -- Mind-numbing Poison (Ranks 1-3)
    5237, 6951, 9186,
    -- Wound Poison (Ranks 1-4)
    10918, 10920, 10921, 10922,
}

-- Checks if the player has learned Vanish
local function PlayerKnowsVanish()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName == "Vanish" then
                return true
            end
        end
    end
    return false
end

-- Checks if the player has learned Poisons (the base poison-making skill)
local function PlayerKnowsPoisons()
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellName = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellName == "Poisons" then
                return true
            end
        end
    end
    return false
end

-- Counts total poison items in bags
local function GetTotalPoisonCount()
    local total = 0
    for _, itemID in ipairs(poisonItemIDs) do
        local count = GetItemCount(itemID)
        if count then
            total = total + count
        end
    end
    return total
end

-- Checks if player has any poison in bags
local function PlayerHasPoisonInBags()
    return GetTotalPoisonCount() > 0
end

-- Checks if player is dual wielding
local function IsDualWielding()
    local offHandID = GetInventoryItemID("player", 17)
    if not offHandID then return false end
    
    local classID
    if GetItemInfoInstant then
        _, _, _, _, _, classID = GetItemInfoInstant(offHandID)
    else
        local _, _, _, _, _, cID = GetItemInfo(offHandID)
        classID = cID
    end

    if classID == 2 then return true end -- 2 is Enum.ItemClass.Weapon
    return false
end

-- Gets weapon poison expiration times (returns mhRemaining, ohRemaining in seconds, or nil if no poison)
local function GetWeaponPoisonInfo()
    local hasMH, mhExp, _, _, hasOH, ohExp = GetWeaponEnchantInfo()
    -- mhExp/ohExp are in milliseconds
    local mhRemaining = nil
    local ohRemaining = nil
    
    if hasMH and mhExp then
        mhRemaining = mhExp / 1000
    end
    if hasOH and ohExp then
        ohRemaining = ohExp / 1000
    end
    
    return hasMH, mhRemaining, hasOH, ohRemaining
end

function RogueReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "ROGUE" then return end
    
    local isResting = IsResting()
    local isMounted = IsMounted()
    
    local criticalTriggered = false
    local count = Prepped:GetAmmoCount()

    for _, config in ipairs(rogueReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = false
            local displayMessage = config.message
            
            -- Basic filters
            local filterPassed = true
            if config.mustRest and not isResting then filterPassed = false end
            if config.mustNotRest and isResting then filterPassed = false end
            
            -- If we already showed a "No Ammo" or "Critical" warning, skip "Low"
            if config.id == "rogue_ammo_low" and criticalTriggered then
                filterPassed = false
            end

            if filterPassed then
                -- Ammo Logic
                if config.ammoCheck then
                    if not count or count == 0 then
                        -- No ammo, skip this check (noAmmoCheck handles it)
                    else
                        local threshold = 0
                        if Prepped and Prepped.GetRuleThreshold then
                            threshold = Prepped:GetRuleThreshold(config.id)
                        end
                        if count < threshold then
                            trigger = true
                            if config.id == "rogue_ammo_critical" then
                                criticalTriggered = true
                            end
                        end
                        displayMessage = string.format(config.message, count)
                    end

                -- No Ammo Check
                elseif config.noAmmoCheck then
                    if count == 0 then
                        trigger = true
                        criticalTriggered = true
                    end

                -- Flash Powder Check (resting, knows Vanish)
                elseif config.id == "rogue_flash_powder" then
                    if PlayerKnowsVanish() then
                        local flashCount = GetItemCount(FLASH_POWDER_ID) or 0
                        local threshold = Prepped:GetRuleThreshold(config.id, 10)
                        if flashCount < threshold then
                            trigger = true
                            displayMessage = string.format(config.message, flashCount)
                        end
                    end

                -- Poison Stock Check (resting, knows Poisons)
                elseif config.id == "rogue_poison_stock" then
                    if PlayerKnowsPoisons() then
                        local poisonCount = GetTotalPoisonCount()
                        local threshold = Prepped:GetRuleThreshold(config.id, 20)
                        if poisonCount < threshold then
                            trigger = true
                            displayMessage = string.format(config.message, poisonCount)
                        end
                    end

                -- Weapon Poison Check (not resting, knows Poisons, has poison in bags)
                elseif config.id == "rogue_weapon_poison" then
                    if not isMounted and PlayerKnowsPoisons() and PlayerHasPoisonInBags() then
                        local hasMH, mhRemaining, hasOH, ohRemaining = GetWeaponPoisonInfo()
                        local isDW = IsDualWielding()
                        
                        local missing = false
                        local isLow = false
                        local lowestTime = nil
                        
                        -- Main Hand check
                        if not hasMH then
                            missing = true
                        elseif mhRemaining then
                            local threshold = Prepped:GetRuleThreshold(config.id, 60)
                            if mhRemaining <= threshold then
                                isLow = true
                                lowestTime = mhRemaining
                            end
                        end
                        
                        -- Off Hand check (only if dual wielding)
                        if isDW then
                            if not hasOH then
                                missing = true
                            elseif ohRemaining then
                                local threshold = Prepped:GetRuleThreshold(config.id, 60)
                                if ohRemaining <= threshold then
                                    isLow = true
                                    if not lowestTime or ohRemaining < lowestTime then
                                        lowestTime = ohRemaining
                                    end
                                end
                            end
                        end
                        
                        if missing then
                            trigger = true
                            displayMessage = config.message
                        elseif isLow then
                            if Prepped:IsLowEnabled(config.id) then
                                trigger = true
                                displayMessage = string.format(config.messageLow, math.max(0, math.floor(lowestTime)))
                            end
                        end
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
    Prepped:RegisterReminderModule(RogueReminders)
end
