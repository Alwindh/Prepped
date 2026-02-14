-- Hunter-specific reminders module
local HunterReminders = {}

local hunterReminders = {
    {
        id = "hunter_no_ammo",
        message = "No ammo equipped",
        noAmmoCheck = true,
    },
    {
        id = "hunter_ammo_critical",
        message = "Critically low on ammo (%s left)",
        ammoCheck = true,
        mustNotRest = true,
        minCount = 200,
    },
    {
        id = "hunter_ammo_low",
        message = "Low on ammo (%s left)",
        ammoCheck = true,
        mustRest = true,
        minCount = 1000,
    },
    {
        id = "hunter_aspect",
        message = "Buff missing: Aspect",
        mustNotRest = true,
        isMountedOnly = true,
        requireOneSpell = { 13163, 13165 },
        missingBuffs = { 34074,5118,27044,13159,27045,13163,13161,13165,25296,14320,14318,14322,14319,20190,20043,14321 }
    },
    {
        id = "hunter_no_pet",
        message = "No pet active",
        mustNotRest = true,
        petCheck = true,
    },
    {
        id = "hunter_pet_unhappy",
        message = "Pet is unhappy",
        petHappinessCheck = true,
    },
    {
        id = "hunter_pet_food",
        message = "Low on pet food (%s left)",
        mustRest = true,
        petFoodCheck = true,
    },
}

-- Getting ammo count moved to Prepped:GetAmmoCount() in core

