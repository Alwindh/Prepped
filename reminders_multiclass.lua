-- Multi-class reminders module
local MultiClassReminders = {}

local lines = {}
local function CreateReminderLine(index)
    local container = _G.PreppedContainer
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

-- Checks if the user is resting and if their equipped gear is not fully repaired.
function MultiClassReminders.CheckDurability()
    if not IsResting() then return false end
    
    for i = 1, 19 do
        local current, max = GetInventoryItemDurability(i)
        if current and max and current < max then
            return true
        end
    end
    return false
end

function MultiClassReminders.CheckReminders()
    if not Prepped or not Prepped:IsRuleEnabled("general_repair") then
        if lines[1] then lines[1]:Hide() end
        return
    end

    -- Clear previous state
    for _, line in ipairs(lines) do line:Hide() end
    
    if MultiClassReminders.CheckDurability() then
        if not lines[1] then
            lines[1] = CreateReminderLine(1)
        end
        lines[1].text:SetText("|cffff0000REPAIR YOUR GEAR!|r")
        lines[1]:Show()
    end
end

if Prepped then
    Prepped:RegisterReminderModule(MultiClassReminders)
end
