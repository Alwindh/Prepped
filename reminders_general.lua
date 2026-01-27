-- General reminders (Multi-class)
local GeneralReminders = {}

local generalRules = {
    {
        id = "general_water",
        message = "BUY WATER! (%s left)",
        mustRest = true,
        onlyMana = true,
        checkWater = true,
        minLevelConfig = "general_water_minlevel",
    }
}

local lines = {}
local function CreateReminderLine(index)
    local container = _G.AlwinPackContainer
    local f = CreateFrame("Frame", nil, container)
    f:SetSize(400, 30)
    f:SetPoint("TOP", container, "TOP", 0, -(index - 1) * 32)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    txt:SetPoint("CENTER")
    f.text = txt
    return f
end

local function IsWaterItem(itemID)
    local spellName = GetItemSpell(itemID)
    -- "Drink" is standard water. "Refreshment" is Mage table food.
    if spellName and (spellName == "Drink" or spellName == "Refreshment") then
        return true
    end
    -- Fallback: Check if item is Consumable -> Food & Drink
    -- However, this includes food.
    -- For now, relying on Spell Name is the best heuristic for "Water" specifically.
    return false
end

local function GetWaterCount()
    local count = 0
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                if IsWaterItem(info.itemID) then
                    count = count + info.stackCount
                end
            end
        end
    end
    return count
end

function GeneralReminders.CheckReminders()
    local isResting = IsResting()
    local powerType = UnitPowerType("player") -- 0 = Mana
    
    for _, line in ipairs(lines) do line:Hide() end
    local activeCount = 0
    
    for _, config in ipairs(generalRules) do
        if not (AlwinPack and config.id and not AlwinPack:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            
            if config.mustRest and not isResting then trigger = false end
            
            -- Mana Check
            if config.onlyMana and powerType ~= 0 then trigger = false end

            -- Min Level Check (if configured)
            if trigger and config.minLevelConfig then
                 local minLevel = AlwinPack:GetRuleThreshold(config.minLevelConfig, 10)
                 if UnitLevel("player") < minLevel then trigger = false end
            end
            
            if trigger and config.checkWater then
                local count = GetWaterCount()
                local threshold = 0
                if AlwinPack and AlwinPack.GetRuleThreshold then
                     threshold = AlwinPack:GetRuleThreshold(config.id)
                end
                
                if count >= threshold then 
                    trigger = false 
                else
                    displayMessage = string.format(config.message, count)
                end
            end
            
            if trigger then
                activeCount = activeCount + 1
                if not lines[activeCount] then
                    lines[activeCount] = CreateReminderLine(activeCount)
                end
                lines[activeCount].text:SetText(displayMessage)
                lines[activeCount]:Show()
            end
        end
    end
end

if AlwinPack then
    AlwinPack:RegisterReminderModule(GeneralReminders)
end
