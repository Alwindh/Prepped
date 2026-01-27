local AlwinPack = {}
AlwinPack.reminderModules = {}

-- Settings
local function EnsureSettings()
    if not AlwinPackSettings then AlwinPackSettings = {} end
    if not AlwinPackSettings.enabledRules then AlwinPackSettings.enabledRules = {} end
    if not AlwinPackSettings.thresholds then AlwinPackSettings.thresholds = {} end
end

function AlwinPack:IsRuleEnabled(ruleId)
    EnsureSettings()
    local enabled = AlwinPackSettings.enabledRules[ruleId]
    if enabled == nil then return true end -- default: enabled
    return enabled
end

function AlwinPack:SetRuleEnabled(ruleId, enabled)
    EnsureSettings()
    AlwinPackSettings.enabledRules[ruleId] = enabled
end

function AlwinPack:GetRuleThreshold(ruleId, default)
    EnsureSettings()
    local val = AlwinPackSettings.thresholds[ruleId]
    if val == nil then return default end
    return val
end

function AlwinPack:SetRuleThreshold(ruleId, value)
    EnsureSettings()
    AlwinPackSettings.thresholds[ruleId] = tonumber(value)
end

-- Slash command to open options menu
SLASH_ALWINPACK1 = "/alwinpack"
SLASH_ALWINPACK2 = "/alwin"
SlashCmdList["ALWINPACK"] = function(msg)
    -- 1. Try the Modern 2026 API using our saved category object
    if AlwinPack.settingsCategory and Settings and Settings.OpenToCategory then
        -- We pass the ID of the category we stored during CreateOptionsPanel
        Settings.OpenToCategory(AlwinPack.settingsCategory.ID)
        return
    end

    -- 2. Fallback for older Classic versions
    if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        -- Still requires the double-call bug fix for older clients
        InterfaceOptionsFrame_OpenToCategory("AlwinPack")
        InterfaceOptionsFrame_OpenToCategory("AlwinPack")
        return
    end

    -- 3. Last resort: Just open the settings at all
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory()
    end
end

function AlwinPack:RegisterReminderModule(module)
    table.insert(self.reminderModules, module)
end

function AlwinPack:CheckReminders()
    for _, module in ipairs(self.reminderModules) do
        if module.CheckReminders then
            module.CheckReminders()
        end
    end
end


function AlwinPack:ShowWelcomeMessage()
    print("|cff00ff00AlwinPack loaded!|r. Type |cffffff00/alwin|r to open the options menu.")
end

-- List of all rule IDs and labels for the options menu
AlwinPack.AllRules = {
    { id = "hunter_ammo", label = "Low Ammo", group = "Hunter", defaultThreshold = 200 },
    { id = "hunter_aspect", label = "Missing Aspect", group = "Hunter" },
    { id = "mage_powder", label = "Low Arcane Powder", group = "Mage", defaultThreshold = 10 },
    { id = "mage_rune_teleport", label = "Low Runes of Teleportation", group = "Mage", defaultThreshold = 10 },
    { id = "shaman_ankh", label = "Buy Ankhs", group = "Shaman", defaultThreshold = 5 },
    -- Add more here as you add rules
}

-- Options panel for Blizzard Interface Options
local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "AlwinPackOptionsPanel", UIParent)
    panel.name = "AlwinPack"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("AlwinPack Reminders")

    local y = -48
    panel.checkboxes = {}
    panel.editboxes = {}
    
    local lastGroup = nil
    
    for i, rule in ipairs(AlwinPack.AllRules) do
        if rule.group and rule.group ~= lastGroup then
            lastGroup = rule.group
            
            -- Add extra spacing before new group (except the first one)
            if i > 1 then y = y - 8 end
            
            local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            header:SetPoint("TOPLEFT", 16, y)
            header:SetText(rule.group)
            y = y - 20
        end

        local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
        local xOffset = rule.group and 26 or 16
        cb:SetPoint("TOPLEFT", xOffset, y)
        cb.Text:SetText(rule.label)
        cb:SetChecked(AlwinPack:IsRuleEnabled(rule.id))
        cb:SetScript("OnClick", function(self)
            AlwinPack:SetRuleEnabled(rule.id, self:GetChecked())
            AlwinPack:CheckReminders()
        end)
        panel.checkboxes[rule.id] = cb
        
        -- If rule has a threshold, add an input box
        if rule.defaultThreshold then
            local eb = CreateFrame("EditBox", "$parentEditBox"..rule.id, panel, "InputBoxTemplate")
            eb:SetSize(40, 20)
            eb:SetPoint("LEFT", cb.Text, "RIGHT", 10, 0)
            eb:SetAutoFocus(false)
            eb:SetMaxLetters(5)
            eb:SetNumeric(true)
            eb:SetText(tostring(AlwinPack:GetRuleThreshold(rule.id, rule.defaultThreshold)))
            eb:SetCursorPosition(0)
            eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            eb:SetScript("OnEnterPressed", function(self)
                AlwinPack:SetRuleThreshold(rule.id, self:GetNumber())
                self:ClearFocus()
                AlwinPack:CheckReminders()
            end)
            eb:SetScript("OnEditFocusLost", function(self)
                AlwinPack:SetRuleThreshold(rule.id, self:GetNumber())
                AlwinPack:CheckReminders()
            end)
            panel.editboxes[rule.id] = eb
        end

        y = y - 32
    end

    panel.refresh = function()
        for _, rule in ipairs(AlwinPack.AllRules) do
            local cb = panel.checkboxes[rule.id]
            if cb then cb:SetChecked(AlwinPack:IsRuleEnabled(rule.id)) end
            
            local eb = panel.editboxes[rule.id]
            if eb and rule.defaultThreshold then
                eb:SetText(tostring(AlwinPack:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                eb:SetCursorPosition(0)
            end
        end
    end

    panel:SetScript("OnShow", panel.refresh)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- This is for the 2026 Anniversary/Modern client
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
        Settings.RegisterAddOnCategory(category)
        AlwinPack.settingsCategory = category -- SAVE THIS FOR THE SLASH COMMAND
    elseif InterfaceOptions_AddCategory then
        -- Legacy fallback
        InterfaceOptions_AddCategory(panel)
    end
end

CreateOptionsPanel()

function AlwinPack:InitializeDefaults()
    EnsureSettings()
    for _, rule in ipairs(self.AllRules) do
        -- Initialize Thresholds
        if rule.defaultThreshold then
            if AlwinPackSettings.thresholds[rule.id] == nil then
                 AlwinPackSettings.thresholds[rule.id] = rule.defaultThreshold
            end
        end
        -- Initialize Enabled State (Default to true)
        if AlwinPackSettings.enabledRules[rule.id] == nil then
             AlwinPackSettings.enabledRules[rule.id] = true
        end
    end
end

local container = CreateFrame("Frame")
container:RegisterEvent("PLAYER_ENTERING_WORLD")
container:RegisterEvent("ADDON_LOADED")
container:RegisterEvent("BAG_UPDATE")
container:RegisterEvent("PLAYER_UPDATE_RESTING")
container:RegisterEvent("UNIT_INVENTORY_CHANGED")
container:RegisterEvent("UNIT_AURA")
container:RegisterEvent("SPELLS_CHANGED")

container:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "AlwinPack" then
            AlwinPack:InitializeDefaults()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        AlwinPack:ShowWelcomeMessage()
    end
    AlwinPack:CheckReminders()
end)

_G.AlwinPack = AlwinPack
