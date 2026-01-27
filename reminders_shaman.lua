-- Shaman-specific reminders module
local ShamanReminders = {}

local shamanReminders = {
    {
        id = "shaman_ankh",
        message = "BUY ANKHS! (%s/10)",
        item = 17030,
        minCount = 10,
        mustRest = true,
        spell = 20608,
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

function ShamanReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "SHAMAN" then return end
    local isResting = IsResting()
    for _, line in ipairs(lines) do line:Hide() end
    local activeCount = 0
    for _, config in ipairs(shamanReminders) do
        if not (AlwinPack and config.id and not AlwinPack:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            if config.mustRest and not isResting then trigger = false end
            if config.mustNotRest and isResting then trigger = false end
            -- Item Logic
            if trigger and config.item and config.minCount then
                local count = GetItemCount(config.item)
                local threshold = config.minCount
                if AlwinPack and AlwinPack.GetRuleThreshold then
                     threshold = AlwinPack:GetRuleThreshold(config.id, config.minCount)
                end
                if count >= threshold then trigger = false end
                displayMessage = string.format(config.message, count)
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
    AlwinPack:RegisterReminderModule(ShamanReminders)
end