-- Hidden tooltip for scanning item food types
local scanner = CreateFrame("GameTooltip", "PreppedScanner", nil, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

-- EXPANDED Keywords for robust detection
-- Added "bleu" for Darnassian Bleu, "stalk"/"whole" for mushrooms, etc.
local DietKeywords = {
    ["Meat"] = { "shank", "meat", "jerky", "steak", "chop", "rib", "wing", "leg", "haunch", "sausage", "bird", "poultry", "venison", "mutton", "beef", "pork", "flesh", "kidney", "loiterer", "spider", "wolf" },
    ["Fish"] = { "fish", "mackerel", "snapper", "sagefish", "catfish", "deviate", "salmon", "squid", "eel", "clam", "mussel", "oyster", "trout", "cod", "yellowtail", "fin", "filet" },
    ["Cheese"] = { "cheese", "blue", "bleu", "curd", "wedge", "block", "cheddar", "brie", "gouda", "swiss", "dairy", "darnassian", "dalaran", "alterac" },
    ["Bread"] = { "bread", "roll", "bun", "biscuit", "croissant", "pastry", "muffin", "sourdough", "grain", "dough", "cake", "toast", "strudel", "flatbread", "ration" },
    ["Fungus"] = { "fungus", "mushroom", "cap", "spore", "truffle", "conk", "stalk", "whole" },
    ["Fruit"] = { "fruit", "apple", "banana", "grape", "melon", "berry", "pear", "pineapple", "orange", "lemon", "lime", "peach", "plum", "nectar", "starfruit", "moonberry", "sunfruit", "pomegranate" },
}


local function GetPetFoodCount()
    if not UnitExists("pet") then return nil end
    
    local foodTypes = { GetPetFoodTypes() }
    if #foodTypes == 0 then return nil end
    
    local activeDiets = {}
    for _, diet in ipairs(foodTypes) do
        activeDiets[diet] = true
    end
    
    local count = 0
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            
            if info and info.itemID then
                local itemName, _, _, _, _, _, _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfo(info.itemID)
                
                -- Cache priming: if info isn't here yet, request it and move on
                if not itemClassID then
                    GetItemInfo(info.itemID)
                else
                    local foundMatch = false
                    local lowerName = itemName:lower()

                    -- 1. THE SKULL FILTER:
                    -- Consumable (0) + Generic (0) is almost always a non-food "Use" item.
                    if not (itemClassID == 0 and itemSubClassID == 0) then
                        
                        -- 2. TOOLTIP SCAN (The primary source)
                        scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
                        scanner:ClearLines()
                        scanner:SetBagItem(bag, slot)
                        
                        for i = 2, 6 do
                            local line = _G["PreppedScannerTextLeft"..i]
                            local text = line and line:GetText()
                            if text and text ~= "" then
                                local lowerText = text:lower()
                                -- Ignore action/level lines
                                if not (lowerText:find("use:") or lowerText:find("requires") or lowerText:find("level")) then
                                    for diet, _ in pairs(activeDiets) do
                                        if lowerText:find("%f[%a]"..diet:lower().."%f[%A]") then
                                            foundMatch = true
                                            break
                                        end
                                    end
                                end
                            end
                            if foundMatch then break end
                        end

                        -- 3. KEYWORD FALLBACK (The Mackerel Fix)
                        -- If tooltip failed, check if the Name contains any diet keywords.
                        -- We only do this for Trade Goods (7) and Food (0,5).
                        if not foundMatch and (itemClassID == 7 or (itemClassID == 0 and itemSubClassID == 5)) then
                            for diet, _ in pairs(activeDiets) do
                                local keywords = DietKeywords[diet]
                                if keywords then
                                    for _, kw in ipairs(keywords) do
                                        if lowerName:find(kw) then
                                            foundMatch = true
                                            break
                                        end
                                    end
                                end
                                if foundMatch then break end
                            end
                        end
                    end

                    if foundMatch then
                        count = count + (info.stackCount or 1)
                    end
                end
            end
        end
    end
    return count
end

local function PlayerHasBuffFromList(buffList)
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        for _, bID in pairs(buffList) do if bID == spellID then return true end end
    end
    return false
end

function HunterReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then return end
    local isResting = IsResting()
    local criticalTriggered = false
    local ammoCount = Prepped:GetAmmoCount()

    for _, config in ipairs(hunterReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            if config.mustRest and not isResting then trigger = false end
            if config.mustNotRest and isResting then trigger = false end

            -- If we already showed a "No Ammo" or "Critical" warning, skip "Low"
            if config.id == "hunter_ammo_low" and criticalTriggered then
                trigger = false
            end
            
            -- Ammo Logic
            if trigger and config.ammoCheck then
                -- Suppress Low/Crit if count is 0 (handled by hunter_no_ammo) or if no weapon (nil)
                if not ammoCount or ammoCount == 0 then 
                    trigger = false 
                else
                    local userThreshold = 0
                    if Prepped and Prepped.GetRuleThreshold then
                        userThreshold = Prepped:GetRuleThreshold(config.id)
                    end
                    
                    local threshold = userThreshold
                    if isResting then
                        threshold = math.max(userThreshold, config.minCountResting or 0)
                    end
                    
                    if ammoCount >= threshold then 
                        trigger = false 
                    else
                        -- If this is the critical warning and it triggered, mark it
                        if config.id == "hunter_ammo_critical" then
                            criticalTriggered = true
                        end
                    end
                    displayMessage = string.format(config.message, ammoCount)
                end
            end

            -- No Ammo Check
            if trigger and config.noAmmoCheck then
                if ammoCount ~= 0 then -- count == nil (no weapon) or count > 0 (has ammo)
                    trigger = false
                else
                    -- If "No Ammo" triggered, also treat it as "critical" to suppress "Low"
                    criticalTriggered = true
                end
            end
            
            -- Buff Logic
            if trigger and config.missingBuffs then
                -- Special Knowledge check for aspects
                if config.id == "hunter_aspect" then
                    local learnedAny = false
                    for _, sID in ipairs(config.missingBuffs) do
                        if IsPlayerSpell(sID) then
                            learnedAny = true
                            break
                        end
                    end
                    if not learnedAny then trigger = false end
                    -- Don't show aspect reminder when mounted
                    if trigger and config.isMountedOnly and IsMounted() then trigger = false end
                end

                if trigger and PlayerHasBuffFromList(config.missingBuffs) then trigger = false end
            end
            
            -- Pet Logic
            if trigger and config.petCheck then
                if IsMounted() then
                    trigger = false
                elseif not IsPlayerSpell(1515) then -- Tame Beast
                    trigger = false
                elseif UnitExists("pet") and not UnitIsDead("pet") then
                    trigger = false
                end
            end
            
            -- Happiness Logic
            if trigger and config.petHappinessCheck then
                if UnitExists("pet") then
                    local happiness = GetPetHappiness()
                    -- happiness: 1 = unhappy, 2 = content, 3 = happy
                    if happiness == 3 then
                        trigger = false
                    end
                else
                    trigger = false
                end
            end
            
            -- Pet Food Logic
            if trigger and config.petFoodCheck then
                local count = GetPetFoodCount()
                if count == nil then 
                    trigger = false 
                else
                    local threshold = 20
                    if Prepped and Prepped.GetRuleThreshold then
                        threshold = Prepped:GetRuleThreshold(config.id)
                    end
                    if count >= threshold then 
                        trigger = false 
                    else
                        displayMessage = string.format(config.message, count or 0)
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
    Prepped:RegisterReminderModule(HunterReminders)
end