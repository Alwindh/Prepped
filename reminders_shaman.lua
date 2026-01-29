-- Shaman-specific reminders module
local ShamanReminders = {}

-- Helper Functions
local function HasAnyBuff(buffList, minDuration)
    local found = false
    local low = false
    
    for i = 1, 40 do
        local name, icon, count, debuffType, duration, expirationTime = UnitBuff("player", i)
        if not name then break end
        for _, buff in ipairs(buffList) do
            if name == buff then
                found = true
                -- Check duration if specified
                if minDuration and minDuration > 0 and expirationTime and expirationTime > 0 then
                     local remaining = expirationTime - GetTime()
                     if remaining <= minDuration then
                         low = true
                     end
                end
                break
            end
        end
        if found then break end
    end
    
    if not found then return false end -- Missing
    if low then return "low" end      -- Found but low
    return true                       -- Satisfied
end

local function IsSpellLearned(spellName)
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

local function IsEnhancementOrLeveling()
    -- Check Primary Stat. Agility (2) implies Melee/Enhancement.
    -- Intellect (4) implies Caster/Healer.
    
    -- If GetSpecialization is not available (Classic Era), we assume true for Shaman (check all), 
    -- as we cannot distinguish spec easily without inspecting talents.
    if not GetSpecialization then return true end

    local specIndex = GetSpecialization()
    if specIndex then
        local id, name, description, icon, role, primaryStat = GetSpecializationInfo(specIndex)
        
        -- Enhancement uses Agility (2)
        -- Also check name just in case
        if primaryStat == 2 then return true end
        if name == "Enhancement" then return true end
        
        return false
    end
    
    -- Leveling / No Spec: Default to YES
    return true
end

local function IsDualWielding()
    local offHandID = GetInventoryItemID("player", 17)
    if not offHandID then return false end
    
    -- Use Instant info to avoid cache delay issues
    local classID
    if GetItemInfoInstant then
        _, _, _, _, _, classID = GetItemInfoInstant(offHandID)
    else
        -- Legacy Fallback
        local _, _, _, _, _, cID = GetItemInfo(offHandID)
        classID = cID
    end

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
        spell = 20608,
    },
    {
        id = "shaman_fish_oil",
        message = "Low on reagents: Fish Oil (%s left)",
        item = 17058,
        mustRest = true,
        spell = 546,
    },
    {
        id = "shaman_fish_scales",
        message = "Low on reagents: Fish Scales (%s left)",
        item = 17057,
        mustRest = true,
        spell = 131,
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
                if not IsSpellLearned(config.requiredSpell) then trigger = false end
            end
            -- Any Spell Learned Check
            if trigger and config.requiredAnySpell then
                if not IsAnySpellLearned(config.requiredAnySpell) then trigger = false end
            end
            
            -- Missing Buffs Check
            if trigger and config.missingBuffs then
                -- Get User Threshold (Duration)
                local threshold = 0
                if Prepped and Prepped.GetRuleThreshold then
                     threshold = Prepped:GetRuleThreshold(config.id, 0)
                end
                
                local status = HasAnyBuff(config.missingBuffs, threshold)
                
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
                    local hasMH, mhExp, _, _, hasOH, ohExp = GetWeaponEnchantInfo()
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
                local count = GetItemCount(config.item)
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
