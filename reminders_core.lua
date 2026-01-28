local Prepped = {}
Prepped.reminderModules = {}

-- Settings
local function EnsureSettings()
    if not PreppedSettings then PreppedSettings = {} end
    if not PreppedSettings.enabledRules then PreppedSettings.enabledRules = {} end
    if not PreppedSettings.enabledLowRules then PreppedSettings.enabledLowRules = {} end
    if not PreppedSettings.thresholds then PreppedSettings.thresholds = {} end
end

function Prepped:IsRuleEnabled(ruleId)
    EnsureSettings()
    
    -- Master Switch Logic
    local master = PreppedSettings.enabledRules["general_master"]
    if master == nil then master = true end -- Default ON
    
    if ruleId == "general_master" then return master end
    if not master then return false end

    local enabled = PreppedSettings.enabledRules[ruleId]
    if enabled == nil then return true end -- default: enabled
    return enabled
end

function Prepped:SetRuleEnabled(ruleId, enabled)
    EnsureSettings()
    PreppedSettings.enabledRules[ruleId] = enabled
end

function Prepped:IsLowEnabled(ruleId)
    EnsureSettings()
    local enabled = PreppedSettings.enabledLowRules[ruleId]
    if enabled == nil then return true end -- Default to TRUE for low warnings if not set
    return enabled
end

function Prepped:SetLowEnabled(ruleId, enabled)
    EnsureSettings()
    PreppedSettings.enabledLowRules[ruleId] = enabled
end

function Prepped:GetRuleThreshold(ruleId, default)
    EnsureSettings()
    local val = PreppedSettings.thresholds[ruleId]
    if val ~= nil then return val end
    
    if default then return default end
    
    -- Look up default from AllRules
    for _, rule in ipairs(self.AllRules) do
        if rule.id == ruleId then
            return rule.defaultThreshold
        end
    end
    return 0
end

function Prepped:SetRuleThreshold(ruleId, value)
    EnsureSettings()
    local num = tonumber(value) or 0
    if ruleId == "general_repair" then
        num = math.min(100, math.max(0, num))
    end
    PreppedSettings.thresholds[ruleId] = num
end

-- Slash command to open options menu
SLASH_PREPPED1 = "/prepped"
SLASH_PREPPED2 = "/prepped"
SlashCmdList["PREPPED"] = function(msg)
    -- 1. Try the Modern 2026 API using our saved category object
    if Prepped.settingsCategory and Settings and Settings.OpenToCategory then
        -- We pass the ID of the category we stored during CreateOptionsPanel
        Settings.OpenToCategory(Prepped.settingsCategory.ID)
        return
    end

    -- 2. Fallback for older Classic versions
    if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        -- Still requires the double-call bug fix for older clients
        InterfaceOptionsFrame_OpenToCategory("Prepped")
        InterfaceOptionsFrame_OpenToCategory("Prepped")
        return
    end

    -- 3. Last resort: Just open the settings at all
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory()
    end
end

function Prepped:RegisterReminderModule(module)
    table.insert(self.reminderModules, module)
end

Prepped.displayLines = {}
Prepped.activeCount = 0

function Prepped:GetNextLine()
    self.activeCount = self.activeCount + 1
    local index = self.activeCount
    if not self.displayLines[index] then
        local container = _G.PreppedContainer
        if not container then return nil end
        
        local f = CreateFrame("Frame", nil, container)
        f:SetSize(400, 30)
        f:SetPoint("TOP", container, "TOP", 0, -(index - 1) * 32)
        
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        
        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        txt:SetPoint("CENTER")
        f.text = txt
        
        self.displayLines[index] = f
    end
    return self.displayLines[index]
end

function Prepped:ResetReminders()
    self.activeCount = 0
    if self.displayLines then
        for _, line in ipairs(self.displayLines) do
            line:Hide()
        end
    end
end

function Prepped:CheckReminders()
    self:ResetReminders()
    for _, module in ipairs(self.reminderModules) do
        if module.CheckReminders then
            module.CheckReminders()
        end
    end
end


function Prepped:ShowWelcomeMessage()
    if not self:IsRuleEnabled("general_welcome") then return end
    print("|cff00ff00Prepped|r |cffffcc00v1.3.2|r |cff00ff00 loaded!|r. Type |cffffff00/prepped|r to open the options menu.")
end

