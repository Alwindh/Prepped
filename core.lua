-- core.lua
-- Prepped's core: the rules (reminders and settings), saved settings, checking
-- the reminders, snoozes, the update scheduler and the game events.
--
-- Reminder modules (reminders_*.lua) describe their reminders as data with
-- Prepped:RegisterModule; each rule carries its options metadata, when it may
-- show, and its check, icon and click action. display.lua draws the reminders,
-- supplies.lua decides when supply reminders show and posts the group message,
-- commands.lua has the slash commands.

local addonName, ns = ...
local API, L = ns.API, ns.L

local Prepped = {}
Prepped.reminderModules = {}
Prepped.API = API
Prepped.L = L
ns.Prepped = Prepped
-- Published right away: the reminder modules register through this global.
_G.Prepped = Prepped

local GetTime = GetTime
local format, floor, max, min = string.format, math.floor, math.max, math.min
local Wipe = API.Wipe

-- Update scheduling (see "Events and scheduling" at the end): events only mark
-- the reminders dirty, and the driver re-checks them in one go.
local UPDATE_MIN_INTERVAL = 0.2 -- seconds between event-driven checks (coalesces bursts)
local HEARTBEAT_INTERVAL = 1    -- countdowns ("30s left") and timers (group message, supply windows, preview)
local dirty, sinceCheck = true, 0

------------------------------------------------------------------------
-- Text helpers
------------------------------------------------------------------------
-- "45s", "3m 20s", "50m"
function ns.FormatDuration(seconds)
    seconds = max(0, floor(seconds))
    if seconds < 60 then return format(L["%ds"], seconds) end
    local minutes, rest = floor(seconds / 60), seconds % 60
    if rest == 0 then return format(L["%dm"], minutes) end
    return format(L["%dm %ds"], minutes, rest)
end

-- "a", "a and b", "a, b and c"
function ns.JoinList(items)
    local count = #items
    if count <= 1 then return items[1] or "" end
    return format(L["%s and %s"], table.concat(items, ", ", 1, count - 1), items[count])
end

function Prepped:Print(message)
    print("|cffff8000Prepped:|r " .. message)
end

