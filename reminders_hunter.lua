-- Hunter-specific reminders module
local HunterReminders = {}

local hunterReminders = {
    {
        id = "hunter_ammo",
        message = "LOW AMMO (%s left!)", -- %s will be replaced by the number
        ammoCheck = true,
        minCountResting = 1000,
        minCountMoving = 200,
    },
    {
        id = "hunter_aspect",
        message = "MISSING ASPECT!",
        mustNotRest = true,
        requireOneSpell = { 13163, 13165 },
        missingBuffs = { 13163, 13165, 5118, 13161, 13155, 20043, 20190, 34074 }
    },
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

local function GetCurrentAmmoCount()
    local itemID = GetInventoryItemID("player", 18)
    if not itemID then return nil end
    return GetInventoryItemCount("player", 0)
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
    for _, line in ipairs(lines) do line:Hide() end
    local activeCount = 0
    for _, config in ipairs(hunterReminders) do
        if not (AlwinPack and config.id and not AlwinPack:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            if config.mustRest and not isResting then trigger = false end
            if config.mustNotRest and isResting then trigger = false end
            -- Ammo Logic
            if trigger and config.ammoCheck then
                local count = GetCurrentAmmoCount()
                if not count then trigger = false else
                    local userThreshold = config.minCountMoving
                    if AlwinPack and AlwinPack.GetRuleThreshold then
                        userThreshold = AlwinPack:GetRuleThreshold(config.id, config.minCountMoving)
                    end
                    
                    local threshold = userThreshold
                    if isResting then
                        threshold = math.max(userThreshold, config.minCountResting or 0)
                    end
                    
                    if count >= threshold then trigger = false end
                    displayMessage = string.format(config.message, count)
                end
            end
            -- Buff Logic
            if trigger and config.missingBuffs then
                if PlayerHasBuffFromList(config.missingBuffs) then trigger = false end
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
    AlwinPack:RegisterReminderModule(HunterReminders)
end
