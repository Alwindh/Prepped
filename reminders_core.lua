local addonName, ns = ...
local API = ns.API

local Prepped = {}
Prepped.reminderModules = {}
Prepped.API = API
-- Publish right away: the reminder modules register through this global, and
-- they must not depend on everything below loading successfully.
_G.Prepped = Prepped

local function GetCharacterKey()
    return (UnitName("player") or "Unknown") .. " - " .. ((GetRealmName and GetRealmName()) or "")
end

-- Settings
local function EnsureSettings()
    if not PreppedSettings then PreppedSettings = {} end

    if PreppedSettings.useAccountWide == nil then
        PreppedSettings.useAccountWide = true
    end

    if not PreppedSettings.global then PreppedSettings.global = {} end

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

-- The rule's own on/off setting, ignoring the master switch (for the options UI).
function Prepped:GetRuleSetting(ruleId)
    return GetCurrentProfile().enabledRules[ruleId] ~= false
end

function Prepped:SetRuleEnabled(ruleId, enabled)
    local profile = GetCurrentProfile()
    profile.enabledRules[ruleId] = enabled
end

function Prepped:GetRule(ruleId)
    for _, rule in ipairs(self.AllRules) do
        if rule.id == ruleId then return rule end
    end
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

function Prepped:ResetAllSettings()
    _G.PreppedSettings = nil
    self:InitializeDefaults()
    self:ApplyAppearance()
    if ns.Options then ns.Options.Refresh() end
    self:CheckReminders()
    print("|cffff8000Prepped:|r All settings have been reset to default.")
end