-- List of all rule IDs and labels for the options menu
Prepped.AllRules = {
    { id = "general_master", label = "Enable Prepped", group = "General", description = "Toggle the entire addon on or off." },
    { id = "general_welcome", label = "Show Welcome Message", group = "General", description = "Show the loaded message when logging in." },
    { id = "general_water", label = "Buy Water", group = "General", defaultThreshold = 40, description = "Show a warning when your Water count drops below specific threshold if you are a mana user." },
    { id = "general_water_minlevel", label = "Water Min Level", group = "General", defaultThreshold = 10, description = "Minimum level required to show the Buy Water reminder." },
    { id = "general_repair", label = "Repair Reminder", group = "General", defaultThreshold = 100, description = "Show a warning if your gear durability drops below the configured percentage while you are resting." },
    { id = "hunter_ammo_low", label = "Low Ammo", group = "Hunter", defaultThreshold = 1000, description = "Show a warning when your ammo count drops below the configured threshold when resting." },
    { id = "hunter_ammo_critical", label = "Critical Ammo", group = "Hunter", defaultThreshold = 200, description = "Show a warning when your ammo count drops below the critical threshold at any time." },
    { id = "hunter_aspect", label = "Missing Aspect", group = "Hunter", description = "Reminds you to have an Aspect buff active." },
    { id = "mage_powder", label = "Low Arcane Powder", group = "Mage", defaultThreshold = 10, description = "Show a warning when your Arcane Powder count drops below the configured threshold when resting." },
    { id = "mage_rune_teleport", label = "Low Runes of Teleportation", group = "Mage", defaultThreshold = 10, description = "Show a warning when your Runes of Teleportation count drops below the configured threshold when resting." },
    { id = "mage_rune_portals", label = "Low Runes of Portals", group = "Mage", defaultThreshold = 10, description = "Show a warning when your Runes of Portals count drops below the configured threshold when resting." },
    { id = "mage_ai_buff", label = "Missing Arcane Intellect Buff", group = "Mage", description = "Reminds you to buff yourself with Arcane Intellect." },
    { id = "mage_armor_buff", label = "Missing Armor Buff", group = "Mage", description = "Reminds you to buff yourself with an Armor buff." },
    { id = "shaman_ankh", label = "Buy Ankhs", group = "Shaman", defaultThreshold = 8, description = "Show a warning when your Ankhs count drops below the configured threshold." },
    { id = "shaman_fish_oil", label = "Buy Fish Oil", group = "Shaman", defaultThreshold = 10, description = "Show a warning when your Fish Oil count drops below the configured threshold." },
    { id = "shaman_fish_scales", label = "Buy Fish Scales", group = "Shaman", defaultThreshold = 10, description = "Show a warning when your Fish Scales count drops below the configured threshold." },
    { id = "shaman_shield_buff", label = "Missing Shield Buff", group = "Shaman", defaultThreshold = 60, hasLowWarningToggle = true, description = "Reminds you to buff yourself with a Shield buff." },
    { id = "shaman_weapon_buff", label = "Missing Weapon Buff", group = "Shaman", defaultThreshold = 60, hasLowWarningToggle = true, description = "Smart reminder for Shaman weapon imbues based on spec/dual-wielding." },

    -- Add more here as you add rules
}

