local addonName, ns = ...
local Compat = ns.Compat

local Prepped = {}
Prepped.reminderModules = {}
Prepped.Compat = Compat

local function GetCharacterKey()
    return (UnitName("player") or "Unknown") .. " - " .. ((GetRealmName and GetRealmName()) or "")
end

-- Settings
local function EnsureSettings()
    if not PreppedSettings then PreppedSettings = {} end
    
    -- Migration / Initialization of new structure
    if PreppedSettings.useAccountWide == nil then
        PreppedSettings.useAccountWide = true
    end
    
    if not PreppedSettings.global then
        PreppedSettings.global = {}
        -- Migrate old top-level settings to global
        if PreppedSettings.enabledRules then
            PreppedSettings.global.enabledRules = PreppedSettings.enabledRules
            PreppedSettings.enabledRules = nil
        end
        if PreppedSettings.enabledLowRules then
            PreppedSettings.global.enabledLowRules = PreppedSettings.enabledLowRules
            PreppedSettings.enabledLowRules = nil
        end
        if PreppedSettings.thresholds then
            PreppedSettings.global.thresholds = PreppedSettings.thresholds
            PreppedSettings.thresholds = nil
        end
    end
    
    if not PreppedSettings.global.enabledRules then PreppedSettings.global.enabledRules = {} end
    if not PreppedSettings.global.enabledLowRules then PreppedSettings.global.enabledLowRules = {} end
    if not PreppedSettings.global.thresholds then PreppedSettings.global.thresholds = {} end
    
    if not PreppedSettings.appearance then
        PreppedSettings.appearance = {}
    end
    if not PreppedSettings.appearance.fontSize then PreppedSettings.appearance.fontSize = 18 end
    if not PreppedSettings.appearance.minWidth then PreppedSettings.appearance.minWidth = 400 end
    if not PreppedSettings.appearance.fontColor then PreppedSettings.appearance.fontColor = { r = 1, g = 0.82, b = 0 } end
    if not PreppedSettings.appearance.bgColor then PreppedSettings.appearance.bgColor = { r = 0, g = 0, b = 0, a = 0.5 } end

    if not PreppedSettings.profiles then PreppedSettings.profiles = {} end

    local charKey = GetCharacterKey()
    if not PreppedSettings.profiles[charKey] then
        PreppedSettings.profiles[charKey] = {
            enabledRules = {},
            enabledLowRules = {},
            thresholds = {}
        }
    end
end

local function GetCurrentProfile()
    EnsureSettings()
    if PreppedSettings.useAccountWide then
        return PreppedSettings.global
    else
        return PreppedSettings.profiles[GetCharacterKey()]
    end
end

function Prepped:IsRuleEnabled(ruleId)
    local profile = GetCurrentProfile()
    
    -- Master Switch Logic (Handled globally or per profile)
    local master = profile.enabledRules["general_master"]
    if master == nil then master = true end -- Default ON
    
    if ruleId == "general_master" then return master end
    if not master then return false end

    local enabled = profile.enabledRules[ruleId]
    if enabled == nil then return true end -- default: enabled
    return enabled
end

function Prepped:SetRuleEnabled(ruleId, enabled)
    local profile = GetCurrentProfile()
    profile.enabledRules[ruleId] = enabled
end

function Prepped:IsLowEnabled(ruleId)
    local profile = GetCurrentProfile()
    local enabled = profile.enabledLowRules[ruleId]
    if enabled == nil then return true end -- Default to TRUE for low warnings if not set
    return enabled
end

function Prepped:SetLowEnabled(ruleId, enabled)
    local profile = GetCurrentProfile()
    profile.enabledLowRules[ruleId] = enabled
end

function Prepped:GetRuleThreshold(ruleId, default)
    local profile = GetCurrentProfile()
    local val = profile.thresholds[ruleId]
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
    local profile = GetCurrentProfile()
    local num = tonumber(value) or 0
    if ruleId == "general_repair" then
        num = math.min(100, math.max(0, num))
    end
    profile.thresholds[ruleId] = num
end

-- Profile Management Functions
function Prepped:IsAccountWide()
    EnsureSettings()
    return PreppedSettings.useAccountWide
end

function Prepped:SetAccountWide(enabled)
    EnsureSettings()
    PreppedSettings.useAccountWide = enabled
