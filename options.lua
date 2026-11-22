-- options.lua
-- Prepped's options in Blizzard's Settings UI (Options > AddOns > Prepped):
-- a General page with one sub-page for Appearance and each class.
-- Every control is a proxy setting that reads and writes the active profile.

local _, ns = ...
local L, Prepped = ns.L, ns.Prepped

local Options = {}
ns.Options = Options

local PREFIX = "PREPPED_"
local CLASS_PAGES = {
    { "Druid", "DRUID" }, { "Hunter", "HUNTER" }, { "Mage", "MAGE" }, { "Paladin", "PALADIN" }, { "Priest", "PRIEST" },
    { "Rogue", "ROGUE" }, { "Shaman", "SHAMAN" }, { "Warlock", "WARLOCK" }, { "Warrior", "WARRIOR" },
}

local proxies = {}
local added = {} -- rules that already have a control

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

local UNIT_FORMATS = {
    count = function(value) return string.format("%d", value) end,
    seconds = function(value) return ns.FormatDuration(value) end,
    percent = function(value) return string.format("%d%%", value) end,
    level = function(value) return string.format("%d", value) end,
    minutes = function(value) return string.format(L["%d min"], value) end,
}
local SLIDER_LABELS = { count = L["Warn below"], percent = L["Warn below"], level = L["From level"], minutes = L["Minutes"] }

local function SliderOptions(rule, unit)
    local range = rule.range
    local options = Settings.CreateSliderOptions(range[1], range[2], range[3])
    local formatValue = UNIT_FORMATS[unit] or UNIT_FORMATS.count
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return formatValue(Round(value))
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

-- One rule = a checkbox, a checkbox with a threshold slider, a plain slider, or
-- a checkbox with an indented "warn when expiring" row for buffs.
local function AddRule(category, layout, rule)
    if not rule or added[rule.id] then return end
    added[rule.id] = true
    local id = rule.id

    if rule.sliderOnly then
        local setting = ThresholdSetting(category, rule, "", rule.label)
        Settings.CreateSlider(category, setting, SliderOptions(rule, rule.unit), rule.description)
        return
    end

    local enabled = Proxy(category, id, Settings.VarType.Boolean, rule.label, rule.defaultEnabled ~= false,
        function() return Prepped:GetRuleSetting(id) end,
        function(value)
            Prepped:SetRuleEnabled(id, value)
            OnRuleChanged()
        end)

    if rule.hasLowWarningToggle then
        local enabledInitializer = Settings.CreateCheckbox(category, enabled, rule.description)
        local warn = Proxy(category, id .. "_LOW", Settings.VarType.Boolean, L["Warn when expiring"], true,
            function() return Prepped:IsLowEnabled(id) end,
            function(value)
                Prepped:SetLowEnabled(id, value)
                OnRuleChanged()
            end)
        local seconds = ThresholdSetting(category, rule, "_SECONDS", L["Time left"])
        local warnInitializer = CreateSettingsCheckboxSliderInitializer(
            warn, L["Warn when expiring"], L["Also warn shortly before the buff runs out."],
            seconds, SliderOptions(rule, "seconds"), L["Time left"], L["Warn when this much time is left."])
        warnInitializer:SetParentInitializer(enabledInitializer, function() return enabled:GetValue() end)
        layout:AddInitializer(warnInitializer)
    elseif rule.defaultThreshold then
        local sliderLabel = rule.sliderLabel or SLIDER_LABELS[rule.unit] or rule.label
        local threshold = ThresholdSetting(category, rule, "_THRESHOLD", sliderLabel)
        layout:AddInitializer(CreateSettingsCheckboxSliderInitializer(
            enabled, rule.label, rule.description,
            threshold, SliderOptions(rule, rule.unit), sliderLabel, rule.description))
    else
        Settings.CreateCheckbox(category, enabled, rule.description)
    end
end

local function AddRules(category, layout, ruleIds)
    for _, ruleId in ipairs(ruleIds) do
        AddRule(category, layout, Prepped:GetRule(ruleId))
    end
end

local function AddRulesForGroup(category, layout, group)
    for _, rule in ipairs(Prepped.AllRules) do
        if rule.group == group then
            AddRule(category, layout, rule)
        end
    end
end

local function Header(layout, text)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