------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------
-- A rule is one row of options and, when it has a check, one reminder:
--   id                    settings key (never rename: saved settings use it)
--   group                 options page ("General", "Mage", ...)
--   label, description    options texts (also the reminder's tooltip and menu title)
--   defaultEnabled=false  off until the player turns it on
--   defaultThreshold, unit, range {min, max, step}, sliderLabel: a slider
--   hasLowWarningToggle   the threshold is "warn when this many seconds are left"
--   sliderOnly            a plain slider without its own checkbox (and no reminder)
--   announce = { state, action }: named in the group message, e.g.
--     { "low on ammo ({count} left)", "buy more ammo" }
-- Reminders also have:
--   check(rule)           returns the text to show (or nil), a value for the
--                         group message (a number or { count =, name = }) and
--                         optionally an icon
--   supply                a supply reminder: only at supply time (Prepped:IsSupplyTime)
--   adventuring           only while not resting
--   outOfCombat, noTravel not in combat / not mounted or in a travel form
--   suppressedBy          { ruleId, ... }: skipped when one of these showed
--                         earlier in the module's list
--   icon                  texture, or function(rule) -> texture; rules with an
--                         `item` default to that item's icon
--   action(rule)          what clicking the reminder does: an ns.Action, or nil
Prepped.AllRules = {}
local rulesById = {}

-- Adds rules in options order.
function Prepped:RegisterRules(group, rules)
    for _, rule in ipairs(rules) do
        rule.group = rule.group or group
        if rulesById[rule.id] then error("Prepped: duplicate rule " .. rule.id) end
        rulesById[rule.id] = rule
        self.AllRules[#self.AllRules + 1] = rule
    end
end

-- module = { class = "MAGE" (nil: every class), group = "Mage", reminders = { rule, ... } }
-- The reminders are checked in this order.
function Prepped:RegisterModule(module)
    self:RegisterRules(module.group, module.reminders)
    self.reminderModules[#self.reminderModules + 1] = module
end

function Prepped:GetRule(ruleId)
    return rulesById[ruleId]
end

local function RuleDefaultEnabled(rule)
    return not (rule and rule.defaultEnabled == false)
end

local function ClampToRange(rule, value)
    local range = rule and rule.range
    if range then value = min(range[2], max(range[1], value)) end
    return value
end

-- Settings that aren't reminders of their own.
Prepped:RegisterRules("General", {
    { id = "general_master", label = L["Enable Prepped"], description = L["Turn all of Prepped's reminders on or off."] },
    { id = "general_account_wide", label = L["Use Account-wide Settings"],
        description = L["Share these settings between all your characters. Turn this off to give each character its own settings."] },
    { id = "general_welcome", label = L["Show Welcome Message"], description = L["Show a line in chat when you log in."] },
    { id = "general_sound", label = L["Sound for New Reminders"], defaultEnabled = false, defaultThreshold = 5, unit = "minutes",
        sliderLabel = L["Repeat after"], range = { 1, 60, 1 },
        description = L["Play a short sound when a reminder appears. The same reminder stays silent for this many minutes afterwards, and there's never a sound in combat."] },
    { id = "general_group_check", label = L["Check Supplies When Joining a Group"],
        description = L["When you join a party or raid, show your supply reminders (reagents, ammo, repairs and so on) for a minute, even outside cities and inns. Only you see them, and not during combat."] },
    { id = "general_ready_check", label = L["Check Supplies on Ready Check"],
        description = L["During a ready check, show your supply reminders even outside cities and inns, so you know what you're short on before the pull. Not during combat."] },
    { id = "general_vendor_check", label = L["Check Supplies at Vendors"],
        description = L["While you talk to a vendor, show your supply reminders even outside cities and inns, for example at a vendor in a camp."] },
    { id = "general_group_announce", label = L["Tell My Group"], defaultThreshold = 50, unit = "percent",
        sliderLabel = L["Repairs below"], range = { 0, 100, 5 },
        description = L["When you join a party, post one line in group chat with what you're low on, for example \"[Prepped] you're at 47% durability, remember to repair soon.\" Once per group, never during combat. Durability is only mentioned below this percentage."] },
    { id = "general_group_announce_raids", label = L["Also Post in Raids"], defaultEnabled = false,
        description = L["Also post that line when you join a raid. Off by default, so a raid doesn't get a line from everyone who uses Prepped."] },
})

------------------------------------------------------------------------
-- Settings (SavedVariables: PreppedSettings)
------------------------------------------------------------------------
-- PreppedSettings = {
--     schemaVersion = 2,
--     useAccountWide = true,             -- false: each character has its own profile
--     global = profile,                  -- the account-wide profile
--     profiles = { ["Name - Realm"] = profile },
--     appearance = { fontSize, minWidth, fontColor = { r, g, b }, bgColor = { r, g, b, a },
--                    showIcons, growUp, clickable, position = { x, y } },  -- the last four: nil = default
--     characters = { ["Name - Realm"] = { snoozed = { [ruleId] = until }, lastSpell = { [ruleId] = spellID } } },
-- }
-- profile = { enabledRules = {}, enabledLowRules = {}, thresholds = {} } holds only
-- what the player changed: anything missing falls back to the rule's default, so a
-- new default reaches everyone who never touched that setting.
local SCHEMA_VERSION = 2
local PROFILE_KEYS = { "enabledRules", "enabledLowRules", "thresholds" }
local DEFAULT_APPEARANCE = {
    fontSize = 18,
    minWidth = 400,
    fontColor = { r = 1, g = 0.82, b = 0 },
    bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
}
local DISPLAY_DEFAULTS = { showIcons = true, growUp = false, clickable = true }

local characterKey
local function CharacterKey()
    if characterKey then return characterKey end
    local name = UnitName("player")
    local key = (name or "Unknown") .. " - " .. ((GetRealmName and GetRealmName()) or "")
    if name and name ~= "" and name ~= UNKNOWNOBJECT then characterKey = key end
    return key
end

local function NewProfile()
    return { enabledRules = {}, enabledLowRules = {}, thresholds = {} }
end

local function RepairProfile(profile)
    for _, key in ipairs(PROFILE_KEYS) do
        if type(profile[key]) ~= "table" then profile[key] = {} end
    end
    return profile
end

local function RepairAppearance(settings)
    local app = settings.appearance
    if type(app) ~= "table" then
        app = {}
        settings.appearance = app
    end
    if type(app.fontSize) ~= "number" then app.fontSize = DEFAULT_APPEARANCE.fontSize end
    if type(app.minWidth) ~= "number" then app.minWidth = DEFAULT_APPEARANCE.minWidth end
    for _, key in ipairs({ "fontColor", "bgColor" }) do
        local color = app[key]
        if type(color) ~= "table" or type(color.r) ~= "number" or type(color.g) ~= "number" or type(color.b) ~= "number" then
            local default = DEFAULT_APPEARANCE[key]
            app[key] = { r = default.r, g = default.g, b = default.b, a = default.a }
        end
    end
    for key in pairs(DISPLAY_DEFAULTS) do
        if app[key] ~= nil and type(app[key]) ~= "boolean" then app[key] = nil end
    end
    local position = app.position
    if position ~= nil and (type(position) ~= "table" or type(position.x) ~= "number" or type(position.y) ~= "number") then
        app.position = nil
    end
end

-- The account-wide profile and every character's.
local function ForEachProfile(settings, fn)
    if type(settings.global) == "table" then fn(settings.global) end
    for _, profile in pairs(settings.profiles) do
        if type(profile) == "table" then fn(profile) end
    end
end

-- Defaults that have changed since schema 1 wrote every default out; a saved
-- value equal to the old default was never the player's choice.
local PRE_SCHEMA2_DEFAULTS = { general_repair = 100 }

-- MIGRATIONS[n] upgrades settings from schema n - 1 to n. Settings from a newer
-- Prepped (a downgrade) are left alone.
local MIGRATIONS = {
    -- 2 (v2.4.0): until now every default was written into the profile at login,
    -- so a changed default never reached existing players. Drop stored values that
    -- equal the default, settings of rules that no longer exist (Seal, Battle
    -- Shout, ...), and put thresholds back inside their slider's range.
    [2] = function(settings)
        ForEachProfile(settings, function(profile)
            RepairProfile(profile)
            for ruleId, enabled in pairs(profile.enabledRules) do
                local rule = rulesById[ruleId]
                if not rule or type(enabled) ~= "boolean" or enabled == RuleDefaultEnabled(rule) then
                    profile.enabledRules[ruleId] = nil
                end
            end
            for ruleId, enabled in pairs(profile.enabledLowRules) do
                local rule = rulesById[ruleId]
                if not (rule and rule.hasLowWarningToggle) or enabled ~= false then
                    profile.enabledLowRules[ruleId] = nil
                end
            end
            for ruleId, value in pairs(profile.thresholds) do
                local rule = rulesById[ruleId]
                if not (rule and rule.defaultThreshold) or type(value) ~= "number" then
                    profile.thresholds[ruleId] = nil
                else
                    value = ClampToRange(rule, value)
                    if value == rule.defaultThreshold or value == PRE_SCHEMA2_DEFAULTS[ruleId] then value = nil end
                    profile.thresholds[ruleId] = value
                end
            end
        end)
    end,
}

local function EnsureSettings()
    local settings = PreppedSettings
    if type(settings) ~= "table" then
        settings = {}
        PreppedSettings = settings
    end
    if settings.useAccountWide == nil then settings.useAccountWide = true end
    if type(settings.global) ~= "table" then settings.global = NewProfile() end
    if type(settings.profiles) ~= "table" then settings.profiles = {} end
    if type(settings.characters) ~= "table" then settings.characters = {} end
    RepairAppearance(settings)

    local version = tonumber(settings.schemaVersion) or 1
    if version < SCHEMA_VERSION then
        for step = version + 1, SCHEMA_VERSION do
            local migrate = MIGRATIONS[step]
            if migrate then migrate(settings) end
        end
        settings.schemaVersion = SCHEMA_VERSION
    end

    RepairProfile(settings.global)
    local key = CharacterKey()
    if type(settings.profiles[key]) ~= "table" then settings.profiles[key] = NewProfile() end
    RepairProfile(settings.profiles[key])
    return settings
end

-- The active profile, appearance and character state are looked up once, not on every read.
local activeProfile, activeAppearance, activeCharacter

local function ResetSettingsCache()
    activeProfile, activeAppearance, activeCharacter = nil, nil, nil
end

local function GetCurrentProfile()
    local profile = activeProfile
    if profile then return profile end
    local settings = EnsureSettings()
    if settings.useAccountWide then
        profile = settings.global
    else
        profile = settings.profiles[CharacterKey()]
    end
    activeProfile = profile
    return profile
end

-- This character's snoozes and remembered spells (not part of the profiles).
local function CharacterState()
    local state = activeCharacter
    if state then return state end
    local characters = EnsureSettings().characters
    local key = CharacterKey()
    state = characters[key]
    if type(state) ~= "table" then
        state = {}
        characters[key] = state
    end
    if type(state.snoozed) ~= "table" then state.snoozed = {} end
    if type(state.lastSpell) ~= "table" then state.lastSpell = {} end
    if characterKey then activeCharacter = state end -- only once the name is known
    return state
end

function Prepped:IsRuleEnabled(ruleId)
    local enabledRules = GetCurrentProfile().enabledRules

    -- Master switch
    local master = enabledRules.general_master
    if master == nil then master = true end
    if ruleId == "general_master" then return master end
    if not master then return false end

    local enabled = enabledRules[ruleId]
    if enabled == nil then return RuleDefaultEnabled(rulesById[ruleId]) end
    return enabled
end

-- The rule's own on/off setting, ignoring the master switch (for the options UI).
function Prepped:GetRuleSetting(ruleId)
    local enabled = GetCurrentProfile().enabledRules[ruleId]
    if enabled == nil then return RuleDefaultEnabled(rulesById[ruleId]) end
    return enabled ~= false
end

function Prepped:SetRuleEnabled(ruleId, enabled)
    GetCurrentProfile().enabledRules[ruleId] = enabled
end

function Prepped:IsLowEnabled(ruleId)
    local enabled = GetCurrentProfile().enabledLowRules[ruleId]
    if enabled == nil then return true end -- "warn when expiring" defaults to on
    return enabled
end

function Prepped:SetLowEnabled(ruleId, enabled)
    GetCurrentProfile().enabledLowRules[ruleId] = enabled
end

-- The player's setting, else the rule's default (the rules are the only source
-- of defaults), else the fallback.
function Prepped:GetRuleThreshold(ruleId, fallback)
    local value = GetCurrentProfile().thresholds[ruleId]
    if value ~= nil then return value end
    local rule = rulesById[ruleId]
    if rule and rule.defaultThreshold ~= nil then return rule.defaultThreshold end
    return fallback or 0
end

function Prepped:SetRuleThreshold(ruleId, value)
    GetCurrentProfile().thresholds[ruleId] = ClampToRange(rulesById[ruleId], tonumber(value) or 0)
end

function Prepped:GetAppearance()
    local app = activeAppearance
    if app then return app end
    app = EnsureSettings().appearance
    activeAppearance = app
    return app
end

-- Display options (showIcons, growUp, clickable): the saved value or the default.
function Prepped:GetDisplayOption(key)
    local value = self:GetAppearance()[key]
    if value == nil then return DISPLAY_DEFAULTS[key] end
    return value
end

function Prepped:SetDisplayOption(key, value)
    if value == DISPLAY_DEFAULTS[key] then value = nil end
    self:GetAppearance()[key] = value
    self:ApplyAppearance()
end

-- Redraws the bars after an appearance change; withPreview shows sample
-- reminders for a moment so the change can be seen.
function Prepped:ApplyAppearance(withPreview)
    if ns.Display then ns.Display:ApplyAppearance(withPreview) end
end

-- Profile management
function Prepped:IsAccountWide()
    return EnsureSettings().useAccountWide
end

function Prepped:SetAccountWide(enabled)
    EnsureSettings().useAccountWide = enabled
    ResetSettingsCache()
end

function Prepped:ClearCharacterSettings()
    EnsureSettings().profiles[CharacterKey()] = NewProfile()
    ResetSettingsCache()
end

-- Loads (and if needed upgrades) the saved settings. Defaults are not written
-- into the profile; they come from the rules when read.
function Prepped:InitializeDefaults()
    ResetSettingsCache()
    GetCurrentProfile()
end

function Prepped:ResetAllSettings()
    _G.PreppedSettings = nil
    self:InitializeDefaults()
    self:ApplyAppearance()
    if ns.Options then ns.Options.Refresh() end
    self:CheckReminders()
    self:Print(L["All settings have been reset to their defaults."])
end

-- Turns a reminder off (its menu's "Turn off this reminder").
function Prepped:TurnOffRule(ruleId)
    local rule = rulesById[ruleId]
    if not rule then return end
    self:SetRuleEnabled(ruleId, false)
    if ns.Options then ns.Options.Refresh() end
    self:CheckReminders()
    self:Print(format(L["%s is off. You can turn it back on in the Prepped options (/prepped)."], rule.label))
end

------------------------------------------------------------------------
-- Snoozes (per character, kept across /reload and logouts)
------------------------------------------------------------------------
local SNOOZE_UNTIL_LOGIN = -1

local function Now()
    return (GetServerTime and GetServerTime()) or time()
end

function Prepped:IsSnoozed(ruleId)
    local snoozed = CharacterState().snoozed
    local untilTime = snoozed[ruleId]
    if untilTime == nil then return false end
    if untilTime == SNOOZE_UNTIL_LOGIN then return true end
    if type(untilTime) ~= "number" or Now() >= untilTime then
        snoozed[ruleId] = nil
        return false
    end
    return true
end

-- Hides one reminder for `seconds`, or until the next login with "login".
function Prepped:SnoozeRule(ruleId, seconds)
    CharacterState().snoozed[ruleId] = (seconds == "login") and SNOOZE_UNTIL_LOGIN or (Now() + seconds)
    self:CheckReminders()
end

-- /prepped snooze: hides the reminders on screen for a while. Returns how many.
function Prepped:Snooze(minutes)
    local snoozed, untilTime, count = CharacterState().snoozed, Now() + minutes * 60, 0
    for i = 1, self.activeCount do
        local ruleId = self.displayLines[i] and self.displayLines[i].ruleId
        if ruleId then
            snoozed[ruleId] = untilTime
            count = count + 1
        end
    end
    self:CheckReminders()
    return count
end

-- Ends every snooze. Returns how many were active.
function Prepped:Unsnooze()
    local snoozed, count = CharacterState().snoozed, 0
    for ruleId in pairs(snoozed) do
        if self:IsSnoozed(ruleId) then count = count + 1 end
    end
    Wipe(snoozed)
    self:CheckReminders()
    return count
end

-- A new session: "until next login" snoozes end (a /reload keeps them).
function Prepped:ClearLoginSnoozes()
    local snoozed = CharacterState().snoozed
    for ruleId, untilTime in pairs(snoozed) do
        if untilTime == SNOOZE_UNTIL_LOGIN then snoozed[ruleId] = nil end
    end
end

-- "ruleId (12m)" / "ruleId (until login)" per active snooze, for /prepped debug.
function Prepped:DescribeSnoozes()
    local list, now = {}, Now()
    for ruleId, untilTime in pairs(CharacterState().snoozed) do
        if untilTime == SNOOZE_UNTIL_LOGIN then
            list[#list + 1] = ruleId .. " (until login)"
        elseif type(untilTime) == "number" and untilTime > now then
            list[#list + 1] = format("%s (%dm)", ruleId, math.ceil((untilTime - now) / 60))
        end
    end
    table.sort(list)
    return list
end

------------------------------------------------------------------------
-- Remembered spells: which aura, aspect, blessing, ... you had up last
------------------------------------------------------------------------
function Prepped:RememberSpell(rule, spellId)
    if rule.dontRemember and rule.dontRemember[spellId] then return end
    local lastSpell = CharacterState().lastSpell
    if lastSpell[rule.id] ~= spellId then lastSpell[rule.id] = spellId end
end

local function Contains(list, value)
    for _, entry in ipairs(list) do
        if entry == value then return true end
    end
    return false
end

-- The spell a rule with several choices asks for: the one you had up last if
-- you still know it, else the first of rule.prefer (lists of spell IDs, rank 1
-- first) you know, else any learned spell of rule.family. rule.upgrades =
-- { { from = ids, to = ids } }: a spell that takes over from the one you had
-- (Ice Armor from Frost Armor) once you know it. Returns name, spellID.
function Prepped:ChooseSpell(rule)
    local remembered = CharacterState().lastSpell[rule.id]
    if remembered then
        for _, upgrade in ipairs(rule.upgrades or {}) do
            if Contains(upgrade.from, remembered) then
                remembered = API.BestKnownSpell(upgrade.to) or remembered
            end
        end
        local name = C_Spell.GetSpellName(remembered)
        if API.KnowsSpellName(name) then return name, remembered end
    end
    for _, ids in ipairs(rule.prefer or {}) do
        local id = API.BestKnownSpell(ids)
        if id then return C_Spell.GetSpellName(id), id end
    end
    if rule.family then
        local id = API.BestKnownFamilySpell(rule.family)
        if id then return C_Spell.GetSpellName(id), id end
    end
    return nil
end

-- UNIT_SPELLCAST_SUCCEEDED: rules with rememberCasts = family remember the
-- spell you cast from it (e.g. which demon you summon).
function Prepped:OnPlayerSpellCast(spellID)
    if type(spellID) ~= "number" or API.IsSecret(spellID) then return false end
    local changed = false
    for _, rule in ipairs(self.AllRules) do
        local family = rule.rememberCasts
        if family and family.idSet[spellID] then
            self:RememberSpell(rule, spellID)
            changed = true
        end
    end
    return changed
end

------------------------------------------------------------------------
-- Click actions (what left-clicking a reminder does; see display.lua)
------------------------------------------------------------------------
local Action = {}
ns.Action = Action

-- Casts a spell by name, so the client picks the highest rank you know.
-- onSelf: on yourself, even with a friendly target selected.
function Action.Cast(spellID, onSelf)
    local name = spellID and C_Spell.GetSpellName(spellID)
    if not name then return nil end
    return { type = "spell", spell = name, unit = onSelf and "player" or nil, label = format(L["Cast %s"], name) }
end

-- Uses the item in a bag slot, on an equipped item if targetSlot is given
-- (poisons and weapon stones go on a weapon).
function Action.UseItem(bag, slot, itemID, targetSlot)
    if not (bag and slot) then return nil end
    local name = API.GetItemName(itemID)
    local label
    if targetSlot == API.MAIN_HAND_SLOT then
        label = format(L["Apply %s to your main hand"], name)
    elseif targetSlot == API.OFF_HAND_SLOT then
        label = format(L["Apply %s to your off hand"], name)
    else
        label = format(L["Use %s"], name)
    end
    return { type = "item", item = bag .. " " .. slot, targetSlot = targetSlot, label = label }
end

function Action.Macro(macrotext, label)
    return { type = "macro", macrotext = macrotext, label = label }
end

function Action.CancelAura(spellName)
    if not spellName then return nil end
    return { type = "cancelaura", spell = spellName, unit = "player", label = format(L["Cancel %s"], spellName) }
end

-- Plain (not secure) Lua, for opening game windows.
function Action.Run(func, label)
    return { func = func, label = label }
end

------------------------------------------------------------------------
-- Checking the reminders
------------------------------------------------------------------------
local playerClass
function Prepped:GetPlayerClass()
    if not playerClass then
        local _, token = UnitClass("player")
        playerClass = token
    end
    return playerClass
end

-- Character state, read once per check and shared by every module.
Prepped.passState = { resting = false, inCombat = false, traveling = false, supplyTime = false }

-- Supply reminders (reagents, ammo, repairs, ...) show while resting in a city
-- or inn, at a vendor, out of combat for a minute after joining a group, and
-- during a ready check (see supplies.lua).
function Prepped:IsSupplyTime(resting, inCombat)
    if resting == nil then resting = IsResting() end
    if resting or self.forceSupplies == true then return true end
    if self.merchantOpen and self:IsRuleEnabled("general_vendor_check") then return true end
    local now = GetTime()
    if now >= (self.supplyCheckUntil or 0) and now >= (self.readyCheckUntil or 0) then return false end
    if inCombat == nil then inCombat = API.InCombat() end
    return not inCombat
end

local reportedErrors, reportedCount = {}, 0

-- One failing module must not take the others down, and a repeating error is
-- only reported once instead of on every check.
local function ReportError(err)
    local key = tostring(err)
    if reportedErrors[key] or reportedCount >= 20 then return end
    reportedErrors[key] = true
    reportedCount = reportedCount + 1
    geterrorhandler()(err)
end

-- Runs every module for the player's class. Reminders end up in ShowReminder.
function Prepped:EvaluateReminders()
    -- Nothing while dead or on a taxi, or with Prepped switched off
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or not self:IsRuleEnabled("general_master") then
        return
    end

    local state = self.passState
    state.resting = IsResting() and true or false
    state.inCombat = API.InCombat()
    state.traveling = API.IsTraveling()
    state.supplyTime = self:IsSupplyTime(state.resting, state.inCombat)

    local class = self:GetPlayerClass()
    for _, module in ipairs(self.reminderModules) do
        if module.class == nil or module.class == class then
            local ok, err = pcall(self.RunReminders, self, module)
            if not ok then ReportError(err) end
        end
    end
end

local shownInList = {}

local function AnyShown(ruleIds)
    for _, ruleId in ipairs(ruleIds) do
        if shownInList[ruleId] then return true end
    end
    return false
end

-- Runs a module's reminders, in order (see "Rules" for the flags).
function Prepped:RunReminders(module)
    local state = self.passState
    local reminders = module.reminders
    Wipe(shownInList)
    for i = 1, #reminders do
        local rule = reminders[i]
        if rule.check and self:IsRuleEnabled(rule.id)
            and not (rule.supply and not state.supplyTime)
            and not (rule.adventuring and state.resting)
            and not (rule.outOfCombat and state.inCombat)
            and not (rule.noTravel and state.traveling)
            and not (rule.suppressedBy and AnyShown(rule.suppressedBy)) then
            local text, value, icon = rule.check(rule)
            if text then
                shownInList[rule.id] = true
                self:ShowReminder(text, rule, value, icon)
            end
        end
    end
end

-- The texts of the check in progress; drawn in one go afterwards.
local pendingTexts, pendingIds, pendingIcons, pendingCount = {}, {}, {}, 0

local function RuleIcon(rule)
    local icon = rule.icon
    if type(icon) == "function" then return icon(rule) end
    if icon == nil and rule.item then return API.GetItemIcon(rule.item) end
    return icon
end

-- Queues one reminder. value (a number, or { count =, name = }) lets the group
-- message say what's missing (see supplies.lua).
function Prepped:ShowReminder(text, rule, value, icon)
    local ruleId = rule and rule.id
    if self.collecting then
        -- A dry run for the group message: record it, don't draw it.
        if ruleId then self.collecting[#self.collecting + 1] = { id = ruleId, value = value } end
        return
    end
    if ruleId and self:IsSnoozed(ruleId) then return end
    pendingCount = pendingCount + 1
    pendingTexts[pendingCount], pendingIds[pendingCount] = text, ruleId
    pendingIcons[pendingCount] = icon or (rule and RuleIcon(rule)) or false
end

-- Optional sound when a reminder appears ("Sound for New Reminders"): once per
-- reminder per cooldown, at most one sound every SOUND_MIN_GAP seconds, never in combat.
local SOUND_MIN_GAP = 10
local REMINDER_SOUND = (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175
local lastSoundTime
local lastSoundByRule = {}
local wasVisible, isVisible, appearedNow = {}, {}, {}

function Prepped:PlayReminderSound(appeared)
    if self.passState.inCombat or not self:IsRuleEnabled("general_sound") then return end
    local now = GetTime()
    local cooldown = self:GetRuleThreshold("general_sound") * 60
    local due = false
    for ruleId in pairs(appeared) do
        local last = lastSoundByRule[ruleId]
        if last == nil or now - last >= cooldown then
            lastSoundByRule[ruleId] = now
            due = true
        end
    end
    if due and (lastSoundTime == nil or now - lastSoundTime >= SOUND_MIN_GAP) then
        lastSoundTime = now
        if PlaySound then pcall(PlaySound, REMINDER_SOUND) end
    end
end

-- Which reminders just appeared (for the sound)?
local function NoteAppearedReminders(self)
    Wipe(isVisible)
    Wipe(appearedNow)
    local anyAppeared = false
    for i = 1, pendingCount do
        local ruleId = pendingIds[i]
        if ruleId then
            isVisible[ruleId] = true
            if not wasVisible[ruleId] then
                appearedNow[ruleId] = true
                anyAppeared = true
            end
        end
    end
    wasVisible, isVisible = isVisible, wasVisible
    if anyAppeared then self:PlayReminderSound(appearedNow) end
end

local debugprofilestop = debugprofilestop
local checkStats = { count = 0, totalMs = 0, slowestMs = 0 }
Prepped.checkStats = checkStats

-- Re-checks every reminder and updates the bars. Normally called by the
-- scheduler; call Prepped:RequestUpdate() instead from event handlers.
function Prepped:CheckReminders()
    dirty, sinceCheck = false, 0
    local started = debugprofilestop and debugprofilestop()

    pendingCount = 0
    self:EvaluateReminders()
    ns.Display:Render(pendingCount, pendingTexts, pendingIds, pendingIcons)
    NoteAppearedReminders(self)

    checkStats.count = checkStats.count + 1
    if started then
        local took = debugprofilestop() - started
        checkStats.totalMs = checkStats.totalMs + took
        if took > checkStats.slowestMs then checkStats.slowestMs = took end
    end
end

-- Marks the reminders out of date: the scheduler re-checks them shortly.
function Prepped:RequestUpdate()
    dirty = true
end

------------------------------------------------------------------------
-- Shared checks for the modules
------------------------------------------------------------------------
-- Missing / expiring check for a self-buff. displayName: what "Missing %s" names
-- (usually the spell a click casts). Remembers which variant was up. Hidden buff
-- data ("unknown") never warns.
function Prepped:CheckTimedBuff(rule, matcher, displayName)
    local state, remaining, spellId, auraName = API.FindPlayerBuff(matcher)
    if state == "present" then
        if spellId then self:RememberSpell(rule, spellId) end
        if remaining and rule.hasLowWarningToggle and self:IsLowEnabled(rule.id)
            and remaining <= self:GetRuleThreshold(rule.id) then
            return format(L["%s expires in %s"], auraName or displayName or "?", ns.FormatDuration(remaining))
        end
    elseif state == "missing" and displayName then
        return format(L["Missing %s"], displayName)
    end
    return nil
end

-- Weapon imbues (poisons, shaman imbues, warlock stones) on the main hand and,
-- with offHandToo, on an off-hand weapon. Returns "missing", missingMain,
-- missingOff; "expiring", secondsLeft; or nil.
function Prepped:CheckWeaponImbue(rule, offHandToo)
    if not API.HasMainHandWeapon() then return nil end
    local missingMain, missingOff, secondsLeft = API.GetWeaponImbueState(offHandToo)
    if missingMain or missingOff then return "missing", missingMain, missingOff end
    if secondsLeft and self:IsLowEnabled(rule.id) and secondsLeft <= self:GetRuleThreshold(rule.id) then
        return "expiring", secondsLeft
    end
    return nil
end

-- A reagent: rule.item, rule.family (the spells that use it) and rule.itemName
-- (English name until the client's has loaded). rule.notSoldByVendors: Reagent
-- Economy doesn't remove it (e.g. Blinding Powder). Hidden when the reagent
-- isn't needed (see API.ReagentNeeded).
function Prepped:CheckReagent(rule)
    if not API.KnowsFamily(rule.family) then return nil end
    if not API.ReagentNeeded(rule.item, API.GetKnownFamilyIDs(rule.family), not rule.notSoldByVendors) then
        return nil
    end
    local count = C_Item.GetItemCount(rule.item)
    if count >= self:GetRuleThreshold(rule.id) then return nil end
    local name = API.GetItemName(rule.item, rule.itemName)
    local value = rule.value or {}
    rule.value = value
    value.count, value.name = count, name
    return format(rule.notSoldByVendors and L["Make %s (%d left)"] or L["Buy %s (%d left)"], name, count), value
end

local RANGED_SLOT = INVSLOT_RANGED or 18
local AMMO_SLOT = INVSLOT_AMMO or 0
local ITEM_CLASS_WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local WEAPON_SUBCLASS_THROWN = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Thrown) or 16
Prepped.RANGED_SLOT = RANGED_SLOT

-- Returns the ammo (or thrown weapon) count, or nil when there is no ranged
-- weapon that uses ammo.
function Prepped:GetAmmoCount()
    local itemID = GetInventoryItemID("player", RANGED_SLOT)
    if not itemID then return nil end

    local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
    if itemClassID == ITEM_CLASS_WEAPON and itemSubClassID == WEAPON_SUBCLASS_THROWN then
        -- Forever's thrown weapons reportedly have durability and never run out;
        -- a stackable thrown weapon (no durability) is counted like ammo.
        local _, maxDurability = GetInventoryItemDurability(RANGED_SLOT)
        if maxDurability and maxDurability > 0 then return nil end
        return GetInventoryItemCount("player", RANGED_SLOT)
    end

    return GetInventoryItemCount("player", AMMO_SLOT)
end

-- The ammo's icon (or the ranged weapon's).
function Prepped.AmmoIcon()
    return GetInventoryItemTexture("player", AMMO_SLOT) or GetInventoryItemTexture("player", RANGED_SLOT)
end

-- Ammo rules for hunters, rogues and warriors.
function Prepped:CheckNoAmmo()
    if self:GetAmmoCount() == 0 then return L["Out of ammo"] end
    return nil
end

-- "Low"/"critical": below the threshold but not empty (CheckNoAmmo covers that).
function Prepped:CheckAmmoBelow(rule, critical)
    local count = self:GetAmmoCount()
    if count and count > 0 and count < self:GetRuleThreshold(rule.id) then
        if critical then return format(L["Ammo almost gone (%d left)"], count), count end
        return format(L["Buy %s (%d left)"], L["ammo"], count), count
    end
    return nil
end

------------------------------------------------------------------------
-- Events and scheduling
------------------------------------------------------------------------
-- Events never run the checks themselves: they invalidate what they changed
-- and mark the reminders dirty. The driver below then checks at most every
-- UPDATE_MIN_INTERVAL seconds (a burst of 20 BAG_UPDATEs while looting costs
-- one check), plus a heartbeat every HEARTBEAT_INTERVAL for countdowns and
-- timers. No high-frequency events (combat log, power, health) are used.
local frame = CreateFrame("Frame")

local function InvalidateSpellsAndTalents()
    API.InvalidateSpells()
    API.InvalidateTalents()
end

local function GroupJoined() Prepped:OnGroupJoined() end

local handlers = {
    ADDON_LOADED = function(loadedAddon)
        if loadedAddon ~= addonName then return false end
        frame:UnregisterEvent("ADDON_LOADED")
        Prepped:InitializeDefaults()
        ns.Display:Initialize()
        -- A problem in the options UI must never stop the reminders from running.
        local ok, err = pcall(function() return ns.Options.Create() end)
        if not ok then
            geterrorhandler()(err)
        end
    end,
    PLAYER_ENTERING_WORLD = function(isLogin, isReload)
        API.InvalidateCaches()
        if isLogin then Prepped:ClearLoginSnoozes() end
        if isLogin or isReload then
            Prepped:ShowWelcomeMessage()
        end
    end,

    -- Spellbook and talents (some of these only exist on one client)
    SPELLS_CHANGED = API.InvalidateSpells,
    LEARNED_SPELL_IN_SKILL_LINE = API.InvalidateSpells,
    LEARNED_SPELL_IN_TAB = API.InvalidateSpells,
    PLAYER_TALENT_UPDATE = InvalidateSpellsAndTalents,
    CHARACTER_POINTS_CHANGED = InvalidateSpellsAndTalents,
    ACTIVE_TALENT_GROUP_CHANGED = InvalidateSpellsAndTalents,
    TRAIT_CONFIG_UPDATED = InvalidateSpellsAndTalents, -- also Legacy perks
    TRAIT_NODE_CHANGED = false,                 -- talent changes staged, not yet applied
    TRAIT_TREE_CURRENCY_INFO_UPDATED = false,
    CONFIG_COMMIT_FAILED = false,
    UNIT_SPELLCAST_SUCCEEDED = function(_, _, spellID)
        if not Prepped:OnPlayerSpellCast(spellID) then return false end
    end,

    -- Buffs, and what Blizzard hides from addons (combat, encounters, zones).
    -- Entering combat also has to put the click buttons away right now: secure
    -- frames can't be hidden once the combat lockdown has started.
    UNIT_AURA = API.InvalidateAuras,
    PLAYER_REGEN_DISABLED = function()
        API.InvalidateAuras()
        ns.Display:OnCombatStart()
    end,
    PLAYER_REGEN_ENABLED = API.InvalidateAuras,
    ENCOUNTER_START = API.InvalidateAuras,
    ENCOUNTER_END = API.InvalidateAuras,
    ZONE_CHANGED_NEW_AREA = API.InvalidateAuras,

    -- Bags; a new pet changes what counts as pet food
    BAG_UPDATE = API.InvalidateBags,
    BAG_UPDATE_DELAYED = API.InvalidateBags,
    UNIT_PET = API.InvalidateBags,
    GET_ITEM_INFO_RECEIVED = API.OnItemInfoReceived, -- only matters after login

    GROUP_JOINED = GroupJoined,
    GROUP_FORMED = GroupJoined,
    GROUP_LEFT = function() Prepped:OnGroupLeft() end,
    READY_CHECK = function(_, timeLeft) Prepped:OnReadyCheck(timeLeft) end,
    READY_CHECK_FINISHED = function() Prepped:OnReadyCheckFinished() end,
    MERCHANT_SHOW = function() Prepped.merchantOpen = true end,
    MERCHANT_CLOSED = function() Prepped.merchantOpen = nil end,

    -- The screen changed size: the click buttons follow the bars
    UI_SCALE_CHANGED = function() ns.Display:OnScreenChanged() end,
    DISPLAY_SIZE_CHANGED = function() ns.Display:OnScreenChanged() end,

    -- State changes that only need a re-check
    PLAYER_UPDATE_RESTING = false,
    PLAYER_MOUNT_DISPLAY_CHANGED = false,
    UPDATE_SHAPESHIFT_FORM = false,
    PLAYER_ALIVE = false,
    PLAYER_DEAD = false,
    PLAYER_UNGHOST = false,
    PLAYER_CONTROL_LOST = false,   -- taxi
    PLAYER_CONTROL_GAINED = false,
    PLAYER_LEVEL_UP = false,
    PLAYER_EQUIPMENT_CHANGED = false,
    UPDATE_INVENTORY_DURABILITY = false,
    GROUP_ROSTER_UPDATE = false,
    PET_UI_UPDATE = false,
    PET_BAR_UPDATE = false,        -- pet autocast toggled
    UNIT_INVENTORY_CHANGED = false, -- weapon poisons/imbues, ammo
    UNIT_HAPPINESS = false,
}

-- Unit events only for the units we care about (avoids firing for every nameplate/raid member).
local UNIT_EVENTS = {
    UNIT_AURA = "player",
    UNIT_INVENTORY_CHANGED = "player",
    UNIT_PET = "player",
    UNIT_HAPPINESS = "pet",
    UNIT_SPELLCAST_SUCCEEDED = "player",
}

for event in pairs(handlers) do
    local unit = UNIT_EVENTS[event]
    if unit then
        API.RegisterUnitEvent(frame, event, unit)
    else
        API.RegisterEvent(frame, event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    -- A handler returns false when the event changed nothing Prepped shows.
    if handler and handler(...) == false then return end
    dirty = true
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    sinceCheck = sinceCheck + elapsed
    local messageAt = Prepped.groupMessageAt
    if messageAt and GetTime() >= messageAt then
        Prepped:TrySendGroupMessage()
    end
    if sinceCheck >= HEARTBEAT_INTERVAL or (dirty and sinceCheck >= UPDATE_MIN_INTERVAL) then
        Prepped:CheckReminders()
    end
end)
