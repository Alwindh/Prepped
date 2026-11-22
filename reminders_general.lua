-- reminders_general.lua
-- Reminders for every class: water, food and bandages, the Hearthstone, the
-- food buff and Camp Benefits while leveling, unspent talent and Legacy points.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local IsFoodBuff = API.Matcher(API.WELL_FED)
-- Sitting at a camp for a minute combines the buffs of its objects into "Camp Benefits" (1 hour).
local CAMP_BENEFITS = API.SpellFamily("Camp Benefits", { 1229741 }, { aura = true })
local IsCampBuff = API.Matcher(CAMP_BENEFITS)

local WELL_FED_SPELL = 1248406
local CAMP_BENEFITS_SPELL = 1229741
local HEARTHSTONE = 6948
local FIRST_AID_SKILL_LINE = 129
local LEVELING_BUFF_MIN_LEVEL = 10 -- new characters are left alone
local WATER_ICON, FOOD_ICON, BANDAGE_ICON = 159, 4536, 1251 -- items whose icons stand for them
local LEGACY_ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- Water and food: items whose use effect is the "Drink" / "Food" spell (any
-- client language), counted once per change of the bags.
function ns.CountWater() return (API.CountBagItemsWhere("water", API.IsDrinkItem)) end
function ns.CountFood() return (API.CountBagItemsWhere("food", API.IsFoodItem)) end

-- Mana users, including druids in a form that uses rage or energy.
local function UsesMana()
    local maxMana = UnitPowerMax("player", 0) -- 0 = Mana
    if maxMana == nil or API.IsSecret(maxMana) then
        return UnitPowerType("player") == 0
    end
    return maxMana > 0
end

local function BelowSupplyLevel()
    return UnitLevel("player") < Prepped:GetRuleThreshold("general_water_minlevel")
end

-- Buffs worth keeping up while leveling, from level 10.
local function CheckLevelingBuff(rule, matcher, spellID, fallbackName)
    if not API.IsLeveling() or UnitLevel("player") < LEVELING_BUFF_MIN_LEVEL then return nil end
    return Prepped:CheckTimedBuff(rule, matcher, C_Spell.GetSpellName(spellID) or fallbackName)
end

-- The talent window, wherever this client has it.
local function TalentWindowOpener()
    local util = PlayerSpellsUtil
    return (util and (util.ToggleClassTalentOrSpecFrame or util.ToggleClassTalentFrame)) or ToggleTalentFrame
end

