-- reminders_multiclass.lua
-- Gear and bags, for every class: repairs, gear about to break, bag space.

local _, ns = ...
local API, L = ns.API, ns.L
local Prepped = ns.Prepped
local format, floor = string.format, math.floor

local REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

local function ItemName(slot)
    local itemID = slot and GetInventoryItemID("player", slot)
    return itemID and API.GetItemName(itemID, L["an item"]) or L["an item"]
end

Prepped:RegisterModule({
    group = "General",
    reminders = {
        {
            -- Anywhere, even in combat: a broken item gives no stats until it's repaired.
            id = "general_gear_breaking", label = L["Gear About to Break"], defaultThreshold = 10, unit = "percent", range = { 0, 50, 5 },
            description = L["Warns anywhere, even in combat, when one of your equipped items is at this durability or lower, or broken. Broken gear gives no stats until it's repaired."],
            announce = { L["at {count}% durability on your {name}"], L["repair soon"] },
            check = function(rule)
                local _, slot, percent = API.GetDurability()
                if not slot or percent > Prepped:GetRuleThreshold(rule.id) then return nil end
                local value = rule.value or {}
                rule.value = value
                value.count, value.name = floor(percent), ItemName(slot)
                local icon = GetInventoryItemTexture("player", slot)
                if percent <= 0 then return format(L["%s is broken"], value.name), value, icon end
                return format(L["%s is about to break (%d%%)"], value.name, value.count), value, icon
            end,
        },
        {
            -- The average hides one worn-out item, so a single item below the
            -- second slider counts too. The group message names the average.
            id = "general_repair", label = L["Repair Reminder"], defaultThreshold = 70, unit = "percent", range = { 0, 100, 5 },
            description = L["While resting, warns when your gear's durability is below this percentage, or one item is below the setting under it."],
            announce = { L["at {count}% durability"], L["repair soon"] },
            supply = true,
            suppressedBy = { "general_gear_breaking" },
            icon = REPAIR_ICON,
            check = function(rule)
                local average, slot, percent = API.GetDurability()
                average = floor(average)
                if average < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Repair your gear (%d%%)"], average), average
                end
                if slot and percent < Prepped:GetRuleThreshold("general_repair_item") then
                    return format(L["Repair your gear (%s at %d%%)"], ItemName(slot), floor(percent)), average
                end
            end,
        },
        {
            id = "general_repair_item", label = L["Repair When One Item Is Below"], sliderOnly = true,
            defaultThreshold = 25, unit = "percent", range = { 0, 100, 5 },
            description = L["The Repair Reminder also shows when a single item is below this durability, even if your gear as a whole is fine."],
        },
        {
            id = "general_bag_space", label = L["Low Bag Space"], defaultThreshold = 4, unit = "count", range = { 0, 30, 1 },
            description = L["While resting, warns when you have fewer free bag slots than this, so you can sell or bank before heading out. Quivers, ammo pouches, soul bags and the reagent bag don't count."],
            supply = true,
            icon = BAG_ICON,
            check = function(rule)
                local free = API.CountFreeBagSlots()
                if free < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Free up bag space (%d free)"], free), free
                end
            end,
        },
    },
})
