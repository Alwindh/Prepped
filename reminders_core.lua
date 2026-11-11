-- reminders_core.lua
-- Prepped's core: rules and settings, the reminder bars, update scheduling, the
-- group message and the slash commands. Reminder modules (reminders_*.lua)
-- register with Prepped:RegisterReminderModule and describe their reminders as
-- data for Prepped:RunReminders.

local addonName, ns = ...
local API = ns.API

local Prepped = {}
Prepped.reminderModules = {}
Prepped.API = API
-- Publish right away: the reminder modules register through this global, and
-- they must not depend on everything below loading successfully.
_G.Prepped = Prepped

local GetTime = GetTime
local format, floor, max, min = string.format, math.floor, math.max, math.min
local Wipe = API.Wipe

-- Update scheduling (see "Events and scheduling" at the end): events only mark
-- the reminders dirty, and the driver re-checks them in one go.
local UPDATE_MIN_INTERVAL = 0.2 -- seconds between event-driven checks (coalesces bursts)
local HEARTBEAT_INTERVAL = 1    -- countdowns ("30s left") and timers (group message, supply windows)
local dirty, sinceCheck = true, 0

------------------------------------------------------------------------
-- Rules (Options > AddOns > Prepped)
------------------------------------------------------------------------
--   defaultThreshold + unit + range {min, max, step}: the rule has a slider
--   hasLowWarningToggle: the threshold is "warn when this many seconds are left"
--   sliderOnly: a plain slider without its own on/off checkbox; sliderLabel: the slider's own label
--   defaultEnabled = false: off until the player turns it on
--   announce = { state, action }: a supply reminder named in the group message, e.g.
--     { "low on ammo ({count} left)", "buy more ammo" } -> "you're low on ammo (150 left), remember to buy more ammo"
Prepped.AllRules = {
    { id = "general_master", label = "Enable Prepped", group = "General", description = "Toggle the entire addon on or off." },
    { id = "general_account_wide", label = "Use Account-wide Settings", group = "General", description = "If enabled, settings are shared across all characters. If disabled, each character has their own config." },
    { id = "general_welcome", label = "Show Welcome Message", group = "General", description = "Show the loaded message when logging in." },
    { id = "general_sound", label = "Sound for New Reminders", group = "General", defaultEnabled = false, defaultThreshold = 5, unit = "minutes", sliderLabel = "Repeat after", range = { 1, 60, 1 }, description = "Play a short sound when a reminder appears. The same reminder stays silent for this many minutes after it sounded, and there's no sound in combat." },
    { id = "general_water", label = "Buy Water", group = "General", defaultThreshold = 40, unit = "count", range = { 0, 200, 5 }, description = "Show a warning while resting when your water count drops below this, if you are a mana user.", announce = { "low on water ({count} left)", "buy more water" } },
    { id = "general_water_minlevel", label = "Water Reminder From Level", group = "General", sliderOnly = true, defaultThreshold = 10, unit = "level", range = { 1, 60, 1 }, description = "Minimum level for the Buy Water reminder." },
    { id = "general_repair", label = "Repair Reminder", group = "General", defaultThreshold = 70, unit = "percent", range = { 0, 100, 5 }, description = "Show a warning while resting when your gear durability drops below this percentage.", announce = { "at {count}% durability", "repair soon" } },
    { id = "general_bag_space", label = "Low Bag Space", group = "General", defaultThreshold = 4, unit = "count", range = { 0, 30, 1 }, description = "Show a warning while resting when you have fewer free bag slots than this, so you can sell or bank before heading out. Quivers, ammo pouches, soul bags and the reagent bag don't count." },
    { id = "general_food", label = "Missing Food Buff", group = "General", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "While leveling (from level 10), reminds you to keep a food buff (Well Fed) up when you carry food that gives one and you're not resting, not in combat and not mounted. In Forever, cooked food also gives +5% experience from kills." },
    { id = "general_camp", label = "Missing Camp Benefits", group = "General", hasLowWarningToggle = true, defaultThreshold = 300, range = { 0, 600, 10 }, description = "While leveling (from level 10), reminds you to get Camp Benefits (sit at a camp for a minute) when you're not resting, not in combat and not mounted. Camp Benefits combines the buffs of the camp's objects and lasts an hour." },
    { id = "general_talents", label = "Unspent Talent Points", group = "General", description = "Reminds you out of combat when you have talent points to spend, or talent changes you haven't confirmed (Apply) yet." },
    { id = "general_group_check", label = "Check Supplies When Joining a Group", group = "General", description = "When you join a party or raid, show your supply reminders (reagents, ammo, repairs and so on) for a minute, even outside cities and inns. Only you see them, and not during combat." },
    { id = "general_group_announce", label = "Tell My Group", group = "General", defaultThreshold = 50, unit = "percent", sliderLabel = "Repairs below", range = { 0, 100, 5 }, description = "When you join a party or raid, post one line in group chat with what you're low on, for example \"[Prepped] you're at 47% durability, remember to repair soon.\" Once per group, never during combat. Durability is only mentioned below this percentage." },
    { id = "general_ready_check", label = "Check Supplies on Ready Check", group = "General", description = "During a ready check, show your supply reminders (reagents, ammo, repairs and so on) even outside cities and inns, so you know what you're short on before the pull. Not during combat." },

    { id = "hunter_no_ammo", label = "No Ammo Equipped", group = "Hunter", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot.", announce = { "out of ammo", "buy more ammo" } },
    { id = "hunter_ammo_low", label = "Low Ammo", group = "Hunter", defaultThreshold = 1000, unit = "count", range = { 0, 4000, 100 }, description = "Show a warning while resting when your ammo count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "hunter_ammo_critical", label = "Critical Ammo", group = "Hunter", defaultThreshold = 200, unit = "count", range = { 0, 1000, 50 }, description = "Show a warning while you're out adventuring when your ammo count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "hunter_aspect", label = "Missing Aspect", group = "Hunter", description = "Reminds you to have an Aspect buff active." },
    { id = "hunter_no_pet", label = "Missing Pet", group = "Hunter", description = "Reminds you to have your pet active if you know Tame Beast and are not resting." },
    { id = "hunter_pet_unhappy", label = "Unhappy Pet", group = "Hunter", description = "Reminds you to feed your pet when it isn't happy (out of combat, when you can feed it)." },
    { id = "hunter_pet_food", label = "Low Pet Food", group = "Hunter", defaultThreshold = 20, unit = "count", range = { 0, 100, 5 }, description = "Show a warning while resting when you have less food your active pet can eat than this.", announce = { "low on pet food ({count} left)", "buy more pet food" } },

    { id = "mage_powder", label = "Low Arcane Powder", group = "Mage", defaultThreshold = 10, unit = "count", range = { 0, 100, 1 }, description = "Show a warning while resting when your Arcane Powder count drops below this.", announce = { "low on Arcane Powder ({count} left)", "buy more Arcane Powder" } },
    { id = "mage_rune_teleport", label = "Low Runes of Teleportation", group = "Mage", defaultThreshold = 10, unit = "count", range = { 0, 60, 1 }, description = "Show a warning while resting when your Runes of Teleportation count drops below this." },
    { id = "mage_rune_portals", label = "Low Runes of Portals", group = "Mage", defaultThreshold = 10, unit = "count", range = { 0, 60, 1 }, description = "Show a warning while resting when your Runes of Portals count drops below this.", announce = { "low on Runes of Portals ({count} left)", "buy more Runes of Portals" } },
    { id = "mage_ai_buff", label = "Missing Arcane Intellect Buff", group = "Mage", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to buff yourself with Arcane Intellect." },
    { id = "mage_armor_buff", label = "Missing Armor Buff", group = "Mage", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to buff yourself with an Armor buff." },
    { id = "mage_mana_gem", label = "Missing Mana Gem", group = "Mage", description = "Reminds you to conjure a Mana Gem if you are not resting and don't have one." },

    { id = "shaman_totems", label = "Missing Totem Items", group = "Shaman", description = "Show a warning out of combat when the Earth, Fire, Water or Air Totem item for totems you know isn't in your bags (for example when it's still in the bank).", announce = { "missing your {name}", "check your bank" } },
    { id = "shaman_ankh", label = "Buy Ankhs", group = "Shaman", defaultThreshold = 8, unit = "count", range = { 0, 40, 1 }, description = "Show a warning while resting when your Ankh count drops below this.", announce = { "low on Ankhs ({count} left)", "buy more Ankhs" } },
    { id = "shaman_fish_oil", label = "Buy Fish Oil", group = "Shaman", defaultThreshold = 10, unit = "count", range = { 0, 40, 1 }, description = "Show a warning while resting when your Fish Oil count drops below this." },
    { id = "shaman_fish_scales", label = "Buy Fish Scales", group = "Shaman", defaultThreshold = 10, unit = "count", range = { 0, 40, 1 }, description = "Show a warning while resting when your Fish Scales count drops below this." },
    { id = "shaman_shield_buff", label = "Missing Shield Buff", group = "Shaman", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to buff yourself with a Shield buff." },
    { id = "shaman_weapon_buff", label = "Missing Weapon Buff", group = "Shaman", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Smart reminder for Shaman weapon imbues based on spec/dual-wielding." },

    { id = "rogue_no_ammo", label = "No Ammo/Thrown Equipped", group = "Rogue", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot (or no thrown weapon charges).", announce = { "out of ammo", "buy more ammo" } },
    { id = "rogue_ammo_low", label = "Low Ammo/Thrown", group = "Rogue", defaultThreshold = 100, unit = "count", range = { 0, 2000, 50 }, description = "Show a warning while resting when your ammo/thrown count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "rogue_ammo_critical", label = "Critical Ammo/Thrown", group = "Rogue", defaultThreshold = 20, unit = "count", range = { 0, 500, 10 }, description = "Show a warning at any time when your ammo/thrown count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "rogue_weapon_poison", label = "Missing Weapon Poison", group = "Rogue", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to apply poison to your weapons when you have poisons in your bags." },
    { id = "rogue_poison_stock", label = "Low Poison Stock", group = "Rogue", defaultThreshold = 20, unit = "count", range = { 0, 100, 5 }, description = "Show a warning while resting when your total poison count drops below this.", announce = { "low on poisons ({count} left)", "make more poisons" } },
    { id = "rogue_flash_powder", label = "Low Flash Powder", group = "Rogue", defaultThreshold = 10, unit = "count", range = { 0, 40, 1 }, description = "Show a warning while resting when your Flash Powder count drops below this (for Vanish).", announce = { "low on Flash Powder ({count} left)", "buy more Flash Powder" } },
    { id = "rogue_blinding_powder", label = "Low Blinding Powder", group = "Rogue", defaultThreshold = 5, unit = "count", range = { 0, 40, 1 }, description = "Show a warning while resting when your Blinding Powder count drops below this (for Blind). It isn't a vendor reagent, so Reagent Economy doesn't hide it.", announce = { "low on Blinding Powder ({count} left)", "make more Blinding Powder" } },

    { id = "warrior_no_ammo", label = "No Ammo/Thrown Equipped", group = "Warrior", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot (or no thrown weapon charges).", announce = { "out of ammo", "buy more ammo" } },
    { id = "warrior_ammo_low", label = "Low Ammo/Thrown", group = "Warrior", defaultThreshold = 100, unit = "count", range = { 0, 2000, 50 }, description = "Show a warning while resting when your ammo/thrown count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "warrior_ammo_critical", label = "Critical Ammo/Thrown", group = "Warrior", defaultThreshold = 20, unit = "count", range = { 0, 500, 10 }, description = "Show a warning at any time when your ammo/thrown count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },

    { id = "paladin_aura", label = "Missing Aura", group = "Paladin", description = "Reminds you to have a Paladin Aura active at all times." },
    { id = "paladin_blessing", label = "Missing Self-Blessing", group = "Paladin", hasLowWarningToggle = true, defaultThreshold = 30, range = { 0, 600, 10 }, description = "Reminds you to have a Blessing active on yourself when not resting." },
    { id = "paladin_kings", label = "Low Symbol of Kings", group = "Paladin", defaultThreshold = 50, unit = "count", range = { 0, 200, 10 }, description = "Show a warning while resting when your Symbol of Kings count drops below this.", announce = { "low on Symbol of Kings ({count} left)", "buy more Symbols of Kings" } },
    { id = "paladin_divinity", label = "Low Symbol of Divinity", group = "Paladin", defaultThreshold = 5, unit = "count", range = { 0, 20, 1 }, description = "Show a warning while resting when your Symbol of Divinity count drops below this.", announce = { "low on Symbol of Divinity ({count} left)", "buy more Symbols of Divinity" } },
    { id = "paladin_righteous_fury", label = "Missing Righteous Fury", group = "Paladin", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to activate Righteous Fury if you are in a group, have a shield equipped, and are Protection spec." },

    { id = "priest_fortitude", label = "Missing Power Word: Fortitude", group = "Priest", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to buff yourself with Power Word: Fortitude (or Prayer of Fortitude if learned). Warns when missing or expiring soon." },
    { id = "priest_inner_fire", label = "Missing Inner Fire", group = "Priest", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to have Inner Fire active when not resting." },
    { id = "priest_candles", label = "Low Candles", group = "Priest", defaultThreshold = 10, unit = "count", range = { 0, 100, 5 }, description = "Show a warning while resting when you have fewer candles than this for your Prayer spells: Sacred Candles once you know Prayer of Fortitude rank 2, Prayer of Spirit or Prayer of Shadow Protection, Holy Candles before that.", announce = { "low on {name} ({count} left)", "buy more {name}" } },

    { id = "druid_mark", label = "Missing Mark of the Wild", group = "Druid", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to buff yourself with Mark of the Wild (or Gift of the Wild) when not resting or traveling." },
    { id = "druid_rebirth_seeds", label = "Low Rebirth Seeds", group = "Druid", defaultThreshold = 5, unit = "count", range = { 0, 40, 1 }, description = "Show a warning while resting when you have fewer seeds for your highest Rebirth rank than this.", announce = { "low on {name} ({count} left)", "buy more {name}" } },
    { id = "druid_gift_reagents", label = "Low Gift of the Wild Reagents", group = "Druid", defaultThreshold = 10, unit = "count", range = { 0, 100, 5 }, description = "Show a warning while resting when you have fewer reagents for your Gift of the Wild rank (Wild Berries or Wild Thornroot) than this.", announce = { "low on {name} ({count} left)", "buy more {name}" } },

    { id = "warlock_armor", label = "Missing Demon Armor", group = "Warlock", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to have Demon Armor (or Demon Skin) active when not resting." },
    { id = "warlock_pet", label = "Missing Demon", group = "Warlock", description = "Reminds you to summon a demon when not resting (not while you have a Demonic Sacrifice buff)." },
    { id = "warlock_weapon_stone", label = "Missing Weapon Stone", group = "Warlock", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "Reminds you to put a Firestone or Spellstone on your weapon once you can create one (weapon imbues in Forever; a wizard oil doesn't count)." },
    { id = "warlock_healthstone", label = "Missing Healthstone", group = "Warlock", description = "Reminds you to create a Healthstone when you are out of combat, not resting, and have a Soul Shard.", announce = { "missing a Healthstone", "create a Healthstone" } },
    { id = "warlock_soulstone", label = "Missing Soulstone", group = "Warlock", description = "Reminds you to create a Soulstone when you are out of combat, not resting, have a Soul Shard and aren't soulstoned yourself.", announce = { "missing a Soulstone", "create a Soulstone" } },
    { id = "warlock_soul_shards", label = "Low Soul Shards", group = "Warlock", defaultThreshold = 5, unit = "count", range = { 0, 40, 1 }, description = "Show a warning out of combat, when not resting, while you have fewer Soul Shards than this.", announce = { "low on Soul Shards ({count} left)", "farm more Soul Shards" } },
}

local rulesById = {}
for _, rule in ipairs(Prepped.AllRules) do rulesById[rule.id] = rule end

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

------------------------------------------------------------------------
-- Settings (SavedVariables: PreppedSettings)
------------------------------------------------------------------------
-- PreppedSettings = {
--     schemaVersion = 2,
--     useAccountWide = true,             -- false: each character has its own profile
--     global = profile,                  -- the account-wide profile
--     profiles = { ["Name - Realm"] = profile },
--     appearance = { fontSize, minWidth, fontColor = { r, g, b }, bgColor = { r, g, b, a } },
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

-- The active profile and appearance are looked up once, not on every read.
local activeProfile, activeAppearance

local function ResetSettingsCache()
    activeProfile, activeAppearance = nil, nil
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

-- The player's setting, else the rule's default (AllRules is the only source of
-- defaults), else the fallback.
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
-- into the profile; they come from AllRules when read.
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
    print("|cffff8000Prepped:|r All settings have been reset to default.")
end

------------------------------------------------------------------------
-- Reminder bars
------------------------------------------------------------------------
Prepped.displayLines = {}
Prepped.activeCount = 0

-- The texts of the check in progress; rendered in one go afterwards.
local pendingTexts, pendingIds, pendingCount = {}, {}, 0

local function LineWidth(line, app)
    return max(app.minWidth or 400, line.text:GetUnboundedStringWidth() + 40)
end

local function StyleLine(line, index, app)
    local fontPath = GameFontNormalLarge:GetFont() -- the game's default font
    local bg, fc = app.bgColor, app.fontColor
    line.bg:SetColorTexture(bg.r, bg.g, bg.b, bg.a or 0.5)
    line.text:SetFont(fontPath, app.fontSize, "OUTLINE")
    line.text:SetTextColor(fc.r or 1, fc.g or 0.82, fc.b or 0, 1)
    line:SetSize(LineWidth(line, app), app.fontSize + 12)
    line:ClearAllPoints()
    line:SetPoint("TOP", _G.PreppedContainer, "TOP", 0, -(index - 1) * (app.fontSize + 14))
end

function Prepped:ApplyAppearance()
    local app = self:GetAppearance()
    for index, line in ipairs(self.displayLines) do
        StyleLine(line, index, app)
    end
end

-- The bar at this position, created (styled) the first time it's needed.
function Prepped:GetLine(index)
    local line = self.displayLines[index]
    if line then return line end
    local container = _G.PreppedContainer
    if not container then return nil end

    line = CreateFrame("Frame", nil, container)
    line.bg = line:CreateTexture(nil, "BACKGROUND")
    line.bg:SetAllPoints()
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    line.text:SetPoint("CENTER")
    self.displayLines[index] = line
    StyleLine(line, index, self:GetAppearance())
    return line
end

-- Snoozed reminders (/prepped snooze): [ruleId] = GetTime() when the snooze ends.
local snoozedUntil = {}

local function IsSnoozed(ruleId)
    local untilTime = snoozedUntil[ruleId]
    if untilTime == nil then return false end
    if GetTime() >= untilTime then
        snoozedUntil[ruleId] = nil
        return false
    end
    return true
end

-- Shows one reminder bar. ruleId and value (a number, or { count =, name = }) let
-- the group message say what's missing (see Prepped:BuildGroupMessage).
function Prepped:ShowReminder(text, ruleId, value)
    if self.collecting then
        -- A dry run for the group message: record it, don't draw it.
        if ruleId then self.collecting[#self.collecting + 1] = { id = ruleId, value = value } end
        return
    end
    if ruleId and IsSnoozed(ruleId) then return end
    pendingCount = pendingCount + 1
    pendingTexts[pendingCount], pendingIds[pendingCount] = text, ruleId
end

-- Optional sound when a reminder appears ("Sound for New Reminders"): once per
-- reminder per cooldown, at most one sound every SOUND_MIN_GAP seconds, never in combat.
local SOUND_MIN_GAP = 10
local REMINDER_SOUND = (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175
local lastSoundTime
local lastSoundByRule = {}
local wasVisible, isVisible = {}, {}

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

local appearedNow = {}

-- Draws the pending reminders, touching only bars whose text or visibility changed.
function Prepped:RenderReminders()
    local app = self:GetAppearance()
    local shown = 0
    for i = 1, pendingCount do
        local line = self:GetLine(i)
        if not line then break end
        local text = pendingTexts[i]
        if line.shownText ~= text then
            line.text:SetText(text)
            line.shownText = text
            line:SetWidth(LineWidth(line, app))
        end
        line.ruleId = pendingIds[i]
        if not line:IsShown() then line:Show() end
        shown = i
    end
    for i = shown + 1, #self.displayLines do
        local line = self.displayLines[i]
        line.ruleId = nil
        if line:IsShown() then line:Hide() end
    end
    self.activeCount = shown

    -- Which reminders just appeared (for the sound)?
    Wipe(isVisible)
    Wipe(appearedNow)
    local anyAppeared = false
    for i = 1, shown do
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

-- /prepped snooze: hides the reminders on screen for a while. Returns how many.
function Prepped:Snooze(minutes)
    local untilTime, count = GetTime() + minutes * 60, 0
    for i = 1, self.activeCount do
        local ruleId = self.displayLines[i].ruleId
        if ruleId then
            snoozedUntil[ruleId] = untilTime
            count = count + 1
        end
    end
    self:CheckReminders()
    return count
end

-- Ends every snooze. Returns how many were active.
function Prepped:Unsnooze()
    local now, count = GetTime(), 0
    for _, untilTime in pairs(snoozedUntil) do
        if untilTime > now then count = count + 1 end
    end
    Wipe(snoozedUntil)
    self:CheckReminders()
    return count
end

------------------------------------------------------------------------
-- Checking the reminders
------------------------------------------------------------------------
function Prepped:RegisterReminderModule(module)
    table.insert(self.reminderModules, module)
end

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

-- Supply reminders (reagents, ammo, repairs, ...) show while resting in a city or
-- inn, and out of combat for a minute after joining a group ("Check Supplies When
-- Joining a Group") or during a ready check ("Check Supplies on Ready Check").
function Prepped:IsSupplyTime(resting, inCombat)
    if resting == nil then resting = IsResting() end
    if resting or self.forceSupplies == true then return true end
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
        if module.CheckReminders and (module.class == nil or module.class == class) then
            local ok, err = pcall(module.CheckReminders)
            if not ok then ReportError(err) end
        end
    end
end

local debugprofilestop = debugprofilestop
local checkStats = { count = 0, totalMs = 0, slowestMs = 0 }

-- Re-checks every reminder and updates the bars. Normally called by the
-- scheduler; call Prepped:RequestUpdate() instead from event handlers.
function Prepped:CheckReminders()
    dirty, sinceCheck = false, 0
    local started = debugprofilestop and debugprofilestop()

    pendingCount = 0
    self:EvaluateReminders()
    self:RenderReminders()

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

local shownInList = {}

local function AnyShown(ruleIds)
    for _, ruleId in ipairs(ruleIds) do
        if shownInList[ruleId] then return true end
    end
    return false
end

-- Runs a module's reminders, in order. Each entry is { id = ruleId, ...flags }:
--   mustRest      a supply reminder: only at supply time (see Prepped:IsSupplyTime)
--   mustNotRest   only while out adventuring
--   outOfCombat   not in combat
--   noTravel      not while mounted or in a travel form (Travel/Aquatic/Flight Form, Ghost Wolf)
--   suppressedBy  { ruleId, ... }: skipped when one of these showed earlier in the list
-- checks[id](entry) returns the text to show (or nil) and, for supplies, the amount.
function Prepped:RunReminders(reminders, checks)
    local state = self.passState
    Wipe(shownInList)
    for i = 1, #reminders do
        local config = reminders[i]
        local ruleId = config.id
        if self:IsRuleEnabled(ruleId)
            and not (config.mustRest and not state.supplyTime)
            and not (config.mustNotRest and state.resting)
            and not (config.outOfCombat and state.inCombat)
            and not (config.noTravel and state.traveling)
            and not (config.suppressedBy and AnyShown(config.suppressedBy)) then
            local text, value = checks[ruleId](config)
            if text then
                shownInList[ruleId] = true
                self:ShowReminder(text, ruleId, value)
            end
        end
    end
end

------------------------------------------------------------------------
-- Shared checks for the modules
------------------------------------------------------------------------
-- Missing / expiring check for a self-buff rule with a "Warn when expiring" option.
-- Returns the text to show, or nil. Hidden buff data ("unknown") never warns.
function Prepped:CheckTimedBuff(ruleId, matcher, missingText, expiringFormat)
    local state, remaining = API.FindPlayerBuff(matcher)
    if state == "missing" then
        return missingText
    elseif state == "present" and remaining and self:IsLowEnabled(ruleId)
        and remaining <= self:GetRuleThreshold(ruleId) then
        return format(expiringFormat, max(0, floor(remaining)))
    end
    return nil
end

-- Missing / expiring check for weapon imbues (poisons, shaman imbues, warlock
-- stones): config.message when the main hand (or, with offHandToo, an off-hand
-- weapon) has none, config.messageLow ("... (%ss left)") when one runs out soon.
function Prepped:CheckWeaponImbue(config, offHandToo)
    if not API.HasMainHandWeapon() then return nil end
    local hasMH, mhMs, hasOH, ohMs = API.GetWeaponImbues()
    local checkOffHand = offHandToo and API.IsOffHandWeapon()
    if not hasMH or (checkOffHand and not hasOH) then
        return config.message
    end
    if not self:IsLowEnabled(config.id) then return nil end
    local msLeft = mhMs
    if checkOffHand and ohMs and (msLeft == nil or ohMs < msLeft) then msLeft = ohMs end
    if msLeft then
        local secondsLeft = msLeft / 1000
        if secondsLeft <= self:GetRuleThreshold(config.id) then
            return format(config.messageLow, max(0, floor(secondsLeft)))
        end
    end
    return nil
end

-- A reagent: config.item, config.family (the spell that uses it) and
-- config.message ("Low on X (%s left)"). config.notSoldByVendors: Reagent Economy
-- doesn't remove it (e.g. Blinding Powder). Hidden when the reagent isn't needed
-- (see API.ReagentNeeded).
function Prepped:CheckReagent(config)
    if not API.KnowsFamily(config.family) then return nil end
    if not API.ReagentNeeded(config.item, API.GetKnownFamilyIDs(config.family), not config.notSoldByVendors) then
        return nil
    end
    local count = C_Item.GetItemCount(config.item)
    if count < self:GetRuleThreshold(config.id) then
        return format(config.message, count), count
    end
    return nil
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

-- Ammo rules for hunters, rogues and warriors.
function Prepped:CheckNoAmmo(config)
    if self:GetAmmoCount() == 0 then return config.message end
    return nil
end

-- "Low"/"critical": below the threshold but not empty (CheckNoAmmo covers that).
function Prepped:CheckAmmoBelow(config)
    local count = self:GetAmmoCount()
    if count and count > 0 and count < self:GetRuleThreshold(config.id) then
        return format(config.message, count), count
    end
    return nil
end

------------------------------------------------------------------------
-- Joining a group: supplies on screen for a minute, and one line in group chat
------------------------------------------------------------------------
local GROUP_CHECK_SECONDS = 60
local GROUP_MESSAGE_DELAY = 2   -- let the group settle first
local GROUP_MESSAGE_MAX = 3     -- shortages named in one message
local CHAT_MESSAGE_LIMIT = 255
local READY_CHECK_SECONDS = 35  -- if the client doesn't say

local function JoinList(items)
    if #items <= 1 then return items[1] or "" end
    return table.concat(items, ", ", 1, #items - 1) .. " and " .. items[#items]
end

local function FillTemplate(template, value)
    local count, name = value, nil
    if type(value) == "table" then count, name = value.count, value.name end
    local text = template:gsub("{count}", tostring(count or "?"))
    text = text:gsub("{name}", tostring(name or ""))
    return text
end

-- Every supply reminder that would show right now (ignoring the resting rule), as
-- { id, value }. A dry run: the bars on screen don't change.
function Prepped:CollectSupplyShortages()
    local found = {}
    self.collecting, self.forceSupplies = found, true
    local ok, err = pcall(self.EvaluateReminders, self)
    self.collecting, self.forceSupplies = nil, nil
    if not ok then geterrorhandler()(err) end
    return found
end

-- "[Prepped] you're at 47% durability and low on ammo (150 left), remember to repair soon and buy more ammo."
-- Uses each supply rule's `announce = { state, action }`; nil when there's nothing to say.
function Prepped:BuildGroupMessage()
    local states, actions, seenAction = {}, {}, {}
    local repairBelow = self:GetRuleThreshold("general_group_announce")
    for _, entry in ipairs(self:CollectSupplyShortages()) do
        local rule = rulesById[entry.id]
        local announce = rule and rule.announce
        local tooMinor = entry.id == "general_repair" and (tonumber(entry.value) or 0) >= repairBelow
        if announce and not tooMinor and #states < GROUP_MESSAGE_MAX then
            states[#states + 1] = FillTemplate(announce[1], entry.value)
            local action = FillTemplate(announce[2], entry.value)
            if not seenAction[action] then
                seenAction[action] = true
                actions[#actions + 1] = action
            end
        end
    end
    if #states == 0 then return nil end
    local message = "[Prepped] you're " .. JoinList(states) .. ", remember to " .. JoinList(actions) .. "."
    if #message > CHAT_MESSAGE_LIMIT then
        message = message:sub(1, CHAT_MESSAGE_LIMIT - 3) .. "..."
    end
    return message
end

function Prepped:OnGroupJoined()
    if self.groupMessageSent then return end -- once per group
    local now = GetTime()
    if self:IsRuleEnabled("general_group_check") then
        self.supplyCheckUntil = now + GROUP_CHECK_SECONDS
    end
    if self:IsRuleEnabled("general_group_announce") then
        self.groupMessageAt = now + GROUP_MESSAGE_DELAY
        self.groupMessageUntil = now + GROUP_CHECK_SECONDS
    end
end

function Prepped:OnGroupLeft()
    self.groupMessageSent, self.groupMessageAt, self.supplyCheckUntil = nil, nil, nil
end

-- Ready check: supplies on screen until it ends.
function Prepped:OnReadyCheck(timeLeft)
    if not self:IsRuleEnabled("general_ready_check") then return end
    if API.IsSecret(timeLeft) then timeLeft = nil end
    self.readyCheckUntil = GetTime() + (tonumber(timeLeft) or READY_CHECK_SECONDS)
end

function Prepped:OnReadyCheckFinished()
    self.readyCheckUntil = nil
end

-- Called while a group message is due. Waits while you're in combat, dead, on a
-- taxi or while Forever blocks add-on chat; gives up after a minute.
function Prepped:TrySendGroupMessage()
    local now = GetTime()
    if now < self.groupMessageAt then return end
    if now > self.groupMessageUntil or not API.GroupChatType() then
        self.groupMessageAt = nil
        return
    end
    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or API.InChatLockdown() then
        self.groupMessageAt = now + 1
        return
    end
    self.groupMessageAt = nil
    self.groupMessageSent = true
    local message = self:BuildGroupMessage()
    if message then
        API.SendGroupMessage(message)
    end
end

------------------------------------------------------------------------
-- /prepped
------------------------------------------------------------------------
SLASH_PREPPED1 = "/prepped"
local DEFAULT_SNOOZE_MINUTES = 30

local function DebugLine(fmt, ...)
    print("  " .. format(fmt, ...))
end

local function ListOrNone(list)
    return (list and #list > 0) and table.concat(list, ", ") or "none"
end

-- /prepped debug: everything needed to check Prepped's view of this client.
function Prepped:PrintDebugReport()
    local _, classToken = UnitClass("player")
    print("|cff00ff00Prepped Debug:|r")
    DebugLine("Client: %s", API.GetClientLabel())
    DebugLine("Buff data hidden right now: %s", tostring(API.AreAurasRestricted()))

    local trees = API.GetTalentTrees()
    if trees then
        local parts = {}
        for i, tree in ipairs(trees) do
            parts[#parts + 1] = format("%d. %s %d", i, tostring(tree.name or "?"), tree.points or 0)
        end
        DebugLine("Talent trees: %s (primary: %s)", table.concat(parts, ", "), tostring(API.GetPrimaryTalentTree()))
    else
        DebugLine("Talent trees: unavailable %s", tostring(API.lastTalentError or ""))
    end

    for _, slot in ipairs({ { "Main hand", Enum.WeaponSlot.MainHand }, { "Off hand", Enum.WeaponSlot.OffHand } }) do
        local parts = {}
        for _, enchant in ipairs(API.GetWeaponEnchantList(slot[2])) do
            if enchant.hasEnchant then
                parts[#parts + 1] = format("%s #%s (%ds)", API.DescribeEnchantType(enchant.enchantType),
                    tostring(enchant.enchantID), floor((enchant.timeLeft or 0) / 1000))
            end
        end
        DebugLine("%s enchants: %s", slot[1], ListOrNone(parts))
    end

    local rangedID = GetInventoryItemID("player", RANGED_SLOT)
    if rangedID then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(rangedID)
        local durability, maxDurability = GetInventoryItemDurability(RANGED_SLOT)
        DebugLine("Ranged: item %s (class %s/%s), durability %s/%s, ammo count %s", tostring(rangedID),
            tostring(classID), tostring(subClassID), tostring(durability), tostring(maxDurability), tostring(self:GetAmmoCount()))
    else
        DebugLine("Ranged: none")
    end

    if classToken == "ROGUE" then
        DebugLine("Poisons skill rank: %d, Poisons spell known: %s", API.GetSkillRank(40), tostring(C_SpellBook.IsSpellKnown(2842)))
    elseif classToken == "DRUID" then
        DebugLine("Shapeshift form ID: %s", tostring(GetShapeshiftFormID()))
    end

    local hasPerk, source = API.HasReagentEconomy()
    DebugLine("Reagent Economy perk: %s%s", hasPerk and "yes" or "no", source and (" (" .. source .. ")") or "")
    local perks = API.GetLegacyPerks()
    DebugLine("Legacy perks: %s", perks and ListOrNone(perks) or "unavailable")
    DebugLine("Spells seen working without their reagent: %s", ListOrNone(API.GetReagentFreeSpells()))

    for _, family in ipairs(API.GetAuraFamiliesForClass(classToken)) do
        if #family.knownIDs > 0 then
            local seen, labels = {}, {}
            for _, id in ipairs(family.knownIDs) do
                local label = API.DescribeAuraSecrecy(id)
                if not seen[label] then
                    seen[label] = true
                    labels[#labels + 1] = label
                end
            end
            DebugLine("%s in combat: %s", family.label, table.concat(labels, " / "))
        end
    end

    local buffs = API.ListPlayerBuffs()
    DebugLine("Buffs on you: %s", buffs and ListOrNone(buffs) or "hidden right now")
    local bagFood, tooltipsNameBuff = API.DescribeBagFood()
    DebugLine("Food and drink in your bags: %s", ListOrNone(bagFood))
    DebugLine("Food tooltips name the food buff: %s", tooltipsNameBuff)

    DebugLine("Unknown spell IDs: %s", ListOrNone(API.GetUnresolvedSpellIDs()))
    DebugLine("Recognised by name, ID not listed: %s", ListOrNone(API.GetUnlistedNameMatches(classToken)))
    DebugLine("Group message when joining: %s", self:BuildGroupMessage() or "nothing to report")

    local now, snoozed = GetTime(), {}
    for ruleId, untilTime in pairs(snoozedUntil) do
        if untilTime > now then snoozed[#snoozed + 1] = format("%s (%dm)", ruleId, math.ceil((untilTime - now) / 60)) end
    end
    table.sort(snoozed)
    DebugLine("Snoozed: %s", ListOrNone(snoozed))
    if checkStats.totalMs > 0 then
        DebugLine("Reminder checks: %d (average %.3f ms, slowest %.3f ms)", checkStats.count,
            checkStats.totalMs / checkStats.count, checkStats.slowestMs)
    else
        DebugLine("Reminder checks: %d", checkStats.count)
    end
    if API.lastBuffScanError then
        DebugLine("Last buff scan error: %s", tostring(API.lastBuffScanError))
    end
end

function Prepped:OpenOptions()
    if not (ns.Options and ns.Options.Open()) then
        print("|cffff8000Prepped:|r the options failed to load; please report /prepped debug output.")
    end
end

local function PrintHelp()
    print("|cffff8000Prepped:|r |cffffff00/prepped|r options, |cffffff00/prepped snooze [minutes]|r hide the reminders on screen for a while (default "
        .. DEFAULT_SNOOZE_MINUTES .. "), |cffffff00/prepped unsnooze|r, |cffffff00/prepped debug|r")
end

SlashCmdList["PREPPED"] = function(msg)
    local command, argument = string.lower(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" then
        Prepped:PrintDebugReport()
    elseif command == "snooze" then
        local minutes = min(max(floor(tonumber(argument) or DEFAULT_SNOOZE_MINUTES), 1), 24 * 60)
        local count = Prepped:Snooze(minutes)
        if count > 0 then
            print(format("|cffff8000Prepped:|r snoozed %d reminder%s for %d minutes; |cffffff00/prepped unsnooze|r brings %s back.",
                count, count == 1 and "" or "s", minutes, count == 1 and "it" or "them"))
        else
            print("|cffff8000Prepped:|r there's nothing to snooze right now.")
        end
    elseif command == "unsnooze" then
        local count = Prepped:Unsnooze()
        print(format("|cffff8000Prepped:|r %d snoozed reminder%s back.", count, count == 1 and "" or "s"))
    elseif command == "help" then
        PrintHelp()
    else
        Prepped:OpenOptions()
    end
end

-- Minimap addon menu entry (## AddonCompartmentFunc in the TOC)
function Prepped_OpenOptions()
    Prepped:OpenOptions()
end

local function GetAddonVersion()
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
end

function Prepped:ShowWelcomeMessage()
    if not self:IsRuleEnabled("general_welcome") then return end
    print("|cff00ff00Prepped|r |cffffcc00v" .. GetAddonVersion() .. "|r |cff00ff00 loaded!|r. Type |cffffff00/prepped|r to open the options menu.")
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
        -- A problem in the options UI must never stop the reminders from running.
        local ok, err = pcall(function() return ns.Options.Create() end)
        if not ok then
            geterrorhandler()(err)
        end
    end,
    PLAYER_ENTERING_WORLD = function(isLogin, isReload)
        API.InvalidateCaches()
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

    -- Buffs, and what Blizzard hides from addons (combat, encounters, zones)
    UNIT_AURA = API.InvalidateAuras,
    PLAYER_REGEN_DISABLED = API.InvalidateAuras,
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
    UNIT_INVENTORY_CHANGED = false, -- weapon poisons/imbues, ammo
    UNIT_HAPPINESS = false,
}

-- Unit events only for the units we care about (avoids firing for every nameplate/raid member).
local UNIT_EVENTS = {
    UNIT_AURA = "player",
    UNIT_INVENTORY_CHANGED = "player",
    UNIT_PET = "player",
    UNIT_HAPPINESS = "pet",
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

_G.Prepped = Prepped