Prepped:RegisterModule({
    group = "General",
    reminders = {
        {
            id = "general_water", label = L["Buy Water"], defaultThreshold = 40, unit = "count", range = { 0, 200, 5 },
            description = L["While resting, warns mana users with less water than this. Mages get their own reminder to conjure it."],
            announce = { L["low on water ({count} left)"], L["buy more water"] },
            supply = true,
            icon = function() return API.GetItemIcon(WATER_ICON) end,
            check = function(rule)
                if Prepped:GetPlayerClass() == "MAGE" or not UsesMana() or BelowSupplyLevel() then return nil end
                local count = ns.CountWater()
                if count < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Buy %s (%d left)"], L["water"], count), count
                end
            end,
        },
        {
            id = "general_food_stock", label = L["Buy Food"], defaultThreshold = 20, unit = "count", range = { 0, 200, 5 },
            description = L["While resting, warns when you have less food than this. Mages get their own reminder to conjure it."],
            supply = true,
            icon = function() return API.GetItemIcon(FOOD_ICON) end,
            check = function(rule)
                if Prepped:GetPlayerClass() == "MAGE" or BelowSupplyLevel() then return nil end
                local count = ns.CountFood()
                if count < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Buy %s (%d left)"], L["food"], count), count
                end
            end,
        },
        {
            id = "general_water_minlevel", label = L["Food and Water From Level"], sliderOnly = true,
            defaultThreshold = 10, unit = "level", range = { 1, 60, 1 },
            description = L["Minimum level for the Buy Water and Buy Food reminders."],
        },
        {
            id = "general_bandages", label = L["Low on Bandages"], defaultThreshold = 10, unit = "count", range = { 0, 60, 5 },
            description = L["While resting, warns when you have fewer bandages than this, once you know First Aid."],
            supply = true,
            icon = function() return API.GetItemIcon(BANDAGE_ICON) end,
            check = function(rule)
                if API.GetSkillRank(FIRST_AID_SKILL_LINE) <= 0 then return nil end
                local count = API.CountBagItemsWhere("bandages", API.IsBandage)
                if count < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Make %s (%d left)"], L["bandages"], count), count
                end
            end,
        },
        {
            id = "general_hearthstone", label = L["Missing Hearthstone"],
            description = L["Out of combat, warns when your Hearthstone isn't in your bags, for example after leaving it in the bank."],
            outOfCombat = true,
            item = HEARTHSTONE,
            check = function()
                if C_Item.GetItemCount(HEARTHSTONE) > 0 then return nil end
                return format(L["Missing %s"], API.GetItemName(HEARTHSTONE, "Hearthstone"))
            end,
        },
        {
            id = "general_food", label = L["Missing Food Buff"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["While leveling (from level 10), reminds you to keep a food buff (Well Fed) up when you carry food that gives one and you're not resting, in combat or mounted. In Forever, cooked food also gives +5% experience from kills."],
            adventuring = true, outOfCombat = true, noTravel = true,
            icon = function() return API.GetSpellIcon(WELL_FED_SPELL) end,
            -- Only while you carry food that gives the buff: without it there's
            -- nothing you can do about the reminder.
            check = function(rule)
                local text = CheckLevelingBuff(rule, IsFoodBuff, WELL_FED_SPELL, "Well Fed")
                if text and not API.HasBuffFood() then return nil end
                return text
            end,
            action = function()
                local itemID, bag, slot = API.GetBuffFood()
                return itemID and Action.UseItem(bag, slot, itemID) or nil
            end,
        },
        {
            id = "general_camp", label = L["Missing Camp Benefits"], hasLowWarningToggle = true, defaultThreshold = 300, range = { 0, 600, 10 },
            description = L["While leveling (from level 10), reminds you to get Camp Benefits (sit at a camp for a minute) when you're not resting, in combat or mounted. Camp Benefits combines the buffs of the camp's objects and lasts an hour."],
            adventuring = true, outOfCombat = true, noTravel = true,
            icon = function() return API.GetSpellIcon(CAMP_BENEFITS_SPELL) end,
            check = function(rule)
                return CheckLevelingBuff(rule, IsCampBuff, CAMP_BENEFITS_SPELL, "Camp Benefits")
            end,
        },
        {
            id = "general_talents", label = L["Unspent Talent Points"],
            description = L["Out of combat, reminds you when you have talent points to spend, or talent changes you haven't confirmed (Apply) yet."],
            outOfCombat = true,
            icon = function() return "Interface\\Icons\\ClassIcon_" .. (Prepped:GetPlayerClass() or "Warrior") end,
            check = function()
                local unspent, staged = API.GetTalentPointStatus()
                if not unspent then return nil end
                if staged then return L["Apply your talent changes"] end
                if unspent == 1 then return L["Spend 1 talent point"] end
                if unspent > 1 then return format(L["Spend %d talent points"], unspent) end
            end,
            action = function()
                local open = TalentWindowOpener()
                if not open then return nil end
                return Action.Run(function() pcall(open) end, L["Open your talents"])
            end,
        },
        {
            id = "general_legacy", label = L["Unspent Legacy Points"],
            description = L["Out of combat, reminds you when you have Legacy points left to spend on Legacy perks."],
            outOfCombat = true,
            icon = LEGACY_ICON,
            check = function()
                local unspent = API.GetUnspentLegacyPoints()
                if not unspent or unspent <= 0 then return nil end
                if unspent == 1 then return L["Spend 1 Legacy point"] end
                return format(L["Spend %d Legacy points"], unspent)
            end,
        },
    },
})