-- Options panel for Blizzard Interface Options
local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "PreppedOptionsPanel", UIParent)
    panel.name = "Prepped"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Prepped Reminders")

    -- 1. Identify Groups in order of appearance
    local groups = {}
    local seen = {}
    for _, rule in ipairs(Prepped.AllRules) do
        if rule.group and not seen[rule.group] then
            seen[rule.group] = true
            table.insert(groups, rule.group)
        end
    end

    -- 2. Create Content Box (Early allocation)
    -- Using BackdropTemplate because OptionsBoxTemplate might be missing in modern clients
    local contentBox = CreateFrame("Frame", "$parentContentBox", panel, "BackdropTemplate")
    contentBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -60)
    contentBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
    
    if contentBox.SetBackdrop then
        contentBox:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        contentBox:SetBackdropColor(0, 0, 0, 0.4)
        contentBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    
    panel.contentBox = contentBox -- Reference for skinning

    -- 3. Create Tabs and Pages
    panel.tabs = {}
    panel.pages = {}
    
    local tabTemplate = "OptionsFrameTabButtonTemplate" 
    
    local function SelectGroup(id)
        PanelTemplates_SetTab(panel, id)
        PanelTemplates_UpdateTabs(panel)
        local groupName = groups[id]
        if not groupName then return end
        for gName, page in pairs(panel.pages) do
            if gName == groupName then page:Show() else page:Hide() end
        end
    end

    panel.numTabs = #groups
    
    for i, groupName in ipairs(groups) do
        local tab = CreateFrame("Button", "$parentTab"..i, panel, tabTemplate)
        tab:SetID(i)
        tab:SetText(groupName)
        tab:SetScript("OnClick", function(self) SelectGroup(self:GetID()) end)
        
        -- Anchor logic
        if i == 1 then
             -- Anchor to ContentBox to ensure they stay attached visually
             tab:SetPoint("BOTTOMLEFT", contentBox, "TOPLEFT", 6, -2) 
        else
             tab:SetPoint("TOPLEFT", panel.tabs[i-1], "TOPRIGHT", -5, 0)
        end
        
        table.insert(panel.tabs, tab)
        
        -- Create Page (Child of ContentBox)
        local page = CreateFrame("Frame", "$parentPage"..groupName, contentBox)
        page:SetPoint("TOPLEFT", 10, -10)
        page:SetPoint("BOTTOMRIGHT", -10, 10)
        page:Hide()
        
        panel.pages[groupName] = page
        page.currentY = 0 
    end

    -- Standard Tab Management
    PanelTemplates_SetNumTabs(panel, #groups)
    PanelTemplates_SetTab(panel, 1)

    -- 3. Populate Pages with Rules
    panel.checkboxes = {}
    panel.editboxes = {}
    panel.ruleFrames = {}

    for i, rule in ipairs(Prepped.AllRules) do
        local gName = rule.group
        if gName and panel.pages[gName] then
            local page = panel.pages[gName]
            local y = page.currentY
            
            -- Create Row Frame (Card)
            local row = CreateFrame("Frame", nil, page, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 10, y)
            row:SetPoint("RIGHT", -10, 0)
            
            if row.SetBackdrop then
                row:SetBackdrop({
                    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 }
                })
                row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
                row:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.5)
            end
            table.insert(panel.ruleFrames, row)
            
            local height = 40

            local cb = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 10, -8)
            cb.Text:SetText(rule.label)
            cb:SetChecked(Prepped:IsRuleEnabled(rule.id))
            cb:SetScript("OnClick", function(self)
                Prepped:SetRuleEnabled(rule.id, self:GetChecked())
                Prepped:CheckReminders()
            end)

            panel.checkboxes[rule.id] = cb
            
            local descY = -8
            local desc = nil
            
            -- Description Logic
            if rule.description then
                desc = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                
                if rule.hasLowWarningToggle then
                     -- New Layout: Description inline with Main Checkbox
                     desc:SetPoint("LEFT", cb.Text, "RIGHT", 8, 0)
                     desc:SetJustifyH("LEFT")
                     -- Don't increase height yet, we stay on line 1
                else
                     -- Standard Layout: Description below
                     desc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 6, 0)
                     desc:SetPoint("RIGHT", -10, 0)
                     desc:SetJustifyH("LEFT")
                     height = 55 -- Increase height for 2nd line
                     descY = -24
                end
                
                desc:SetText(rule.description)
                desc:SetTextColor(0.6, 0.6, 0.6)
            end
            
            -- If rule has a threshold, add controls
            if rule.defaultThreshold then
                
                if rule.hasLowWarningToggle then
                    -- Row 2: Low Warning Wrapper
                    height = height + 25 -- Add height for the second row
                    
                    -- Low Warning Checkbox
                    local lowCb = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
                    -- Align horizontally with the main checkbox (Same X), but underneath (New Y)
                    lowCb:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -2) 
                    lowCb.Text:SetText("Warn if low")
                    lowCb.Text:SetTextColor(0.8, 0.8, 0.8)
                    lowCb:SetChecked(Prepped:IsLowEnabled(rule.id))
                    lowCb:SetScript("OnClick", function(self)
                        Prepped:SetLowEnabled(rule.id, self:GetChecked())
                        Prepped:CheckReminders()
                    end)
                    panel.checkboxes[rule.id.."_low"] = lowCb
                    
                    -- Small explanatory text
                    local lowDesc = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    lowDesc:SetPoint("LEFT", lowCb.Text, "RIGHT", 5, 0)
                    lowDesc:SetText("Show a warning if active but running out. Shows warning with")
                    lowDesc:SetTextColor(0.5, 0.5, 0.5)

                    -- EditBox
                    local ebName = "$parentEditBox"..rule.id
                    local eb = CreateFrame("EditBox", ebName, row, "InputBoxTemplate")
                    eb:SetSize(40, 20)
                    eb:SetPoint("LEFT", lowDesc, "RIGHT", 10, 0)
                    eb:SetAutoFocus(false)
                    eb:SetMaxLetters(5)
                    eb:SetNumeric(true)
                    eb:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                    eb:SetCursorPosition(0)
                    
                    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                    eb:SetScript("OnEnterPressed", function(self)
                        Prepped:SetRuleThreshold(rule.id, self:GetNumber())
                        self:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                        self:ClearFocus()
                        Prepped:CheckReminders()
                    end)
                    eb:SetScript("OnEditFocusLost", function(self)
                        Prepped:SetRuleThreshold(rule.id, self:GetNumber())
                        self:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                        Prepped:CheckReminders()
                    end)
                    panel.editboxes[rule.id] = eb
                    
                    -- Helper text
                    local secondsText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    secondsText:SetPoint("LEFT", eb, "RIGHT", 5, 0)
                    secondsText:SetText(rule.lowLabel or "seconds remaining.")
                    secondsText:SetTextColor(0.6, 0.6, 0.6)
                    
                else
                    -- Simple Layout: Single row, just threshold
                    -- EditBox to the right of the label
                    local ebName = "$parentEditBox"..rule.id
                    local eb = CreateFrame("EditBox", ebName, row, "InputBoxTemplate")
                    eb:SetSize(40, 20)
                    eb:SetPoint("LEFT", cb.Text, "RIGHT", 10, 0)
                    eb:SetAutoFocus(false)
                    eb:SetMaxLetters(5)
                    eb:SetNumeric(true)
                    eb:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                    eb:SetCursorPosition(0)
                    
                    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                    eb:SetScript("OnEnterPressed", function(self)
                        Prepped:SetRuleThreshold(rule.id, self:GetNumber())
                        self:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                        self:ClearFocus()
                        Prepped:CheckReminders()
                    end)
                    eb:SetScript("OnEditFocusLost", function(self)
                        Prepped:SetRuleThreshold(rule.id, self:GetNumber())
                        self:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                        Prepped:CheckReminders()
                    end)
                    panel.editboxes[rule.id] = eb
                    
                    local lbl = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", eb, "RIGHT", 5, 0)
                    if rule.id == "general_repair" then
                        lbl:SetText("% Durability")
                    else
                        lbl:SetText("Count")
                    end
                    lbl:SetTextColor(0.6, 0.6, 0.6)
                end
            end    
            
            row:SetHeight(height)
            page.currentY = y - (height + 5)
        end
    end
    
    -- Initialize
    SelectGroup(1)

    panel.refresh = function()
        for _, rule in ipairs(Prepped.AllRules) do
            local cb = panel.checkboxes[rule.id]
            if cb then cb:SetChecked(Prepped:IsRuleEnabled(rule.id)) end
            
            local eb = panel.editboxes[rule.id]
            if eb and rule.defaultThreshold then
                eb:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                eb:SetCursorPosition(0)
            end
        end
    end
    
    -- ElvUI Support (Lazy Load on Show)
    panel:SetScript("OnShow", function(self)
        self.refresh()
        
        if not self.isSkinned and _G.ElvUI then
             local E = _G.ElvUI[1]
             if E then
                 local S = E:GetModule("Skins")
                 if S then
                     for _, tab in ipairs(self.tabs) do S:HandleTab(tab) end
                     for _, cb in pairs(self.checkboxes) do S:HandleCheckBox(cb) end
                     for _, eb in pairs(self.editboxes) do S:HandleEditBox(eb) end
                     if self.contentBox then S:HandleFrame(self.contentBox) end
                     for _, row in ipairs(self.ruleFrames) do S:HandleFrame(row) end
                     self.isSkinned = true
                 end
             end
        end
    end)


    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- This is for the 2026 Anniversary/Modern client
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
        Settings.RegisterAddOnCategory(category)
        Prepped.settingsCategory = category -- SAVE THIS FOR THE SLASH COMMAND
    elseif InterfaceOptions_AddCategory then
        -- Legacy fallback
        InterfaceOptions_AddCategory(panel)
    end
end

CreateOptionsPanel()

function Prepped:InitializeDefaults()
    EnsureSettings()
    for _, rule in ipairs(self.AllRules) do
        -- Initialize Thresholds and Low Enabled
        if rule.defaultThreshold then
            if PreppedSettings.thresholds[rule.id] == nil then
                 PreppedSettings.thresholds[rule.id] = rule.defaultThreshold
            end
            if PreppedSettings.enabledLowRules[rule.id] == nil then
                 PreppedSettings.enabledLowRules[rule.id] = true
            end
        end
        -- Initialize Enabled State (Default to true)
        if PreppedSettings.enabledRules[rule.id] == nil then
            PreppedSettings.enabledRules[rule.id] = true
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
        if addonName == "Prepped" then
            Prepped:InitializeDefaults()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Prepped:ShowWelcomeMessage()
    end
    Prepped:CheckReminders()
end)

_G.Prepped = Prepped