-- Slash command to open options menu
SLASH_PREPPED1 = "/prepped"
SLASH_PREPPED2 = "/prepped"
local function DebugLine(fmt, ...)
    print("  " .. string.format(fmt, ...))
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
            parts[#parts + 1] = string.format("%d. %s %d", i, tostring(tree.name or "?"), tree.points or 0)
        end
        DebugLine("Talent trees: %s (primary: %s)", table.concat(parts, ", "), tostring(API.GetPrimaryTalentTree()))
    else
        DebugLine("Talent trees: unavailable %s", tostring(API.lastTalentError or ""))
    end

    for _, slot in ipairs({ { "Main hand", Enum.WeaponSlot.MainHand }, { "Off hand", Enum.WeaponSlot.OffHand } }) do
        local parts = {}
        for _, enchant in ipairs(API.GetWeaponEnchantList(slot[2])) do
            if enchant.hasEnchant then
                parts[#parts + 1] = string.format("%s #%s (%ds)", API.DescribeEnchantType(enchant.enchantType),
                    tostring(enchant.enchantID), math.floor((enchant.timeLeft or 0) / 1000))
            end
        end
        DebugLine("%s enchants: %s", slot[1], #parts > 0 and table.concat(parts, ", ") or "none")
    end

    local rangedID = GetInventoryItemID("player", INVSLOT_RANGED)
    if rangedID then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(rangedID)
        local durability, maxDurability = GetInventoryItemDurability(INVSLOT_RANGED)
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
    DebugLine("Buffs on you: %s", buffs and (#buffs > 0 and table.concat(buffs, ", ") or "none") or "hidden right now")

    local unresolved = API.GetUnresolvedSpellIDs()
    DebugLine("Unknown spell IDs: %s", #unresolved > 0 and table.concat(unresolved, ", ") or "none")
    local unlisted = API.GetUnlistedNameMatches(classToken)
    DebugLine("Recognised by name, ID not listed: %s", #unlisted > 0 and table.concat(unlisted, ", ") or "none")
    DebugLine("Group message when joining: %s", self:BuildGroupMessage() or "nothing to report")
    if API.lastBuffScanError then
        DebugLine("Last buff scan error: %s", tostring(API.lastBuffScanError))
    end
end

function Prepped:OpenOptions()
    if not (ns.Options and ns.Options.Open()) then
        print("|cffff8000Prepped:|r the options failed to load; please report /prepped debug output.")
    end
end

SlashCmdList["PREPPED"] = function(msg)
    if msg == "debug" then
        Prepped:PrintDebugReport()
        return
    end
    Prepped:OpenOptions()
end

-- Minimap addon menu entry (## AddonCompartmentFunc in the TOC)
function Prepped_OpenOptions()
    Prepped:OpenOptions()
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

-- Shows one reminder bar. ruleId and value (a number, or { count =, name = }) let
-- the group message say what's missing (see Prepped:BuildGroupMessage).
function Prepped:ShowReminder(text, ruleId, value)
    if self.collecting and ruleId then
        self.collecting[#self.collecting + 1] = { id = ruleId, value = value }
    end
    local line = self:GetNextLine()
    if line then
        line.text:SetText(text)
        line:Show()
    end
end

-- Supply reminders (reagents, ammo, repairs, ...) show while resting in a city or
-- inn, and for a minute after joining a group ("Check Supplies When Joining a Group").
function Prepped:IsSupplyTime()
    return IsResting() or self.forceSupplies == true or GetTime() < (self.supplyCheckUntil or 0)
end

-- Missing / expiring check for a self-buff rule with a "Warn when expiring" option.
-- Returns the text to show, or nil. Hidden buff data ("unknown") never warns.
function Prepped:CheckTimedBuff(ruleId, matcher, missingText, expiringFormat)
    local state, remaining = API.FindPlayerBuff(matcher)
    if state == "missing" then
        return missingText
    elseif state == "present" and remaining and self:IsLowEnabled(ruleId)
        and remaining <= self:GetRuleThreshold(ruleId) then
        return string.format(expiringFormat, math.max(0, math.floor(remaining)))
    end
    return nil
end

-- Runs a module's reminders. Each entry is { id = ruleId, [mustRest | mustNotRest | outOfCombat] = true, ... };
-- checks[id](entry) returns the text to show (or nil) and, for supplies, the amount.
-- mustRest marks a supply reminder: see Prepped:IsSupplyTime().
function Prepped:RunReminders(reminders, checks)
    local isResting = IsResting()
    local supplyTime = self:IsSupplyTime()
    local inCombat = UnitAffectingCombat("player") or InCombatLockdown()
    for _, config in ipairs(reminders) do
        if self:IsRuleEnabled(config.id)
            and not (config.mustRest and not supplyTime)
            and not (config.mustNotRest and isResting)
            and not (config.outOfCombat and inCombat) then
            local text, value = checks[config.id](config)
            if text then
                self:ShowReminder(text, config.id, value)
            end
        end
    end
end

------------------------------------------------------------------------
-- Joining a group: supplies on screen for a minute, and one line in group chat
------------------------------------------------------------------------
local GROUP_CHECK_SECONDS = 60
local GROUP_MESSAGE_DELAY = 2   -- let the group settle first
local GROUP_MESSAGE_MAX = 3     -- shortages named in one message
local CHAT_MESSAGE_LIMIT = 255

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

-- Every supply reminder that would show right now (ignoring the resting rule), as { id, value }.
function Prepped:CollectSupplyShortages()
    self.collecting, self.forceSupplies = {}, true
    local ok, err = pcall(self.CheckReminders, self)
    local found = self.collecting
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
        local rule = self:GetRule(entry.id)
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

-- Called on every update while a group message is pending. Waits while you're in
-- combat, dead, on a taxi or while Forever blocks add-on chat; gives up after a minute.
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
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
end

function Prepped:ShowWelcomeMessage()
    if not self:IsRuleEnabled("general_welcome") then return end
    print("|cff00ff00Prepped|r |cffffcc00v" .. GetAddonVersion() .. "|r |cff00ff00 loaded!|r. Type |cffffff00/prepped|r to open the options menu.")
end

-- All rules, as shown in the options (Options > AddOns > Prepped).
--   defaultThreshold + unit + range {min, max, step}: the rule has a slider
--   hasLowWarningToggle: the threshold is "warn when this many seconds are left"
--   sliderOnly: a plain slider without its own on/off checkbox; sliderLabel: the slider's own label
--   announce = { state, action }: a supply reminder named in the group message, e.g.
--     { "low on ammo ({count} left)", "buy more ammo" } -> "you're low on ammo (150 left), remember to buy more ammo"
Prepped.AllRules = {
    { id = "general_master", label = "Enable Prepped", group = "General", description = "Toggle the entire addon on or off." },
    { id = "general_account_wide", label = "Use Account-wide Settings", group = "General", description = "If enabled, settings are shared across all characters. If disabled, each character has their own config." },
    { id = "general_welcome", label = "Show Welcome Message", group = "General", description = "Show the loaded message when logging in." },
    { id = "general_water", label = "Buy Water", group = "General", defaultThreshold = 40, unit = "count", range = { 0, 200, 5 }, description = "Show a warning while resting when your water count drops below this, if you are a mana user.", announce = { "low on water ({count} left)", "buy more water" } },
    { id = "general_water_minlevel", label = "Water Reminder From Level", group = "General", sliderOnly = true, defaultThreshold = 10, unit = "level", range = { 1, 60, 1 }, description = "Minimum level for the Buy Water reminder." },
    { id = "general_repair", label = "Repair Reminder", group = "General", defaultThreshold = 100, unit = "percent", range = { 0, 100, 5 }, description = "Show a warning while resting when your gear durability drops below this percentage.", announce = { "at {count}% durability", "repair soon" } },
    { id = "general_food", label = "Missing Food Buff", group = "General", hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 }, description = "While leveling, reminds you to keep a food buff (Well Fed) up when you're not resting, not in combat and not mounted. In Forever, cooked food also gives +5% experience from kills." },
    { id = "general_camp", label = "Missing Camp Benefits", group = "General", hasLowWarningToggle = true, defaultThreshold = 300, range = { 0, 600, 10 }, description = "While leveling, reminds you to get Camp Benefits (sit at a camp for a minute) when you're not resting, not in combat and not mounted. Camp Benefits combines the buffs of the camp's objects and lasts an hour." },
    { id = "general_group_check", label = "Check Supplies When Joining a Group", group = "General", description = "When you join a party or raid, show your supply reminders (reagents, ammo, repairs and so on) for a minute, even outside cities and inns. Only you see them." },
    { id = "general_group_announce", label = "Tell My Group", group = "General", defaultThreshold = 50, unit = "percent", sliderLabel = "Repairs below", range = { 0, 100, 5 }, description = "When you join a party or raid, post one line in group chat with what you're low on, for example \"[Prepped] you're at 47% durability, remember to repair soon.\" Once per group, never during combat. Durability is only mentioned below this percentage." },

    { id = "hunter_no_ammo", label = "No Ammo Equipped", group = "Hunter", description = "Show a warning when you have a ranged weapon equipped but no ammo in your ammo slot.", announce = { "out of ammo", "buy more ammo" } },
    { id = "hunter_ammo_low", label = "Low Ammo", group = "Hunter", defaultThreshold = 1000, unit = "count", range = { 0, 4000, 100 }, description = "Show a warning while resting when your ammo count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "hunter_ammo_critical", label = "Critical Ammo", group = "Hunter", defaultThreshold = 200, unit = "count", range = { 0, 1000, 50 }, description = "Show a warning while you're out adventuring when your ammo count drops below this.", announce = { "low on ammo ({count} left)", "buy more ammo" } },
    { id = "hunter_aspect", label = "Missing Aspect", group = "Hunter", description = "Reminds you to have an Aspect buff active." },
    { id = "hunter_no_pet", label = "Missing Pet", group = "Hunter", description = "Reminds you to have your pet active if you know Tame Beast and are not resting." },
    { id = "hunter_pet_unhappy", label = "Unhappy Pet", group = "Hunter", description = "Reminds you to feed your pet if it is unhappy." },
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
    "GROUP_JOINED",
    "GROUP_FORMED",
    "GROUP_LEFT",
}) do
    API.RegisterEvent(container, event)
end
-- Unit events only for the units we care about (avoids firing for every nameplate/raid member).
API.RegisterUnitEvent(container, "UNIT_INVENTORY_CHANGED", "player")
API.RegisterUnitEvent(container, "UNIT_AURA", "player")
API.RegisterUnitEvent(container, "UNIT_STATS", "player")
API.RegisterUnitEvent(container, "UNIT_PET", "player")
API.RegisterUnitEvent(container, "UNIT_HEALTH", "player", "pet")
API.RegisterUnitEvent(container, "UNIT_HAPPINESS", "pet")

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
        API.InvalidateCaches()
    end

    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            Prepped:InitializeDefaults()
            -- A problem in the options UI must never stop the reminders from running.
            local ok, err = pcall(ns.Options.Create)
            if not ok then
                geterrorhandler()(err)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if isLogin or isReload then
            Prepped:ShowWelcomeMessage()
        end
    elseif event == "GROUP_JOINED" or event == "GROUP_FORMED" then
        Prepped:OnGroupJoined()
    elseif event == "GROUP_LEFT" then
        Prepped:OnGroupLeft()
    end
    Prepped:CheckReminders()
end)

local updateTimer = 0
container:SetScript("OnUpdate", function(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= 0.1 then
        updateTimer = 0
        if Prepped.groupMessageAt then
            Prepped:TrySendGroupMessage()
        end
        Prepped:CheckReminders()
    end
end)

_G.Prepped = Prepped
