-- reminders_rogue.lua
-- Rogue reminders: ammo, weapon poisons, poison stock, Flash and Blinding Powder.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local VANISH = API.SpellFamily("Vanish", { 1856, 1857 }, { class = "ROGUE" })
local BLIND = API.SpellFamily("Blind", { 2094 }, { class = "ROGUE" })
-- Poisons is a secondary skill in Forever (skill line 40), not a spellbook spell.
local POISONS = API.SpellFamily("Poisons", { 2842 }, { class = "ROGUE" })
local POISONS_SKILL_LINE = 40

local FLASH_POWDER = 5140    -- vendor reagent
local BLINDING_POWDER = 5530 -- made with Poisons, not sold by vendors

-- Poison items, highest rank first.
local INSTANT = { 8928, 8927, 8926, 6950, 6949, 6947 }
local DEADLY = { 20844, 8985, 8984, 2893, 2892 }
local CRIPPLING = { 3776, 3775 }
local MIND_NUMBING = { 9186, 6951, 5237 }
local WOUND = { 10922, 10921, 10920, 10918 }

local POISON_ITEMS = {}
for _, list in ipairs({ INSTANT, DEADLY, CRIPPLING, MIND_NUMBING, WOUND }) do
    for _, id in ipairs(list) do POISON_ITEMS[#POISON_ITEMS + 1] = id end
end

-- What clicking applies: Instant Poison on the main hand, Deadly Poison on the
-- off hand, else whatever poison you carry.
local MAIN_HAND_CHOICE = { INSTANT, DEADLY, WOUND, MIND_NUMBING, CRIPPLING }
local OFF_HAND_CHOICE = { DEADLY, INSTANT, CRIPPLING, WOUND, MIND_NUMBING }

local function FindPoison(choices)
    for _, list in ipairs(choices) do
        for _, itemID in ipairs(list) do
            local bag, slot = API.FindBagItem(itemID)
            if bag then return itemID, bag, slot end
        end
    end
    return nil
end

-- Learned Poisons (the poison-making skill)
local function KnowsPoisons()
    return API.GetSkillRank(POISONS_SKILL_LINE) > 0 or API.KnowsFamily(POISONS)
end

local function PoisonIcon()
    return API.GetItemIcon((FindPoison(MAIN_HAND_CHOICE)) or INSTANT[#INSTANT])
end

local function CheckReagent(rule) return Prepped:CheckReagent(rule) end

Prepped:RegisterModule({
    class = "ROGUE",
    group = "Rogue",
    reminders = {
        {
            id = "rogue_no_ammo", label = L["No Ammo/Thrown Equipped"],
            description = L["Warns when you have a ranged weapon equipped but no ammo in your ammo slot (or no thrown weapon charges)."],
            announce = { L["out of ammo"], L["buy more ammo"] },
            icon = Prepped.AmmoIcon,
            check = function() return Prepped:CheckNoAmmo() end,
        },
        {
            id = "rogue_ammo_critical", label = L["Critical Ammo/Thrown"], defaultThreshold = 20, unit = "count", range = { 0, 500, 10 },
            description = L["Warns at any time when your ammo or thrown weapons drop below this."],
            announce = { L["low on ammo ({count} left)"], L["buy more ammo"] },
            icon = Prepped.AmmoIcon,
            check = function(rule) return Prepped:CheckAmmoBelow(rule, true) end,
        },
        {
            id = "rogue_ammo_low", label = L["Low Ammo/Thrown"], defaultThreshold = 100, unit = "count", range = { 0, 2000, 50 },
            description = L["While resting, warns when your ammo or thrown weapons drop below this."],
            announce = { L["low on ammo ({count} left)"], L["buy more ammo"] },
            supply = true,
            suppressedBy = { "rogue_no_ammo", "rogue_ammo_critical" },
            icon = Prepped.AmmoIcon,
            check = function(rule) return Prepped:CheckAmmoBelow(rule) end,
        },
        {
            id = "rogue_flash_powder", label = L["Low Flash Powder"], defaultThreshold = 10, unit = "count", range = { 0, 40, 1 },
            description = L["While resting, warns when you have less Flash Powder than this (for Vanish)."],
            announce = { L["low on Flash Powder ({count} left)"], L["buy more Flash Powder"] },
            supply = true, item = FLASH_POWDER, itemName = "Flash Powder", family = VANISH,
            check = CheckReagent,
        },
        {
            id = "rogue_blinding_powder", label = L["Low Blinding Powder"], defaultThreshold = 5, unit = "count", range = { 0, 40, 1 },
            description = L["While resting, warns when you have less Blinding Powder than this (for Blind). It isn't a vendor reagent, so Reagent Economy doesn't hide it."],
            announce = { L["low on Blinding Powder ({count} left)"], L["make more Blinding Powder"] },
            supply = true, item = BLINDING_POWDER, itemName = "Blinding Powder", family = BLIND,
            notSoldByVendors = true, -- Reagent Economy doesn't remove it
            check = CheckReagent,
        },
        {
            id = "rogue_poison_stock", label = L["Low Poison Stock"], defaultThreshold = 20, unit = "count", range = { 0, 100, 5 },
            description = L["While resting, warns when you have fewer poisons than this, all kinds together."],
            announce = { L["low on poisons ({count} left)"], L["make more poisons"] },
            supply = true,
            icon = PoisonIcon,
            check = function(rule)
                if not KnowsPoisons() then return nil end
                local count = API.CountItems(POISON_ITEMS)
                if count < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Make %s (%d left)"], L["poisons"], count), count
                end
            end,
        },
        {
            -- Both weapons when dual wielding; only poisons count, not sharpening
            -- stones (which Forever lets you use on top of a poison).
            id = "rogue_weapon_poison", label = L["Missing Weapon Poison"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to put poison on your weapons when you carry poisons. Clicking it applies one from your bags."],
            adventuring = true, noTravel = true,
            icon = PoisonIcon,
            check = function(rule)
                if not KnowsPoisons() or API.CountItems(POISON_ITEMS) == 0 then return nil end
                local state, first, second = Prepped:CheckWeaponImbue(rule, true)
                if state == "expiring" then return format(L["%s expires in %s"], L["Poison"], ns.FormatDuration(first)) end
                if state ~= "missing" then return nil end
                if first and second then return L["Apply poison to your weapons"] end
                return first and L["Apply poison to your main hand"] or L["Apply poison to your off hand"]
            end,
            action = function()
                local missingMain, missingOff = API.GetWeaponImbueState(true)
                local slot = missingMain and API.MAIN_HAND_SLOT or (missingOff and API.OFF_HAND_SLOT) or nil
                if not slot then return nil end
                local itemID, bag, bagSlot = FindPoison(slot == API.MAIN_HAND_SLOT and MAIN_HAND_CHOICE or OFF_HAND_CHOICE)
                return itemID and Action.UseItem(bag, bagSlot, itemID, slot) or nil
            end,
        },
    },
})
