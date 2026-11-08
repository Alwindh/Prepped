-- Rogue-specific reminders module
local _, ns = ...
local API = ns.API

local RogueReminders = {}

local VANISH = API.SpellFamily("Vanish", { 1856, 1857 }, { class = "ROGUE" })
local BLIND = API.SpellFamily("Blind", { 2094 }, { class = "ROGUE" })
-- Poisons is a secondary skill in Forever (skill line 40), not a spellbook spell.
local POISONS = API.SpellFamily("Poisons", { 2842 }, { class = "ROGUE" })
local POISONS_SKILL_LINE = 40

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
        id = "rogue_blinding_powder",
        message = "Low on Blinding Powder (%s left)",
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

-- Flash Powder item ID (vendor reagent)
local FLASH_POWDER_ID = 5140
-- Blinding Powder item ID (made with Poisons, not sold by vendors)
local BLINDING_POWDER_ID = 5530

-- Poison item IDs (all ranks of each poison type)
local poisonItemIDs = {
    -- Instant Poison (Ranks 1-6)
    6947, 6949, 6950, 8926, 8927, 8928,
    -- Deadly Poison (Ranks 1-5)
    2892, 2893, 8984, 8985, 20844,
    -- Crippling Poison (Ranks 1-2)
    3775, 3776,
    -- Mind-numbing Poison (Ranks 1-3)
    5237, 6951, 9186,
    -- Wound Poison (Ranks 1-4)
    10918, 10920, 10921, 10922,
}

-- Checks if the player has learned Vanish
local function PlayerKnowsVanish()
    return API.KnowsFamily(VANISH)
end

-- Checks if the player has learned Poisons (the poison-making skill)
local function PlayerKnowsPoisons()
    return API.GetSkillRank(POISONS_SKILL_LINE) > 0 or API.KnowsFamily(POISONS)
end

-- Counts total poison items in bags
local function GetTotalPoisonCount()
    local total = 0
    for _, itemID in ipairs(poisonItemIDs) do
        total = total + C_Item.GetItemCount(itemID)
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
    
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(offHandID)

    if classID == 2 then return true end -- 2 is Enum.ItemClass.Weapon
    return false
end

-- Gets weapon poison expiration times (returns mhRemaining, ohRemaining in seconds, or nil if no poison).
-- Only poisons count, not sharpening stones (which Forever lets you use on top of a poison).
local function GetWeaponPoisonInfo()
    local hasMH, mhExp, hasOH, ohExp = API.GetWeaponImbues()
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
                    -- Not needed with the Legacy perk "Reagent Economy"
                    if PlayerKnowsVanish() and not API.HasReagentEconomy() then
                        local flashCount = C_Item.GetItemCount(FLASH_POWDER_ID)
                        local threshold = Prepped:GetRuleThreshold(config.id, 10)
                        if flashCount < threshold then
                            trigger = true
                            displayMessage = string.format(config.message, flashCount)
                        end
                    end

                -- Blinding Powder Check (resting, knows Blind). Not a vendor
                -- reagent, so Reagent Economy doesn't remove it.
                elseif config.id == "rogue_blinding_powder" then
                    if API.KnowsFamily(BLIND) then
                        local powderCount = C_Item.GetItemCount(BLINDING_POWDER_ID)
                        if powderCount < Prepped:GetRuleThreshold(config.id) then
                            trigger = true
                            displayMessage = string.format(config.message, powderCount)
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