end

function Prepped:ClearCharacterSettings()
    PreppedSettings.profiles[GetCharacterKey()] = {
        enabledRules = {},
        enabledLowRules = {},
        thresholds = {}
    }
end

-- Warning Dialog for switching to Account-wide
StaticPopupDialogs["PREPPED_CONFIRM_ACCOUNT_WIDE"] = {
    text = "Are you sure you want to enable Account-wide settings? Your current character-specific settings will be cleared for this character.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        Prepped:ClearCharacterSettings()
        Prepped:SetAccountWide(true)
        if PreppedOptionsPanel then PreppedOptionsPanel.refresh() end
        Prepped:CheckReminders()
    end,
    OnCancel = function()
        if PreppedOptionsPanel and PreppedOptionsPanel.checkboxes["general_account_wide"] then
            PreppedOptionsPanel.checkboxes["general_account_wide"]:SetChecked(false)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Prepped:ResetAllSettings()
    _G.PreppedSettings = nil
    EnsureSettings()
    self:ApplyAppearance()
    if PreppedOptionsPanel then 
        PreppedOptionsPanel.refresh() 
    end
    print("|cffff8000Prepped:|r All settings have been reset to default.")
end

StaticPopupDialogs["PREPPED_RESET_ALL_SETTINGS"] = {
    text = "Are you sure you want to reset ALL Prepped settings? This will clear all account-wide settings, character-specific profiles, and appearance customizations.",
    button1 = "Reset Everything",
    button2 = "Cancel",
    OnAccept = function()
        Prepped:ResetAllSettings()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

-- Slash command to open options menu
SLASH_PREPPED1 = "/prepped"
SLASH_PREPPED2 = "/prepped"
SlashCmdList["PREPPED"] = function(msg)
    if msg == "debug" then
        print("|cff00ff00Prepped Debug:|r")
        print("  Client: " .. Compat.GetClientLabel())
        print("  Buff data hidden by combat restrictions: " .. tostring(Compat.AreAurasRestricted()))
        local trees = Compat.GetTalentTrees()
        if trees then
            for i, tree in ipairs(trees) do
                print(string.format("  Talent tree %d (%s): %d points", i, tostring(tree.name or "?"), tree.points or 0))
            end
        else
            print("  Talent trees: unavailable")
        end
        print("  Primary talent tree: " .. tostring(Compat.GetPrimaryTalentTree()))
        if Compat.lastTalentError then
            print("  Last talent read error: " .. tostring(Compat.lastTalentError))
        end
        if Compat.lastBuffScanError then
            print("  Last buff scan error: " .. tostring(Compat.lastBuffScanError))
        end
        print("  GetSpecialization exists: " .. tostring(GetSpecialization ~= nil))
        if GetSpecialization then
            local specIndex = GetSpecialization()
            print("  GetSpecialization() = " .. tostring(specIndex))
            if specIndex then
                local id, name, description, icon, role, primaryStat = GetSpecializationInfo(specIndex)
                print("  Spec name=" .. tostring(name) .. " primaryStat=" .. tostring(primaryStat))
            end
        end
        print("  GetTalentTabInfo exists: " .. tostring(GetTalentTabInfo ~= nil))
        if GetTalentTabInfo then
            for i = 1, 3 do
                local a, b, c, d, e, f = GetTalentTabInfo(i)
                print("  Tab " .. i .. " raw: |" .. tostring(a) .. "|" .. tostring(b) .. "|" .. tostring(c) .. "|" .. tostring(d) .. "|" .. tostring(e) .. "|" .. tostring(f) .. "|")
            end
        end
        print("  GetNumTalents/GetTalentInfo exists: " .. tostring(GetNumTalents ~= nil) .. " / " .. tostring(GetTalentInfo ~= nil))
        if GetNumTalents and GetTalentInfo then
            for i = 1, 3 do
                local total = 0
                for j = 1, GetNumTalents(i) do
                    local _, _, _, _, currentRank = GetTalentInfo(i, j)
                    total = total + (currentRank or 0)
                end
                print("  Tab " .. i .. " counted points: " .. total)
            end
        end
        return
    end
    -- 1. Try the Modern 2026 API using our saved category object
    if Prepped.settingsCategory and Settings and Settings.OpenToCategory then
        -- We pass the ID of the category we stored during CreateOptionsPanel
        local category = Prepped.settingsCategory
        Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
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

local RANGED_SLOT = INVSLOT_RANGED or 18
local AMMO_SLOT = INVSLOT_AMMO or 0
local ITEM_CLASS_WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local WEAPON_SUBCLASS_THROWN = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Thrown) or 16

-- Returns the ammo (or thrown weapon) count, or nil when there is no ranged
-- weapon that uses ammo.
function Prepped:GetAmmoCount()
    local itemID = GetInventoryItemID("player", RANGED_SLOT)
    if not itemID then return nil end

    local _, _, _, _, _, itemClassID, itemSubClassID = Compat.GetItemInfoInstant(itemID)
    if itemClassID == ITEM_CLASS_WEAPON and itemSubClassID == WEAPON_SUBCLASS_THROWN then
        -- Vanilla-style thrown weapons (Forever) are stacks that get used up.
        -- TBC-style thrown weapons have durability instead and never run out.
        local _, maxDurability = GetInventoryItemDurability(RANGED_SLOT)
        if maxDurability and maxDurability > 0 then return nil end
        return GetInventoryItemCount("player", RANGED_SLOT)
    end

    return GetInventoryItemCount("player", AMMO_SLOT)
end

Prepped.displayLines = {}
Prepped.activeCount = 0

function Prepped:GetAppearance()
    EnsureSettings()
    return PreppedSettings.appearance
end

function Prepped:ApplyAppearance()
    local app = self:GetAppearance()
    local fontPath, _, fontFlags = GameFontNormalLarge:GetFont() -- Fallback to game default font
    
    for i, line in ipairs(self.displayLines) do
        -- Update Background
        if line.bg then
            line.bg:SetColorTexture(app.bgColor.r, app.bgColor.g, app.bgColor.b, app.bgColor.a or 0.5)
        end
        
        -- Update Text
        if line.text then
            line.text:SetFont(fontPath, app.fontSize, "OUTLINE")
            local tr, tg, tb = app.fontColor.r or 1, app.fontColor.g or 0.82, app.fontColor.b or 0
            line.text:SetTextColor(tr, tg, tb, 1)
        end
        
        -- Update Sizing and Positioning
        local minWidth = app.minWidth or 400
        local textWidth = (line.text and line.text:GetUnboundedStringWidth()) or 0
        local width = math.max(minWidth, textWidth + 40)
        
        line:SetSize(width, app.fontSize + 12)
        line:ClearAllPoints()
        line:SetPoint("TOP", _G.PreppedContainer, "TOP", 0, -(i - 1) * (app.fontSize + 14))
    end
end

function Prepped:GetNextLine()
    self.activeCount = self.activeCount + 1
    local index = self.activeCount
    if not self.displayLines[index] then
        local container = _G.PreppedContainer
        if not container then return nil end
        
        local f = CreateFrame("Frame", nil, container)
        
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        f.bg = bg
        
        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        txt:SetPoint("CENTER")
        f.text = txt
        
        -- Hook SetText to handle dynamic width resizing
        local originalSetText = txt.SetText
        txt.SetText = function(self, msg)
            originalSetText(self, msg)
            local app = Prepped:GetAppearance()
            local textWidth = self:GetUnboundedStringWidth()
            local width = math.max(app.minWidth or 400, textWidth + 40)
            f:SetWidth(width)
        end
        
        self.displayLines[index] = f
        self:ApplyAppearance() -- Apply styles to the new line
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

local reportedErrors = {}

function Prepped:CheckReminders()
    self:ResetReminders()
    
    -- Don't show reminders if dead or on a taxi
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
        return
    end

    for _, module in ipairs(self.reminderModules) do
        if module.CheckReminders then
            -- One failing module must not take the others down, and a repeating
            -- error is only reported once instead of on every update.
            local ok, err = pcall(module.CheckReminders)
            if not ok and not reportedErrors[err] then
                reportedErrors[err] = true
                geterrorhandler()(err)
            end
        end
    end
end

local function GetAddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (getMetadata and getMetadata(addonName, "Version")) or "?"
end

function Prepped:ShowWelcomeMessage()
    if not self:IsRuleEnabled("general_welcome") then return end
    print("|cff00ff00Prepped|r |cffffcc00v" .. GetAddonVersion() .. "|r |cff00ff00 loaded!|r. Type |cffffff00/prepped|r to open the options menu.")
end

-- List of all rule IDs and labels for the options menu
Prepped.AllRules = {
    { id = "general_master", label = "Enable Prepped", group = "General", description = "Toggle the entire addon on or off." },
    { id = "general_account_wide", label = "Use Account-wide Settings", group = "General", description = "If enabled, settings are shared across all characters. If disabled, each character has their own config." },
    { id = "general_welcome", label = "Show Welcome Message", group = "General", description = "Show the loaded message when logging in." },
    { id = "general_water", label = "Buy Water", group = "General", defaultThreshold = 40, description = "Show a warning when your Water count drops below specific threshold if you are a mana user." },
    { id = "general_water_minlevel", label = "Water Min Level", group = "General", defaultThreshold = 10, description = "Minimum level required to show the Buy Water reminder." },
    { id = "general_repair", label = "Repair Reminder", group = "General", defaultThreshold = 100, description = "Show a warning if your gear durability drops below the configured percentage while you are resting." },
    { id = "hunter_no_ammo", label = "No Ammo Equipped", group = "Hunter", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot." },
    { id = "hunter_ammo_low", label = "Low Ammo", group = "Hunter", defaultThreshold = 1000, description = "Show a warning when your ammo count drops below the configured threshold when resting." },
    { id = "hunter_ammo_critical", label = "Critical Ammo", group = "Hunter", defaultThreshold = 200, description = "Show a warning when your ammo count drops below the critical threshold at any time." },
    { id = "hunter_aspect", label = "Missing Aspect", group = "Hunter", description = "Reminds you to have an Aspect buff active." },
    { id = "hunter_no_pet", label = "Missing Pet", group = "Hunter", description = "Reminds you to have your pet active if you know Tame Beast and are not resting." },
    { id = "hunter_pet_unhappy", label = "Unhappy Pet", group = "Hunter", description = "Reminds you to feed your pet if it is unhappy." },
    { id = "hunter_pet_food", label = "Low Pet Food", group = "Hunter", defaultThreshold = 20, description = "Show a warning when you have little food in your bags that your active pet can eat while resting." },


    { id = "mage_powder", label = "Low Arcane Powder", group = "Mage", defaultThreshold = 10, description = "Show a warning when your Arcane Powder count drops below the configured threshold when resting." },
    { id = "mage_rune_teleport", label = "Low Runes of Teleportation", group = "Mage", defaultThreshold = 10, description = "Show a warning when your Runes of Teleportation count drops below the configured threshold when resting." },
    { id = "mage_rune_portals", label = "Low Runes of Portals", group = "Mage", defaultThreshold = 10, description = "Show a warning when your Runes of Portals count drops below the configured threshold when resting." },
    { id = "mage_ai_buff", label = "Missing Arcane Intellect Buff", group = "Mage", hasLowWarningToggle = true, defaultThreshold = 60, lowLabel = "seconds remaining.", description = "Reminds you to buff yourself with Arcane Intellect." },
    { id = "mage_armor_buff", label = "Missing Armor Buff", group = "Mage", hasLowWarningToggle = true, defaultThreshold = 60, lowLabel = "seconds remaining.", description = "Reminds you to buff yourself with an Armor buff." },
    { id = "mage_mana_gem", label = "Missing Mana Gem", group = "Mage", description = "Reminds you to conjure a Mana Gem if you are not resting and don't have one." },
    { id = "shaman_ankh", label = "Buy Ankhs", group = "Shaman", defaultThreshold = 8, description = "Show a warning when your Ankhs count drops below the configured threshold." },
    { id = "shaman_fish_oil", label = "Buy Fish Oil", group = "Shaman", defaultThreshold = 10, description = "Show a warning when your Fish Oil count drops below the configured threshold." },
    { id = "shaman_fish_scales", label = "Buy Fish Scales", group = "Shaman", defaultThreshold = 10, description = "Show a warning when your Fish Scales count drops below the configured threshold." },
    { id = "shaman_shield_buff", label = "Missing Shield Buff", group = "Shaman", defaultThreshold = 60, hasLowWarningToggle = true, description = "Reminds you to buff yourself with a Shield buff." },
    { id = "shaman_weapon_buff", label = "Missing Weapon Buff", group = "Shaman", defaultThreshold = 60, hasLowWarningToggle = true, description = "Smart reminder for Shaman weapon imbues based on spec/dual-wielding." },

    { id = "rogue_no_ammo", label = "No Ammo/Thrown Equipped", group = "Rogue", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot (or no thrown weapon charges)." },
    { id = "rogue_ammo_low", label = "Low Ammo/Thrown", group = "Rogue", defaultThreshold = 100, description = "Show a warning when your ammo/thrown count drops below the configured threshold when resting." },
    { id = "rogue_ammo_critical", label = "Critical Ammo/Thrown", group = "Rogue", defaultThreshold = 20, description = "Show a warning when your ammo/thrown count drops below the critical threshold at any time." },

    { id = "warrior_no_ammo", label = "No Ammo/Thrown Equipped", group = "Warrior", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot (or no thrown weapon charges)." },
    { id = "warrior_ammo_low", label = "Low Ammo/Thrown", group = "Warrior", defaultThreshold = 100, description = "Show a warning when your ammo/thrown count drops below the configured threshold when resting." },
    { id = "warrior_ammo_critical", label = "Critical Ammo/Thrown", group = "Warrior", defaultThreshold = 20, description = "Show a warning when your ammo/thrown count drops below the critical threshold at any time." },
    { id = "warrior_battle_shout", label = "Missing Battle Shout", group = "Warrior", defaultThreshold = 10, hasLowWarningToggle = true, lowLabel = "seconds remaining.", description = "Reminds you to have Battle Shout active when you are in combat." },
    
    { id = "paladin_seal", label = "Missing Seal in Combat", group = "Paladin", defaultThreshold = 5, hasLowWarningToggle = true, lowLabel = "seconds remaining.", description = "Reminds you to have a Seal active when you are in combat." },
    { id = "paladin_aura", label = "Missing Aura", group = "Paladin", description = "Reminds you to have a Paladin Aura active at all times." },
    { id = "paladin_blessing", label = "Missing Self-Blessing", group = "Paladin", hasLowWarningToggle = true, defaultThreshold = 30, lowLabel = "seconds remaining.", description = "Reminds you to have a Blessing active on yourself when not resting." },
    { id = "paladin_kings", label = "Low Symbol of Kings", group = "Paladin", defaultThreshold = 50, description = "Show a warning when your Symbol of Kings count drops below the configured threshold when resting." },
    { id = "paladin_divinity", label = "Low Symbol of Divinity", group = "Paladin", defaultThreshold = 5, description = "Show a warning when your Symbol of Divinity count drops below the configured threshold when resting." },
    { id = "paladin_righteous_fury", label = "Missing Righteous Fury", group = "Paladin", hasLowWarningToggle = true, defaultThreshold = 60, lowLabel = "seconds remaining.", description = "Reminds you to activate Righteous Fury if you are in a group, have a shield equipped, and are Protection spec." },

    { id = "priest_fortitude", label = "Missing Power Word: Fortitude", group = "Priest", hasLowWarningToggle = true, defaultThreshold = 60, lowLabel = "seconds remaining.", description = "Reminds you to buff yourself with Power Word: Fortitude (or Prayer of Fortitude if learned). Warns when missing or expiring soon." },

    -- Add more here as you add rules
}

-- Color picker: current clients (TBC Anniversary and Forever) use
-- SetupColorPickerAndShow/swatchFunc; the old field-based setup is kept as a fallback.
local function GetPickerAlpha()
    if ColorPickerFrame.GetColorAlpha then
        return ColorPickerFrame:GetColorAlpha()
    elseif OpacitySliderFrame then
        return 1 - OpacitySliderFrame:GetValue()
    end
    return 1
end

local function OpenColorPicker(color, hasOpacity, onChange, onCancel)
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b,
            opacity = color.a or 1,
            hasOpacity = hasOpacity,
            swatchFunc = onChange,
            opacityFunc = onChange,
            cancelFunc = onCancel,
        })
    else
        ColorPickerFrame.func = onChange
        ColorPickerFrame.swatchFunc = onChange
        ColorPickerFrame.opacityFunc = onChange
        ColorPickerFrame.cancelFunc = onCancel
        ColorPickerFrame.hasOpacity = hasOpacity
        ColorPickerFrame.opacity = 1 - (color.a or 1)
        ColorPickerFrame:SetColorRGB(color.r, color.g, color.b)
        ColorPickerFrame:Hide() -- Toggle refresh
        ColorPickerFrame:Show()
    end
end

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
    table.insert(groups, "Appearance")

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
             tab:SetPoint("TOPLEFT", panel.tabs[i-1], "TOPRIGHT", -14, 0)
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
            
            if rule.id == "general_account_wide" then
                cb:SetChecked(Prepped:IsAccountWide())
            end

            cb:SetScript("OnClick", function(self)
                if rule.id == "general_account_wide" then
                    if self:GetChecked() then
                        -- Switching to Account-wide: Warning
                        StaticPopup_Show("PREPPED_CONFIRM_ACCOUNT_WIDE")
                    else
                        -- Switching to Character: No warning needed
                        Prepped:SetAccountWide(false)
                        panel.refresh()
                        Prepped:CheckReminders()
                    end
                else
                    Prepped:SetRuleEnabled(rule.id, self:GetChecked())
                    Prepped:CheckReminders()
                end
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
                     desc:SetPoint("RIGHT", -10, 0)
                     desc:SetJustifyH("LEFT")
                     desc:SetWordWrap(true)
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

    -- 3.5 Add Reset Button to General Page
    local genPage = panel.pages["General"]
    if genPage then
        local resetBtn = CreateFrame("Button", nil, genPage, "UIPanelButtonTemplate")
        resetBtn:SetSize(140, 24)
        resetBtn:SetPoint("BOTTOMLEFT", 10, 0)
        resetBtn:SetText("Reset All Settings")
        resetBtn:SetScript("OnClick", function()
            StaticPopup_Show("PREPPED_RESET_ALL_SETTINGS")
        end)
        panel.resetBtn = resetBtn
    end

    -- 4. Create Appearance Page Controls
    local appPage = panel.pages["Appearance"]
    if appPage then
        local app = Prepped:GetAppearance()
        
        local function CreateAppRow(height)
            local y = appPage.currentY
            local row = CreateFrame("Frame", nil, appPage, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 10, y)
            row:SetPoint("RIGHT", -10, 0)
            row:SetHeight(height)
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
            appPage.currentY = y - (height + 5)
            return row
        end

        panel.colorButtons = {}
        local function CreateColorButton(name, parent, colorKey, labelText)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetSize(24, 24)
            btn:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground", 
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", 
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            
            local swatch = btn:CreateTexture(nil, "OVERLAY")
            swatch:SetPoint("TOPLEFT", 3, -3)
            swatch:SetPoint("BOTTOMRIGHT", -3, 3)
            btn.swatch = swatch
            btn.colorKey = colorKey
            
            local curApp = Prepped:GetAppearance()
            local c = curApp[colorKey]
            swatch:SetColorTexture(c.r, c.g, c.b, c.a or 1)
            
            local lbl = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            lbl:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            lbl:SetText(labelText)
            
            table.insert(panel.colorButtons, btn)

            btn:SetScript("OnClick", function()
                local c = Prepped:GetAppearance()[colorKey]
                local hasOpacity = (c.a ~= nil)
                local old = { r = c.r, g = c.g, b = c.b, a = c.a }

                local function ApplyColor(r, g, b, a)
                    local color = Prepped:GetAppearance()[colorKey]
                    color.r, color.g, color.b = r, g, b
                    if color.a ~= nil and a ~= nil then color.a = a end
                    if btn.swatch then
                        btn.swatch:SetColorTexture(r, g, b, color.a or 1)
                    end
                    Prepped:ApplyAppearance()
                end

                local function OnColorChanged()
                    -- The picker also fires this while it is being set up; ignore that.
                    if not ColorPickerFrame:IsShown() then return end
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    ApplyColor(r, g, b, hasOpacity and GetPickerAlpha() or nil)
                end

                local function OnCancel()
                    ApplyColor(old.r, old.g, old.b, old.a)
                end

                OpenColorPicker(c, hasOpacity, OnColorChanged, OnCancel)
            end)
            return btn
        end

        -- Font Size row
        local sizeRow = CreateAppRow(40)
        local sizeSlider = CreateFrame("Slider", "PreppedFontSizeSlider", sizeRow, "OptionsSliderTemplate")
        sizeSlider:SetPoint("LEFT", 10, 0)
        sizeSlider:SetSize(200, 16)
        sizeSlider:SetMinMaxValues(10, 40)
        sizeSlider:SetValueStep(1)
        sizeSlider:SetObeyStepOnDrag(true)
        sizeSlider:SetValue(app.fontSize)
        _G[sizeSlider:GetName().."Low"]:SetText("10")
        _G[sizeSlider:GetName().."High"]:SetText("40")
        _G[sizeSlider:GetName().."Text"]:SetText("Font Size: " .. app.fontSize)
        
        sizeSlider:SetScript("OnValueChanged", function(self, value)
            local val = math.floor(value)
            local curApp = Prepped:GetAppearance()
            curApp.fontSize = val
            _G[self:GetName().."Text"]:SetText("Font Size: " .. val)
            Prepped:ApplyAppearance()
        end)
        panel.fontSizeSlider = sizeSlider

        -- Minimum Width row
        local widthRow = CreateAppRow(40)
        local widthSlider = CreateFrame("Slider", "PreppedMinWidthSlider", widthRow, "OptionsSliderTemplate")
        widthSlider:SetPoint("LEFT", 10, 0)
        widthSlider:SetSize(200, 16)
        widthSlider:SetMinMaxValues(100, 1200)
        widthSlider:SetValueStep(10)
        widthSlider:SetObeyStepOnDrag(true)
        widthSlider:SetValue(app.minWidth or 400)
        _G[widthSlider:GetName().."Low"]:SetText("100")
        _G[widthSlider:GetName().."High"]:SetText("1200")
        _G[widthSlider:GetName().."Text"]:SetText("Minimum Width: " .. (app.minWidth or 400))
        
        widthSlider:SetScript("OnValueChanged", function(self, value)
            local val = math.floor(value)
            local curApp = Prepped:GetAppearance()
            curApp.minWidth = val
            _G[self:GetName().."Text"]:SetText("Minimum Width: " .. val)
            Prepped:ApplyAppearance()
        end)
        panel.minWidthSlider = widthSlider

        -- Font Color row
        local fontColorRow = CreateAppRow(40)
        local fontColorBtn = CreateColorButton("FontColor", fontColorRow, "fontColor", "Font Color")
        fontColorBtn:SetPoint("LEFT", 10, 0)

        -- Background Color row
        local bgColorRow = CreateAppRow(40)
        local bgColorBtn = CreateColorButton("BgColor", bgColorRow, "bgColor", "Background Color (with Opacity)")
        bgColorBtn:SetPoint("LEFT", 10, 0)
    end
    
    -- Initialize
    SelectGroup(1)

    panel.refresh = function()
        for _, rule in ipairs(Prepped.AllRules) do
            local cb = panel.checkboxes[rule.id]
            if cb then 
                if rule.id == "general_account_wide" then
                    cb:SetChecked(Prepped:IsAccountWide())
                else
                    cb:SetChecked(Prepped:IsRuleEnabled(rule.id)) 
                end
            end
            
            local eb = panel.editboxes[rule.id]
            if eb and rule.defaultThreshold then
                eb:SetText(tostring(Prepped:GetRuleThreshold(rule.id, rule.defaultThreshold)))
                eb:SetCursorPosition(0)
            end
        end

        if panel.fontSizeSlider then
            local app = Prepped:GetAppearance()
            panel.fontSizeSlider:SetValue(app.fontSize)
        end

        if panel.minWidthSlider then
            local app = Prepped:GetAppearance()
            panel.minWidthSlider:SetValue(app.minWidth or 400)
        end

        if panel.colorButtons then
            local app = Prepped:GetAppearance()
            for _, btn in ipairs(panel.colorButtons) do
                if btn.swatch and btn.colorKey then
                    local c = app[btn.colorKey]
                    btn.swatch:SetColorTexture(c.r, c.g, c.b, c.a or 1)
                end
            end
        end
    end
    
    -- ElvUI Support (Lazy Load on Show)
    panel:SetScript("OnShow", function(self)
        self.refresh()
        
        if not self.isSkinned and _G.ElvUI then
            local E = _G.ElvUI[1]
            local S = E and E:GetModule("Skins")
            if S then
                local function SafeSkin(method, obj)
                    if obj and S[method] then
                        pcall(function() S[method](S, obj) end)
                    end
                end

                for _, tab in ipairs(self.tabs) do SafeSkin("HandleTab", tab) end
                for _, cb in pairs(self.checkboxes) do SafeSkin("HandleCheckBox", cb) end
                for _, eb in pairs(self.editboxes) do SafeSkin("HandleEditBox", eb) end
                
                if self.fontSizeSlider then
                    -- Standard ElvUI method is HandleSliderFrame
                    if S.HandleSliderFrame then
                        SafeSkin("HandleSliderFrame", self.fontSizeSlider)
                        SafeSkin("HandleSliderFrame", self.minWidthSlider)
                    elseif S.HandleSlider then
                        SafeSkin("HandleSlider", self.fontSizeSlider)
                        SafeSkin("HandleSlider", self.minWidthSlider)
                    end
                end

                if self.colorButtons then
                    for _, btn in ipairs(self.colorButtons) do 
                        SafeSkin("HandleButton", btn) 
                    end
                end

                if self.resetBtn then
                    SafeSkin("HandleButton", self.resetBtn)
                end

                SafeSkin("HandleFrame", self.contentBox)
                
                if self.ruleFrames then
                    for _, row in ipairs(self.ruleFrames) do 
                        -- Some versions prefer HandleFrame, others HandleBackdrop for cards
                        if S.HandleFrame then
                            SafeSkin("HandleFrame", row)
                        elseif S.HandleBackdrop then
                            SafeSkin("HandleBackdrop", row)
                        end
                    end
                end
                
                self.isSkinned = true
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
    local profile = GetCurrentProfile()
    for _, rule in ipairs(self.AllRules) do
        if rule.id ~= "general_account_wide" then
            -- Initialize Thresholds and Low Enabled
            if rule.defaultThreshold then
                if profile.thresholds[rule.id] == nil then
                     profile.thresholds[rule.id] = rule.defaultThreshold
                end
                if profile.enabledLowRules[rule.id] == nil then
                     profile.enabledLowRules[rule.id] = true
                end
            end
            -- Initialize Enabled State (Default to true)
            if profile.enabledRules[rule.id] == nil then
                profile.enabledRules[rule.id] = true
            end
        end
    end
end

local container = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "ADDON_LOADED",
    "BAG_UPDATE",
    "PLAYER_UPDATE_RESTING",
    "SPELLS_CHANGED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PET_UI_UPDATE",
    "PLAYER_ALIVE",
    "PLAYER_DEAD",
    "PLAYER_UNGHOST",
    "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TALENT_UPDATE",
    -- Spell/talent changes; some of these only exist on one client.
    "LEARNED_SPELL_IN_SKILL_LINE",
    "CHARACTER_POINTS_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED",
}) do
    Compat.RegisterEvent(container, event)
end
-- Unit events only for the units we care about (avoids firing for every nameplate/raid member).
Compat.RegisterUnitEvent(container, "UNIT_INVENTORY_CHANGED", "player")
Compat.RegisterUnitEvent(container, "UNIT_AURA", "player")
Compat.RegisterUnitEvent(container, "UNIT_STATS", "player")
Compat.RegisterUnitEvent(container, "UNIT_PET", "player")
Compat.RegisterUnitEvent(container, "UNIT_HEALTH", "player", "pet")
Compat.RegisterUnitEvent(container, "UNIT_HAPPINESS", "pet")

local cacheInvalidatingEvents = {
    PLAYER_ENTERING_WORLD = true,
    SPELLS_CHANGED = true,
    LEARNED_SPELL_IN_SKILL_LINE = true,
    PLAYER_TALENT_UPDATE = true,
    CHARACTER_POINTS_CHANGED = true,
    ACTIVE_TALENT_GROUP_CHANGED = true,
    TRAIT_CONFIG_UPDATED = true,
}

container:SetScript("OnEvent", function(self, event, ...)
    if cacheInvalidatingEvents[event] then
        Compat.InvalidateCaches()
    end

    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            Prepped:InitializeDefaults()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if isLogin or isReload then
            Prepped:ShowWelcomeMessage()
        end
    end
    Prepped:CheckReminders()
end)

local updateTimer = 0
container:SetScript("OnUpdate", function(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= 0.1 then
        updateTimer = 0
        Prepped:CheckReminders()
    end
end)

_G.Prepped = Prepped
