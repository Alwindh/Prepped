-- Hunter-specific reminders module
local HunterReminders = {}

local hunterReminders = {
    {
        id = "hunter_ammo_critical",
        message = "CRITICAL AMMO (%s left!)", -- %s will be replaced by the number
        ammoCheck = true,
        mustNotRest = true,
        minCount = 200,
    },
    {
        id = "hunter_ammo_low",
        message = "LOW AMMO (%s left!)", -- %s will be replaced by the number
        ammoCheck = true,
        mustRest = true,
        minCount = 1000,
    },
    {
        id = "hunter_aspect",
        message = "MISSING ASPECT!",
        mustNotRest = true,
        requireOneSpell = { 13163, 13165 },
        missingBuffs = { 13163, 13165, 5118, 13161, 13155, 20043, 20190, 34074 }
    },
}

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
    for _, config in ipairs(hunterReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            if config.mustRest and not isResting then trigger = false end
            if config.mustNotRest and isResting then trigger = false end
            -- Ammo Logic
            if trigger and config.ammoCheck then
                local count = GetCurrentAmmoCount()
                if not count then trigger = false else
                    local userThreshold = 0
                    if Prepped and Prepped.GetRuleThreshold then
                        userThreshold = Prepped:GetRuleThreshold(config.id)
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
