-- reminders_warrior.lua
-- Warrior reminders: ammo and thrown weapons.
-- (Forever hides buffs from add-ons in combat, so there is no Battle Shout reminder.)

local _, ns = ...
local L = ns.L
local Prepped = ns.Prepped

Prepped:RegisterModule({
    class = "WARRIOR",
    group = "Warrior",
    reminders = {
        {
            id = "warrior_no_ammo", label = L["No Ammo/Thrown Equipped"],
            description = L["Warns when you have a ranged weapon equipped but no ammo in your ammo slot (or no thrown weapon charges)."],
            announce = { L["out of ammo"], L["buy more ammo"] },
            icon = Prepped.AmmoIcon,
            check = function() return Prepped:CheckNoAmmo() end,
        },
        {
            id = "warrior_ammo_critical", label = L["Critical Ammo/Thrown"], defaultThreshold = 20, unit = "count", range = { 0, 500, 10 },
            description = L["Warns at any time when your ammo or thrown weapons drop below this."],
            announce = { L["low on ammo ({count} left)"], L["buy more ammo"] },
            icon = Prepped.AmmoIcon,
            check = function(rule) return Prepped:CheckAmmoBelow(rule, true) end,
        },
        {
            id = "warrior_ammo_low", label = L["Low Ammo/Thrown"], defaultThreshold = 100, unit = "count", range = { 0, 2000, 50 },
            description = L["While resting, warns when your ammo or thrown weapons drop below this."],
            announce = { L["low on ammo ({count} left)"], L["buy more ammo"] },
            supply = true,
            suppressedBy = { "warrior_no_ammo", "warrior_ammo_critical" },
            icon = Prepped.AmmoIcon,
            check = function(rule) return Prepped:CheckAmmoBelow(rule) end,
        },
    },
})
