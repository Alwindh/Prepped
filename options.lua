-- options.lua
-- Prepped's options in Blizzard's Settings UI (Options > AddOns > Prepped):
-- a General page with one sub-page for Appearance and each class.
-- Every control is a proxy setting that reads and writes the active profile.

local _, ns = ...

local Options = {}
ns.Options = Options

local PREFIX = "PREPPED_"
local CLASS_PAGES = { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" }

local proxies = {}

local function Proxy(category, key, varType, name, defaultValue, getValue, setValue)
    local setting = Settings.RegisterProxySetting(category, PREFIX .. key, varType, name, defaultValue, getValue, setValue)
    proxies[#proxies + 1] = setting
    return setting
end

-- Re-read every control (after switching profile or resetting).
function Options.Refresh()
    for _, setting in ipairs(proxies) do
        setting:NotifyUpdate()
    end
end

local function Round(value)
    return math.floor(value + 0.5)
end

local UNIT_FORMATS = { count = "%d", seconds = "%ds", percent = "%d%%", level = "%d" }
local SLIDER_LABELS = { count = "Warn below", percent = "Warn below", level = "From level" }

local function SliderOptions(rule, unit)
    local range = rule.range
    local options = Settings.CreateSliderOptions(range[1], range[2], range[3])
    local format = UNIT_FORMATS[unit] or "%d"
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format(format, Round(value))
    end)
    return options
end

local function OnRuleChanged()
    Prepped:CheckReminders()
end

local function ThresholdSetting(category, rule, key, name)
    local id, default = rule.id, rule.defaultThreshold
    return Proxy(category, id .. key, Settings.VarType.Number, name, default,
        function() return Prepped:GetRuleThreshold(id, default) end,
        function(value)
            Prepped:SetRuleThreshold(id, Round(value))
            OnRuleChanged()
        end)
end

-- One rule = a checkbox, a checkbox with a threshold slider, or a checkbox
-- with an indented "warn when expiring" row for buffs.
local function AddRule(category, layout, rule)
    local id = rule.id

    if rule.sliderOnly then
        local setting = ThresholdSetting(category, rule, "", rule.label)
        Settings.CreateSlider(category, setting, SliderOptions(rule, rule.unit), rule.description)
        return
    end

    local enabled = Proxy(category, id, Settings.VarType.Boolean, rule.label, true,
        function() return Prepped:GetRuleSetting(id) end,
        function(value)
            Prepped:SetRuleEnabled(id, value)
            OnRuleChanged()
        end)

    if rule.hasLowWarningToggle then
        local enabledInitializer = Settings.CreateCheckbox(category, enabled, rule.description)
        local warn = Proxy(category, id .. "_LOW", Settings.VarType.Boolean, "Warn when expiring", true,
            function() return Prepped:IsLowEnabled(id) end,
            function(value)
                Prepped:SetLowEnabled(id, value)
                OnRuleChanged()
            end)
        local seconds = ThresholdSetting(category, rule, "_SECONDS", "Seconds left")
        local warnInitializer = CreateSettingsCheckboxSliderInitializer(
            warn, "Warn when expiring", "Also warn shortly before the buff runs out.",
            seconds, SliderOptions(rule, "seconds"), "Seconds left", "Warn when this many seconds are left.")
        warnInitializer:SetParentInitializer(enabledInitializer, function() return enabled:GetValue() end)
        layout:AddInitializer(warnInitializer)
    elseif rule.defaultThreshold then
        local threshold = ThresholdSetting(category, rule, "_THRESHOLD", SLIDER_LABELS[rule.unit] or rule.label)
        layout:AddInitializer(CreateSettingsCheckboxSliderInitializer(
            enabled, rule.label, rule.description,
            threshold, SliderOptions(rule, rule.unit), SLIDER_LABELS[rule.unit] or rule.label, rule.description))
    else
        Settings.CreateCheckbox(category, enabled, rule.description)
    end
end

local function AddRulesForGroup(category, layout, group)
    for _, rule in ipairs(Prepped.AllRules) do
        if rule.group == group then
            AddRule(category, layout, rule)
        end
    end
end

------------------------------------------------------------------------
-- Dialogs
------------------------------------------------------------------------
StaticPopupDialogs["PREPPED_CONFIRM_ACCOUNT_WIDE"] = {
    text = "Use account-wide settings? This character's own Prepped settings will be cleared.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        Prepped:ClearCharacterSettings()
        Prepped:SetAccountWide(true)
        Options.Refresh()
        Prepped:CheckReminders()
    end,
    OnCancel = function()
        Options.Refresh() -- puts the checkbox back
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PREPPED_RESET_ALL_SETTINGS"] = {
    text = "Reset ALL Prepped settings? This clears account-wide settings, character profiles and appearance.",
    button1 = RESET,
    button2 = CANCEL,
    OnAccept = function()
        Prepped:ResetAllSettings()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local function BuildGeneralPage(category, layout)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"))

    AddRule(category, layout, Prepped:GetRule("general_master"))

    local accountWide = Proxy(category, "ACCOUNT_WIDE", Settings.VarType.Boolean, "Use Account-wide Settings", true,
        function() return Prepped:IsAccountWide() end,
        function(value)
            if value then
                StaticPopup_Show("PREPPED_CONFIRM_ACCOUNT_WIDE")
            else
                Prepped:SetAccountWide(false)
                Options.Refresh()
                Prepped:CheckReminders()
            end
        end)
    Settings.CreateCheckbox(category, accountWide, Prepped:GetRule("general_account_wide").description)

    AddRule(category, layout, Prepped:GetRule("general_welcome"))

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Supplies"))
    AddRule(category, layout, Prepped:GetRule("general_water"))
    AddRule(category, layout, Prepped:GetRule("general_water_minlevel"))
    AddRule(category, layout, Prepped:GetRule("general_repair"))

    layout:AddInitializer(CreateSettingsButtonInitializer("Reset All Settings", RESET,
        function() StaticPopup_Show("PREPPED_RESET_ALL_SETTINGS") end,
        "Reset every Prepped setting, profile and appearance option to its default.", true))
end

local function ColorToHex(color)
    return CreateColor(color.r, color.g, color.b, 1):GenerateHexColor()
end

local function ColorSetting(category, key, name, colorKey, defaultHex)
    return Proxy(category, key, Settings.VarType.String, name, defaultHex,
        function() return ColorToHex(Prepped:GetAppearance()[colorKey]) end,
        function(value)
            local color = Prepped:GetAppearance()[colorKey]
            color.r, color.g, color.b = CreateColorFromHexString(value):GetRGB()
            Prepped:ApplyAppearance()
        end)
end

local function AppearanceSlider(category, key, name, appKey, default, min, max, step, format, tooltip)
    local setting = Proxy(category, key, Settings.VarType.Number, name, default,
        function() return Prepped:GetAppearance()[appKey] or default end,
        function(value)
            Prepped:GetAppearance()[appKey] = Round(value)
            Prepped:ApplyAppearance()
        end)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format(format, Round(value))
    end)
    Settings.CreateSlider(category, setting, options, tooltip)
end

local function BuildAppearancePage(category)
    AppearanceSlider(category, "FONT_SIZE", "Font Size", "fontSize", 18, 10, 40, 1, "%d", "Size of the reminder text.")
    AppearanceSlider(category, "MIN_WIDTH", "Minimum Width", "minWidth", 400, 100, 1200, 10, "%d",
        "Reminder bars are at least this wide and grow to fit longer text.")
    Settings.CreateColorSwatch(category, ColorSetting(category, "FONT_COLOR", "Text Color", "fontColor", "ffffd100"),
        "Color of the reminder text.")
    Settings.CreateColorSwatch(category, ColorSetting(category, "BG_COLOR", "Background Color", "bgColor", "ff000000"),
        "Color of the reminder bars.")

    local opacity = Proxy(category, "BG_OPACITY", Settings.VarType.Number, "Background Opacity", 50,
        function() return Round((Prepped:GetAppearance().bgColor.a or 0.5) * 100) end,
        function(value)
            Prepped:GetAppearance().bgColor.a = Round(value) / 100
            Prepped:ApplyAppearance()
        end)
    local options = Settings.CreateSliderOptions(0, 100, 5)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format("%d%%", Round(value))
    end)
    Settings.CreateSlider(category, opacity, options, "How see-through the reminder bars are.")
end

-- Called once SavedVariables are loaded (ADDON_LOADED).
function Options.Create()
    if Options.category then return Options.category end

    local category, layout = Settings.RegisterVerticalLayoutCategory("Prepped")
    BuildGeneralPage(category, layout)

    local appearance = Settings.RegisterVerticalLayoutSubcategory(category, "Appearance")
    BuildAppearancePage(appearance)

    for _, group in ipairs(CLASS_PAGES) do
        local page, pageLayout = Settings.RegisterVerticalLayoutSubcategory(category, group)
        AddRulesForGroup(page, pageLayout, group)
    end

    Settings.RegisterAddOnCategory(category)
    Options.category = category
    return category
end

function Options.Open()
    if Options.category then
        Settings.OpenToCategory(Options.category:GetID())
        return true
    end
    return false
end
