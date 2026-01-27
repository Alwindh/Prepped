----------------------------------------------------------------------
-- CONFIGURATION SECTION
----------------------------------------------------------------------
local REMINDERS = {
    {
        message = "LOW AMMO (%s left!)", -- %s will be replaced by the number
        class = "HUNTER",
        ammoCheck = true,
        minCountResting = 1000,
        minCountMoving = 200,
    },
    {
        message = "MISSING ASPECT!",
        class = "HUNTER",
        mustNotRest = true,
        requireOneSpell = { 13163, 13165 },
        missingBuffs = { 13163, 13165, 5118, 13161, 13155, 20043, 20190, 34074 }
    },
    {
        message = "BUY ANKHS! (%s/10)",
        class = "SHAMAN",
        item = 17030,
        minCount = 10,
        mustRest = true,
        spell = 20608,
    },
}

----------------------------------------------------------------------
-- CORE ENGINE v4.0 (Multi-Line Support)
----------------------------------------------------------------------
local container = CreateFrame("Frame", "MySquadRemindersContainer", UIParent)
container:SetSize(400, 200)
container:SetPoint("CENTER", 0, 200)

local lines = {}

-- Function to create a new text line frame
local function CreateReminderLine(index)
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

local function CheckReminders()
    local _, playerClass = UnitClass("player")
    local isResting = IsResting()
    
    -- Hide all existing lines first
    for _, line in ipairs(lines) do line:Hide() end
    
    local activeCount = 0

    for _, config in ipairs(REMINDERS) do
        local trigger = true
        local displayMessage = config.message

        if config.class and config.class ~= playerClass then trigger = false end
        if trigger and config.mustRest and not isResting then trigger = false end
        if trigger and config.mustNotRest and isResting then trigger = false end
        
        -- Ammo Logic
        if trigger and config.ammoCheck then
            local count = GetCurrentAmmoCount()
            if not count then trigger = false else
                local threshold = isResting and config.minCountResting or config.minCountMoving
                if count >= threshold then trigger = false end
                displayMessage = string.format(config.message, count)
            end
        end

        -- Item Logic
        if trigger and config.item and config.minCount then
            local count = GetItemCount(config.item)
            if count >= config.minCount then trigger = false end
            displayMessage = string.format(config.message, count)
        end

        -- Buff Logic
        if trigger and config.missingBuffs then
            if PlayerHasBuffFromList(config.missingBuffs) then trigger = false end
        end

        -- Show the line if triggered
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

-- Events
container:RegisterEvent("PLAYER_ENTERING_WORLD")
container:RegisterEvent("BAG_UPDATE")
container:RegisterEvent("PLAYER_UPDATE_RESTING")
container:RegisterEvent("UNIT_INVENTORY_CHANGED")
container:RegisterEvent("UNIT_AURA")
container:RegisterEvent("SPELLS_CHANGED")
-- Show a welcome message when the addon loads
local function ShowWelcomeMessage()
    print("|cff00ff00AlwinPack loaded!|r Simple reminders for the squad are now active.")
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        ShowWelcomeMessage()
    end
    CheckReminders()
end

container:SetScript("OnEvent", OnEvent)