------------------------------------------------------------------------
-- Dialogs
------------------------------------------------------------------------
StaticPopupDialogs["PREPPED_CONFIRM_ACCOUNT_WIDE"] = {
    text = L["Use account-wide settings? This character's own Prepped settings will be cleared."],
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
    text = L["Reset ALL Prepped settings? This clears account-wide settings, character profiles, snoozes and appearance."],
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
    Header(layout, L["General"])
    AddRule(category, layout, Prepped:GetRule("general_master"))

    local accountWide = Proxy(category, "ACCOUNT_WIDE", Settings.VarType.Boolean, L["Use Account-wide Settings"], true,
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
    added.general_account_wide = true

    AddRules(category, layout, { "general_welcome", "general_sound" })

    Header(layout, L["Supplies"])
    AddRules(category, layout, { "general_water", "general_food_stock", "general_water_minlevel", "general_bandages",
        "general_repair", "general_repair_item", "general_gear_breaking", "general_bag_space", "general_hearthstone" })

    Header(layout, L["Groups and Vendors"])
    AddRules(category, layout, { "general_group_check", "general_ready_check", "general_vendor_check",
        "general_group_announce", "general_group_announce_raids" })

    Header(layout, L["Leveling"])
    AddRules(category, layout, { "general_food", "general_camp", "general_talents", "general_legacy" })

    -- Anything on the General page not placed above
    AddRulesForGroup(category, layout, "General")

    layout:AddInitializer(CreateSettingsButtonInitializer(L["Reset All Settings"], RESET,
        function() StaticPopup_Show("PREPPED_RESET_ALL_SETTINGS") end,
        L["Reset every Prepped setting, profile, snooze and appearance option to its default."], true))
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
            Prepped:ApplyAppearance(true)
        end)
end

local function AppearanceSlider(category, key, name, appKey, default, minValue, maxValue, step, format, tooltip)
    local setting = Proxy(category, key, Settings.VarType.Number, name, default,
        function() return Prepped:GetAppearance()[appKey] or default end,
        function(value)
            Prepped:GetAppearance()[appKey] = Round(value)
            Prepped:ApplyAppearance(true)
        end)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format(format, Round(value))
    end)
    Settings.CreateSlider(category, setting, options, tooltip)
end

local function DisplayCheckbox(category, key, optionKey, name, default, tooltip)
    local setting = Proxy(category, key, Settings.VarType.Boolean, name, default,
        function() return Prepped:GetDisplayOption(optionKey) end,
        function(value) Prepped:SetDisplayOption(optionKey, value) end)
    Settings.CreateCheckbox(category, setting, tooltip)
end

local function BuildAppearancePage(category, layout)
    Header(layout, L["Position"])
    layout:AddInitializer(CreateSettingsButtonInitializer(L["Move Reminders"], L["Move"],
        function() Prepped:SetMoving(true) end,
        L["Shows sample reminders you can drag anywhere. Right-click them or press Escape when you're done. Edit Mode moves them too."], true))
    layout:AddInitializer(CreateSettingsButtonInitializer(L["Reset Position"], RESET,
        function() ns.Display:ResetPosition() end, L["Put the reminders back in their default place."], true))
    DisplayCheckbox(category, "GROW_UP", "growUp", L["Grow Upwards"], false,
        L["New reminders are added above the first one instead of below it."])

    Header(layout, L["Reminders"])
    DisplayCheckbox(category, "SHOW_ICONS", "showIcons", L["Show Icons"], true,
        L["Show the spell or item a reminder is about next to its text."])
    DisplayCheckbox(category, "CLICKABLE", "clickable", L["Clickable Reminders"], true,
        L["Out of combat, left-click a reminder to fix it (cast the buff, apply the poison, ...) and right-click it to snooze or turn it off. While a reminder shows, its text and icon catch your clicks instead of the world behind them."])

    Header(layout, L["Look"])
    AppearanceSlider(category, "FONT_SIZE", L["Font Size"], "fontSize", 18, 10, 40, 1, "%d", L["Size of the reminder text."])
    AppearanceSlider(category, "MIN_WIDTH", L["Minimum Width"], "minWidth", 400, 100, 1200, 10, "%d",
        L["Reminder bars are at least this wide and grow to fit longer text."])
    Settings.CreateColorSwatch(category, ColorSetting(category, "FONT_COLOR", L["Text Color"], "fontColor", "ffffd100"),
        L["Color of the reminder text."])
    Settings.CreateColorSwatch(category, ColorSetting(category, "BG_COLOR", L["Background Color"], "bgColor", "ff000000"),
        L["Color of the reminder bars."])

    local opacity = Proxy(category, "BG_OPACITY", Settings.VarType.Number, L["Background Opacity"], 50,
        function() return Round((Prepped:GetAppearance().bgColor.a or 0.5) * 100) end,
        function(value)
            Prepped:GetAppearance().bgColor.a = Round(value) / 100
            Prepped:ApplyAppearance(true)
        end)
    local options = Settings.CreateSliderOptions(0, 100, 5)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format("%d%%", Round(value))
    end)
    Settings.CreateSlider(category, opacity, options, L["How see-through the reminder bars are."])
end

-- Called once SavedVariables are loaded (ADDON_LOADED).
function Options.Create()
    if Options.category then return Options.category end

    local category, layout = Settings.RegisterVerticalLayoutCategory("Prepped")
    BuildGeneralPage(category, layout)

    local appearance, appearanceLayout = Settings.RegisterVerticalLayoutSubcategory(category, L["Appearance"])
    BuildAppearancePage(appearance, appearanceLayout)

    Options.pages = { Appearance = appearance }
    local classNames = LOCALIZED_CLASS_NAMES_MALE or {}
    for _, page in ipairs(CLASS_PAGES) do
        local group, classToken = page[1], page[2]
        local subcategory, pageLayout = Settings.RegisterVerticalLayoutSubcategory(category, classNames[classToken] or group)
        AddRulesForGroup(subcategory, pageLayout, group)
        Options.pages[group] = subcategory
    end

    Settings.RegisterAddOnCategory(category)
    Options.category = category
    return category
end

-- Opens Prepped's options, on a rule group's page if given ("Mage", ...).
function Options.Open(group)
    if not Options.category then return false end
    local page = (group and Options.pages and Options.pages[group]) or Options.category
    Settings.OpenToCategory(page:GetID())
    return true
end
